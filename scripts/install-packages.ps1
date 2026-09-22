$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

# Restores the Wally-managed dependency trees, reshapes them for Studio's Script Sync, then
# rewrites the generated link files so their exported Luau types are visible to requiring modules.
#
# Wally lays packages out for Rojo: `_Index/<package>/<name>/default.project.json` names the
# source root (`src/`, `lib/`, a single file...). Script Sync has no project files and mirrors
# directories literally, which would turn every package root into a Folder and break the
# `require` in each link file. Flattening moves the mapped root up so `<name>/init.luau` is the
# package, keeps only scripts, and normalises the extension to `.luau` because that is what
# Script Sync writes back.
$projectRoot = Split-Path -Parent $PSScriptRoot
$packageDirectories = @(
    (Join-Path $projectRoot "ReplicatedStorage\Packages"),
    (Join-Path $projectRoot "ServerStorage\ServerPackages")
)
$scriptExtensions = @(".lua", ".luau")

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Tool @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Tool $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ProjectRoot {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$PackageDirectory)

    $projectPath = Join-Path $PackageDirectory.FullName "default.project.json"
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        return $null
    }

    $tree = (Get-Content -LiteralPath $projectPath -Raw | ConvertFrom-Json).tree
    $pathProperty = $tree.PSObject.Properties['$path']
    if (-not $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) {
        return $null
    }

    return Join-Path $PackageDirectory.FullName ([string]$pathProperty.Value)
}

function Remove-NonScriptContent {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    Get-ChildItem -LiteralPath $Directory.FullName -Recurse -File -Force |
    Where-Object { $_.Extension -notin $scriptExtensions } |
    Remove-Item -Force

    # Deepest directories first so emptied parents are removed in the same pass.
    Get-ChildItem -LiteralPath $Directory.FullName -Recurse -Directory -Force |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force | Select-Object -First 1) } |
    Remove-Item -Force
}

function Rename-LuaToLuau {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    # -Filter "*.lua" would also match .luau through short-name matching, so compare extensions.
    Get-ChildItem -LiteralPath $Directory.FullName -Recurse -File -Force |
    Where-Object { $_.Extension -eq ".lua" } |
    ForEach-Object {
        $target = [System.IO.Path]::ChangeExtension($_.FullName, ".luau")
        if (Test-Path -LiteralPath $target) {
            throw "Both $($_.FullName) and $target exist; resolve the collision before flattening."
        }
        Move-Item -LiteralPath $_.FullName -Destination $target
    }
}

function Convert-Package {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$PackageDirectory)

    $mappedRoot = Get-ProjectRoot -PackageDirectory $PackageDirectory
    if (-not $mappedRoot) {
        return
    }

    $parent = $PackageDirectory.Parent.FullName
    $name = $PackageDirectory.Name

    if (Test-Path -LiteralPath $mappedRoot -PathType Leaf) {
        # A single-file root becomes `<name>/init.luau`: still one ModuleScript in Studio, and it
        # keeps the `_Index/<package>/` level free for wally-package-types, which treats every
        # script there as a dependency link.
        $temporary = Join-Path $parent "$name.flatten.tmp"
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $extension = [System.IO.Path]::GetExtension($mappedRoot)
        Move-Item -LiteralPath $mappedRoot -Destination (Join-Path $temporary "init$extension")
        Remove-Item -LiteralPath $PackageDirectory.FullName -Recurse -Force
        Move-Item -LiteralPath $temporary -Destination $PackageDirectory.FullName
        return
    }

    if (Test-Path -LiteralPath $mappedRoot -PathType Container) {
        $temporary = Join-Path $parent "$name.flatten.tmp"
        Move-Item -LiteralPath $mappedRoot -Destination $temporary
        Remove-Item -LiteralPath $PackageDirectory.FullName -Recurse -Force
        Move-Item -LiteralPath $temporary -Destination $PackageDirectory.FullName
    }
}

function Convert-PackagesDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $indexPath = Join-Path $Path "_Index"
    if (Test-Path -LiteralPath $indexPath -PathType Container) {
        foreach ($entry in Get-ChildItem -LiteralPath $indexPath -Directory) {
            foreach ($package in Get-ChildItem -LiteralPath $entry.FullName -Directory) {
                Convert-Package -PackageDirectory $package
            }
        }
    }

    $directory = Get-Item -LiteralPath $Path
    Remove-NonScriptContent -Directory $directory
    Rename-LuaToLuau -Directory $directory
}

# Wally does not clear files it did not write, so start from empty trees for a deterministic result.
foreach ($packagesDirectory in $packageDirectories) {
    if (Test-Path -LiteralPath $packagesDirectory -PathType Container) {
        Remove-Item -LiteralPath $packagesDirectory -Recurse -Force
    }
}

foreach ($manifestDirectory in @("ReplicatedStorage", "ServerStorage")) {
    Invoke-Tool -WorkingDirectory (Join-Path $projectRoot $manifestDirectory) -Tool "wally" install
}

foreach ($packagesDirectory in $packageDirectories) {
    if (Test-Path -LiteralPath $packagesDirectory -PathType Container) {
        Convert-PackagesDirectory -Path $packagesDirectory
    }
}

& (Join-Path $PSScriptRoot "..\.vscode\generate-sourcemap.ps1")

Invoke-Tool -WorkingDirectory $projectRoot -Tool "wally-package-types" `
    --sourcemap sourcemap.json ReplicatedStorage/Packages ServerStorage/ServerPackages

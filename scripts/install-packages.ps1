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

function Assert-ContainedPath {
    param([string]$Root, [string]$Path)

    $absoluteRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/")
    $absolutePath = [System.IO.Path]::GetFullPath($Path)
    if (-not $absolutePath.StartsWith($absoluteRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its owning directory: $absolutePath"
    }
}

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

    $mappedPath = Join-Path $PackageDirectory.FullName ([string]$pathProperty.Value)
    Assert-ContainedPath -Root $PackageDirectory.FullName -Path $mappedPath
    return $mappedPath
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
    Assert-ContainedPath -Root $parent -Path $PackageDirectory.FullName

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

# Never install raw Wally output into a watched service directory. Script Sync can import its
# folders/test runners before flattening, then write that stale hierarchy back over the result.
# Build and type the complete replacement outside the project before exposing either tree.
# A sibling uses the same filesystem, so publishing is a directory rename rather than a
# cross-volume copy that could expose children before their init.luau module root arrives.
$stagingParent = Split-Path -Parent $projectRoot
$stagingRoot = Join-Path $stagingParent (".cake-game-packages-" + [guid]::NewGuid().ToString("N"))
$published = [System.Collections.Generic.List[string]]::new()
$backups = @{}
$originalLocks = @{}
$cleanupStaging = $true
try {
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot ".vscode") -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot "rokit.toml") -Destination $stagingRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot ".vscode/generate-sourcemap.ps1") -Destination (Join-Path $stagingRoot ".vscode")

    foreach ($serviceName in @("ReplicatedStorage", "ServerStorage")) {
        $servicePath = Join-Path $stagingRoot $serviceName
        New-Item -ItemType Directory -Path $servicePath | Out-Null
        foreach ($fileName in @("wally.toml", "wally.lock")) {
            $sourcePath = Join-Path (Join-Path $projectRoot $serviceName) $fileName
            if (Test-Path -LiteralPath $sourcePath) {
                Copy-Item -LiteralPath $sourcePath -Destination $servicePath
            }
        }
        Invoke-Tool -WorkingDirectory $servicePath -Tool "wally" install
    }

    foreach ($relativePath in @("ReplicatedStorage/Packages", "ServerStorage/ServerPackages")) {
        $stagedPackages = Join-Path $stagingRoot $relativePath
        if (-not (Test-Path -LiteralPath $stagedPackages -PathType Container)) {
            throw "Wally did not produce $relativePath"
        }
        Convert-PackagesDirectory -Path $stagedPackages
        # Every installed root must be a ModuleScript, never the original Wally wrapper folder.
        foreach ($entry in Get-ChildItem -LiteralPath (Join-Path $stagedPackages "_Index") -Directory) {
            foreach ($package in Get-ChildItem -LiteralPath $entry.FullName -Directory) {
                if (-not (Test-Path -LiteralPath (Join-Path $package.FullName "init.luau") -PathType Leaf)) {
                    throw "Package root is not a ModuleScript: $($package.FullName)"
                }
            }
        }
    }

    & (Join-Path $stagingRoot ".vscode/generate-sourcemap.ps1")
    Invoke-Tool -WorkingDirectory $stagingRoot -Tool "wally-package-types" `
        --sourcemap sourcemap.json ReplicatedStorage/Packages ServerStorage/ServerPackages

    foreach ($serviceName in @("ReplicatedStorage", "ServerStorage")) {
        $lockPath = Join-Path $projectRoot "$serviceName/wally.lock"
        $originalLocks[$lockPath] = if (Test-Path -LiteralPath $lockPath) {
            [System.IO.File]::ReadAllBytes($lockPath)
        } else {
            $null
        }
    }

    foreach ($packagesDirectory in $packageDirectories) {
        Assert-ContainedPath -Root $projectRoot -Path $packagesDirectory
        $relativePath = $packagesDirectory.Substring($projectRoot.Length).TrimStart([char[]]"\/")
        if (Test-Path -LiteralPath $packagesDirectory) {
            $backupPath = Join-Path $stagingRoot ("backup-" + [System.IO.Path]::GetFileName($packagesDirectory))
            Assert-ContainedPath -Root $stagingRoot -Path $backupPath
            Move-Item -LiteralPath $packagesDirectory -Destination $backupPath
            $backups[$packagesDirectory] = $backupPath
        }
        Move-Item -LiteralPath (Join-Path $stagingRoot $relativePath) -Destination $packagesDirectory
        $published.Add($packagesDirectory)
    }

    foreach ($serviceName in @("ReplicatedStorage", "ServerStorage")) {
        Copy-Item -LiteralPath (Join-Path $stagingRoot "$serviceName/wally.lock") `
            -Destination (Join-Path $projectRoot "$serviceName/wally.lock") -Force
    }
    & (Join-Path $projectRoot ".vscode/generate-sourcemap.ps1")
    Write-Host "Prepared package trees installed. Verify Script Sync has imported ModuleScript roots before Play."
}
catch {
    # If rollback itself fails, retain the staging directory and its backups for recovery.
    $cleanupStaging = $false
    foreach ($packagesDirectory in $published) {
        Assert-ContainedPath -Root $projectRoot -Path $packagesDirectory
        Remove-Item -LiteralPath $packagesDirectory -Recurse -Force
    }
    foreach ($packagesDirectory in $backups.Keys) {
        Assert-ContainedPath -Root $projectRoot -Path $packagesDirectory
        Assert-ContainedPath -Root $stagingRoot -Path $backups[$packagesDirectory]
        Move-Item -LiteralPath $backups[$packagesDirectory] -Destination $packagesDirectory
    }
    foreach ($lockPath in $originalLocks.Keys) {
        if ($null -ne $originalLocks[$lockPath]) {
            [System.IO.File]::WriteAllBytes($lockPath, $originalLocks[$lockPath])
        } elseif (Test-Path -LiteralPath $lockPath) {
            Remove-Item -LiteralPath $lockPath -Force
        }
    }
    $cleanupStaging = $true
    throw
}
finally {
    if ($cleanupStaging -and (Test-Path -LiteralPath $stagingRoot)) {
        Assert-ContainedPath -Root $stagingParent -Path $stagingRoot
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    } elseif (-not $cleanupStaging) {
        Write-Warning "Package rollback was interrupted. Backups retained at $stagingRoot"
    }
}

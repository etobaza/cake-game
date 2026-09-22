$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectRoot "sourcemap.json"
$pathTrimCharacters = [char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)

# Rojo/ScriptSync file-name suffixes and the script class they produce.
$scriptSuffixClasses = [ordered]@{
    ".client" = "LocalScript"
    ".server" = "Script"
    ".legacy" = "Script"
}
$sourceExtensions = @(".lua", ".luau")
$caseInsensitivePaths = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$pathComparison = if ($caseInsensitivePaths) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$normalizedProjectRoot = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd($pathTrimCharacters) +
[System.IO.Path]::DirectorySeparatorChar

function New-TreeNode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($ClassName)) {
        throw "Sourcemap nodes require non-empty names and class names."
    }

    return [ordered]@{
        name      = $Name
        className = $ClassName
        children  = @()
    }
}

function Add-ChildNode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parent,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Child,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    foreach ($existingChild in $Parent.children) {
        if ([string]::Equals($existingChild.name, $Child.name, [System.StringComparison]::Ordinal)) {
            throw "Ambiguous DataModel child '$($Child.name)' in $Context. Rename the colliding file or directory."
        }
    }

    $Parent.children += $Child
}

function Assert-NotReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not supported in sourcemap roots: $($Item.FullName)"
    }
}

function Get-ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    # A plain prefix check, case-insensitive on Windows: Uri.MakeRelativeUri treats `c:` and `C:`
    # as different roots and silently falls back to absolute paths.
    $normalizedPath = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $normalizedPath.StartsWith($normalizedProjectRoot, $pathComparison)) {
        throw "Source file is outside the project root: $normalizedPath"
    }

    return $normalizedPath.Substring($normalizedProjectRoot.Length).Replace("\", "/")
}

function Get-ScriptIdentity {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$SourceFile)

    $scriptName = $SourceFile.BaseName
    $scriptClass = "ModuleScript"

    foreach ($suffix in $scriptSuffixClasses.Keys) {
        if ($scriptName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $scriptName = $scriptName.Substring(0, $scriptName.Length - $suffix.Length)
            $scriptClass = $scriptSuffixClasses[$suffix]
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($scriptName)) {
        throw "Source file produces an empty DataModel name: $($SourceFile.FullName)"
    }

    return [ordered]@{
        Name      = $scriptName
        ClassName = $scriptClass
    }
}

function Find-InitSourceFile {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    $candidates = @("init") + @($scriptSuffixClasses.Keys | ForEach-Object { "init$_" })
    foreach ($candidate in $candidates) {
        foreach ($extension in $sourceExtensions) {
            $candidatePath = Join-Path $Directory.FullName "$candidate$extension"
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                return Get-Item -LiteralPath $candidatePath -Force
            }
        }
    }

    return $null
}

function Convert-SourceDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Directory,

        [string]$ClassName = "Folder",

        [System.Collections.IDictionary]$ChildClassNames = @{}
    )

    Assert-NotReparsePoint -Item $Directory

    # A directory holding an init file is that script, with siblings as children. This is the
    # same rule Studio's Script Sync applies, so the sourcemap and the place agree.
    $initSourceFile = Find-InitSourceFile -Directory $Directory
    if ($initSourceFile) {
        $ClassName = (Get-ScriptIdentity -SourceFile $initSourceFile).ClassName
    }

    $node = New-TreeNode -Name $Directory.Name -ClassName $ClassName
    if ($initSourceFile) {
        $node.filePaths = @(Get-ProjectRelativePath -FullPath $initSourceFile.FullName)
    }

    $childDirectories = Get-ChildItem -LiteralPath $Directory.FullName -Directory -Force |
    Sort-Object @{ Expression = { $_.Name.ToUpperInvariant() } }, @{ Expression = { $_.Name } }

    foreach ($childDirectory in $childDirectories) {
        Assert-NotReparsePoint -Item $childDirectory
        $childClassName = if ($ChildClassNames.Contains($childDirectory.Name)) {
            [string]$ChildClassNames[$childDirectory.Name]
        }
        else {
            "Folder"
        }
        $childNode = Convert-SourceDirectory -Directory $childDirectory -ClassName $childClassName
        Add-ChildNode -Parent $node -Child $childNode -Context $Directory.FullName
    }

    $sourceFiles = Get-ChildItem -LiteralPath $Directory.FullName -File -Force |
    Where-Object { $_.Extension -in $sourceExtensions -and (-not $initSourceFile -or $_.FullName -ne $initSourceFile.FullName) } |
    Sort-Object @{ Expression = { $_.Name.ToUpperInvariant() } }, @{ Expression = { $_.Name } }

    foreach ($sourceFile in $sourceFiles) {
        Assert-NotReparsePoint -Item $sourceFile
        $identity = Get-ScriptIdentity -SourceFile $sourceFile
        $scriptNode = [ordered]@{
            name      = $identity.Name
            className = $identity.ClassName
            filePaths = @(Get-ProjectRelativePath -FullPath $sourceFile.FullName)
        }
        Add-ChildNode -Parent $node -Child $scriptNode -Context $Directory.FullName
    }

    return $node
}

function Get-ProjectSourceFiles {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Directory,

        [switch]$IsProjectRoot
    )

    Assert-NotReparsePoint -Item $Directory

    Get-ChildItem -LiteralPath $Directory.FullName -File -Force |
    Where-Object { $_.Extension -in $sourceExtensions }

    $ignoredRootDirectories = @(".agents", ".codex", ".cursor", ".git", ".vscode", ".zed", "node_modules")
    foreach ($childDirectory in Get-ChildItem -LiteralPath $Directory.FullName -Directory -Force) {
        if ($IsProjectRoot -and $childDirectory.Name -in $ignoredRootDirectories) {
            continue
        }
        Get-ProjectSourceFiles -Directory $childDirectory
    }
}

function Add-MappedFilePaths {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$MappedPaths
    )

    if ($Node.Contains("filePaths")) {
        foreach ($filePath in $Node.filePaths) {
            if (-not $MappedPaths.Add([string]$filePath)) {
                throw "Source file is mapped more than once: $filePath"
            }
        }
    }

    if ($Node.Contains("children")) {
        foreach ($child in $Node.children) {
            Add-MappedFilePaths -Node $child -MappedPaths $MappedPaths
        }
    }
}

$root = New-TreeNode -Name "cake-game" -ClassName "DataModel"

$serviceRoots = [ordered]@{
    ReplicatedFirst     = "ReplicatedFirst"
    ReplicatedStorage   = "ReplicatedStorage"
    ServerScriptService = "ServerScriptService"
    ServerStorage       = "ServerStorage"
    Workspace           = "Workspace"
    StarterGui          = "StarterGui"
    StarterPack         = "StarterPack"
    Lighting            = "Lighting"
    SoundService        = "SoundService"
    TextChatService     = "TextChatService"
    Chat                = "Chat"
    Teams               = "Teams"
    LocalizationService = "LocalizationService"
    TestService         = "TestService"
}

foreach ($entry in $serviceRoots.GetEnumerator()) {
    $sourcePath = Join-Path $projectRoot $entry.Key
    if (Test-Path -LiteralPath $sourcePath -PathType Container) {
        $serviceNode = Convert-SourceDirectory -Directory (Get-Item -LiteralPath $sourcePath -Force) -ClassName $entry.Value
        Add-ChildNode -Parent $root -Child $serviceNode -Context $projectRoot
    }
}

$starterContainers = [ordered]@{
    StarterCharacterScripts = "StarterCharacterScripts"
    StarterPlayerScripts    = "StarterPlayerScripts"
}
$starterPlayerPath = Join-Path $projectRoot "StarterPlayer"
$hasStarterPlayerRoot = Test-Path -LiteralPath $starterPlayerPath -PathType Container
$hasLegacyStarterContainers = $false

foreach ($containerName in $starterContainers.Keys) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $containerName) -PathType Container) {
        $hasLegacyStarterContainers = $true
        break
    }
}

if ($hasStarterPlayerRoot -or $hasLegacyStarterContainers) {
    $starterPlayer = if ($hasStarterPlayerRoot) {
        Convert-SourceDirectory `
            -Directory (Get-Item -LiteralPath $starterPlayerPath -Force) `
            -ClassName "StarterPlayer" `
            -ChildClassNames $starterContainers
    }
    else {
        New-TreeNode -Name "StarterPlayer" -ClassName "StarterPlayer"
    }

    foreach ($entry in $starterContainers.GetEnumerator()) {
        $sourcePath = Join-Path $projectRoot $entry.Key
        if (Test-Path -LiteralPath $sourcePath -PathType Container) {
            $containerNode = Convert-SourceDirectory `
                -Directory (Get-Item -LiteralPath $sourcePath -Force) `
                -ClassName $entry.Value
            Add-ChildNode -Parent $starterPlayer -Child $containerNode -Context $starterPlayerPath
        }
    }

    Add-ChildNode -Parent $root -Child $starterPlayer -Context $projectRoot
}

$pathComparer = if ($caseInsensitivePaths) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$mappedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
Add-MappedFilePaths -Node $root -MappedPaths $mappedPaths

foreach ($sourceFile in Get-ProjectSourceFiles -Directory (Get-Item -LiteralPath $projectRoot -Force) -IsProjectRoot) {
    $relativePath = Get-ProjectRelativePath -FullPath $sourceFile.FullName
    if (-not $mappedPaths.Contains($relativePath)) {
        throw "Source file is outside the supported DataModel roots: $relativePath"
    }
}

$json = $root | ConvertTo-Json -Depth 100
$temporaryPath = "$outputPath.$PID.$([System.Guid]::NewGuid().ToString('N')).tmp"

try {
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

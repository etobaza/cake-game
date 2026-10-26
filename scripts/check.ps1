[CmdletBinding()]
param(
    # Roblox API definitions file. Defaults to the copy the luau-lsp editor extension keeps.
    [string]$Definitions
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

# The full Luau verification gate from AGENTS.md: sourcemap, Selene, then the Rokit-pinned
# analyzer with the Roblox definitions, sourcemap and workspace settings it needs. A bare
# `luau-lsp analyze .` has none of those and reports every Roblox global as unknown.
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRoots = @(
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterCharacterScripts",
    "StarterPlayerScripts"
)

function Resolve-Definitions {
    param([string]$Requested)

    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) {
            throw "Definitions file not found: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $fileName = "globalTypes.PluginSecurity.d.luau"
    $zedDefinitions = Join-Path $projectRoot ".zed\.cache\$fileName"
    if (Test-Path -LiteralPath $zedDefinitions -PathType Leaf) {
        return $zedDefinitions
    }
    foreach ($editor in @("Cursor", "Code")) {
        $candidate = Join-Path $env:APPDATA "$editor\User\globalStorage\johnnymorganz.luau-lsp\$fileName"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "No Roblox definitions file found. Run scripts/setup-zed.ps1, open a Luau file in VS Code/Cursor, or pass -Definitions <path>."
}

# luau-lsp and Selene cannot open paths with non-ASCII characters on Windows (the project lives
# under the localized OneDrive Documents folder), and the 8.3 short path does not help because luau-lsp canonicalises
# its working directory. Run them through an ASCII junction in %TEMP% that points here.
function Resolve-AnalysisRoot {
    if ($projectRoot -notmatch "[^\x00-\x7F]") {
        return $projectRoot
    }

    $safeName = ((Split-Path -Leaf $projectRoot) -replace "[^A-Za-z0-9_-]", "_")
    $junction = Join-Path $env:TEMP "luau-check\$safeName"
    if (Test-Path -LiteralPath $junction) {
        $existing = Get-Item -LiteralPath $junction -Force
        # Compare normalised paths: a junction target can come back with a "\\?\" prefix or a trailing
        # backslash, and -eq already ignores case.
        $target = "$(@($existing.Target)[0])" -replace "^\\\\\?\\", ""
        $sameTarget = $target.TrimEnd("\") -eq "$projectRoot".TrimEnd("\")
        if ($existing.LinkType -eq "Junction" -and $sameTarget) {
            return $junction
        }
        # Never clear this path with Remove-Item -Recurse: on a junction it deletes the target's files.
        throw "Path $junction already exists and is not a junction to $projectRoot. Remove it with 'cmd /c rmdir `"$junction`"' and run again."
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $junction) -Force | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $projectRoot | Out-Null
    return $junction
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "== $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

Push-Location -LiteralPath $projectRoot
try {
    $definitionsPath = Resolve-Definitions -Requested $Definitions
    $roots = @($sourceRoots | Where-Object { Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Container })
    $analysisRoot = Resolve-AnalysisRoot

    Invoke-Step -Name "Sourcemap" -Action {
        & (Join-Path $projectRoot ".vscode\generate-sourcemap.ps1")
        $global:LASTEXITCODE = 0
    }

    Invoke-Step -Name "Selene" -Action {
        Push-Location -LiteralPath $analysisRoot
        try {
            & selene .
        }
        finally {
            Pop-Location
        }
    }

    # Every first-party module is strict; vendored code is exempt through the analyzer's own ignore globs.
    Invoke-Step -Name "Strict mode" -Action {
        $settings = Get-Content -Raw -LiteralPath (Join-Path $projectRoot ".vscode\settings.json") | ConvertFrom-Json
        $ignored = @($settings."luau-lsp.ignoreGlobs" | ForEach-Object { $_ -replace "\*\*", "*" })
        $missing = @(foreach ($root in $roots) {
            Get-ChildItem -LiteralPath (Join-Path $projectRoot $root) -Recurse -File |
                Where-Object { $_.Extension -in ".lua", ".luau" } |
                ForEach-Object {
                    $relative = $_.FullName.Substring($projectRoot.Length + 1) -replace "\\", "/"
                    $isIgnored = @($ignored | Where-Object { $relative -like $_ }).Count -gt 0
                    if (-not $isIgnored -and (Get-Content -LiteralPath $_.FullName -TotalCount 1) -notmatch "^--!strict\s*$") {
                        $relative
                    }
                }
        })
        foreach ($path in $missing) {
            Write-Host "Missing --!strict on the first line: $path" -ForegroundColor Red
        }
        $global:LASTEXITCODE = [int]($missing.Count -gt 0)
    }

    Invoke-Step -Name "Luau analysis (luau-lsp $(& luau-lsp --version))" -Action {
        Push-Location -LiteralPath $analysisRoot
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = @(& luau-lsp analyze `
                    --platform roblox `
                    --definitions $definitionsPath `
                    --sourcemap sourcemap.json `
                    --settings .vscode/settings.json `
                    @roots 2>&1 | ForEach-Object { "$_" })
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
            Pop-Location
        }
        $output | ForEach-Object { Write-Host $_ }

        # luau-lsp reports an unreadable project as one line and analyses nothing, so a run that only
        # failed to load must not pass as a clean or ordinary type-error result.
        $fatal = @($output | Where-Object { $_ -match "path does not exist|Failed to load sourcemap" })
        if ($fatal.Count -gt 0) {
            throw "luau-lsp could not read the project; the analysis did not run"
        }
        # A file in the sourcemap prints its instance path in brackets before the position; others do not.
        $diagnostics = @($output | Where-Object { $_ -match "^.+?\.luau?( \[[^\]]*\])?\(\d+,\d+\): " })
        Write-Host "Type diagnostics: $($diagnostics.Count)"
        $global:LASTEXITCODE = $exitCode
    }

    Write-Host "All checks passed." -ForegroundColor Green
}
finally {
    Pop-Location
}

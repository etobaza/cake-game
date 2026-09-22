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
    $roots = $sourceRoots | Where-Object { Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Container }

    Invoke-Step -Name "Sourcemap" -Action {
        & (Join-Path $projectRoot ".vscode\generate-sourcemap.ps1")
        $global:LASTEXITCODE = 0
    }

    Invoke-Step -Name "Selene" -Action {
        & selene .
    }

    Invoke-Step -Name "Luau analysis (luau-lsp $(& luau-lsp --version))" -Action {
        & luau-lsp analyze `
            --platform roblox `
            --definitions $definitionsPath `
            --sourcemap sourcemap.json `
            --settings .vscode/settings.json `
            @roots
    }

    Write-Host "All checks passed." -ForegroundColor Green
}
finally {
    Pop-Location
}

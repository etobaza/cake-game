[CmdletBinding()]
param([switch]$Refresh)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

# Zed's Luau extension normally downloads these itself. Keep a project-local copy so
# starting the editor does not depend on Zed's proxy or on another editor's installation.
$projectRoot = Split-Path -Parent $PSScriptRoot
$cacheDirectory = Join-Path $projectRoot ".zed\.cache"
$proxyDirectory = Join-Path $env:LOCALAPPDATA "Zed\extensions\work\luau\proxy-binaries\luau-lsp-proxy-v0.1.0"
New-Item -ItemType Directory -Path $cacheDirectory, $proxyDirectory -Force | Out-Null

$downloads = @{
    "globalTypes.PluginSecurity.d.luau" = "https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau"
    "api-docs.json" = "https://luau-lsp.pages.dev/api-docs/en-us.json"
}
foreach ($entry in $downloads.GetEnumerator()) {
    $destination = Join-Path $cacheDirectory $entry.Key
    if ($Refresh -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        $temporary = "$destination.download"
        Invoke-WebRequest -UseBasicParsing -Uri $entry.Value -OutFile $temporary
        Move-Item -LiteralPath $temporary -Destination $destination -Force
    }
}

$proxyPath = Join-Path $proxyDirectory "luau-lsp-proxy.exe"
if ($Refresh -or -not (Test-Path -LiteralPath $proxyPath -PathType Leaf)) {
    $archive = Join-Path $cacheDirectory "luau-lsp-proxy-0.1.0-windows-x86_64.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/4teapo/luau-lsp-proxy/releases/download/v0.1.0/luau-lsp-proxy-0.1.0-windows-x86_64.zip" -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $proxyDirectory -Force
    if (-not (Test-Path -LiteralPath $proxyPath -PathType Leaf)) {
        throw "Studio proxy was not found after extraction: $proxyPath"
    }
}

& (Join-Path $projectRoot ".vscode\generate-sourcemap.ps1")
Write-Host "Zed setup ready. Open a Luau file; Studio companion uses port 3668."

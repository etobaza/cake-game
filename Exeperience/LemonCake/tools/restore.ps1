param(
    [string]$GameRoot = "C:/Program Files (x86)/Steam/steamapps/common/Lemon Cake"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0
$researchRoot = Split-Path -Parent $PSScriptRoot
$cacheRoot = Join-Path $researchRoot ".local"
$pak = Join-Path $GameRoot "LemonCake/Content/Paks/LemonCake-WindowsNoEditor.pak"
if (-not (Test-Path -LiteralPath $pak)) { throw "Lemon Cake PAK not found: $pak" }
$fingerprint = Get-Content (Join-Path $researchRoot "data/build.json") -Raw | ConvertFrom-Json
$actualHash = (Get-FileHash -LiteralPath $pak -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $fingerprint.pak.sha256) {
    throw "Installed PAK differs from the documented build. Create a separate build snapshot before extraction."
}
$toolRoot = Join-Path $cacheRoot "tools"
New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
$archive = Join-Path $toolRoot "repak.zip"
$expected = "6720d602144d75df477a99d5bedb6ea780997546afc335901d4937cafeaa73fa"
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest "https://github.com/trumank/repak/releases/download/v0.2.3/repak_cli-x86_64-pc-windows-msvc.zip" -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw "repak v0.2.3 archive SHA256 mismatch."
}
$repak = Join-Path $toolRoot "repak/repak.exe"
if (-not (Test-Path -LiteralPath $repak)) {
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $toolRoot "repak") -Force
}
$unpacked = Join-Path $cacheRoot "unpacked"
if (-not (Test-Path -LiteralPath $unpacked)) {
    & $repak unpack $pak -o $unpacked -q
    if ($LASTEXITCODE -ne 0) { throw "repak extraction failed: $LASTEXITCODE" }
}
# An existing extraction is hash-checked before trusting it or rebuilding derived indexes.
Import-Csv (Join-Path $researchRoot "data/files.csv") | ForEach-Object {
    $file = Join-Path $unpacked $_.path
    if (-not (Test-Path -LiteralPath $file)) { throw "Extraction incomplete: $file" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $_.sha256) {
        throw "Extracted file differs: $file"
    }
}
& dotnet restore (Join-Path $PSScriptRoot "AssetDump") --locked-mode --nologo
if ($LASTEXITCODE -ne 0) { throw "Locked package restore failed: $LASTEXITCODE" }
& dotnet run --project (Join-Path $PSScriptRoot "AssetDump") --no-restore -- (Join-Path $unpacked "LemonCake/Content") (Join-Path $cacheRoot "json") VER_UE4_24
if ($LASTEXITCODE -ne 0) { throw "UAssetAPI export failed: $LASTEXITCODE" }
& python (Join-Path $PSScriptRoot "index_assets.py")
if ($LASTEXITCODE -ne 0) { throw "Evidence indexing failed: $LASTEXITCODE" }
& python (Join-Path $PSScriptRoot "catalogs.py")
if ($LASTEXITCODE -ne 0) { throw "Catalog generation failed: $LASTEXITCODE" }
& python (Join-Path $PSScriptRoot "verify.py") --game-root $GameRoot
if ($LASTEXITCODE -ne 0) { throw "Evidence verification failed: $LASTEXITCODE" }

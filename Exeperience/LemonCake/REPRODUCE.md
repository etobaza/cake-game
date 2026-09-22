# Reproduction and targeted lookup

Run all commands from `D:/Github/Rojo/cake-game`. The tools read the installed game and write only under `Exeperience/LemonCake`. They do not launch the game, modify the PAK, or touch user saves.

## Existing data

```powershell
python Exeperience/LemonCake/tools/query.py recipe LemonCake
python Exeperience/LemonCake/tools/query.py item Flour
python Exeperience/LemonCake/tools/query.py shop Oven
python Exeperience/LemonCake/tools/query.py bonus QuickBake
python Exeperience/LemonCake/tools/query.py asset BP_KitchenOven
python Exeperience/LemonCake/tools/query.py function GainExperience
python Exeperience/LemonCake/tools/query.py default BP_DailyCycle
```

Search is case-insensitive and prints a limited number of matches. Increase `--limit` when needed. Original row IDs and field names remain unchanged.

To inspect a bytecode function:

```powershell
python Exeperience/LemonCake/tools/query.py code BP_Client --function ExecuteUbergraph_BP_Client --start 636 --limit 13
rg -n 'BurnedCookTime' Exeperience/LemonCake/.local/readable
rg -n 'SaveGameToSlot' Exeperience/LemonCake/.local/readable
```

`--start` is the top-level instruction index; `@...` in the output is its Kismet byte offset. These are different values. The JSON AST preserves every node form; the text renderer is a reading aid, not compilable C++/Luau.

## Restoring the complete local database

Requirements: PowerShell, Python 3.11+ (`hashlib.file_digest`), .NET SDK 10, and an installed game matching the SHA256 in [build.json](data/build.json). The first run needs internet access for portable repak and NuGet. Wally/Rokit and the Roblox runtime are not involved.

```powershell
./Exeperience/LemonCake/tools/restore.ps1
```

For a different Steam library:

```powershell
./Exeperience/LemonCake/tools/restore.ps1 -GameRoot 'D:/SteamLibrary/steamapps/common/Lemon Cake'
```

The script checks the PAK fingerprint and repak ZIP checksum, extracts 11,123 files, compares them with the recorded SHA256 hashes, restores pinned NuGet dependencies, parses game packages, and generates indexes/catalogs. Final verification also checks that installed game files are unchanged. If the local extraction is incomplete or modified, the script stops with the exact path; it does not delete directories automatically.

An installed build with a different hash is not silently accepted. A new version requires a separate snapshot, updated fingerprints, and a comparison of results.

## Individual stages

```powershell
dotnet build Exeperience/LemonCake/tools/AssetDump --nologo
dotnet run --no-build --project Exeperience/LemonCake/tools/AssetDump -- Exeperience/LemonCake/.local/unpacked/LemonCake/Content Exeperience/LemonCake/.local/json VER_UE4_24
python Exeperience/LemonCake/tools/index_assets.py
python Exeperience/LemonCake/tools/catalogs.py
python Exeperience/LemonCake/tools/verify.py
```

`AssetDump` accepts a fourth argument: a path substring for focused investigation. Run that extraction **into a different output directory**: each run creates its own `parse-report.json`, and a partial report must not replace the complete one.

## Formats

| Path | Purpose |
| --- | --- |
| `data/build.json` | Build identity, tools, hashes of installed files |
| `data/files.csv` | Every PAK entry: path, bytes, SHA256 |
| `data/assets.jsonl` | Export classes and imported packages for each game asset |
| `data/functions.jsonl` | Functions, instruction counts, static calls |
| `data/defaults.jsonl` | Serialized defaults of gameplay Blueprint classes |
| `data/enums.json` | Exact enum ID → display label |
| `data/tables.json` | Catalog of all tables, schemas, and output paths |
| `data/tables/*.json` | Tabular data for queries |
| `data/curves.json` | Gameplay curves with preserved keys/tangents |
| `data/save-schema.json` | SaveGame fields and types |
| `data/map-gameplay-objects.json` | Placed gameplay actors and their overrides |
| `data/coverage.json`, `data/verification.json` | Parsing coverage and verification actually performed |
| `.local/unpacked` | Full PAK extraction, including Engine resources and localization |
| `.local/json` | Complete UAssetAPI JSON for all gameplay packages |
| `.local/bytecode`, `.local/readable` | ASTs and readable output for 914 functions |
| `.local/map-objects.json` | 1,946 selected level exports with component references |
| `.local/property-schemas.json` | Blueprint fields, including function parameters |
| `.local/tables`, `.local/string-tables` | Complete local dialogue, notifications, and string table |

The simplified tables resolve UObject references through import/export indexes and enum display maps. User-defined struct suffixes such as `_35_<GUID>` are removed only from convenient field names; the complete original remains in `.local/json`. `textKey` is stored with its table reference; it is not a translation. UAssetAPI sometimes writes floating-point zero as the string `"+0"`; this representation is preserved rather than hidden by an incorrect conversion.

Class defaults contain only serialized fields: an absent field cannot be declared `false`/`0` on that basis. Also check inheritance, level overrides, and Blueprint assignments.

## Verifier coverage

The verifier checks package/table/function counts, uniqueness of key row IDs, absence of RawExport entries and errors, bytecode size agreement, SHA256 of every extracted and installed game file, JSON readability, and local Markdown links. Results are saved to `data/verification.json`.

The verifier does not simulate Unreal Engine, check every control-flow branch, or establish visual/audio correctness. The Luau gate was not run: this work did not modify Roblox source.

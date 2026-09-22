# Lemon Cake research database

Static analysis of installed Steam build **6596857**, dated **2026-09-22**, prepared to support future work on cake-game. This examines files, data, and executable Blueprint bytecode; it is not a recovered source project or a runtime playthrough.

## Extracted coverage

| Area | Coverage |
| --- | ---: |
| PAK files, with paths, sizes, and SHA256 hashes | 11,123 |
| Game `.uasset` / `.umap` packages | 4,511 |
| Blueprint functions, ASTs, and instruction offsets | 914 |
| Tables / rows | 15 / 623 |
| Recipes / items | 42 / 98 |
| Purchases / menu bonuses | 48 / 13 |
| Appearance records / tutorial steps | 105 / 21 |
| Exported level objects of selected types | 1,946 |

All game packages passed the parser without exceptions or `RawExport` entries; computed sizes matched recorded sizes for all 914 functions. This confirms coverage and structural consistency, but does not verify every branch in the game. Full results: [coverage.json](data/coverage.json), [verification.json](data/verification.json).

However, **7,677 exports** retain a binary remainder in `Extras`, totaling **243,925,387 bytes**. These bytes are preserved but not all are semantically decoded; they include specialized resource payloads and serialization tails. Zero `RawExport` entries does not mean complete recovery of geometry, audio, or native code.

## Where to look

| Question | Material |
| --- | --- |
| How gameplay systems work | [SYSTEMS.md](SYSTEMS.md) |
| Exact formulas, thresholds, and bytecode offsets | [FORMULAS.md](FORMULAS.md) |
| Ingredients, prices, timing, dietary flags | [RECIPES.md](RECIPES.md), [table](data/tables/DAT_Recipe.json) |
| Purchases and prices | [UPGRADES.md](UPGRADES.md), [table](data/tables/DAT_Shop.json) |
| World, ingredient sources, instances | [WORLD.md](WORLD.md) |
| Assets, Blueprint owners, dependencies | [ASSET_MAP.md](ASSET_MAP.md) |
| Saving, settings, UI | [SAVE_UI.md](SAVE_UI.md) |
| Where a mechanic belongs in cake-game | [ROBLOX_MAPPING.md](ROBLOX_MAPPING.md) |
| Repeat extraction or retrieve a specific function | [REPRODUCE.md](REPRODUCE.md) |
| Sources, version, evidence limits | [SOURCES.md](SOURCES.md), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| Brief memory for the next chat | [mem/lemon-cake.md](../../mem/lemon-cake.md) |

## Storage layout

`data/` contains portable indexes, tables, schemas, and fingerprints. `tools/` contains custom reproducible tools. `.local/` contains the full extraction of original resources, UAssetAPI JSON, decoded ASTs, readable instructions, and dialogue. `.local/` is excluded from Git; it is available on the current machine and can be restored from the same game build.

Original binary assets have not been embedded in the Roblox project. The indexes describe them for research. Lemon Cake facts and adaptation recommendations are kept separate; Roblox balance changes are outside this work.

## Quick search

From the repository root:

```powershell
python Exeperience/LemonCake/tools/query.py recipe LemonCake
python Exeperience/LemonCake/tools/query.py shop Oven
python Exeperience/LemonCake/tools/query.py function GainExperience
python Exeperience/LemonCake/tools/query.py default BP_DailyCycle
rg -n 'Patience|BurnedCookTime' Exeperience/LemonCake/.local/readable
```

# Lemon Cake: notes for the next session

Research dated **2026-09-22**. [Main index](../Exeperience/LemonCake/README.md).

- Steam app `1338330`, installed build `6596857`, UE `4.24`, CL `11590370`. [Fingerprint](../Exeperience/LemonCake/data/build.json).
- The PAK was fully extracted: **11,123 files**. Game Content: **4,511 packages**, **914 Blueprint functions**, **15 tables / 623 rows**. No parse errors or RawExport entries; all 914 function lengths matched. This is static verification, not complete proof of correct decompilation.
- Catalogs: **42 recipes**, **98 items**, **48 purchases**, **13 menu bonuses**, **105 appearance records**, **21 tutorial steps**. One gameplay level: `LVL_Game`.
- Start with [RECIPES](../Exeperience/LemonCake/RECIPES.md), [UPGRADES](../Exeperience/LemonCake/UPGRADES.md), [SYSTEMS](../Exeperience/LemonCake/SYSTEMS.md), [formulas](../Exeperience/LemonCake/FORMULAS.md), and the [Roblox ownership map](../Exeperience/LemonCake/ROBLOX_MAPPING.md).
- Exact values: `Exeperience/LemonCake/data/tables/*.json`. Defaults: `data/defaults.jsonl`; level overrides: `data/map-gameplay-objects.json`. Do not treat a default as the final runtime value.
- Complete local database: `Exeperience/LemonCake/.local/{unpacked,json,bytecode,readable}`. It is ignored by Git and remains on this machine. [Restoration](../Exeperience/LemonCake/REPRODUCE.md) reads the installed game and verifies SHA256 hashes.
- Search from the repository root: `python Exeperience/LemonCake/tools/query.py recipe LemonCake`; `python Exeperience/LemonCake/tools/query.py function Patience`; `rg -n 'BurnedCookTime' Exeperience/LemonCake/.local/readable`.
- Function lookup: `python Exeperience/LemonCake/tools/query.py code BP_Client --function ExecuteUbergraph_BP_Client --start 636 --limit 13`.
- Key differences: the original changes stage length by level; cake-game uses a 480-second shift. In the original, `Patience` increases from 0 to 1, tips use a 0.2 coefficient, and XP is normalized by a curve. Roblox tuning differs.
- The original tip path contains `Divide_IntInt(BonusPercentage, 100)`. Do not mentally replace it with floating-point division or copy this behavior into Roblox without a user decision.
- Preserve the exact casing of `chocolatePancake`, `CherryBundtCake`, and row IDs such as `NewRow...`. A recipe row number is not its unlock level. Some original dietary flags are questionable, but they were extracted literally.
- The game was not launched. No walkthrough, frame/timing measurements, complete upgrade testing, or save/reload testing was performed. Original C++ and editor Blueprint graphs were not recovered. [Open questions](../Exeperience/LemonCake/OPEN_QUESTIONS.md).
- The parser preserves unread specialized payloads as `Extras`: 7,677 exports, 243,925,387 bytes. `RawExport=0` does not mean complete semantic decoding of every resource. `DAT_Recipe` has `chocolatePancake`, while `DAT_Item` has `ChocolatePancake`; preserve original spelling and account for UE FName case-insensitive matching.

This research did not modify Luau, Studio, or user saves. Existing working-tree changes were preserved.

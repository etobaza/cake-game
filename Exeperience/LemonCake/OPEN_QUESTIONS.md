# Limits and follow-up work

The available PAK was fully extracted, and all 4,511 game packages were machine-parsed. This does not mean the entire game has been recovered semantically and visually. All 914 functions are available for targeted analysis, but not every branch has been manually explained in the documentation.

The parser retained `Extras` in 7,677 exports, totaling 243,925,387 bytes of binary remainders. These include specialized resource payloads and serialization tails; the absence of `RawExport` must not be treated as evidence of complete decoding.

## Unverified areas

| Area | Available evidence | Required follow-up |
| --- | --- | --- |
| Full playthrough | Tables, class defaults, functions, tutorial steps | Use a new test slot; play the tutorial, a normal day, and mid/late progression |
| Tips and bonuses | `Divide_IntInt`, per-addition clamping, exact thresholds | Compare payments at bonuses 0, 50, 99, 100 and several waiting values |
| Timing and spawning | Stage/interval formulas, initial delay | Measure the first customer, morning/lunch/closing, pauses, and early closing |
| Menu unlocking | Learned/Unlocked/NewRecipes, UI branches, ingredient requirements | Trace every selection and slot condition; do not assign levels from recipe indexes |
| Upgrade tree | All 48 prices and IDs, purchase logic | Recover and verify every prerequisite and effect in `WBP_ShopSingle`/`WBP_ShopTree` branches |
| XP and ranks | Normalized field, curve, UI functions | Check level-up overflow, displayed XP, rank history, and the late-game cap |
| Oven / freezer / mixer | Exact tables and timer/cooking branches | Measure the complete cycle, fuel consumption, pauses, collection at tick boundaries, and all upgrades |
| Garden and care | Each spawner's overrides, watering/brushing branches | Measure capacity, drying, stopping/resuming, fertilizer, and automatic watering |
| Assistant / cats | Functions, defaults, static rewards | Check assistant task ordering, path failures, adoption conditions, and caps |
| Minigame / bedroom | Classes, enums, dialogue, save fields | Check triggers, duration, rewards, and the complete event sequence |
| UI and visual assets | Widget exports, archived models/materials/textures | Inspect screens, animations, scale/occlusion, and mesh/texture previews |
| Audio | All paths and extracted resources | Listen to audio; check mixing and actual triggers |
| Translations | Original keys, string table, localized files | Decode and compare all `.locres` files |
| Save/Steam | SaveGame schema, API calls, fingerprints | Test save/reload, slot changes, and Steam achievements/Cloud at runtime |
| Native EXE | Files, SHA256, UE build strings | C++/engine machine code was not fully decompiled; original source was not recovered |

## Continuing without repeating the extraction

Find the owner in [ASSET_MAP.md](ASSET_MAP.md), then locate its function in `data/functions.jsonl` and `.local/readable`. For `ExecuteUbergraph_*` branches, a small event function typically passes an entry point into the shared graph: open both files and match offsets. The readable renderer leaves unsupported forms as JSON rather than inventing high-level source code.

If `.local` is missing, follow [REPRODUCE.md](REPRODUCE.md). If the game's SHA256 has changed, create a separate build snapshot and compare it with this database. Do not overwrite old findings with new numbers without identifying the version.

Runtime verification requires an available interface for controlling the Windows game. Native computer APIs were disabled in the research session, so no playthrough was performed. Existing saves and cloud data should not be used as disposable test material.

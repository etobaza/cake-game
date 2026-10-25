# Mapping to cake-game

This is navigation for future changes. The research does not change Luau, balance, or ownership rules. [ARCHITECTURE.md](../../ARCHITECTURE.md) defines the architecture. Source was inspected on 2026-09-22 in an already modified working tree; this mapping is not tied to a clean Git commit.

## Where each mechanic belongs

| Lemon Cake | cake-game: existing owner / configuration |
| --- | --- |
| `BP_DailyCycle` | `ServerScriptService/Handlers/DayCycleHandler.luau`, `Shared/Configs/DayCycle.luau` |
| Daily overview / statistics | `DayReportHandler.luau`, `Configs/DayReport.luau`, client `ReportHandler`, `HudHandler` |
| `DAT_Recipe`, `DAT_Item` | `ReplicatedStorage/Shared/Configs/Registries/Recipes.luau`, `Ingredients.luau`, `Products.luau` |
| Oven, mixer, freezer | `ServerScriptService/Handlers/BuildingHandler`, `Configs/Buildings.luau`, `OvenFuel.luau`, `MixerInteraction.luau` |
| Plants and animals | `BuildingHandler/GardenCare.luau`, `GardenWorld.luau`, `GardenSave.luau`, `Kinds/GardenNode.luau`, `Configs/Garden.luau` |
| Customers | `ServerScriptService/Handlers/CustomerHandler`, `CustomerViewHandler`, `Configs/Orders.luau`, `DisplayCustomers.luau`, `TableMenus.luau` |
| Displays and tables | `DisplayHandler.luau`, `TableHandler.luau`, existing building kinds |
| Rewards and XP | `EconomyHandler.luau`, `Configs/Economy.luau`, `Progression.luau`, `Rewards.luau` |
| Upgrades | `UpgradeHandler.luau`, `UpgradeViewHandler.luau`, `Configs/Registries/Upgrades.luau`, `UpgradeTree.luau` |
| Assistant and cats | Server `AssistantHandler.luau`, `CatHandler.luau`, `Configs/Cats.luau`; client `CatHandler.luau` |
| SaveGame | `DataHandler`, `DataHandlerClient` / `DataClient`; existing Cloud/Session templates |
| HUD / menu / controls | `UIHandler`, authored `StarterGui.MainGui`, `MenuHandler`, `RecipePickHandler`, `InteractHandler`, `RunHandler` |
| Tutorial | Server and client `TutorialHandler`, `Configs/Tutorial.luau`, `TutorialEvents` |
| World | `Shared/World.luau`, place-only `Workspace.World`, templates in `ReplicatedStorage.Assets.Models` |

`Shared/...` in this table means `ReplicatedStorage/Shared/...`. These directories are starting points for inspection, not permission to import another game's architecture. Read the complete owning handler and an adjacent implementation before editing.

## Existing differences

The inspected source confirms:

- The Recipes registry is described as 42 Lemon Cake rows plus coffee as a cake-game extension. `unlockLevel`, mixer timing, and freezer timing are explicitly adaptations. Preserve Roblox stable IDs: the original `FrenchBaguette` corresponds to the local `bread` entry, so registry keys must not be renamed to Steam IDs.
- `Configs/DayCycle` follows the `BP_DailyCycle` formulas: Morning and Lunch each last `100 + 2.5 × Level` seconds (**08:00–12:00–16:00**), and arrivals come every `15 × (0.95 − 0.01 × Level)` seconds at lunch and 2.5 times that in the morning, times the display-flow multiplier (0.5–2). The original restarts its spawn timer at each stage (first fire after 0.2 of the period); here the morning's first guest uses `FirstSpawnDelay` and lunch brings the pending arrival forward to 0.2 of the lunch gap. `MenuMin=3`, `MenuMax=5`; admission stops 5 game-clock minutes before closing.
- Retained adaptations: prep is untimed (the original's Start Day stage runs one stage length), the shift's first guest arrives after 0.5 seconds, an empty bakery calls its next guest within 1.5 seconds, the closing wait cuts off a protected or stuck guest after 30 seconds and everyone after 240, and the day report opens once the last guest leaves, as the original's 3-second `CheckClients` timer does.
- `Configs/Economy`: `TipFraction=0.35`, `TipPatienceFloor=0.2`, `XPPerCoin=0.35`, `XPMinPerDish=2`, a separate completion reward, and a lost-customer penalty. The original 0.2 and `Value×3` use different units and formulas.
- Upgrades (`Configs/Registries/Upgrades`, `Configs/UpgradeTree`): every purchase sits in its `DAT_Shop` cell, and prices are the design sheet's ×100, which matches Lemon Cake ×100 except Two Seats & Table (290.50 vs 235.5), Assistant (500 vs 525.5), Firewood Upgrade (22.25 vs 17.5) and the first Oven (85.75 vs 65.75). Not built: Outfit Upgrade, Magic Broom (Kitchen #11) and the whole Bedroom tab. Speed Boost's run-speed effect sits on the Quick Sprint node (#9), as there is no sprint stamina to recharge. Changed effects: Kitchen Counter makes the mixer 25% faster instead of adding a place-items counter; Cat Cafe also adds +25% tips per level; Coffee Machine adds coffee as a menu dish instead of resetting seated guests' patience; the Assistant has no world character and works the window, coffee, tables and display on an 8-second interval. The tree prerequisites are cake-game's own, since `WBP_ShopTree` was not recovered.
- The `bread` example has `burnSeconds=15`. The original oven defaults to `BurnedCookTime=30`, upgraded to 60. Do not substitute one for the other without an agreed balance task.

## Using this research

1. To reproduce behavior, choose a specific build and source Blueprint path first; check table → default → map override → runtime mutation.
2. Coins, XP, purchases, items, and customer outcomes remain server-authoritative in Roblox. The single-player `BP_Player` must not become client authority.
3. Use the current Crystal `OnInit` / `OnStart`, Packet Bus, DataHandler proxies, and DataList. Unreal SaveGame does not replace ProfileStore.
4. Drive existing UI through `UIHandler:GetPanel/GetHud` and resolve the existing world through `Shared/World.luau`.
5. Steam data is reference material; original meshes, textures, and music are not automatically added to Roblox assets.
6. After actual Luau changes, run the mandatory project gate and exercise the scenario in Studio. This research has only static and documentation verification.

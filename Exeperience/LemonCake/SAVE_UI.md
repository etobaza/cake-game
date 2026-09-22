# Saves, UI, and settings

Sources are Blueprints and configuration from build `6596857`; user save files were neither read nor modified. The game was not launched.

## Saving

`Blueprints/Player/SV_SaveGame.uasset` contains progress, appearance, and settings fields. The complete schema, including types and original outer references, is in [save-schema.json](data/save-schema.json). Repeated names can describe an array's inner element rather than a second independent variable.

| Group | Fields / examples |
| --- | --- |
| Player and progression | `SV_PlayerName`, `SV_Money`, `SV_Experience`, `SV_Level`, `SV_Day`, `SV_IsNewGame`, `SV_CompletedGame` |
| Menu and recipes | `SV_DailyRecipes`, `SV_LearnedRecipes`, `SV_NewRecipes`, `SV_RecipeActiveDays`, `SV_RecipeDayOldBonus`, `SV_BonusPercentage` |
| Upgrades | `SV_IsStoreUpgradePurchased`, `SV_IsKitchenUpgradePurchased`, `SV_IsGreenhouseUpgradePurchased`, `SV_IsBedroomUpgradePurchased` |
| Movement and customer flow | `SV_WalkSpeed`, `SV_SprintRecharge`, `SV_ClientMultiplier` |
| Minigame | `SV_DaysSinceMinigame`, `SV_TotalMinigamePlayed` |
| Achievements | `SV_ACVCatsAdopted`, `SV_ACVCoinsEarned`, `SV_ACVLevelReached`, `SV_ACVPerfectOrders`, `SV_ACVSpillsCleaned`, `SV_ACVSprintCounter` |
| Books and graphics | `SV_LibraryCurrentPage`, `SV_IsFogHidden`, `SV_DetailMode` |
| Audio / controls | `SV_MusicVolume`, `SV_SoundVolume`, `SV_ControlKeys`, `SV_ControlName` |
| Appearance | Skin, eyes, hairstyle/color, top/bottom, apron, hat, shoes, and their material/texture references |

`WBP_SaveGameSlot.ExecuteUbergraph_WBP_SaveGameSlot` uses `LoadGameFromSlot`, `SaveGameToSlot`, `DoesSaveGameExist`, and `DeleteGameInSlot`. The save call at `@6440` is `SaveGameToSlot(SV_SaveGame, SaveSlotName, 0)`. The slot name comes from `SaveSlotName`; do not substitute an invented filename. UE SaveGame calls are a separate mechanism from Roblox ProfileStore and its migration schema.

A `SaveGameToSlot` call in bytecode does not prove a successful disk write. Full save/reload and Steam Cloud behavior have not been tested. Steam Cloud support on the store page does not replace investigation of cloud-save conflicts.

## UI

Main widgets: `WBP_HUD`, `WBP_MainMenu`, `WBP_DailyOverview`, `WBP_Recipe`, `WBP_RecipeDaily`, `WBP_RecipeNew`, `WBP_Shop`, `WBP_ShopTree`, `WBP_ShopSingle`, `WBP_OrderAll`, `WBP_OrderSingle`, `WBP_Dialogue`, `WBP_PlayerCreation`, `WBP_SaveGame`, `WBP_SaveGameSlot`, `WBP_Options`, `WBP_Controls`, `WBP_Language`, `WBP_Library`, `WBP_MinigameTimer`.

The cooked JSON preserves widget exports, parameters, dependencies, and functions, including hover/click events and animations. They are available under `.local/json/Blueprints/Interface`; use `data/assets.jsonl` to find the relevant package. Visual layout was not verified by rendering. Descriptions of widget names must not be presented as captured screenshots of finished screens.

`DefaultEngine.ini` specifies the `WBP_Cursor` software cursor, the `ShortestSide` UI scale rule, and the `LVL_Game` startup map. Configuration references the template `ThirdPersonGameMode`, while game Content contains `BP_GameMode` with `DefaultPawnClass=BP_Player`. Final GameMode resolution requires separate level inspection or a launch; a single configuration entry does not establish it.

## Controls and settings

Source: `.local/unpacked/LemonCake/Config/DefaultInput.ini`, corroborated by `SV_SaveGame` defaults.

| Action | Key |
| --- | --- |
| Movement | WASD; arrow-key axes also exist |
| Interact | SpaceBar |
| Sprint | LeftShift |
| Pause | Escape |
| Recipe 1–6 | One–Six |

`BP_Player` contains separate mouse input events. Complete click-to-move behavior and key combinations were not tested. Save defaults: music 0.5, sound 0.5, detail mode 2, `ClientMultiplier=1`. Input definitions in files do not prove compatibility with a particular controller.

## Text and tutorial

`DAT_Tutorial` contains 21 rows: step number, text/text reference, arrow visibility, and coordinates. Complete table: [DAT_Tutorial.json](data/tables/DAT_Tutorial.json). Tutorial, shop, new-recipe, daily-summary, ending, and minigame dialogue is under `.local/tables/`. All 15 tables and their row counts are listed in [tables.json](data/tables.json).

One `StringTableExport` is saved under `.local/string-tables/`. In a simplified table, `textKey` is a key accompanied by `table`, not an automatically resolved translation. Localized `.locres` resources remain in the full extraction; translations for every language have not been decoded or manually verified.

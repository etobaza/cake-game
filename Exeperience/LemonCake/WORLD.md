# World and item sources

One level was found in game Content: `Level/LVL_Game.umap`. Complete local object export: `.local/map-objects.json`; gameplay objects: [map-gameplay-objects.json](data/map-gameplay-objects.json). Component coordinates are in the complete export, not the simplified table below.

`ENUM_Location` zones: Greenhouse, Kitchen, Store, Bedroom. Authored model names and tables do not replace visual map inspection.

## Placed BP_ItemSpawner instances

The values below are level overrides. The base `SpawnTimer=10` must not be applied to every plant: the level overrides it. An initial `IsUnlocked=false` also does not mean the source remains locked after the tutorial or loading.

| Actor | ItemToSpawn | SpawnTimer | IsPlant | Tags |
| --- | --- | ---: | --- | --- |
| `BP_ItemSpawner10` | Apple | 15.0 | True | ShopAppleTree, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner11` | Carrot | 15.0 | True | ShopCarrotPlant, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner12_2` | Lemon | 15.0 | True | ShopLemonTree, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner13_2` | Egg | 3.0 | False | ShopChickens |
| `BP_ItemSpawner14_5` | Cocoa | 15.0 | True | ShopCocoaTree, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner15` | Cherry | 15.0 | True | ShopCherryTree, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner16` | Firewood | 1.0 | False | BaseItemSpawner |
| `BP_ItemSpawner17` | Honey | 5.0 | False | ShopHoney, ShopFertilizerUpgrade |
| `BP_ItemSpawner3` | Strawberry | 15.0 | True | ShopStrawberryPlant, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner5` | Flour | 3.0 | False | Tutorial05, BaseItemSpawner |
| `BP_ItemSpawner6` | Milk | 3.0 | False | ShopCow |
| `BP_ItemSpawner7` | Sugar | 3.0 | False | BaseItemSpawner |
| `BP_ItemSpawner8` | Grape | 15.0 | True | ShopGrapeVine, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner9` | Blueberry | 15.0 | True | ShopBlueberryPlant, ShopFertilizerUpgrade, SprinklersPlant |
| `BP_ItemSpawner_2` | Coffee | 2.0 | False | ShopCoffeeMachine |

## Gameplay object counts by class

These are placed-object counts, not counts of simultaneously active or available objects.

| Class | Count |
| --- | ---: |
| `BP_Bed_C` | 1 |
| `BP_BedroomTable_C` | 1 |
| `BP_Library_C` | 1 |
| `BP_Wardrobe_C` | 1 |
| `BP_DailyCycle_C` | 1 |
| `BP_Chicken_C` | 1 |
| `BP_Coww_C` | 1 |
| `BP_Counter_C` | 4 |
| `BP_Freezer_C` | 1 |
| `BP_Garbage_C` | 1 |
| `BP_ItemRailSpawner_C` | 1 |
| `BP_ItemSpawner_C` | 15 |
| `BP_KitchenMixer_C` | 1 |
| `BP_KitchenOven_C` | 3 |
| `BP_RecipeBook_C` | 1 |
| `BP_Spill_C` | 3 |
| `BP_SpillSpawner_C` | 1 |
| `BP_Location_C` | 1 |
| `BP_BugMinigame_C` | 1 |
| `BP_BugSpawner_C` | 3 |
| `BP_Music_C` | 1 |
| `BP_Player_C` | 1 |
| `BP_TutorialArrow_C` | 1 |
| `BP_CatCafe_C` | 1 |
| `BP_ClientChair_C` | 4 |
| `BP_ClientDish_C` | 4 |
| `BP_ClientSpawner_C` | 1 |
| `BP_StoreCounter_C` | 5 |

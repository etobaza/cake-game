# Мир и источники предметов

В игровом Content найден один уровень: `Level/LVL_Game.umap`. Полная локальная выгрузка объектов: `.local/map-objects.json`; игровые объекты: [map-gameplay-objects.json](data/map-gameplay-objects.json). Координаты компонентов находятся в полной выгрузке, а не в сокращённой таблице ниже.

Зоны enum `ENUM_Location`: Greenhouse, Kitchen, Store, Bedroom. Авторские модельные названия и таблицы не заменяют визуальную проверку карты.

## Размещённые BP_ItemSpawner

Значения ниже — overrides уровня. Базовый `SpawnTimer=10` не следует применять ко всем растениям: на уровне он заменён. Начальный `IsUnlocked=false` также не означает, что источник останется закрытым после обучения/загрузки.

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

## Количество игровых объектов по классу

Это число размещённых объектов, не число одновременно активных или доступных объектов.

| Класс | Количество |
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

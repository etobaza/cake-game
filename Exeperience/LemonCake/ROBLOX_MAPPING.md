# Связь с cake-game

Это навигация для будущих изменений. Исследование не меняет Luau, баланс или правила владения. Источник архитектуры — [ARCHITECTURE.md](../../ARCHITECTURE.md), исходники просмотрены 2026-09-22 в существовавшем изменённом рабочем дереве; таблица не привязана к чистому Git-коммиту.

## Куда идти с механикой

| Lemon Cake | cake-game: существующий владелец / конфигурация |
| --- | --- |
| `BP_DailyCycle` | `ServerScriptService/Handlers/DayCycleHandler.luau`, `Shared/Configs/DayCycle.luau` |
| Daily overview / статистика | `DayReportHandler.luau`, `Configs/DayReport.luau`, клиентские `ReportHandler`, `HudHandler` |
| `DAT_Recipe`, `DAT_Item` | `ReplicatedStorage/Shared/Configs/Registries/Recipes.luau`, `Ingredients.luau`, `Products.luau` |
| Печь, миксер, морозильник | `ServerScriptService/Handlers/BuildingHandler`, `Configs/Buildings.luau`, `OvenFuel.luau`, `MixerInteraction.luau` |
| Растения и животные | `BuildingHandler/GardenCare.luau`, `GardenWorld.luau`, `GardenSave.luau`, `Kinds/GardenNode.luau`, `Configs/Garden.luau` |
| Клиенты | `ServerScriptService/Handlers/CustomerHandler`, `CustomerViewHandler`, `Configs/Orders.luau`, `DisplayCustomers.luau`, `TableMenus.luau` |
| Витрины и столы | `DisplayHandler.luau`, `TableHandler.luau`, существующие building kinds |
| Награды и XP | `EconomyHandler.luau`, `Configs/Economy.luau`, `Progression.luau`, `Rewards.luau` |
| Улучшения | `UpgradeHandler.luau`, `UpgradeViewHandler.luau`, `Configs/Registries/Upgrades.luau`, `UpgradeTree.luau` |
| Помощник и кошки | Серверные `AssistantHandler.luau`, `CatHandler.luau`, `Configs/Cats.luau`; клиентские одноимённые handlers |
| SaveGame | `DataHandler`, `DataHandlerClient` / `DataClient`; существующие Cloud/Session templates |
| HUD / меню / управление | `UIHandler`, authored `StarterGui.MainGui`, `MenuHandler`, `RecipePickHandler`, `InteractHandler`, `RunHandler` |
| Tutorial | Серверный и клиентский `TutorialHandler`, `Configs/Tutorial.luau`, `TutorialEvents` |
| Мир | `Shared/World.luau`, place-only `Workspace.World`, templates `ReplicatedStorage.Assets.Models` |

`Shared/...` в таблице — `ReplicatedStorage/Shared/...`. Названные папки — точки поиска, не разрешение переносить чужую архитектуру. Перед изменением нужно читать полный owning handler и смежную реализацию.

## Уже существующие отличия

Просмотренные исходники подтверждают:

- Registry Recipes описан как 42 строки Lemon Cake плюс coffee как отдельное расширение cake-game. `unlockLevel`, время миксера и морозильника явно являются адаптациями. Сохраняйте Roblox stable IDs; оригинальное `FrenchBaguette` соответствует local entry `bread`, поэтому нельзя переименовать registry по Steam ID.
- `Configs/DayCycle`: смена **480 секунд**, время **08:00–16:00**, `MenuMin=3`, `MenuMax=5`, admission прекращается за 5 игровых минут до закрытия. Оригинал имеет другую логику стадий и расчёт интервалов по уровню.
- `DayCycle.SpawnInterval=10` ссылается на default `BP_ClientSpawner`. Исследование показало, что оригинальный `BP_DailyCycle` далее заменяет `ClientDelayTimer`. Следовательно, 10 — осознанная настройка адаптации, а не полная формула Lemon Cake.
- `Configs/Economy`: `TipFraction=0.35`, `TipPatienceFloor=0.2`, `XPPerCoin=0.35`, `XPMinPerDish=2`, отдельная награда завершения и штраф потери клиента. Оригинальные 0.2 и `Value×3` относятся к другим единицам и другой формуле.
- В примере `bread` указано `burnSeconds=15`. В оригинале у печи default `BurnedCookTime=30`, после улучшения 60. Не подменять одно другим без согласованной задачи на баланс.

## Правила использования исследования

1. Для воспроизведения поведения сначала выберите конкретную сборку и исходный Blueprint-путь; проверьте table → default → map override → runtime mutation.
2. Решения о монетах, XP, покупках, предметах и клиентских результатах остаются на сервере Roblox. Однопользовательский `BP_Player` не переносится как клиентский авторитет.
3. Используйте текущие Crystal `OnInit` / `OnStart`, Packet Bus, DataHandler proxies и DataList. Unreal SaveGame не заменяет ProfileStore.
4. Существующий UI ведётся через `UIHandler:GetPanel/GetHud`, существующий мир — через `Shared/World.luau`.
5. Steam-данные служат референсом; исходные meshes, textures и музыка не добавляются в ассеты Roblox автоматически.
6. После реальных Luau-изменений выполняйте обязательный gate проекта и проверку сценария в Studio. Настоящее исследование имеет только статическую и документальную проверку.

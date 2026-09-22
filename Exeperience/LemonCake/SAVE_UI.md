# Сохранения, UI и настройки

Источник — Blueprint и конфигурация build `6596857`; пользовательские save-файлы не читались и не менялись. Игра не запускалась.

## Сохранение

Класс `Blueprints/Player/SV_SaveGame.uasset` содержит поля прогресса, внешности и настроек. Полная схема с типами и исходными outer-ссылками: [save-schema.json](data/save-schema.json). Повтор имени в этой схеме может означать внутреннее описание элемента массива, а не вторую независимую переменную.

| Группа | Поля / примеры |
| --- | --- |
| Игрок и прогресс | `SV_PlayerName`, `SV_Money`, `SV_Experience`, `SV_Level`, `SV_Day`, `SV_IsNewGame`, `SV_CompletedGame` |
| Меню и рецепты | `SV_DailyRecipes`, `SV_LearnedRecipes`, `SV_NewRecipes`, `SV_RecipeActiveDays`, `SV_RecipeDayOldBonus`, `SV_BonusPercentage` |
| Улучшения | `SV_IsStoreUpgradePurchased`, `SV_IsKitchenUpgradePurchased`, `SV_IsGreenhouseUpgradePurchased`, `SV_IsBedroomUpgradePurchased` |
| Движение и поток | `SV_WalkSpeed`, `SV_SprintRecharge`, `SV_ClientMultiplier` |
| Мини-игра | `SV_DaysSinceMinigame`, `SV_TotalMinigamePlayed` |
| Достижения | `SV_ACVCatsAdopted`, `SV_ACVCoinsEarned`, `SV_ACVLevelReached`, `SV_ACVPerfectOrders`, `SV_ACVSpillsCleaned`, `SV_ACVSprintCounter` |
| Книги и графика | `SV_LibraryCurrentPage`, `SV_IsFogHidden`, `SV_DetailMode` |
| Звук / управление | `SV_MusicVolume`, `SV_SoundVolume`, `SV_ControlKeys`, `SV_ControlName` |
| Внешность | skin, eye, hairstyle/color, top/bottom, apron, hat, shoes и их material/texture references |

`WBP_SaveGameSlot.ExecuteUbergraph_WBP_SaveGameSlot` использует `LoadGameFromSlot`, `SaveGameToSlot`, `DoesSaveGameExist`, `DeleteGameInSlot`. Вызов сохранения `@6440`: `SaveGameToSlot(SV_SaveGame, SaveSlotName, 0)`. Имя слота приходит из поля `SaveSlotName`; не подставляйте придуманное имя файла. Вызовы UE SaveGame — отдельный механизм от Roblox ProfileStore и его схемы миграций.

`SaveGameToSlot` в байткоде не доказывает успешную запись на диск. Полный save/reload и Steam Cloud не проверены. Декларация Steam Cloud на странице магазина не заменяет исследование конфликтов облачного сохранения.

## UI

Главные виджеты: `WBP_HUD`, `WBP_MainMenu`, `WBP_DailyOverview`, `WBP_Recipe`, `WBP_RecipeDaily`, `WBP_RecipeNew`, `WBP_Shop`, `WBP_ShopTree`, `WBP_ShopSingle`, `WBP_OrderAll`, `WBP_OrderSingle`, `WBP_Dialogue`, `WBP_PlayerCreation`, `WBP_SaveGame`, `WBP_SaveGameSlot`, `WBP_Options`, `WBP_Controls`, `WBP_Language`, `WBP_Library`, `WBP_MinigameTimer`.

В cooked JSON сохранены widget exports, параметры, зависимости и функции, включая hover/click events и анимации. Они доступны в `.local/json/Blueprints/Interface`; в `data/assets.jsonl` можно найти нужный пакет. Визуальная компоновка не проверялась рендером. Не выдавать описания имён виджетов за снятые скриншоты готовых экранов.

`DefaultEngine.ini` задаёт software cursor `WBP_Cursor`, UI scale rule `ShortestSide` и стартовую карту `LVL_Game`. В конфигурации есть ссылка на шаблонный `ThirdPersonGameMode`, а игровой Content содержит `BP_GameMode` с `DefaultPawnClass=BP_Player`. Итоговое разрешение GameMode требует отдельного чтения уровня/запуска; по одной конфигурационной строке его не объявляем установленным.

## Управление и настройки

Источник: `.local/unpacked/LemonCake/Config/DefaultInput.ini`, подтверждённые defaults `SV_SaveGame`.

| Действие | Клавиша |
| --- | --- |
| Движение | WASD; также оси стрелок |
| Interact | SpaceBar |
| Sprint | LeftShift |
| Pause | Escape |
| Recipe 1–6 | One–Six |

В `BP_Player` есть отдельные mouse input events. Полная доступность click-to-move и сочетаний не тестировалась. Save defaults: music 0.5, sound 0.5, detail mode 2, `ClientMultiplier=1`. Наличие управления в файлах не доказывает совместимость конкретного контроллера.

## Тексты и обучение

`DAT_Tutorial` содержит 21 строку: номер шага, текст/ссылку на текст, флаг стрелки и координаты. Полная таблица: [DAT_Tutorial.json](data/tables/DAT_Tutorial.json). Диалоги tutorial, магазина, нового рецепта, итогов дня и завершения, а также диалоги мини-игры находятся в `.local/tables/`. Каталог всех 15 таблиц с количеством строк: [tables.json](data/tables.json).

Один `StringTableExport` сохранён в `.local/string-tables/`. Значение `textKey` в сокращённой таблице — ключ вместе с `table`, а не автоматически разрешённый перевод. Локализованные ресурсы `.locres` остаются в полной распаковке; переводы всех языков не декодированы и не проверены вручную.

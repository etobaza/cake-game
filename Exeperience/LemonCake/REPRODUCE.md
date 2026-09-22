# Воспроизведение и точечный поиск

Все команды выполняются из корня `D:/Github/Rojo/cake-game`. Рабочие инструменты читают установленную игру; записи идут только в `Exeperience/LemonCake`. Они не запускают игру, не меняют PAK и не трогают пользовательские сохранения.

## Готовые данные

```powershell
python Exeperience/LemonCake/tools/query.py recipe LemonCake
python Exeperience/LemonCake/tools/query.py item Flour
python Exeperience/LemonCake/tools/query.py shop Oven
python Exeperience/LemonCake/tools/query.py bonus QuickBake
python Exeperience/LemonCake/tools/query.py asset BP_KitchenOven
python Exeperience/LemonCake/tools/query.py function GainExperience
python Exeperience/LemonCake/tools/query.py default BP_DailyCycle
```

Поиск регистронезависимый и выводит ограниченное число совпадений. Увеличивайте `--limit`, если нужно. Оригинальные row IDs и названия полей при этом не меняются.

Для функции с байткодом:

```powershell
python Exeperience/LemonCake/tools/query.py code BP_Client --function ExecuteUbergraph_BP_Client --start 636 --limit 13
rg -n 'BurnedCookTime' Exeperience/LemonCake/.local/readable
rg -n 'SaveGameToSlot' Exeperience/LemonCake/.local/readable
```

`--start` — индекс top-level инструкции, а `@...` в выводе — её Kismet byte offset. Это разные величины. JSON AST сохраняет все формы узлов; текстовый renderer — вспомогательное чтение, не компилируемый C++/Luau.

## Полное восстановление локальной базы

Требования: PowerShell, Python 3.11+ (`hashlib.file_digest`), .NET SDK 10, установленная игра с SHA256 из [build.json](data/build.json). Для первого запуска нужен интернет для portable repak и NuGet. Wally/Rokit и Roblox runtime здесь не участвуют.

```powershell
./Exeperience/LemonCake/tools/restore.ps1
```

При другой Steam library:

```powershell
./Exeperience/LemonCake/tools/restore.ps1 -GameRoot 'D:/SteamLibrary/steamapps/common/Lemon Cake'
```

Скрипт проверяет fingerprint PAK, checksum repak ZIP, распаковывает 11 123 файла, сверяет их с сохранёнными SHA256, восстанавливает закреплённые NuGet dependencies, разбирает игровые пакеты и генерирует индексы/каталоги. Итоговая проверка также убеждается, что установленные файлы игры остались прежними. Если локальная распаковка неполная или изменилась, скрипт останавливается с точным путём; он не удаляет каталоги автоматически.

Установленная сборка с другим hash не принимается молча. Для новой версии нужен отдельный snapshot, обновлённые fingerprints и сравнение результатов.

## Отдельные стадии

```powershell
dotnet build Exeperience/LemonCake/tools/AssetDump --nologo
dotnet run --no-build --project Exeperience/LemonCake/tools/AssetDump -- Exeperience/LemonCake/.local/unpacked/LemonCake/Content Exeperience/LemonCake/.local/json VER_UE4_24
python Exeperience/LemonCake/tools/index_assets.py
python Exeperience/LemonCake/tools/catalogs.py
python Exeperience/LemonCake/tools/verify.py
```

`AssetDump` поддерживает четвёртый аргумент — подстроку пути для узкого исследования. Запускайте такой разбор **в другой output-каталог**: каждый запуск создаёт свой `parse-report.json`; частичный отчёт не должен заменить полный.

## Форматы

| Путь | Назначение |
| --- | --- |
| `data/build.json` | Идентичность сборки, инструменты, hashes установленных файлов |
| `data/files.csv` | Каждая запись PAK: path, bytes, SHA256 |
| `data/assets.jsonl` | Классы экспортов и импортируемые пакеты каждого игрового ассета |
| `data/functions.jsonl` | Функции, число инструкций, статические вызовы |
| `data/defaults.jsonl` | Сериализованные defaults игровых Blueprint-классов |
| `data/enums.json` | Точное enum ID → display label |
| `data/tables.json` | Каталог всех таблиц, схемы и пути результатов |
| `data/tables/*.json` | Табличные данные для запросов |
| `data/curves.json` | Игровые кривые с сохранением ключей/tangents |
| `data/save-schema.json` | Поля SaveGame и типы |
| `data/map-gameplay-objects.json` | Размещённые игровые акторы и их overrides |
| `data/coverage.json`, `data/verification.json` | Покрытие парсинга и реально выполненная проверка |
| `.local/unpacked` | Полная распаковка PAK, включая Engine resources и локализацию |
| `.local/json` | Полные UAssetAPI JSON всех игровых пакетов |
| `.local/bytecode`, `.local/readable` | AST и читаемое представление 914 функций |
| `.local/map-objects.json` | 1 946 выбранных exports уровня с component references |
| `.local/property-schemas.json` | Поля Blueprint, включая параметры функций |
| `.local/tables`, `.local/string-tables` | Полные локальные диалоги, уведомления и string table |

Сокращённые таблицы разрешают ссылки на UObject через import/export index и enum display map. User-defined struct suffix вида `_35_<GUID>` удаляется только в удобных именах полей; полный оригинал сохраняется в `.local/json`. `textKey` хранится вместе с таблицей; это не перевод. UAssetAPI иногда записывает float zero как строку `"+0"`; она сохраняется, а не маскируется ложным преобразованием.

Class defaults содержат только сериализованные поля: отсутствие поля не даёт права объявить его `false`/`0`. Дополнительно проверяйте наследование, overrides уровня и присваивания в Blueprint.

## Что проверяет verifier

Согласованность числа пакетов/таблиц/функций, уникальность ключевых row IDs, отсутствие RawExport и ошибок, совпадение размеров байткода, SHA256 каждого распакованного файла и каждого установленного файла игры, JSON-читаемость и локальные Markdown-ссылки. Результат сохраняется в `data/verification.json`.

Verifier не симулирует Unreal Engine, не проверяет каждую ветвь управления и не подтверждает visuals/audio. Luau gate не запускался: исходники Roblox этой работой не изменялись.

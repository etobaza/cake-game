# Lemon Cake: ориентир для следующей сессии

Исследование от **2026-09-22**. [Главный индекс](../Exeperience/LemonCake/README.md).

- Steam app `1338330`, установленный build `6596857`, UE `4.24`, CL `11590370`. [Fingerprint](../Exeperience/LemonCake/data/build.json).
- PAK распакован полностью: **11 123 файла**. Игровой Content: **4 511 пакетов**, **914 Blueprint-функций**, **15 таблиц / 623 строки**. Ошибок разбора и RawExport нет; длины всех 914 функций совпали. Это статическая проверка, не полное доказательство правильности декомпиляции.
- Каталоги: **42 рецепта**, **98 предметов**, **48 покупок**, **13 меню-бонусов**, **105 записей внешности**, **21 шаг tutorial**. Один игровой уровень `LVL_Game`.
- Начинайте с [RECIPES](../Exeperience/LemonCake/RECIPES.md), [UPGRADES](../Exeperience/LemonCake/UPGRADES.md), [SYSTEMS](../Exeperience/LemonCake/SYSTEMS.md), [формул](../Exeperience/LemonCake/FORMULAS.md), [карты владельцев Roblox](../Exeperience/LemonCake/ROBLOX_MAPPING.md).
- Точные значения: `Exeperience/LemonCake/data/tables/*.json`. Defaults: `data/defaults.jsonl`; overrides уровня: `data/map-gameplay-objects.json`. Не принимайте default за финальное runtime-значение.
- Полная локальная база: `Exeperience/LemonCake/.local/{unpacked,json,bytecode,readable}`. Она игнорируется Git, остаётся на этой машине. [Восстановление](../Exeperience/LemonCake/REPRODUCE.md) работает из установленной игры с проверкой SHA256.
- Поиск из корня: `python Exeperience/LemonCake/tools/query.py recipe LemonCake`; `python Exeperience/LemonCake/tools/query.py function Patience`; `rg -n 'BurnedCookTime' Exeperience/LemonCake/.local/readable`.
- Адрес функции: `python Exeperience/LemonCake/tools/query.py code BP_Client --function ExecuteUbergraph_BP_Client --start 636 --limit 13`.
- Существенные отличия: оригинал меняет длину стадии по уровню; cake-game использует смену 480 секунд. Оригинал: `Patience` растёт от 0 к 1, чаевые с коэффициентом 0.2, XP нормализуется кривой. Roblox-настройки другие.
- В оригинальном пути чаевых найден `Divide_IntInt(BonusPercentage, 100)`. Не заменять его мысленно на float-деление и не копировать странность в Roblox без решения пользователя.
- Регистры `chocolatePancake`, `CherryBundtCake` и row IDs `NewRow...` сохранять точно. Номер строки рецепта не равен уровню открытия. Диетические флаги оригинала иногда спорные, но выгружены буквально.
- Игра не запускалась. Нет walkthrough, измерений кадров/времени, проверки всех улучшений и save/reload. Оригинальный C++ и редакторские Blueprint-графы не восстановлены. [Оставшиеся вопросы](../Exeperience/LemonCake/OPEN_QUESTIONS.md).

Luau, Studio и пользовательские сохранения этим исследованием не изменялись. Существовавшие изменения рабочего дерева сохранены.

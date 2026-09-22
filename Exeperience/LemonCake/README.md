# Lemon Cake — база исследования

Статический разбор установленной Steam-сборки **6596857** от **2026-09-22**, подготовленный для дальнейшей работы над cake-game. Это исследование файлов, данных и исполняемого Blueprint-байткода; не восстановленный исходный проект и не пройденная в runtime игра.

## Что извлечено

| Область | Покрытие |
| --- | ---: |
| Файлы PAK, с путями, размерами и SHA256 | 11 123 |
| Игровые пакеты `.uasset` / `.umap` | 4 511 |
| Blueprint-функции, AST и адреса инструкций | 914 |
| Таблицы / строки | 15 / 623 |
| Рецепты / предметы | 42 / 98 |
| Покупки / меню-бонусы | 48 / 13 |
| Записи внешности / шаги обучения | 105 / 21 |
| Выгруженные объекты уровня выбранных типов | 1 946 |

Все игровые пакеты прошли парсер без исключений и `RawExport`; вычисленные размеры всех 914 функций совпали с записанными размерами. Это подтверждает покрытие и структурную согласованность, но не равнозначно проверке каждой ветви в игре. Полный результат: [coverage.json](data/coverage.json), [verification.json](data/verification.json).

## Где искать

| Вопрос | Материал |
| --- | --- |
| Как устроены игровые системы | [SYSTEMS.md](SYSTEMS.md) |
| Точные формулы, пороги и адреса байткода | [FORMULAS.md](FORMULAS.md) |
| Состав, цены, время, диетические флаги | [RECIPES.md](RECIPES.md), [таблица](data/tables/DAT_Recipe.json) |
| Покупки и цены | [UPGRADES.md](UPGRADES.md), [таблица](data/tables/DAT_Shop.json) |
| Мир, источники ингредиентов, экземпляры | [WORLD.md](WORLD.md) |
| Ассеты, Blueprint-владельцы, зависимости | [ASSET_MAP.md](ASSET_MAP.md) |
| Сохранение, настройки, UI | [SAVE_UI.md](SAVE_UI.md) |
| Куда относится механика в cake-game | [ROBLOX_MAPPING.md](ROBLOX_MAPPING.md) |
| Повторить выгрузку или точечно достать функцию | [REPRODUCE.md](REPRODUCE.md) |
| Источники, версия, границы достоверности | [SOURCES.md](SOURCES.md), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| Краткая память для следующего чата | [mem/lemon-cake.md](../../mem/lemon-cake.md) |

## Устройство хранения

`data/` содержит переносимые индексы, таблицы, схемы и fingerprints. `tools/` содержит собственные воспроизводимые инструменты. `.local/` содержит полную распаковку оригинальных ресурсов, UAssetAPI JSON, декодированный AST, читаемое представление инструкций и диалоги. `.local/` исключена из Git; она доступна на текущей машине и восстанавливается из той же сборки игры.

Оригинальные бинарные ассеты не встроены в Roblox-проект. Индексы описывают их для исследования. Факты о Lemon Cake и рекомендации по адаптации разделены; изменения баланса Roblox не входят в эту работу.

## Быстрый поиск

Из корня репозитория:

```powershell
python Exeperience/LemonCake/tools/query.py recipe LemonCake
python Exeperience/LemonCake/tools/query.py shop Oven
python Exeperience/LemonCake/tools/query.py function GainExperience
python Exeperience/LemonCake/tools/query.py default BP_DailyCycle
rg -n 'Patience|BurnedCookTime' Exeperience/LemonCake/.local/readable
```

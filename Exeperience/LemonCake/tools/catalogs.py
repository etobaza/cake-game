"""Generate compact catalogs directly from the captured build, preserving source IDs."""
from collections import Counter
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def table(name):
    return json.loads((ROOT / "data/tables" / f"{name}.json").read_text(encoding="utf-8"))["rows"]


def label(value):
    if isinstance(value, dict):
        return value.get("label") or value.get("textKey") or json.dumps(value, ensure_ascii=False)
    return str(value)


def main():
    recipes = table("DAT_Recipe")
    lines = ["# Каталог рецептов", "", "Источник: `Blueprints/Items/DAT_Recipe.uasset`, build `6596857`. Табличные значения; не измерение полного цикла приготовления.", "",
             "`Value` — базовое значение таблицы, `BakeTime` — поле времени. Нулевое `BakeTime` не доказывает мгновенное приготовление: существуют миксер и морозильник. Диетические флаги сохранены буквально, даже если противоречат составу. Порядок строк не означает уровень открытия.", "",
             "Полные записи, ссылки на иконки и исходные enum IDs: [DAT_Recipe.json](data/tables/DAT_Recipe.json).", "",
             "| № | ID | Категория | Value | BakeTime | Ингредиенты | Vegan | GlutenFree |",
             "| --- | --- | --- | ---: | ---: | --- | --- | --- |"]
    for i, row in enumerate(recipes):
        ingredients = ", ".join(label(v) for v in row["IngredientsName"])
        lines.append(f"| {i} | `{row['id']}` | {label(row['Type'])} | {row['Value']:g} | {row['BakeTime']:g} | {ingredients} | {row['IsVegan']} | {row['IsGlutenFree']} |")
    (ROOT / "RECIPES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    shop = table("DAT_Shop")
    lines = ["# Каталог улучшений", "", "Источник: `Blueprints/Interface/DAT_Shop.uasset`, build `6596857`. 48 строк, по 12 в каждой категории. `Number` имеет смысл внутри категории; `BaseName` может повторяться. Для точной записи используйте исходный row ID.", "",
             "Цена и порядок в таблице не доказывают зависимости дерева. Реализация покупки и воздействия: `WBP_ShopSingle`, структура дерева: `WBP_ShopTree`. Полные записи: [DAT_Shop.json](data/tables/DAT_Shop.json).", ""]
    for category in ("Store", "Kitchen", "Greenhouse", "Bedroom"):
        rows = [r for r in shop if label(r["Type"]) == category]
        lines += [f"## {category}", "", "| Number | Row ID | BaseName | Название | Cost |", "| ---: | --- | --- | --- | ---: |"]
        lines += [f"| {r['Number']} | `{r['id']}` | `{r['BaseName']}` | {r['Name']} | {r['Cost']:g} |" for r in rows]
        lines += ["", f"Сумма табличных цен: **{sum(r['Cost'] for r in rows):g}**. Это арифметическая сумма, не симуляция прохождения.", ""]
    (ROOT / "UPGRADES.md").write_text("\n".join(lines), encoding="utf-8")
    maps = json.loads((ROOT / "data/map-gameplay-objects.json").read_text(encoding="utf-8"))
    lines = ["# Мир и источники предметов", "", "В игровом Content найден один уровень: `Level/LVL_Game.umap`. Полная локальная выгрузка объектов: `.local/map-objects.json`; игровые объекты: [map-gameplay-objects.json](data/map-gameplay-objects.json). Координаты компонентов находятся в полной выгрузке, а не в сокращённой таблице ниже.", "",
             "Зоны enum `ENUM_Location`: Greenhouse, Kitchen, Store, Bedroom. Авторские модельные названия и таблицы не заменяют визуальную проверку карты.", "",
             "## Размещённые BP_ItemSpawner", "",
             "Значения ниже — overrides уровня. Базовый `SpawnTimer=10` не следует применять ко всем растениям: на уровне он заменён. Начальный `IsUnlocked=false` также не означает, что источник останется закрытым после обучения/загрузки.", "",
             "| Actor | ItemToSpawn | SpawnTimer | IsPlant | Tags |", "| --- | --- | ---: | --- | --- |"]
    for m in maps:
        if "BP_ItemSpawner." not in m["class"]:
            continue
        v = m["values"]
        lines.append(f"| `{m['name']}` | {v.get('ItemToSpawn')} | {v.get('SpawnTimer', 10)} | {v.get('IsPlant', True)} | {', '.join(v.get('Tags', []))} |")
    lines += ["", "## Количество игровых объектов по классу", "", "Это число размещённых объектов, не число одновременно активных или доступных объектов.", "", "| Класс | Количество |", "| --- | ---: |"]
    for key, count in sorted(Counter(m["class"] for m in maps).items()):
        lines.append(f"| `{key.rsplit('.', 1)[-1]}` | {count} |")
    (ROOT / "WORLD.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    assets = [json.loads(x) for x in (ROOT / "data/assets.jsonl").read_text(encoding="utf-8").splitlines()]
    functions = [json.loads(x) for x in (ROOT / "data/functions.jsonl").read_text(encoding="utf-8").splitlines()]
    lines = ["# Карта ассетов и функций", "", "Все пути относительны `LemonCake/Content`. Полный индекс зависимостей: [assets.jsonl](data/assets.jsonl); вызовы: [functions.jsonl](data/functions.jsonl). Это статические ссылки и вызовы, не runtime-трасса.", "",
             "## Функциональные Blueprint-пакеты", "", "| Пакет | Функций | Statements |", "| --- | ---: | ---: |"]
    for source in sorted({f["source"] for f in functions}):
        rows = [f for f in functions if f["source"] == source]
        lines.append(f"| `{source}` | {len(rows)} | {sum(r['statements'] for r in rows)} |")
    lines += ["", "## Группы Content", "", "| Папка верхнего уровня | Пакетов |", "| --- | ---: |"]
    lines += [f"| {k} | {v} |" for k, v in sorted(Counter(a["path"].split('/')[0] for a in assets).items())]
    (ROOT / "ASSET_MAP.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Catalogs: {len(recipes)} recipes; {len(shop)} upgrades; {len(maps)} placed gameplay objects.")


if __name__ == "__main__":
    main()

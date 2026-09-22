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
    lines = ["# Recipe catalog", "", "Source: `Blueprints/Items/DAT_Recipe.uasset`, build `6596857`. These are table values, not measurements of the complete preparation cycle.", "",
             "`Value` is the base table value; `BakeTime` is the timing field. Zero `BakeTime` does not prove instant preparation: the mixer and freezer also exist. Dietary flags are preserved literally, even when they contradict the ingredients. Row order does not indicate unlock level.", "",
             "Complete records, icon references, and original enum IDs: [DAT_Recipe.json](data/tables/DAT_Recipe.json).", "",
             "| Index | ID | Category | Value | BakeTime | Ingredients | Vegan | GlutenFree |",
             "| --- | --- | --- | ---: | ---: | --- | --- | --- |"]
    for i, row in enumerate(recipes):
        ingredients = ", ".join(label(v) for v in row["IngredientsName"])
        lines.append(f"| {i} | `{row['id']}` | {label(row['Type'])} | {float(row['Value']):g} | {float(row['BakeTime']):g} | {ingredients} | {row['IsVegan']} | {row['IsGlutenFree']} |")
    (ROOT / "RECIPES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    shop = table("DAT_Shop")
    lines = ["# Upgrade catalog", "", "Source: `Blueprints/Interface/DAT_Shop.uasset`, build `6596857`. There are 48 rows, 12 per category. `Number` is meaningful within its category; `BaseName` can repeat. Use the original row ID to identify an exact record.", "",
             "Price and table order do not establish tree dependencies. Purchases and their effects are implemented in `WBP_ShopSingle`; the tree structure is in `WBP_ShopTree`. Complete records: [DAT_Shop.json](data/tables/DAT_Shop.json).", ""]
    for category in ("Store", "Kitchen", "Greenhouse", "Bedroom"):
        rows = [r for r in shop if label(r["Type"]) == category]
        lines += [f"## {category}", "", "| Number | Row ID | BaseName | Name | Cost |", "| ---: | --- | --- | --- | ---: |"]
        lines += [f"| {r['Number']} | `{r['id']}` | `{r['BaseName']}` | {r['Name']} | {r['Cost']:g} |" for r in rows]
        lines += ["", f"Total table prices: **{sum(r['Cost'] for r in rows):g}**. This is an arithmetic sum, not a playthrough simulation.", ""]
    (ROOT / "UPGRADES.md").write_text("\n".join(lines), encoding="utf-8")
    maps = json.loads((ROOT / "data/map-gameplay-objects.json").read_text(encoding="utf-8"))
    lines = ["# World and item sources", "", "One level was found in game Content: `Level/LVL_Game.umap`. Complete local object export: `.local/map-objects.json`; gameplay objects: [map-gameplay-objects.json](data/map-gameplay-objects.json). Component coordinates are in the complete export, not the simplified table below.", "",
             "`ENUM_Location` zones: Greenhouse, Kitchen, Store, Bedroom. Authored model names and tables do not replace visual map inspection.", "",
             "## Placed BP_ItemSpawner instances", "",
             "The values below are level overrides. The base `SpawnTimer=10` must not be applied to every plant: the level overrides it. An initial `IsUnlocked=false` also does not mean the source remains locked after the tutorial or loading.", "",
             "| Actor | ItemToSpawn | SpawnTimer | IsPlant | Tags |", "| --- | --- | ---: | --- | --- |"]
    for m in maps:
        if "BP_ItemSpawner." not in m["class"]:
            continue
        v = m["values"]
        lines.append(f"| `{m['name']}` | {v.get('ItemToSpawn')} | {v.get('SpawnTimer', 10)} | {v.get('IsPlant', True)} | {', '.join(v.get('Tags', []))} |")
    lines += ["", "## Gameplay object counts by class", "", "These are placed-object counts, not counts of simultaneously active or available objects.", "", "| Class | Count |", "| --- | ---: |"]
    for key, count in sorted(Counter(m["class"] for m in maps).items()):
        lines.append(f"| `{key.rsplit('.', 1)[-1]}` | {count} |")
    (ROOT / "WORLD.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    assets = [json.loads(x) for x in (ROOT / "data/assets.jsonl").read_text(encoding="utf-8").splitlines()]
    functions = [json.loads(x) for x in (ROOT / "data/functions.jsonl").read_text(encoding="utf-8").splitlines()]
    lines = ["# Asset and function map", "", "All paths are relative to `LemonCake/Content`. Complete dependency index: [assets.jsonl](data/assets.jsonl); calls: [functions.jsonl](data/functions.jsonl). These are static references and calls, not a runtime trace.", "",
             "## Blueprint packages containing functions", "", "| Package | Functions | Statements |", "| --- | ---: | ---: |"]
    for source in sorted({f["source"] for f in functions}):
        rows = [f for f in functions if f["source"] == source]
        lines.append(f"| `{source}` | {len(rows)} | {sum(r['statements'] for r in rows)} |")
    lines += ["", "## Content groups", "", "| Top-level folder | Packages |", "| --- | ---: |"]
    lines += [f"| {k} | {v} |" for k, v in sorted(Counter(a["path"].split('/')[0] for a in assets).items())]
    (ROOT / "ASSET_MAP.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Catalogs: {len(recipes)} recipes; {len(shop)} upgrades; {len(maps)} placed gameplay objects.")


if __name__ == "__main__":
    main()

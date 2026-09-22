"""Build searchable evidence from local UAssetAPI exports; never writes game files."""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import re
from query import render

ROOT = Path(__file__).resolve().parents[1]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def kind(value):
    return value.get("$type", "").split(",")[0].split(".")[-1]


def clean_name(name):
    return re.sub(r"_\d+_[A-F0-9]{32}$", "", name)


def ref(asset, index, seen=None):
    if not isinstance(index, int):
        return index
    if index == 0:
        return None
    seen = set() if seen is None else seen
    if index in seen:
        return f"cycle:{index}"
    seen.add(index)
    rows = asset["Imports"] if index < 0 else asset["Exports"]
    position = -index - 1 if index < 0 else index - 1
    if position >= len(rows):
        return f"unresolved:{index}"
    row = rows[position]
    parent = ref(asset, row.get("OuterIndex", 0), seen)
    return f"{parent}.{row['ObjectName']}" if parent else row["ObjectName"]


def prop(value, asset, enums):
    if isinstance(value, list):
        return [prop(x, asset, enums) for x in value]
    if not isinstance(value, dict):
        return value
    t = kind(value)
    if t == "TextPropertyData":
        if value.get("TableId"):
            return {"textKey": value.get("Value"), "table": value["TableId"]}
        return value.get("CultureInvariantString") or value.get("Value")
    if t in ("ObjectPropertyData", "ClassPropertyData"):
        return ref(asset, value.get("Value", 0))
    if "EnumValue" in value:
        enum_value = value["EnumValue"]
        return {"id": enum_value, "label": enums.get(enum_value)}
    if t == "StructPropertyData":
        return {clean_name(x["Name"]): prop(x, asset, enums) for x in value.get("Value", [])}
    if t == "MapPropertyData":
        return [prop(x, asset, enums) for x in value.get("Value", [])]
    if "Value" in value and t.endswith("PropertyData"):
        return prop(value["Value"], asset, enums)
    return {k: prop(v, asset, enums) for k, v in value.items() if k != "$type"}


def walk(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


def expression(value, asset):
    """Readable AST, not reconstructed source; preserve unknown node fields."""
    if isinstance(value, list):
        return [expression(x, asset) for x in value]
    if not isinstance(value, dict):
        return value
    t = kind(value)
    if t == "KismetPropertyPointer":
        return ref(asset, value.get("Old", 0)) if "Old" in value else value
    output = {"op": t.removeprefix("EX_")} if t else {}
    for key, item in value.items():
        if key == "$type":
            continue
        if (key in ("StackNode", "ObjectRef", "ClassPtr", "Struct") or (t == "EX_ObjectConst" and key == "Value")) and isinstance(item, int):
            output[key] = ref(asset, item)
        else:
            output[key] = expression(item, asset)
    return output


def main():
    source = ROOT / ".local/json"
    unpacked = ROOT / ".local/unpacked"
    data = ROOT / "data"
    data.mkdir(exist_ok=True)
    inventory = []
    for path in sorted(unpacked.rglob("*")):
        if path.is_file():
            inventory.append({"path": path.relative_to(unpacked).as_posix(), "bytes": path.stat().st_size,
                              "sha256": hashlib.file_digest(path.open("rb"), "sha256").hexdigest()})
    with (data / "files.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["path", "bytes", "sha256"])
        writer.writeheader()
        writer.writerows(inventory)
    enums = {}
    for path in sorted(source.rglob("ENUM_*.json")):
        asset = json.loads(path.read_text(encoding="utf-8"))
        for export in asset["Exports"]:
            if kind(export) != "EnumExport":
                continue
            for field in export.get("Data", []):
                if field["Name"] == "DisplayNameMap":
                    for key, value in field["Value"]:
                        enums[f"{export['ObjectName']}::{key['Value']}"] = prop(value, asset, {})
    write_json(data / "enums.json", enums)
    assets, functions, defaults, tables, map_actors, schemas = [], [], [], [], [], []
    bytecode_failures, size_mismatches, curves = [], [], []
    export_types = Counter()
    opaque_exports = 0
    opaque_bytes = 0
    for path in sorted(source.rglob("*.json")):
        if path.name == "parse-report.json":
            continue
        asset = json.loads(path.read_text(encoding="utf-8"))
        relative = path.relative_to(source).as_posix().removesuffix(".json")
        exports = asset["Exports"]
        export_types.update(kind(e) for e in exports)
        classes = sorted({str(ref(asset, e.get("ClassIndex", 0))) for e in exports})
        packages = sorted({i["ObjectName"] for i in asset["Imports"] if i.get("ClassName") == "Package"})
        assets.append({"path": relative, "exports": len(exports), "rawExports": sum(kind(e) == "RawExport" for e in exports),
                       "classes": classes, "imports": packages})
        for export in exports:
            name = export["ObjectName"]
            t = kind(export)
            extras = export.get("Extras")
            if extras:
                opaque_exports += 1
                opaque_bytes += len(extras) * 3 // 4 - (len(extras) - len(extras.rstrip("=")))
            if relative.startswith("Blueprints/") and "/CRV_" in relative:
                curves.append({"source": relative, "name": name,
                               "values": {p["Name"]: prop(p, asset, enums) for p in export.get("Data", [])}})
            if t == "StringTableExport":
                write_json(ROOT / ".local/string-tables" / f"{name}.json", export)
            if t == "PropertyExport" and relative.startswith("Blueprints/"):
                schemas.append({"source": relative, "name": name, "outer": ref(asset, export.get("OuterIndex", 0)),
                                "property": expression(export.get("Property"), asset)})
            if t == "DataTableExport":
                rows = [{"id": row["Name"], **prop(row, asset, enums)} for row in export["Table"]["Data"]]
                target = data / "tables" / f"{name}.json"
                if "Dialogue" in name or "MinigameBug" in name or name == "DAT_Notification":
                    target = ROOT / ".local/tables" / f"{name}.json"
                write_json(target, {"source": relative, "rows": rows})
                tables.append({"name": name, "source": relative, "rows": len(rows), "output": target.relative_to(ROOT).as_posix(),
                               "fields": list(rows[0]) if rows else []})
            if name.startswith("Default__") and not relative.startswith("Art/"):
                values = {clean_name(p["Name"]): prop(p, asset, enums) for p in export.get("Data", [])}
                defaults.append({"source": relative, "export": name, "class": ref(asset, export.get("ClassIndex", 0)), "values": values})
            if t == "FunctionExport":
                code = export.get("ScriptBytecode")
                nodes = list(walk(code))
                calls = sorted({str(ref(asset, n["StackNode"])) if "StackNode" in n else n["VirtualFunctionName"]
                                for n in nodes if "StackNode" in n or "VirtualFunctionName" in n})
                functions.append({"source": relative, "name": name, "statements": len(code or []), "calls": calls,
                                  "parsed": code is not None})
                if code is None:
                    bytecode_failures.append({"source": relative, "function": name})
                else:
                    target = ROOT / ".local/bytecode" / relative / f"{name}.json"
                    offsets = asset.get("ResearchBytecodeOffsets", {}).get(name, {})
                    if offsets.get("computedSize") != offsets.get("declaredSize"):
                        size_mismatches.append({"source": relative, "function": name, "offsets": offsets})
                    write_json(target, {"source": relative, "function": name, "offsets": offsets,
                                        "statements": expression(code, asset)})
                    readable = ROOT / ".local/readable" / relative / f"{name}.txt"
                    readable.parent.mkdir(parents=True, exist_ok=True)
                    positions = offsets.get("positions", [])
                    readable.write_text("\n".join(
                        f"[{i}] @{positions[i] if positions else 'unknown'} {render(s)}"
                        for i, s in enumerate(expression(code, asset))) + "\n", encoding="utf-8")
            if relative.endswith(".umap") and t in ("NormalExport", "SceneComponentExport", "ActorComponentExport"):
                values = {clean_name(p["Name"]): prop(p, asset, enums) for p in export.get("Data", [])}
                map_actors.append({"name": name, "class": ref(asset, export.get("ClassIndex", 0)),
                                   "outer": ref(asset, export.get("OuterIndex", 0)), "values": values})
    for filename, rows in (("assets.jsonl", assets), ("functions.jsonl", functions), ("defaults.jsonl", defaults)):
        (data / filename).write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    write_json(data / "tables.json", tables)
    write_json(ROOT / ".local/map-objects.json", map_actors)
    write_json(ROOT / ".local/property-schemas.json", schemas)
    write_json(data / "save-schema.json", [s for s in schemas if s["source"].endswith("/SV_SaveGame.uasset")])
    write_json(data / "curves.json", curves)
    write_json(data / "map-gameplay-objects.json", [m for m in map_actors if str(m["class"]).startswith("/Game/Blueprints/")])
    write_json(data / "parse-report.json", json.loads((source / "parse-report.json").read_text()))
    summary = {"fileCount": len(inventory), "extractedBytes": sum(r["bytes"] for r in inventory), "assets": len(assets),
               "functions": len(functions), "functionsWithUnparsedBytecode": bytecode_failures, "defaultObjects": len(defaults),
               "bytecodeSizeMismatches": size_mismatches,
               "exportsWithOpaqueExtras": opaque_exports, "opaqueExtrasBytes": opaque_bytes,
               "tables": len(tables), "tableRows": sum(t["rows"] for t in tables), "mapObjects": len(map_actors),
               "enumLabels": len(enums), "exportTypes": dict(export_types),
               "rawExportAssets": [{"path": r["path"], "rawExports": r["rawExports"]} for r in assets if r["rawExports"]]}
    write_json(data / "coverage.json", summary)
    print(json.dumps({k: v for k, v in summary.items() if k not in ("rawExportAssets", "functionsWithUnparsedBytecode")}, indent=2))
    print(f"Partial assets: {len(summary['rawExportAssets'])}; unparsed functions: {len(bytecode_failures)}")


if __name__ == "__main__":
    main()

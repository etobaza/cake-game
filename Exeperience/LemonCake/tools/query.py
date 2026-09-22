"""Search reference facts or inspect a decoded Kismet function without opening huge dumps."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def short(value):
    return str(value).rsplit(".", 1)[-1] if value is not None else "null"


def render(node):
    if not isinstance(node, dict):
        return json.dumps(node, ensure_ascii=False)
    op = node.get("op", "")
    if op.endswith("Variable"):
        return short(node.get("Variable"))
    if op in ("IntConst", "IntConstByte", "FloatConst", "ByteConst", "NameConst", "StringConst", "UnicodeStringConst", "Int64Const", "UInt64Const"):
        return json.dumps(node.get("Value"), ensure_ascii=False)
    if op in ("True", "False", "IntZero", "IntOne", "Self", "NoObject", "Nothing", "EndOfScript", "PopExecutionFlow"):
        return op
    if op in ("CallMath", "FinalFunction", "LocalFinalFunction", "VirtualFunction", "LocalVirtualFunction"):
        name = node.get("StackNode", node.get("VirtualFunctionName"))
        return short(name) + "(" + ", ".join(render(p) for p in node.get("Parameters", [])) + ")"
    if op in ("Context", "Context_FailSilent", "ClassContext"):
        return render(node["ObjectExpression"]) + "." + render(node["ContextExpression"])
    if op == "Let":
        return render(node["Variable"]) + " = " + render(node["Expression"])
    if op.startswith("Let") and "VariableExpression" in node:
        return render(node["VariableExpression"]) + " = " + render(node["AssignmentExpression"])
    if op == "JumpIfNot":
        return f"if not ({render(node['BooleanExpression'])}) jump @{node['CodeOffset']}"
    if op in ("Jump", "PushExecutionFlow"):
        return f"{op} @{node.get('CodeOffset', node.get('PushingAddress'))}"
    if op == "ComputedJump":
        return f"ComputedJump {render(node.get('CodeOffsetExpression'))}"
    if op == "Return":
        return "return " + render(node.get("ReturnExpression"))
    if op == "ObjectConst":
        return short(node.get("Value", node.get("ObjectRef")))
    return op + " " + json.dumps({k: v for k, v in node.items() if k != "op"}, ensure_ascii=False, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["recipe", "shop", "bonus", "item", "asset", "function", "default", "code"])
    parser.add_argument("query")
    parser.add_argument("--function", dest="function_name")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--start", type=int, default=0, help="First statement index for code")
    args = parser.parse_args()
    if args.mode == "code":
        paths = [p for p in (ROOT / ".local/bytecode").rglob("*.json")
                 if args.query.lower() in str(p.parent).lower()
                 and (not args.function_name or p.stem == args.function_name)]
        if len(paths) != 1:
            print("Select one function with --function. Matches:")
            print("\n".join(str(p.relative_to(ROOT)) for p in paths[:args.limit]))
            return
        content = json.loads(paths[0].read_text(encoding="utf-8"))
        positions = content.get("offsets", {}).get("positions", [])
        print(str(paths[0].relative_to(ROOT)))
        for i, node in enumerate(content["statements"]):
            if args.start <= i < args.start + args.limit:
                offset = f"@{positions[i]}" if positions else "@unknown"
                print(f"[{i}] {offset} {render(node)}")
        return
    tables = {"recipe": "DAT_Recipe", "shop": "DAT_Shop", "bonus": "DAT_Bonus", "item": "DAT_Item"}
    if args.mode in tables:
        rows = json.loads((ROOT / "data/tables" / (tables[args.mode] + ".json")).read_text(encoding="utf-8"))["rows"]
    else:
        filename = {"asset": "assets", "function": "functions", "default": "defaults"}[args.mode]
        rows = [json.loads(line) for line in (ROOT / "data" / (filename + ".jsonl")).read_text(encoding="utf-8").splitlines()]
    matches = [r for r in rows if args.query.lower() in json.dumps(r, ensure_ascii=False).lower()]
    print(f"{len(matches)} matches")
    for row in matches[:args.limit]:
        print(json.dumps(row, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

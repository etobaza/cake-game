"""Validate evidence coverage, bytecode lengths, extraction hashes, and local document links."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path)
    args = parser.parse_args()
    build = read(ROOT / "data/build.json")
    coverage = read(ROOT / "data/coverage.json")
    report = read(ROOT / "data/parse-report.json")
    assert len(report) == coverage["assets"] == 4511
    assert all(r["status"] == "ok" and r["rawExports"] == 0 for r in report)
    assert not coverage["functionsWithUnparsedBytecode"]
    assert not coverage["bytecodeSizeMismatches"]
    files = list(csv.DictReader((ROOT / "data/files.csv").open(encoding="utf-8")))
    assert len(files) == coverage["fileCount"] == build["pak"]["entries"]
    for row in files:
        path = ROOT / ".local/unpacked" / row["path"]
        assert path.stat().st_size == int(row["bytes"]), path
        assert digest(path) == row["sha256"], path
    for path in (ROOT / "data").rglob("*.json"):
        read(path)
    for name, count in (("DAT_Recipe", 42), ("DAT_Item", 98), ("DAT_Shop", 48), ("DAT_Bonus", 13)):
        rows = read(ROOT / "data/tables" / f"{name}.json")["rows"]
        assert len(rows) == count and len({r['id'] for r in rows}) == count
    for row in read(ROOT / "data/tables.json"):
        content = read(ROOT / row["output"])
        assert len(content["rows"]) == row["rows"]
    functions = list((ROOT / ".local/bytecode").rglob("*.json"))
    assert len(functions) == coverage["functions"] == 914
    for path in functions:
        content = read(path)
        offsets = content["offsets"]
        assert len(offsets["positions"]) == len(content["statements"]), path
        assert offsets["computedSize"] == offsets["declaredSize"], path
    game = args.game_root or Path(build["gameRoot"])
    for row in build["installedFiles"]:
        path = game / row["path"]
        assert digest(path) == row["sha256"], f"Installed file changed: {path}"
    docs = list(ROOT.glob("*.md")) + list((ROOT.parents[1] / "mem").glob("*.md")) + [ROOT.parent / "README.md"]
    links = 0
    for path in docs:
        text = path.read_text(encoding="utf-8")
        for link in re.findall(r"\]\(([^)]+)\)", text):
            if re.match(r"https?://|#", link):
                continue
            target = link.split("#")[0].strip("<>")
            resolved = (path.parent / target).resolve()
            # This report is written only after every check has passed, including first restoration.
            if resolved != (ROOT / "data/verification.json").resolve():
                assert resolved.exists(), f"Broken link in {path}: {target}"
            links += 1
    result = {"status": "passed", "build": build["steamBuildId"], "verifiedExtractedFiles": len(files),
              "verifiedUnchangedInstalledFiles": len(build["installedFiles"]), "parsedPackages": len(report),
              "bytecodeFunctionsWithMatchingSizes": len(functions), "localMarkdownLinks": links,
              "runtimeTested": False, "note": "Parsing and size checks do not establish semantic or visual equivalence."}
    (ROOT / "data/verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

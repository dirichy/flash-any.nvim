#!/usr/bin/env python3
"""Convert a character/code table into common Lua and sorted full TSV."""
from __future__ import annotations
import argparse
import re
from pathlib import Path

RIME = re.compile(r"^([^\t]+)\t([^\t]+)(?:\t(-?\d+))?(?:\t.*)?$")
LUA_KEY = re.compile(r'^\s*\["(.*?)"\]\s*=', re.MULTILINE)

def read_rows(path: Path, separator: str) -> dict[str, set[str]]:
    rows: dict[str, set[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or line.startswith("---"):
            continue
        if separator == "auto":
            match = RIME.match(line)
            fields = match.groups()[:2] if match else line.split(None, 2)[:2]
        else:
            fields = line.split(separator, 2)
        if len(fields) < 2:
            continue
        char, code = fields[0].strip(), fields[1].strip()
        if len(char) != 1 or not code or char.startswith("name:"):
            continue
        rows.setdefault(char, set()).add(code)
    return rows

def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

def common_keys(path: Path) -> list[str]:
    return [m.group(1) for m in LUA_KEY.finditer(path.read_text(encoding="utf-8"))]

def is_cjk(char: str) -> bool:
    cp = ord(char)
    return (
        0x3400 <= cp <= 0x4DBF
        or 0x4E00 <= cp <= 0x9FFF
        or 0x20000 <= cp <= 0x323AF
    )

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path)
    ap.add_argument("lua", type=Path)
    ap.add_argument("tsv", type=Path)
    ap.add_argument("--separator", choices=("auto", "tab", "space"), default="auto")
    ap.add_argument("--common-from", type=Path, default=Path("lua/flash-any/tables/tiger.lua"))
    ap.add_argument("--cjk-only", action="store_true")
    args = ap.parse_args()
    separator = {"tab": "\t", "space": " ", "auto": "auto"}[args.separator]
    rows = read_rows(args.source, separator)
    if args.cjk_only:
        rows = {char: codes for char, codes in rows.items() if is_cjk(char)}
    keys = common_keys(args.common_from) if args.common_from.exists() else sorted(rows)
    selected = [char for char in keys if char in rows]
    with args.lua.open("w", encoding="utf-8") as out:
        out.write("return {\n")
        for char in selected:
            values = ", ".join(lua_quote(v) for v in sorted(rows[char]))
            out.write(f"  [{lua_quote(char)}] = {{{values}}},\n")
        out.write("}\n")
    with args.tsv.open("w", encoding="utf-8") as out:
        for char in sorted(rows, key=lambda c: c.encode("utf-8")):
            for code in sorted(rows[char]):
                out.write(char + "\t" + code + "\n")
    print(f"common={len(selected)} full={len(rows)}")

if __name__ == "__main__":
    main()

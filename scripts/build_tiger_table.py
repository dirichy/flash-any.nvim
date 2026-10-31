#!/usr/bin/env python3
"""Build a compact character -> Tiger-code Lua table from a Rime dictionary.

The dictionary's weights are used as the common-character ranking.  All codes
for a selected character are kept, so multi-code entries are not lost.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROW = re.compile(r"^([^\t]+)\t([^\t]+)\t(-?\d+)(?:\t.*)?$")


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def read_rows(path: Path) -> dict[str, list[tuple[int, str]]]:
    rows: dict[str, list[tuple[int, str]]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ROW.match(line)
        if not match:
            continue
        char, code, weight = match.groups()
        if len(char) != 1 or not code:
            continue
        rows.setdefault(char, []).append((int(weight), code))
    return rows


def build(rows: dict[str, list[tuple[int, str]]], limit: int) -> list[str]:
    ranked = sorted(
        rows,
        key=lambda char: max(weight for weight, _ in rows[char]),
        reverse=True,
    )
    return ranked[:limit]


def write_lua(path: Path, rows: dict[str, list[tuple[int, str]]], chars: list[str]) -> None:
    lines = ["return {"]
    for char in chars:
        codes = sorted({code for _, code in rows[char]})
        values = ", ".join(lua_string(code) for code in codes)
        lines.append(f"  [{lua_string(char)}] = {{{values}}},")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--limit", type=int, default=3500)
    args = parser.parse_args()
    rows = read_rows(args.source)
    chars = build(rows, args.limit)
    write_lua(args.output, rows, chars)
    print(f"selected {len(chars)} characters from {len(rows)} entries")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build char -> standard Mandarin pinyin from mozillazg/pinyin-data."""
from __future__ import annotations
import argparse
import re
import unicodedata
from pathlib import Path

ROW = re.compile(r"^U\+([0-9A-F]+):\s*([^#]+?)\s+#\s*(.)")

def normalize(value: str) -> str:
    value = value.strip().lower().replace("ü", "v").replace("ǖ", "v").replace("ǘ", "v").replace("ǚ", "v").replace("ǜ", "v")
    value = "".join(c for c in unicodedata.normalize("NFD", value) if unicodedata.category(c) != "Mn")
    return value.replace("u", "u")

def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--extra", type=Path, action="append", default=[])
    parser.add_argument("--common-lua", type=Path)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    rows: dict[str, list[str]] = {}
    sources = [args.source, *args.extra]
    for source in sources:
      for line in source.read_text(encoding="utf-8").splitlines():
          m = ROW.match(line)
          if not m:
              continue
          char = m.group(3)
          values = rows.setdefault(char, [])
          for value in m.group(2).split(","):
              value = normalize(value)
              if value and value not in values:
                  values.append(value)
    if args.common_lua:
        common = re.findall(r'^\s*\["(.*?)"\]\s*=', args.common_lua.read_text(encoding="utf-8"), re.MULTILINE)
        selected = [char for char in (common[:args.limit] if args.limit else common) if char in rows]
    else:
        selected = sorted(rows)
    with args.output.open("w", encoding="utf-8") as out:
        out.write("return {\n")
        for char in selected:
            out.write(f"  [{lua_quote(char)}] = {{{', '.join(lua_quote(v) for v in rows[char])}}},\n")
        out.write("}\n")
    print(f"wrote {len(selected)} characters")

if __name__ == "__main__":
    main()

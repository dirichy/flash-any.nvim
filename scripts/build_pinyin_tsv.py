#!/usr/bin/env python3
"""Build sorted full character -> pinyin TSV from pinyin-data."""
from __future__ import annotations
import argparse
import re
import unicodedata
from pathlib import Path
ROW = re.compile(r"^U\+([0-9A-F]+):\s*([^#]+?)\s+#\s*(.)")
def normalize(value: str) -> str:
    value = value.strip().lower()
    value = value.replace("ǖ", "v").replace("ǘ", "v").replace("ǚ", "v").replace("ǜ", "v").replace("ü", "v")
    return "".join(c for c in unicodedata.normalize("NFD", value) if unicodedata.category(c) != "Mn")
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("source", type=Path); ap.add_argument("output", type=Path); a=ap.parse_args()
    rows = {}
    for line in a.source.read_text(encoding="utf-8").splitlines():
        m=ROW.match(line)
        if not m: continue
        values=[]
        for value in m.group(2).split(","):
            value=normalize(value)
            if value and value not in values: values.append(value)
        if values: rows[m.group(3)] = values
    with a.output.open("w",encoding="utf-8") as out:
        for char in sorted(rows, key=lambda c:c.encode()): out.write(char+"\t"+",".join(rows[char])+"\n")
    print(f"wrote {len(rows)} characters")
if __name__ == "__main__": main()

#!/usr/bin/env python3
"""Build a sorted full character -> Tiger codes TSV from a Rime dictionary."""
from __future__ import annotations
import argparse
import re
from pathlib import Path
ROW = re.compile(r"^([^\t]+)\t([^\t]+)\t(-?\d+)(?:\t.*)?$")
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('source',type=Path); ap.add_argument('output',type=Path); a=ap.parse_args()
    rows={}
    for line in a.source.read_text(encoding='utf-8').splitlines():
        m=ROW.match(line)
        if not m: continue
        char, code, _ = m.groups()
        if len(char) != 1 or not code: continue
        rows.setdefault(char, set()).add(code)
    with a.output.open('w',encoding='utf-8') as out:
        for char in sorted(rows,key=lambda c:c.encode()):
            out.write(char+'\t'+','.join(sorted(rows[char]))+'\n')
    print(f'wrote {len(rows)} characters')
if __name__ == '__main__': main()

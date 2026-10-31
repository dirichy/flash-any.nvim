#!/usr/bin/env python3
"""Sort a character/code table by its first UTF-8 field."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--separator", choices=("tab", "space"), default="tab")
    args = parser.parse_args()

    separator = "\t" if args.separator == "tab" else " "
    rows = []
    for line in args.input.read_text(encoding="utf-8").splitlines(keepends=True):
        body = line.rstrip("\r\n")
        if not body or body.startswith("#"):
            continue
        key = body.split(separator, 1)[0]
        rows.append((key.encode("utf-8"), line))

    rows.sort(key=lambda item: item[0])
    args.output.write_text("".join(line for _, line in rows), encoding="utf-8")


if __name__ == "__main__":
    main()

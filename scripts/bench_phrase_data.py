"""Generate controlled phrase stress packages from explicit Rime Ice dictionaries.

The uniform package uses synthetic code x. The annotated package keeps real
ASCII codes with syllable-separating whitespace removed. Does not execute schemas.
The benchmark-only v11 writer is validated by the production C loader.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("data", type=Path, help="directory with 8105/base/ext/tencent/others.dict.yaml and revision")
args = parser.parse_args()
out = args.data
annotated, all_keys, stats = {}, set(), []
for name in ("8105", "base", "ext", "tencent", "others"):
    path = out / (name + ".dict.yaml")
    columns, section, started = ["text", "code", "weight"], False, False
    rows, with_code = 0, 0
    for line in path.read_text().splitlines():
        if not started:
            text = line.split("#", 1)[0].strip()
            if text == "...":
                started = True
                continue
            if text.startswith("columns:"):
                columns, section = [], True
            elif section and text.startswith("- "):
                columns.append(text[2:].strip())
            elif text:
                section = False
            continue
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        key = fields[columns.index("text")].strip()
        if not key or "\0" in key:
            continue
        all_keys.add(key)
        rows += 1
        if "code" in columns and len(fields) > columns.index("code"):
            code = "".join(fields[columns.index("code")].split())
            if code and code.isascii() and "\0" not in code:
                annotated.setdefault(key, set()).add(code)
                with_code += 1
    assert started, f"missing Rime header terminator: {path}"
    stats.append(dict(name=name, rows=rows, with_explicit_code=with_code,
                      sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
print("keys", len(all_keys), "annotated", len(annotated), "rows", sum(x["rows"] for x in stats), flush=True)


def package(name, values, uniform):
    scalars = sorted(k for k in values if len(k) == 1)
    text = sorted(k for k in values if len(k) > 1)
    capacity = 2 if text else 0
    while capacity * 3 < len(text) * 4:
        capacity *= 2
    highs, directory = sorted({ord(k) >> 8 for k in scalars}), [0] * 4352
    for i, high in enumerate(highs):
        directory[high] = i + 1
    pages, entries, slots = [0] * (len(highs) * 256), [], [0] * capacity
    pool, intern = bytearray(), {}

    def add(data):
        if data not in intern:
            intern[data] = len(pool)
            pool.extend(data)
        return intern[data]

    for key in scalars + text:
        codebytes = (b"\x81x\0" if uniform else
                     b"".join(b"\x81" + code.encode() for code in sorted(values[key])) + b"\0")
        codes = add(codebytes)
        if len(key) == 1:
            pages[(directory[ord(key) >> 8] - 1) * 256 + (ord(key) & 255)] = codes + 1
        else:
            key_offset = add(key.encode() + b"\0")
            index = len(entries)
            entries.append((key_offset, codes))
            h = 2166136261
            for cp in map(ord, key):
                h = ((h ^ cp) * 16777619) & 0xFFFFFFFF
            slot = h & (capacity - 1)
            while slots[slot]:
                slot = (slot + 1) & (capacity - 1)
            slots[slot] = index + 1
    total = (40 + (4352 if highs else 0) * 4 + len(pages) * 4 + len(entries) * 8
             + len(slots) * 4 + len(pool))
    with (out / (name + ".bin")).open("wb") as file:
        file.write(b"FANYBIN\x0b")
        file.write(struct.pack("<8I", 17, total, len(text), capacity, len(highs), len(pool), 0, len(scalars)))
        if highs:
            file.write(struct.pack("<4352I", *directory))
        file.write(struct.pack("<" + "I" * len(pages), *pages))
        for entry in entries:
            file.write(struct.pack("<II", *entry))
        file.write(struct.pack("<" + "I" * len(slots), *slots))
        file.write(pool)
    return dict(name=name, total_bytes=total, keys=len(values), scalar_keys=len(scalars),
                text_keys=len(text), max_codepoints=max(map(len, values)), capacity=capacity,
                pages=len(highs), pool_bytes=len(pool))


reports = [package("ice_uniform", all_keys, True), package("ice_annotated", annotated, False)]
rng = random.Random(20261112)
words = sorted(k for k in all_keys if len(k) > 1)
real = sorted(k for k in annotated if len(k) > 1)
fixtures = {}
for name, source in (("ice_uniform", words), ("ice_annotated", real)):
    chosen = rng.sample(source, 512)
    lines = ["".join(chosen[i:i + 16]) for i in range(0, len(chosen), 16)]
    repeats = ["中" * 128, "中国人民" * 32, "的" * 128, "啊" * 128]
    # Generated random Han text, not real prose; shorter entries may still match.
    misses = ["".join(chr(rng.randrange(0x4E00, 0x9FFF)) for _ in range(64)) for _ in range(32)]
    queries = ["x", "xx", "xxx", "xy", "z", "zh", "zhong", "zhongguo"]
    if name == "ice_annotated":
        queries += sorted(annotated[chosen[0]])[:1]
        queries += [sorted(annotated[key])[0][:2] for key in chosen[1:4]]
    fixtures[name] = dict(lines=lines, misses=misses, repeats=repeats, queries=queries)
(out / "workloads.json").write_text(json.dumps(fixtures, ensure_ascii=False))
report = dict(revision=(out / "revision").read_text(), files=stats, packages=reports,
              unannotated_keys=len(all_keys - set(annotated)),
              uniform_note="All keys use synthetic code x only for controlled index/matcher stress; no pronunciation inference.")
(out / "data-report.json").write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))

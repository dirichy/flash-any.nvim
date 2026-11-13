"""Compare linear fingerprints and Robin Hood distance layouts on Tiger phrase keys.

python scripts/bench_robin_hood.py tiger.zip --samples 7
No runtime changes; phrase keys exercise the index only, not phrase matching.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import random
import statistics
from bench_keys import hash_key, write_fixture
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
METHODS = ("linear", "fingerprint", "rh4", "rh6", "rh8", "rh_byte")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
parser.add_argument("--samples", type=int, default=7)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
out = args.output or Path(tempfile.mkdtemp(prefix="flash-any-robin-hood-"))
out.mkdir(parents=True, exist_ok=True)
cpu = min(os.sched_getaffinity(0))
os.sched_setaffinity(0, {cpu})
SEED = 20261112


def read_dictionary(archive, name):
    member = next(n for n in archive.namelist() if n.endswith("/" + name + ".dict.yaml"))
    keys, imports, columns = set(), [], ["text", "code", "weight"]
    section = None
    with archive.open(member) as raw:
        lines = io.TextIOWrapper(raw, encoding="utf-8-sig")
        for line in lines:
            text = line.split("#", 1)[0].strip()
            if text == "...":
                break
            if text.startswith("columns:"):
                columns = []
                section = columns
            elif text.startswith("import_tables:"):
                section = imports
            elif section is not None and text.startswith("- "):
                section.append(text[2:].strip())
            elif text:
                section = None
        for line in lines:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.rstrip("\r\n").split("\t")
            if len(fields) <= max(columns.index("text"), columns.index("code")):
                raise ValueError(f"invalid row in {member}: {line!r}")
            key, code = fields[columns.index("text")].strip(), fields[columns.index("code")].strip()
            if key and code:
                keys.add(key)
    return keys, imports


with zipfile.ZipFile(args.archive) as archive:
    seen, merged = set(), set()

    def merge(name):
        if name in seen:
            return
        seen.add(name)
        keys, imports = read_dictionary(archive, name)
        merged.update(keys)
        for child in imports:
            merge(child)

    merge("tigress.extended")
    tiger = sorted(k for k in merged if len(k) > 1)
    english, _ = read_dictionary(archive, "easy_english")
    english = sorted(k for k in english if len(k) > 1)



print(out, flush=True)
subset = tiger.copy()
random.Random(SEED + 1).shuffle(subset)
datasets = [write_fixture(out / "tiger.bin", tiger), write_fixture(out / "tiger75.bin", subset[:98304], 131072),
            write_fixture(out / "english.bin", english)]
# Force 512 keys into one initial bucket, exercising every distance sentinel,
# including the separate byte array's 255 sentinel. Excluded from timing tables.
stress_keys = []
for cp in range(0x4E00, 0x4E00 + 512):
    first = ((2166136261 ^ cp) * 16777619) & 0xFFFFFFFF
    stress_keys.append(chr(cp) + chr(0x3000 | (first & 1023)))
assert all(hash_key(key) & 1023 == 0 for key in stress_keys)
stress_fixture = write_fixture(out / "saturation.bin", stress_keys, 1024)
for index, method in enumerate(METHODS):
    subprocess.run(["cc", "-O3", "-std=c99", "-Wall", "-Wextra", "-Werror",
                    f"-DMETHOD={index}", str(ROOT / "scripts/bench_robin_hood.c"),
                    "-o", str(out / method)], check=True)
stress = {}
for method in METHODS:
    result = subprocess.run([str(out / method), stress_fixture["path"]], check=True,
                            text=True, capture_output=True)
    stress[method] = json.loads(result.stdout)
print("distance saturation checks passed", flush=True)
raw = []
for sample in range(args.samples):
    order = list(METHODS)
    random.Random(SEED + sample).shuffle(order)
    for dataset in datasets:
        for method in order:
            result = subprocess.run([str(out / method), dataset["path"]], check=True,
                                    text=True, capture_output=True)
            raw.append(dict(dataset=dataset["name"], method=method, sample=sample,
                            **json.loads(result.stdout)))
    print(f"completed sample {sample + 1}/{args.samples}", flush=True)
    (out / "raw.json").write_text(json.dumps(raw, indent=2))
summary = []
for dataset in datasets:
    for method in METHODS:
        rows = [r for r in raw if r["dataset"] == dataset["name"] and r["method"] == method]
        row = {k: v for k, v in rows[0].items() if k not in ("sample", "queries", "build_ms")}
        row["build_ms"] = statistics.median(r["build_ms"] for r in rows)
        row["queries"] = []
        for j, kind in enumerate(("hit", "near_miss", "random_miss")):
            query = dict(rows[0]["queries"][j], kind=kind)
            query["ns"] = [statistics.median(r["queries"][j]["ns"][i] for r in rows) for i in range(2)]
            query["cached_range_ns"] = [min(r["queries"][j]["ns"][0] for r in rows),
                                         max(r["queries"][j]["ns"][0] for r in rows)]
            row["queries"].append(query)
        summary.append(row)
report = dict(cpu=cpu, seed=SEED, samples=args.samples, stress=stress,
              cpu_model=next(line.split(":", 1)[1].strip() for line in
                             Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")),
              cflags="-O3 -std=c99 -Wall -Wextra -Werror",
              query_order=["hit", "near_miss", "random_miss"],
              timing_order=["cached_hash", "decode_and_hash"],
              archive_sha256=hashlib.sha256(args.archive.read_bytes()).hexdigest(),
              compiler=subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
              datasets=datasets, results=summary)
(out / "report.json").write_text(json.dumps(report, indent=2))
for row in summary:
    print(row["dataset"], row["method"], "fp", row["fp_bits"], "distance", row["max_distance"],
          "saturated", row["saturated"], [(q["kind"], q["ns"], q["avg_probes"]) for q in row["queries"]])

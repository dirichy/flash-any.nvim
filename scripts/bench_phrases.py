"""Compare phrase scans with interval, prefix-hash, DAT and paged-root DAT indexes.

Requires v11 C sources, prepared v11 packages and workloads.json (see docs/benchmarks.md).
python scripts/bench_phrases.py --source-root /tmp/flash-any-native-v11 --data /tmp/flash-any-rime-ice --samples 7
Builds isolated modules; production files and external source tables stay unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--data", type=Path, required=True)
parser.add_argument("--output", type=Path)
parser.add_argument("--samples", type=int, default=7)
parser.add_argument("--datasets", nargs="+", default=["ice_uniform", "ice_annotated"])
parser.add_argument("--mod-bits", type=int, default=18)
parser.add_argument("--methods", nargs="+", choices=["hash", "dat", "paged", "range", "split", "packed", "packed-all"],
                    default=["hash", "dat", "paged", "range"])
parser.add_argument("--pool-images", type=Path, help="directory with DATASET.{plain,codes,all}.bin from bench_root_pool.cc")
parser.add_argument("--source-root", type=Path, default=ROOT, help="v11 C source snapshot for these historical format experiments")
args = parser.parse_args()
SOURCE = args.source_root.resolve()
if '"FANYBIN\\x0B"' not in (SOURCE / "src/native.h").read_text():
    parser.error("this experiment requires a v11 C source snapshot; pass --source-root PATH")
pool_modes = {"split": "plain", "packed": "codes", "packed-all": "all"}
if any(name in pool_modes for name in args.methods) and (not args.pool_images or args.mod_bits != 18):
    parser.error("pool methods require --pool-images and --mod-bits 18")
out = args.output or Path(tempfile.mkdtemp(prefix="flash-any-phrases-"))
out.mkdir(parents=True, exist_ok=True)
cpu = min(os.sched_getaffinity(0))
os.sched_setaffinity(0, {cpu})
print(out, flush=True)
flags = ["-O3", "-fPIC", "-Wall", "-Wextra", "-Werror",
         "-I" + str(ROOT / "vendor/luajit"), "-I" + str(SOURCE / "src")]
binary = (SOURCE / "src/binary.c").read_text().replace(
    '#include "native.h"', '#include "native.h"\nextern void bench_prepare_index(const Dictionary *dictionary);')
binary = binary.replace("  /* The dictionary contains borrowed pointers:",
                        "  if (instance->phrase_depth) bench_prepare_index(dictionary);\n  /* The dictionary contains borrowed pointers:")
(out / "binary.c").write_text(binary)
objects = []
for name, source in (("native", SOURCE / "src/native.c"), ("scan", SOURCE / "src/scan.c"),
                     ("binary", out / "binary.c")):
    obj = out / (name + ".o")
    subprocess.run(["cc", "-std=c99", *flags, "-c", str(source), "-o", str(obj)], check=True)
    objects.append(str(obj))
# The paged variant starts a prefix and obtains scalar codes in one root lookup.
# Keep this scanner change isolated from the production format and implementation.
scan = (SOURCE / "src/scan.c").read_text()
before, phrase = scan.split("static Result *scan_phrases", 1)
phrase, after = phrase.split("Result *scan_line", 1)
scan = phrase
replacements = [
    ('  int32_t first = -1;\n  while (1)', '  int32_t first = -1;\n  const unsigned char *first_codes = NULL;\n  while (1)'),
    ('count == 1 && first >= 0 ? scalar_codes(&instance->table, (uint32_t)first) : NULL',
     'count == 1 && first >= 0 ? first_codes : NULL'),
    ('? scalar_codes(&instance->table, (uint32_t)first)\n                                 : NULL',
     '? first_codes\n                                 : NULL'),
    ('      active[nactive++] = (ActivePrefix){.prefix = {0, instance->table.text.count, 0},\n'
     '                                         .glyph = glyph,\n'
     '                                         .col = col,\n'
     '                                         .before = before};\n', ''),
    ('    nactive = remaining;\n    last = col;',
     '    nactive = remaining;\n'
     '    if (!count) {\n'
     '      ActivePrefix root = {.glyph = glyph, .col = col, .before = before};\n'
     '      first_codes = bench_root_start(&instance->table, value, token.size, &root.prefix);\n'
     '      if (root.prefix.begin != NONE) active[nactive++] = root;\n'
     '    }\n    last = col;'),
]
for old, new in replacements:
    assert scan.count(old) == 1, ("scanner changed", old)
    scan = scan.replace(old, new)
(out / "paged-scan.c").write_text(
    before + 'extern const unsigned char *bench_root_start(const Dictionary *, uint32_t, uint32_t, TextPrefix *);\n'
    + "static Result *scan_phrases" + scan + "Result *scan_line" + after)
paged_scan = out / "paged-scan.o"
subprocess.run(["cc", "-std=c99", *flags, "-c", str(out / "paged-scan.c"),
                "-o", str(paged_scan)], check=True)
modules = {}
for name, kind in (("hash", 0), ("dat", 1), ("paged", 2)):
    if name not in args.methods:
        continue
    obj = out / (name + ".o")
    subprocess.run(["c++", "-std=c++17", *flags, f"-DINDEX_KIND={kind}", "-c",
                    str(ROOT / "scripts/bench_phrase_index.cc"), "-o", str(obj)], check=True)
    inputs = objects + [str(obj)]
    if kind == 2:
        inputs = [str(paged_scan) if p == str(out / "scan.o") else p for p in inputs]
    if kind:
        dat = out / (name + "-build.o")
        subprocess.run(["c++", "-std=c++17", *flags, "-DKIND=2", "-DBUILD_WIDE=1",
                        "-DCOMPRESS_FREE=1", "-DSIGNED_BASE=1", f"-DMOD_BITS={args.mod_bits}",
                        "-DBENCH_PHRASES", f"-DPAGED_ROOT={int(kind == 2)}", "-c", str(ROOT / "scripts/bench_trie.cc"),
                        "-o", str(dat)], check=True)
        inputs.append(str(dat))
    modules[name] = out / (name + ".so")
    subprocess.run(["c++", "-shared", *inputs, "-o", str(modules[name])], check=True)
for name in pool_modes:
    if name not in args.methods:
        continue
    obj = out / (name + ".o")
    subprocess.run(["c++", "-std=c++17", *flags, f"-DPOOL_RELOCATED={int(name != 'split')}", "-c",
                    str(ROOT / "scripts/bench_packed_root.cc"), "-o", str(obj)], check=True)
    inputs = [str(paged_scan) if p == str(out / "scan.o") else p for p in objects] + [str(obj)]
    modules[name] = out / (name + ".so")
    subprocess.run(["c++", "-shared", *inputs, "-o", str(modules[name])], check=True)
if "range" in args.methods:
    modules["range"] = out / "range.so"
    subprocess.run(["cc", "-std=c99", *flags, "-shared", *[str(SOURCE / ("src/" + name + ".c"))
                    for name in ("native", "binary", "scan", "prefix")],
                    "-o", str(modules["range"])], check=True)
indexed = [name for name in modules if name != "range"]
cached = [name for name in indexed if name not in pool_modes]
stamps = {}
for dataset in args.datasets:
    identity = hashlib.sha256((args.data / (dataset + ".bin")).read_bytes()).hexdigest()
    for method in cached:
        key = dataset + "." + method
        sources = [ROOT / "scripts/bench_phrase_index.cc"]
        if method in ("dat", "paged"):
            sources.append(ROOT / "scripts/bench_trie.cc")
        stamps[key] = dict(package=identity, mod_bits=args.mod_bits,
                           sources=[hashlib.sha256(path.read_bytes()).hexdigest() for path in sources])
stamp_path = out / "index-stamps.json"
old_stamps = json.loads(stamp_path.read_text()) if stamp_path.exists() else {}
for key, identity in stamps.items():
    if old_stamps.get(key) != identity:
        (out / (key + ".index")).unlink(missing_ok=True)


def run(dataset, method, prepare=False):
    env = dict(os.environ, NVIM_LOG_FILE=str(out / "nvim.log"))
    if method in pool_modes:
        env["FLASH_ANY_BENCH_INDEX"] = str(args.pool_images / (dataset + "." + pool_modes[method] + ".bin"))
    elif method != "range":
        env["FLASH_ANY_BENCH_INDEX"] = str(out / (dataset + "." + method + ".index"))
    command = ["nvim", "--clean", "-l", str(ROOT / "scripts/bench_phrases.lua"),
               str(modules[method]), str(args.data), dataset]
    if prepare:
        command.append("prepare")
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    if result.returncode:
        print(result.stderr, flush=True)
        result.check_returncode()
    row = json.loads(result.stdout)
    row["stderr"] = result.stderr
    return row


preparation = []
for dataset in args.datasets:
    for method in indexed:
        print("prepare", dataset, method, flush=True)
        row = run(dataset, method, True)
        preparation.append(dict(dataset=dataset, method=method, **row))
        (out / "preparation.json").write_text(json.dumps(preparation, indent=2))
        if method in cached:
            old_stamps[dataset + "." + method] = stamps[dataset + "." + method]
        stamp_path.write_text(json.dumps(old_stamps, indent=2))
raw = []
expected = {}
for sample in range(args.samples):
    methods = list(modules)
    random.Random(20261112 + sample).shuffle(methods)
    for dataset in args.datasets:
        for method in methods:
            print("sample", sample + 1, dataset, method, flush=True)
            row = run(dataset, method)
            if dataset not in expected:
                expected[dataset] = row["signatures"]
            assert row["signatures"] == expected[dataset], (dataset, method, "different scan results")
            raw.append(dict(dataset=dataset, method=method, sample=sample, **row))
            (out / "raw.json").write_text(json.dumps(raw, indent=2))
summary = []
for dataset in args.datasets:
    header = struct.unpack_from("<8I", (args.data / (dataset + ".bin")).read_bytes(), 8)
    scalar_bytes = (4352 + header[4] * 256) * 4 if header[4] else 0
    for method in modules:
        rows = [r for r in raw if r["dataset"] == dataset and r["method"] == method]
        cases = []
        for j, case in enumerate(rows[0]["rows"]):
            cases.append(dict(case, cpu_ms=statistics.median(r["rows"][j]["cpu_ms"] for r in rows),
                              elapsed_ms=statistics.median(r["rows"][j]["elapsed_ms"] for r in rows)))
        index = (args.pool_images / (dataset + "." + pool_modes[method] + ".bin")
                 if method in pool_modes else out / (dataset + "." + method + ".index"))
        index_bytes = index.stat().st_size if index.exists() else 0
        summary.append(dict(dataset=dataset, method=method, cases=cases,
                            extra_index_bytes=index_bytes, original_scalar_bytes=scalar_bytes,
                            combined_index_bytes=(None if method in pool_modes else
                                                  index_bytes + (0 if method == "paged" else scalar_bytes)),
                            image_contains_pool=method in pool_modes,
                            rss_kib=statistics.median(r["rss_kib"] for r in rows),
                            peak_rss_kib=max(r["peak_rss_kib"] for r in rows),
                            load_ms=statistics.median(r["load_ms"] for r in rows)))
report = dict(samples=args.samples, cpu=cpu, mod_bits=args.mod_bits, preparation=preparation, summary=summary,
              index_stamps=stamps, compiler=subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
              cpu_model=next(line.split(":", 1)[1].strip() for line in
                             Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")),
              codepoints_reused=True, hash_prefix_record_bytes=12)
if args.pool_images:
    report["pool_reader_sha256"] = hashlib.sha256((ROOT / "scripts/bench_packed_root.cc").read_bytes()).hexdigest()
    report["pool_images"] = {dataset + "." + mode: hashlib.sha256(
        (args.pool_images / (dataset + "." + mode + ".bin")).read_bytes()).hexdigest()
        for dataset in args.datasets for method, mode in pool_modes.items() if method in modules}
(out / "report.json").write_text(json.dumps(report, indent=2))
for row in summary:
    print(json.dumps(row), flush=True)

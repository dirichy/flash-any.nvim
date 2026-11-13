"""Compare Rime Darts, byte/codepoint DAT prototypes and fingerprinted hash.

First generate fixtures with bench_robin_hood.py, then:
python scripts/bench_trie.py --fixtures /tmp/flash-any-robin-hood-final \
    --darts-header /tmp/flash-any-rime-trie/darts.h
Uses installed MARISA for an additional control. Does not change the runtime.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--fixtures", type=Path, required=True)
parser.add_argument("--darts-header", type=Path, required=True)
parser.add_argument("--samples", type=int, default=7)
parser.add_argument("--datasets", nargs="+", default=["tiger"])
parser.add_argument("--packing", action="store_true", help="compare breadth/width order and free-link compression")
parser.add_argument("--wide-first", action="store_true", help="use width-first packing in the normal Trie comparison")
parser.add_argument("--compress-free", action="store_true", help="compress stale free links in the normal comparison")
parser.add_argument("--signed-base", action="store_true", help="also compare codepoint DAT with signed offsets")
parser.add_argument("--mod-bits", type=int, default=0, help="also compare modulo labels with original-label verification")
parser.add_argument("--methods", nargs="+", help="time only the named methods")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
out = args.output or Path(tempfile.mkdtemp(prefix="flash-any-darts-"))
out.mkdir(parents=True, exist_ok=True)
cpu = min(os.sched_getaffinity(0))
os.sched_setaffinity(0, {cpu})
shutil.copyfile(args.darts_header, out / "darts.h")
print(out, flush=True)

# Reuse the lookup benchmark's fixtures, validation, clock and timing loops.
# All methods use the same expanded query records and predecoded query storage.
common = (ROOT / "scripts/bench_robin_hood.c").read_text()
common = common.replace("offset, size, hash, expected;", "offset, size, hash, expected, cp_offset, cp_count;")
common = common.replace("static char *pool;", "static char *pool;\nstatic uint32_t *codepoints, cp_cursor;")
common = common.replace("  pool = malloc(header[2]);", "  pool = malloc(header[2]);\n  codepoints = malloc((size_t)header[2] * 4);")
old = "    read_exact(queries[j], count * sizeof(Query), f);"
assert old in common
common = common.replace(old, """    for (uint32_t i = 0; i < count; ++i) {
      Query *q = queries[j] + i;
      read_exact(q, 16, f);
      q->cp_offset = cp_cursor;
      const unsigned char *p = (const unsigned char *)pool + q->offset, *end = p + q->size;
      while (p < end) {
        uint32_t cp = *p++;
        if (cp >= 0xc0) {
          unsigned more = cp < 0xe0 ? 1 : cp < 0xf0 ? 2 : 3;
          cp &= (1u << (6 - more)) - 1;
          while (more--) cp = (cp << 6) | (*p++ & 63);
        }
        codepoints[cp_cursor++] = cp;
      }
      q->cp_count = cp_cursor - q->cp_offset;
    }""")
pos = common.index("static double measure(")
common = common[:pos] + """static uint32_t hash_ready(const Query *q) {
  uint32_t h = 2166136261u;
  for (uint32_t i = 0; i < q->cp_count; ++i)
    h = (h ^ codepoints[q->cp_offset + i]) * 16777619u;
  return h;
}

""" + common[pos:]
common = common.replace("  if (full) {\n    for (unsigned r", """  if (full == 2) {
    for (unsigned r = 0; r < rounds; ++r)
      for (uint32_t i = 0; i < count; ++i)
        total += lookup(qs + i, hash_ready(qs + i), NULL);
  } else if (full) {
    for (unsigned r""")
common = common.replace("full < 2", "full < 3")
common = common.replace("  free(pool);", "  free(pool);\n  free(codepoints);")
(out / "hash.c").write_text(common)

begin = common.index("static inline uint32_t lookup(")
end = common.index("static double seconds(", begin)
trie = common[:begin] + """extern size_t trie_build(const char **keys, const size_t *sizes, uint32_t count);
extern uint32_t trie_lookup(const char *key, size_t size);
#if CP_READY
extern uint32_t trie_lookup_cp(const uint32_t *key, size_t size);
#endif
static inline uint32_t lookup(const Query *q, uint32_t h, Stats *stats) {
  (void)h; (void)stats;
#if CP_READY
  return trie_lookup_cp(codepoints + q->cp_offset, q->cp_count);
#else
  return trie_lookup(pool + q->offset, q->size);
#endif
}

""" + common[end:]
begin = trie.index("  uint32_t *build_dist =")
end = trie.index("  unsigned fp_bits =", begin)
trie = trie[:begin] + """  const char **key_ptrs = malloc(count * sizeof(*key_ptrs));
  size_t *sizes = malloc(count * sizeof(*sizes));
  for (uint32_t i = 0; i < count; ++i) {
    key_ptrs[i] = pool + entries[i].offset;
    sizes[i] = strlen(key_ptrs[i]);
  }
  double build_start = seconds();
  size_t index_bytes = trie_build(key_ptrs, sizes, count);
  double build_ms = (seconds() - build_start) * 1e3;
  free(key_ptrs); free(sizes);
  uint32_t max_distance = 0, saturated = 0;
""" + trie[end:]
trie = trie.replace("(unsigned long long)capacity * (METHOD == 5 ? 5 : 4)", "(unsigned long long)index_bytes")
trie = trie.replace("full < 3", "full < 1")
(out / "trie.c").write_text(trie)
flags = ["-O3", "-Wall", "-Wextra", "-Werror"]
for method, index in (("linear", 0), ("fingerprint", 1), ("rh4", 2)):
    subprocess.run(["cc", "-std=c99", *flags, f"-DMETHOD={index}", str(out / "hash.c"),
                    "-o", str(out / method)], check=True)
methods = [] if args.packing else ["linear", "fingerprint", "rh4"]
variants = [("darts_byte", 0, 0, 0, 0, 0), ("dat_byte", 1, 0, 0, 0, 0),
            ("dat_cp_ready", 2, 1, 0, 0, 0), ("dat_cp_decode", 2, 0, 0, 0, 0),
            ("marisa_fast", 3, 0, 0, 0, 0)]
if args.signed_base:
    assert not args.packing, "--signed-base is a separate query/layout comparison"
    variants += [("dat_signed_cp_ready", 2, 1, 0, 0, 1), ("dat_signed_cp_decode", 2, 0, 0, 0, 1)]
if args.mod_bits:
    assert not args.packing and 1 <= args.mod_bits <= 21
    variants += [("dat_mod_cp_ready", 2, 1, 0, 0, 1), ("dat_mod_cp_decode", 2, 0, 0, 0, 1)]
if args.wide_first:
    assert not args.packing, "choose either --packing or --wide-first"
    variants = [(name, kind, ready, int(kind in (1, 2)), compress, signed)
                for name, kind, ready, _, compress, signed in variants]
if args.compress_free:
    assert not args.packing, "--packing already includes both free-link policies"
    variants = [(name, kind, ready, wide, int(kind in (1, 2)), signed)
                for name, kind, ready, wide, _, signed in variants]
if args.packing:
    variants = [("rime-original", 0, 0, 0, 0, 0)] + [
        (f"{unit}-wide{wide}-compress{compress}", kind, ready, wide, compress, 0)
        for unit, kind, ready in (("byte", 1, 0), ("cp", 2, 1))
        for wide, compress in ((0, 0), (1, 0), (0, 1), (1, 1))]
for method, kind, ready, wide, compress, signed in variants:
    methods.append(method)
    obj = out / (method + ".o")
    subprocess.run(["cc", "-std=c99", *flags, f"-DCP_READY={ready}", "-c", str(out / "trie.c"),
                    "-o", str(obj)], check=True)
    subprocess.run(["c++", "-std=c++17", *flags, f"-DKIND={kind}", f"-DBUILD_WIDE={wide}",
                    f"-DCOMPRESS_FREE={compress}", f"-DSIGNED_BASE={signed}",
                    f"-DMOD_BITS={args.mod_bits if method.startswith('dat_mod_') else 0}", "-isystem", str(out),
                    str(ROOT / "scripts/bench_trie.cc"), str(obj), "-lmarisa", "-o", str(out / method)], check=True)

if args.methods:
    assert set(args.methods) <= set(methods), "unknown method requested"
    methods = args.methods
raw = []
for sample in range(args.samples):
    order = methods.copy()
    random.Random(20261112 + sample).shuffle(order)
    for dataset in args.datasets:
        for method in order:
            print(f"sample {sample + 1}: {dataset} / {method}", flush=True)
            result = subprocess.run([str(out / method), str(args.fixtures / (dataset + ".bin"))],
                                    check=True, text=True, capture_output=True)
            raw.append(dict(dataset=dataset, method=method, sample=sample, **json.loads(result.stdout)))
            (out / "raw.json").write_text(json.dumps(raw, indent=2))
    (out / "raw.json").write_text(json.dumps(raw, indent=2))
    print(f"completed {sample + 1}/{args.samples}", flush=True)

summary = []
for dataset in args.datasets:
    data = (args.fixtures / (dataset + ".bin")).read_bytes()
    count, capacity, poolbytes = struct.unpack_from("<III", data)
    pool = data[12 + count * 8:12 + count * 8 + poolbytes]
    keybytes = 0
    for i in range(count):
        offset = struct.unpack_from("<I", data, 12 + i * 8)[0]
        keybytes += pool.index(0, offset) - offset + 1
    for method in methods:
        rows = [r for r in raw if r["dataset"] == dataset and r["method"] == method]
        row = dict(dataset=dataset, method=method, keys=count, bytes=rows[0]["bytes"],
                   build_ms=statistics.median(r["build_ms"] for r in rows), queries=[])
        for j, kind in enumerate(("hit", "near_miss", "random_miss")):
            timings = [statistics.median(r["queries"][j]["ns"][i] for r in rows)
                       for i in range(len(rows[0]["queries"][j]["ns"]))]
            ranges = [[min(r["queries"][j]["ns"][i] for r in rows),
                       max(r["queries"][j]["ns"][i] for r in rows)] for i in range(len(timings))]
            row["queries"].append(dict(kind=kind, ns=timings, ranges_ns=ranges))
        row["index_and_keys_bytes"] = row["bytes"] + (count * 8 + keybytes if method in ("linear", "fingerprint", "rh4") else 0)
        summary.append(row)
report = dict(cpu=cpu, samples=args.samples, summary=summary, packing=args.packing, wide_first=args.wide_first,
              compress_free=args.compress_free, signed_base=args.signed_base, mod_bits=args.mod_bits,
              cpu_model=next(line.split(":", 1)[1].strip() for line in
                             Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")),
              marisa=subprocess.check_output(["pkg-config", "--modversion", "marisa"], text=True).strip(),
              cflags="-O3 -Wall -Wextra -Werror",
              darts_sha256=hashlib.sha256(args.darts_header.read_bytes()).hexdigest(),
              fixtures={name: hashlib.sha256((args.fixtures / (name + ".bin")).read_bytes()).hexdigest()
                        for name in args.datasets},
              hash_timing_order=["cached_hash", "decode_and_hash", "predecoded_codepoints_and_hash"],
              compiler=subprocess.check_output(["c++", "--version"], text=True).splitlines()[0])
(out / "report.json").write_text(json.dumps(report, indent=2))
for row in summary:
    print(json.dumps(row), flush=True)

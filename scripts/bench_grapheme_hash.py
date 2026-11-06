"""Analyze multi-codepoint graphemes and benchmark experimental hashes, without changing runtime.

python scripts/bench_grapheme_hash.py --emoji /tmp/emoji-test.txt
Use Unicode 17 emoji-test.txt: https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt
"""
import argparse
from collections import Counter
import itertools
import json
import os
from pathlib import Path
import statistics
import struct
import subprocess
import sys
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parent.parent
METHODS = ('sum', 'poly31', 'poly33', 'poly65599', 'poly_golden', 'fnv_cp', 'fnv_bytes', 'rot5', 'rot13', 'poly33_mix', 'poly_golden_mix', 'structured', 'structured_mix')
parser = argparse.ArgumentParser()
parser.add_argument('--emoji', type=Path, required=True)
args = parser.parse_args()
assert sys.byteorder == 'little', 'benchmark input uses little-endian words'
out = Path(tempfile.mkdtemp(prefix='flash-any-grapheme-hash-'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
groups = {'emoji': [], 'nfd': [], 'hangul': [], 'mark_orders': [], 'grapheme_tests': []}
emoji_types = Counter()
for line in args.emoji.read_text().splitlines():
    raw = line.split('#', 1)[0].strip()
    if not raw or ';' not in raw:
        continue
    points = tuple(int(cp, 16) for cp in raw.split(';')[0].split())
    if len(points) < 2:
        continue
    groups['emoji'].append(''.join(map(chr, points)))
    kind = ('zwj' if 0x200D in points else 'flag' if all(0x1F1E6 <= cp <= 0x1F1FF for cp in points)
            else 'keycap' if 0x20E3 in points else 'tag' if any(0xE0020 <= cp <= 0xE007F for cp in points)
            else 'skin' if any(0x1F3FB <= cp <= 0x1F3FF for cp in points) else 'variation' if 0xFE0F in points else 'other')
    emoji_types[kind] += 1
for cp in range(0x110000):
    char = chr(cp)
    nfd = unicodedata.normalize('NFD', char)
    if len(nfd) > 1:
        groups['hangul' if 0xAC00 <= cp <= 0xD7A3 else 'nfd'].append(nfd)
for n in range(1, 7):
    for marks in itertools.product(('\u0300', '\u0301', '\u0308'), repeat=n):
        for base in ('a', 'b'):
            groups['mark_orders'].append(base + ''.join(marks))
for line in (ROOT / 'tests/data/GraphemeBreakTest-17.0.0.txt').read_text().splitlines():
    part = []
    for token in line.split('#')[0].split():
        if token == '÷':
            if len(part) > 1:
                groups['grapheme_tests'].append(''.join(part))
            part = []
        elif token != '×':
            part.append(chr(int(token, 16)))

# Validate with the repository's exact Unicode 17 segmenter; also inspect complete built-ins.
(out / 'input.json').write_text(json.dumps(groups))
(out / 'prepare.lua').write_text('''vim.opt.runtimepath:prepend(''' + json.dumps(str(ROOT)) + ''')
local path = ''' + json.dumps(str(out / 'input.json')) + '''
local file = assert(io.open(path)); local groups = vim.json.decode(file:read('*a')); file:close()
local grapheme = require('flash-any.grapheme')
for name, values in pairs(groups) do
  local ret = {}
  for _, value in ipairs(values) do if grapheme.len(value) == 1 then ret[#ret + 1] = value end end
  groups[name] = ret
end
local builtins = {}
for _, name in ipairs({'pinyin', 'tiger', 'wubi86', 'unicode', 'nerdfont'}) do
  local source = require('flash-any.source').resolve({name})[2]
  local data = require('flash-any.table').materialize(source.data)
  local stats = {entries = 0, single_scalar = 0, compound_grapheme = 0, words = 0}
  for key in pairs(data) do
    stats.entries = stats.entries + 1
    local clusters, scalars = 0, 0
    grapheme.each(key, function(_, _, count) clusters = clusters + 1; scalars = scalars + count end)
    if clusters > 1 then stats.words = stats.words + 1
    elseif scalars > 1 then stats.compound_grapheme = stats.compound_grapheme + 1
    else stats.single_scalar = stats.single_scalar + 1 end
  end
  builtins[name] = stats
end
io.write(vim.json.encode({groups=groups, builtins=builtins}))
''')
prep = subprocess.run(['nvim', '--clean', '-l', str(out / 'prepare.lua')], text=True, capture_output=True, check=True,
                      env=dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log')))
prepared = json.loads(prep.stdout)
groups = {name: sorted(set(values)) for name, values in prepared['groups'].items()}
groups['combined'] = sorted(set().union(*map(set, groups.values())))

def write_keys(path, values):
    with path.open('wb') as file:
        file.write(struct.pack('<I', len(values)))
        for value in values:
            data = value.encode()
            file.write(struct.pack('<II', len(value), len(data)))
            file.write(struct.pack('<' + 'I' * len(value), *map(ord, value)))
            file.write(data)

subprocess.run(['cc', '-O3', '-std=c99', '-Wall', '-Wextra', '-Werror', str(ROOT / 'scripts/bench_grapheme_hash.c'), '-o', str(out / 'hash')], check=True)
rows = []
for name, values in groups.items():
    path = out / (name + '.bin')
    write_keys(path, values)
    capacity = 1
    while capacity * 3 < len(values) * 4:
        capacity *= 2
    for method in METHODS:
        result = subprocess.run([str(out / 'hash'), str(path), method, 'hashes'], capture_output=True, check=True)
        hashes = struct.unpack('<' + 'I' * len(values), result.stdout)
        slots, probes = {}, []
        for h in hashes:
            slot, steps = h & (capacity - 1), 1
            while slot in slots:
                slot, steps = (slot + 1) & (capacity - 1), steps + 1
            slots[slot] = True
            probes.append(steps)
        rows.append(dict(group=name, method=method, keys=len(values), capacity=capacity,
                         collisions32=len(values) - len(set(hashes)),
                         collisions31=len(values) - len({h & 0x7FFFFFFF for h in hashes}),
                         collisions21=len(values) - len({h & 0x1FFFFF for h in hashes}),
                         bucket_collisions=len(values) - len({h & (capacity - 1) for h in hashes}),
                         average_probes=sum(probes) / len(probes), max_probes=max(probes)))
timings = []
for sample in range(3):
    for method in METHODS[::1 if sample % 2 == 0 else -1]:
        result = subprocess.run([str(out / 'hash'), str(out / 'combined.bin'), method, 'time'], text=True, capture_output=True, check=True)
        timings.append(dict(method=method, sample=sample, **json.loads(result.stdout)))
for row in rows:
    row['median_ns'] = statistics.median(r['median_ns'] for r in timings if r['method'] == row['method'])
report = dict(unicode_normalization_version=unicodedata.unidata_version, emoji_types=dict(emoji_types),
              builtins=prepared['builtins'], group_sizes={name: len(v) for name, v in groups.items()}, results=rows, timings=timings)
(out / 'report.json').write_text(json.dumps(report, indent=2))
print(out)
print(json.dumps({k: v for k, v in report.items() if k not in ('results', 'timings')}, ensure_ascii=False, indent=2))
for row in rows:
    if row['group'] == 'combined':
        print(json.dumps(row))

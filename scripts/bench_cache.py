"""Compare native text/result cache reuse in isolated, CPU-pinned processes.

python3 scripts/bench_cache.py --root /path/to/indexed-snapshot --samples 9
The rescan variant changes only the result-cache hit branch in a temporary C copy.
Production sources, libraries and configuration are untouched.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import statistics
import subprocess
import tempfile

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
parser = argparse.ArgumentParser()
parser.add_argument('--samples', type=int, default=9)
parser.add_argument('--root', type=Path, default=ROOT, help='Indexed implementation snapshot')
args = parser.parse_args()
ROOT = args.root.resolve()
out = Path(tempfile.mkdtemp(prefix='flash-any-cache-'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log'))
source = (ROOT / 'src/native.c').read_text()
assert 'make_text(L' in source, 'Text-index comparison requires an indexed snapshot; pass --root'
assert source.count('if (same) {') == 1
(out / 'rescan.c').write_text(source.replace('if (same) {', 'if (0 && same) {'))
cflags = ['-I', str(SCRIPTS.parent / 'vendor/luajit')]
libs = []
subprocess.run(shlex.split(os.environ.get('CC', 'cc')) + [
    '-O3', '-std=c99', '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror', *cflags,
    '-I', str(ROOT / 'src'), '-I', str(SCRIPTS.parent / 'build'), str(out / 'rescan.c'),
    '-o', str(out / 'rescan.so'), *libs, '-lm'], check=True)
build = subprocess.run(['nvim', '--clean', '-l', str(SCRIPTS / 'bench_merge.lua'),
                        str(ROOT), str(out), 'build'], env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
(out / 'build.jsonl').write_text(build.stdout)
print(out, flush=True)
records = []
modes = ['typing_cached', 'typing_rebuild', 'result_cached', 'result_rescan']
summary = []
for rows in (1, 40):
    for case in ('pinyin', 'all'):
        for sample in range(args.samples):
            order = modes[sample % len(modes):] + modes[:sample % len(modes)]
            for mode in order:
                library = out / 'rescan.so' if mode == 'result_rescan' else ROOT / 'lua/flash-any/native.so'
                result = subprocess.run(['nvim', '--clean', '-l', str(SCRIPTS / 'bench_cache.lua'),
                                         str(library), str(out / (case + '.bin')), str(rows), mode],
                                        env=env, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, check=True)
                records.append(dict(case=case, process=sample, **json.loads(result.stdout.strip())))
        group = [r for r in records if (r['rows'], r['case']) == (rows, case)]
        for a, b in [('typing_cached', 'typing_rebuild'), ('result_cached', 'result_rescan')]:
            assert len({tuple(r['samples'][0]['counts']) for r in group if r['mode'] in (a, b)}) == 1
        for mode in modes:
            selected = [r for r in group if r['mode'] == mode]
            elapsed = [statistics.median(sum(s['elapsed_ms']) for s in r['samples']) for r in selected]
            cpu = [statistics.median(sum(s['cpu_ms']) for s in r['samples']) for r in selected]
            summary.append(dict(rows=rows, case=case, mode=mode,
                                elapsed_ms=statistics.median(elapsed), cpu_ms=statistics.median(cpu),
                                counts=selected[0]['samples'][0]['counts']))
        (out / 'raw.json').write_text(json.dumps(records, indent=2))
        (out / 'summary.json').write_text(json.dumps(summary, indent=2))
        print('done', rows, case, flush=True)
for row in summary:
    print(json.dumps(row), flush=True)
print('finished', out, flush=True)

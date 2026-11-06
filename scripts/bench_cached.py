"""Compare cached Lua common-character scans with the merged C backend.

python scripts/bench_cached.py --samples 9
The baseline Lua snapshot is read from git; source files and editor configuration are untouched.
"""
import argparse
import io
import json
import os
from pathlib import Path
import statistics
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--samples', type=int, default=9)
parser.add_argument('--baseline-ref', default='d3f1fec', help='Git revision of the original Lua implementation')
args = parser.parse_args()
out = Path(tempfile.mkdtemp(prefix='flash-any-cached-bench-'))
head = out / 'head'
head.mkdir()
archive = subprocess.check_output(['git', 'archive', args.baseline_ref, 'lua'], cwd=ROOT)
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    files.extractall(head, filter='data')
commit = subprocess.check_output(['git', 'rev-parse', args.baseline_ref], cwd=ROOT, text=True).strip()
(out / 'baseline.json').write_text(json.dumps(dict(commit=commit, head_root=str(head)), indent=2))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log'))
# Reuse the same exact configurations as bench_merge; compilation is outside timing.
build = subprocess.run(['nvim', '--clean', '-l', str(ROOT / 'scripts/bench_merge.lua'), str(ROOT), str(out), 'build'], text=True, capture_output=True, check=True, env=env)
(out / 'build.jsonl').write_text(build.stdout + build.stderr)
print(out, flush=True)
versions = {'lua_head': (head, 'lua'), 'lua_reference': (ROOT, 'lua'), 'binary': (ROOT, 'binary')}
records = []
for rows in (1, 40):
    for case in ('pinyin', 'all'):
        for phase in ('cold', 'warm', 'new_jump'):
            for sample in range(args.samples):
                names = list(versions)
                names = names[sample % 3:] + names[:sample % 3]
                for version in names:
                    root, backend = versions[version]
                    process = subprocess.run(['nvim', '--clean', '-l', str(ROOT / 'scripts/bench_cached.lua'), str(root), str(out / (case + '.bin')), backend, case, phase, str(rows)], text=True, capture_output=True, check=True, env=env)
                    value = json.loads((process.stdout + process.stderr).strip())
                    records.append(dict(version=version, process=sample, **value))
            group = [r for r in records if (r['rows'], r['case'], r['phase']) == (rows, case, phase)]
            assert len({tuple(r['counts']) for r in group}) == 1, 'result counts differ'
            print('done', rows, case, phase, flush=True)
            (out / 'raw.json').write_text(json.dumps(records, indent=2))
summary = []
for rows in (1, 40):
    for case in ('pinyin', 'all'):
        for phase in ('cold', 'warm', 'new_jump'):
            for version in versions:
                group = [r for r in records if (r['rows'], r['case'], r['phase'], r['version']) == (rows, case, phase, version)]
                first = [statistics.median(s['elapsed_ms'][0] for s in r['samples']) for r in group]
                total = [statistics.median(sum(s['elapsed_ms']) for s in r['samples']) for r in group]
                cpu = [statistics.median(s['cpu_ms'][0] for s in r['samples']) for r in group]
                keys = [statistics.median(statistics.median(s['elapsed_ms'][i] for s in r['samples']) for r in group) for i in range(8)]
                summary.append(dict(rows=rows, case=case, phase=phase, version=version,
                                    first_ms=statistics.median(first), first_cpu=statistics.median(cpu),
                                    typing_ms=statistics.median(total), per_key_ms=keys, counts=group[0]['counts'], tsv_queries=0))
(out / 'summary.json').write_text(json.dumps(summary, indent=2))
for row in summary:
    print(json.dumps(row), flush=True)
print('finished', out, flush=True)

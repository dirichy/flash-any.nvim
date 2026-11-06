"""Compare independent native backends: python scripts/bench_merge.py BEFORE_ROOT [--samples 9]."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('before', type=Path)
parser.add_argument('--samples', type=int, default=9)
args = parser.parse_args()
out = Path(tempfile.mkdtemp(prefix='flash-any-merge-bench-'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log'))
roots = {'before': args.before.resolve(), 'after': ROOT}
def run(version, phase, case='pinyin'):
    folder = out / version
    folder.mkdir(exist_ok=True)
    result = subprocess.run(['nvim', '--clean', '-l', str(ROOT / 'scripts/bench_merge.lua'), str(roots[version]), str(folder), phase, case], text=True, capture_output=True, check=True, env=env)
    return [dict(version=version, **json.loads(line)) for line in (result.stdout + result.stderr).splitlines() if line.startswith('{')]
build = []
for version in roots:
    build.extend(run(version, 'build'))
(out / 'build.json').write_text(json.dumps(build, indent=2))
rows = []
for case in ('pinyin', 'all', 'graphemes'):
    for phase in ('cold', 'warm'):
        for sample in range(args.samples):
            for version in ('before', 'after')[::1 if sample % 2 == 0 else -1]:
                rows.extend(run(version, phase, case))
        group = [r for r in rows if r['case'] == case and r['phase'] == phase]
        assert len({tuple(r['counts']) for r in group}) == 1, 'backend result counts differ'
        print('done', case, phase, flush=True)
(out / 'raw.json').write_text(json.dumps(rows, indent=2))
summary = []
for case in ('pinyin', 'all', 'graphemes'):
    for phase in ('cold', 'warm'):
        for version in roots:
            group = [r for r in rows if (r['case'], r['phase'], r['version']) == (case, phase, version)]
            summary.append(dict(case=case, phase=phase, version=version,
                                load_ms=statistics.median(r['load_ms'] for r in group),
                                first_ms=statistics.median(r['elapsed_ms'][0] for r in group),
                                first_cpu=statistics.median(r['cpu_ms'][0] for r in group),
                                typing_ms=statistics.median(sum(r['elapsed_ms']) for r in group),
                                dictionary_kib=statistics.median(r['dictionary_kib'] for r in group), counts=group[0]['counts']))
(out / 'summary.json').write_text(json.dumps(summary, indent=2))
print(out, flush=True)
print(json.dumps(dict(build=build, summary=summary), indent=2), flush=True)

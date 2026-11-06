"""Compare indexed and sequential native scanning using complete plugin snapshots.

python3 scripts/bench_scan.py /path/to/indexed-snapshot --samples 9
The snapshot must include lua/ and its compiled native.so. Both backends use the
same package and fresh, CPU-pinned processes. Files in the snapshot are untouched.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('--samples', type=int, default=9)
args = parser.parse_args()
baseline = args.baseline.resolve()
assert (baseline / 'lua/flash-any/native.so').is_file()
out = Path(tempfile.mkdtemp(prefix='flash-any-scan-'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log'))
build = subprocess.run(['nvim', '--clean', '-l', str(ROOT / 'scripts/bench_merge.lua'),
                        str(ROOT), str(out), 'build'], env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
(out / 'build.jsonl').write_text(build.stdout)
(out / 'baseline.json').write_text(json.dumps({'root': str(baseline)}, indent=2))
print(out, flush=True)
versions = {'indexed': baseline, 'sequential': ROOT}
records, summary = [], []
for rows in (1, 40):
    for case in ('pinyin', 'all'):
        for phase in ('cold', 'warm', 'new_jump'):
            for sample in range(args.samples):
                order = list(versions)
                if sample % 2:
                    order.reverse()
                for version in order:
                    process = subprocess.run([
                        'nvim', '--clean', '-l', str(ROOT / 'scripts/bench_cached.lua'),
                        str(versions[version]), str(out / (case + '.bin')), 'binary', case, phase, str(rows)
                    ], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
                    records.append(dict(version=version, process=sample, **json.loads(process.stdout.strip())))
            group = [r for r in records if (r['rows'], r['case'], r['phase']) == (rows, case, phase)]
            assert len({tuple(r['counts']) for r in group}) == 1
            for version in versions:
                selected = [r for r in group if r['version'] == version]
                first = [statistics.median(s['elapsed_ms'][0] for s in r['samples']) for r in selected]
                total = [statistics.median(sum(s['elapsed_ms']) for s in r['samples']) for r in selected]
                cpu = [statistics.median(s['cpu_ms'][0] for s in r['samples']) for r in selected]
                summary.append(dict(rows=rows, case=case, phase=phase, version=version,
                                    first_ms=statistics.median(first), typing_ms=statistics.median(total),
                                    first_cpu_ms=statistics.median(cpu), counts=selected[0]['counts']))
            (out / 'raw.json').write_text(json.dumps(records, indent=2))
            (out / 'summary.json').write_text(json.dumps(summary, indent=2))
            print('done', rows, case, phase, flush=True)
for row in summary:
    print(json.dumps(row), flush=True)
print('finished', out, flush=True)

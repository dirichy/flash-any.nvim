# Build complete built-in packages, then benchmark native lookup in isolated processes.
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import build_native

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--marisa', action='store_true', help='also compare the installed MARISA library')
parser.add_argument('--packages', type=Path, help='reuse packages from an earlier run')
args = parser.parse_args()
OUT = Path(tempfile.mkdtemp(prefix='flash-any-binary-bench-'))
script = OUT / 'build.lua'
script.write_text('''vim.opt.runtimepath:prepend('''+json.dumps(str(ROOT))+''')
local build = require("flash-any.build")
local root = '''+json.dumps(str(OUT))+'''
for _, name in ipairs({"pinyin", "tiger", "wubi86", "unicode", "nerdfont"}) do
  local path = root .. "/" .. name .. ".bin"
  collectgarbage("collect")
  local start = vim.uv.hrtime()
  local sources, entries = build.binary({sources={name},output=path})
  print(vim.json.encode({name=name, entries=entries, bytes=assert(vim.uv.fs_stat(path)).size, build_ms=(vim.uv.hrtime()-start)/1e6}))
end
local codes = {}
for i=1,2000 do
  codes[vim.fn.nr2char(0x4E00 + i) .. "́"] = {"abc", "abcd"}
end
build.binary({sources={{data={codes=codes}}}, output=root .. "/graphemes.bin"})
''')
env = dict(os.environ, NVIM_LOG_FILE=str(OUT / 'nvim.log'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
if args.packages:
    import shutil
    for file in args.packages.glob('*.bin'): shutil.copyfile(file, OUT / file.name)
    build_output = 'reused packages from ' + str(args.packages)
else:
    result = subprocess.run(['nvim', '--clean', '-l', str(script)], env=env, text=True, capture_output=True, check=True)
    build_output = result.stdout + result.stderr
    (OUT / 'build.jsonl').write_text(build_output)
print(OUT, flush=True)
print(build_output, flush=True)
build_native.unicode_header(OUT / 'grapheme_data.h')
cflags = subprocess.check_output(['pkg-config','--cflags','luajit'],text=True).split()
libs = subprocess.check_output(['pkg-config','--libs','luajit'],text=True).split()
flags = ['-O3','-Wall','-Wextra','-Werror',*cflags,'-I',str(OUT),'-I',str(ROOT / 'src')]
modes = ['hash', 'scalar', 'pages', 'sorted']
if args.marisa:
    marisa_flags = subprocess.check_output(['pkg-config', '--cflags', 'marisa'], text=True).split()
    marisa_libs = subprocess.check_output(['pkg-config', '--libs', 'marisa'], text=True).split()
    subprocess.run(['cc', '-std=c99', *flags, '-DBENCH_MARISA', '-c', str(ROOT / 'scripts/bench_binary.c'), '-o', str(OUT / 'lookup.o')], check=True)
    subprocess.run(['c++', '-std=c++17', *flags, *marisa_flags, str(ROOT / 'scripts/bench_marisa.cc'), str(OUT / 'lookup.o'), '-o', str(OUT / 'lookup'), *libs, *marisa_libs, '-lm'], check=True)
    modes.extend(['marisa', 'marisa_reuse'])
else:
    subprocess.run(['cc','-std=c99',*flags,str(ROOT / 'scripts/bench_binary.c'),'-o',str(OUT / 'lookup'),*libs,'-lm'], check=True)
records = []
for name in ('pinyin','tiger','wubi86','unicode','nerdfont','graphemes'):
    for work in ('hit','miss'):
        for i in range(3):
            for mode in modes[::1 if i % 2 == 0 else -1]:
                result = subprocess.run([str(OUT / 'lookup'), str(OUT / (name+'.bin')),mode,work], text=True,capture_output=True,check=True)
                row = dict(table=name,mode=mode,workload=work,**json.loads(result.stdout))
                records.append(row)
                with (OUT / 'raw.jsonl').open('a') as log: log.write(json.dumps(row)+'\n')
        print('done',name,work,flush=True)
summary = []
for name,work,mode in sorted({(r['table'],r['workload'],r['mode']) for r in records}):
    rows = [r for r in records if (r['table'],r['workload'],r['mode'])==(name,work,mode)]
    summary.append(dict(table=name,workload=work,mode=mode,median_ns=statistics.median(r['median_ns'] for r in rows),
                        load_ms=statistics.median(r['load_ms'] for r in rows),index_bytes=rows[0]['index_bytes']))
(OUT / 'summary.json').write_text(json.dumps(summary,indent=2))
print('finished', OUT, flush=True)

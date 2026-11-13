"""Benchmark a simple single-grapheme Lua callback from a temporary native module.

Requires a v11 checkout (the scanner injection is historical).
python3 scripts/bench_lua_matcher.py --samples 9
Production C sources and APIs are untouched. The experimental callback takes
(grapheme, input, 1-based byte position), returning consumed bytes and/or next ASCII byte.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--samples', type=int, default=9)
parser.add_argument('--multiple', action='store_true', help='compare separate C calls with Lua fan-out')
args = parser.parse_args()
if '"FANYBIN\\x0B"' not in (ROOT / "src/native.h").read_text():
    parser.error("historical callback experiment requires a v11 checkout")
out = Path(tempfile.mkdtemp(prefix='flash-any-lua-matcher-'))
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, NVIM_LOG_FILE=str(out / 'nvim.log'))
subprocess.run(['make'], cwd=ROOT, check=True, stdout=subprocess.PIPE)
source = ('#define _POSIX_C_SOURCE 200809L\n#include "binary.c"\n#include "prefix.c"\n'
          + (ROOT / 'src/scan.c').read_text()
          + (ROOT / 'src/native.c').read_text())


def replace_once(old, new):
    global source
    assert source.count(old) == 1, old
    source = source.replace(old, new)


replace_once('typedef struct {\n  const unsigned char *codes, *letter_codes;', '''typedef struct {
  lua_State *L;
  int callback_mode, glyph_key;
  const unsigned char *codes, *letter_codes;''')
replace_once('static void match_codes(MatchContext *context) {', '''/* Experimental API, outside production: arguments remain pinned on the scan stack. */
static void match_lua(MatchContext *context) {
  lua_State *L = context->L;
  int multiple = lua_istable(L, 11);
  size_t count = multiple ? lua_objlen(L, 11) : 1;
  for (size_t i = 0; i < count; ++i) {
    if (multiple) lua_rawgeti(L, 11, (int)i + 1);
    else lua_pushvalue(L, 11);
    lua_pushvalue(L, context->glyph_key);
    lua_pushvalue(L, 8);
    lua_pushinteger(L, context->input_offset + 1);
    lua_call(L, 3, 2);
    lua_Integer consumed = lua_isnumber(L, -2) ? lua_tointeger(L, -2) : 0;
    lua_Integer next = lua_isnumber(L, -1) ? lua_tointeger(L, -1) : -1;
    lua_pop(L, 2);
    if (consumed > 0 && (uint64_t)consumed <= context->input_size - context->input_offset)
      emit(context, EMIT_CONSUMED, (uint32_t)consumed);
    if (next >= 0 && next < 128)
      emit(context, EMIT_NEXT, (uint32_t)next);
  }
}

static void match_codes(MatchContext *context) {
  if (context->callback_mode == 2) match_lua(context);''')
replace_once('  context->found = 0;\n  if (context->character)', '''  context->found = 0;
  if (context->callback_mode == 1) match_lua(context);
  if (context->character)''')
replace_once('  MatchContext context = {0};', '''  MatchContext context = {0};
  context.L = L;
  context.callback_mode = (lua_isfunction(L, 11) || lua_istable(L, 11)) ? luaL_optint(L, 12, 2) : 0;''')
replace_once('      result = scan_grapheme(L, result_index, result, &context, row, start, before);', '''      if (context.callback_mode) {
        lua_pushlstring(L, key.data, key.size);
        context.glyph_key = lua_gettop(L);
      }
      result = scan_grapheme(L, result_index, result, &context, row, start, before);
      if (context.callback_mode) lua_pop(L, 1);''')
replace_once('int luaopen_flash_any_native(lua_State *L) {', '''/* Dispatch microbenchmark; matching and rendering are measured separately above. */
static int bench_calls(lua_State *L) {
  int multiple = lua_istable(L, 1);
  luaL_argcheck(L, multiple || lua_isfunction(L, 1), 1, "callback or callback list required");
  luaL_checktype(L, 2, LUA_TTABLE);
  luaL_checktype(L, 3, LUA_TSTRING);
  uint32_t rounds = (uint32_t)luaL_checkinteger(L, 4);
  uint32_t count = (uint32_t)lua_objlen(L, 2);
  luaL_argcheck(L, count > 0, 2, "empty glyph list");
  size_t matchers = multiple ? lua_objlen(L, 1) : 1;
  uint64_t sum = 0;
  for (uint32_t i = 0; i < rounds; ++i) {
    for (size_t j = 0; j < matchers; ++j) {
      if (multiple) lua_rawgeti(L, 1, (int)j + 1);
      else lua_pushvalue(L, 1);
      lua_rawgeti(L, 2, (int)(i % count) + 1);
      lua_pushvalue(L, 3);
      lua_pushinteger(L, i % 3 + 1);
      lua_call(L, 3, 2);
      sum += (uint64_t)lua_tointeger(L, -2) + (uint64_t)lua_tointeger(L, -1);
      lua_pop(L, 2);
    }
  }
  lua_pushnumber(L, (lua_Number)sum);
  return 1;
}

int luaopen_flash_any_native(lua_State *L) {''')
replace_once('  lua_pushcfunction(L, load_binary);', '''  lua_pushcfunction(L, bench_calls);
  lua_setfield(L, -2, "bench_calls");
  lua_pushcfunction(L, load_binary);''')
(out / 'native.c').write_text(source)
cflags = ['-I', str(ROOT / 'vendor/luajit')]
libs = []
subprocess.run(shlex.split(os.environ.get('CC', 'cc')) + [
    '-O3', '-std=c99', '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror', *cflags,
    '-I', str(ROOT / 'src'), '-I', str(ROOT / 'build'), str(out / 'native.c'),
    '-o', str(out / 'native.so'), *libs, '-lm'], check=True)


def run(mode, case='common', phase='warm', rows=40):
    library = ROOT / 'lua/flash-any/native.so' if mode == 'native' else out / 'native.so'
    result = subprocess.run([
        'nvim', '--clean', '-l', str(ROOT / 'scripts/bench_lua_matcher.lua'),
        str(ROOT), str(library), str(out), mode, case, phase, str(rows)
    ], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return json.loads(result.stdout.strip())


run('build')
print(out, flush=True)
if args.multiple:
    records, summary = [], []
    baseline = []
    for sample in range(args.samples):
        for mode in (['native', 'control'] if sample % 2 == 0 else ['control', 'native']):
            baseline.append(dict(process=sample, **run(mode)))
    expected = {tuple(r['signatures']) for r in baseline}
    assert len(expected) == 1
    (out / 'baseline.json').write_text(json.dumps(baseline, indent=2))
    for body in ('noop', 'split', 'repeat'):
        for count in (1, 2, 4, 8, 16):
            for sample in range(args.samples):
                routes = ['direct', 'batch'] if sample % 2 == 0 else ['batch', 'direct']
                for route in routes:
                    records.append(dict(body=body, count=count, route=route, process=sample,
                                        **run(f'multi_{route}_{body}_{count}')))
            group = [r for r in records if (r['body'], r['count']) == (body, count)]
            assert {tuple(r['signatures']) for r in group} == expected, 'separate/batched/C results differ'
            for route in ('direct', 'batch'):
                selected = [r for r in group if r['route'] == route]
                total = [statistics.median(sum(s['elapsed_ms']) for s in r['samples']) for r in selected]
                cpu = [statistics.median(sum(s['cpu_ms']) for s in r['samples']) for r in selected]
                summary.append(dict(body=body, count=count, route=route,
                                    total_ms=statistics.median(total), cpu_ms=statistics.median(cpu),
                                    callbacks=selected[0]['callbacks'], counts=selected[0]['counts']))
            (out / 'raw.json').write_text(json.dumps(records, indent=2))
            (out / 'summary.json').write_text(json.dumps(summary, indent=2))
            print('done', body, count, flush=True)
    micro = []
    for count in (1, 2, 4, 8, 16):
        for sample in range(args.samples):
            routes = ['direct', 'batch'] if sample % 2 == 0 else ['batch', 'direct']
            for route in routes:
                micro.append(dict(count=count, route=route, process=sample,
                                  **run(f'multi_micro_{route}_{count}')))
        group = [r for r in micro if r['count'] == count]
        assert len({r['checksum'] for r in group}) == 1
    (out / 'micro.json').write_text(json.dumps(micro, indent=2))
    for row in summary:
        print(json.dumps(row), flush=True)
    for count in (1, 2, 4, 8, 16):
        for route in ('direct', 'batch'):
            selected = [r for r in micro if (r['count'], r['route']) == (count, route)]
            print('micro', count, route,
                  statistics.median(statistics.median(r['ns_per_group']) for r in selected), 'ns/group')
    print('finished', out, flush=True)
    raise SystemExit(0)
modes = ['native', 'control', 'noop_glyph', 'noop_request', 'lua_match']
records, summary = [], []
for rows in (1, 40):
    for case in ('common', 'complex'):
        for phase in ('cold', 'warm'):
            for sample in range(args.samples):
                order = modes[sample % len(modes):] + modes[:sample % len(modes)]
                for mode in order:
                    records.append(dict(process=sample, **run(mode, case, phase, rows)))
            group = [r for r in records if (r['rows'], r['case'], r['phase']) == (rows, case, phase)]
            assert len({tuple(r['signatures']) for r in group}) == 1, 'results/labels differ'
            for mode in modes:
                selected = [r for r in group if r['mode'] == mode]
                first = [statistics.median(s['elapsed_ms'][0] for s in r['samples']) for r in selected]
                total = [statistics.median(sum(s['elapsed_ms']) for s in r['samples']) for r in selected]
                cpu = [statistics.median(sum(s['cpu_ms']) for s in r['samples']) for r in selected]
                summary.append(dict(rows=rows, case=case, phase=phase, mode=mode,
                                    first_ms=statistics.median(first), total_ms=statistics.median(total),
                                    cpu_ms=statistics.median(cpu), counts=selected[0]['counts'],
                                    callbacks=selected[0]['callbacks']))
            (out / 'raw.json').write_text(json.dumps(records, indent=2))
            (out / 'summary.json').write_text(json.dumps(summary, indent=2))
            print('done', rows, case, phase, flush=True)
micro = []
for sample in range(args.samples):
    for mode in (['micro_c', 'micro_lua'] if sample % 2 == 0 else ['micro_lua', 'micro_c']):
        micro.append(dict(process=sample, **run(mode)))
(out / 'micro.json').write_text(json.dumps(micro, indent=2))
assert len({r['checksum'] for r in micro}) == 1, 'dispatch checksums differ'
for row in summary:
    print(json.dumps(row), flush=True)
for mode in ('micro_c', 'micro_lua'):
    selected = [r for r in micro if r['mode'] == mode]
    print(mode, statistics.median(statistics.median(r['ns_per_call']) for r in selected), 'ns/call')
print('finished', out, flush=True)

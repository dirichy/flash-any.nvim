"""Compare prebuilt/direct syllable matchers and optional-byte C prototypes.

python scripts/bench_pinyin.py --baseline-native V7_NATIVE.c [--samples 7] [--nvim PATH]
Production sources and native.so are never rewritten. See prototype_pinyin.h.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def patch_native(baseline):
    code = baseline.read_text()

    def replace(old, new):
        nonlocal code
        assert code.count(old) == 1, (old, code.count(old))
        code = code.replace(old, new)

    replace('#define BINARY_MAGIC "FANYBIN\\7"', '#define BINARY_MAGIC "FANYPYI\\1"')
    replace('#define ENGINE_MT "flash-any.native-engine"', '#define ENGINE_MT "flash-any.pinyin-prototype-engine"')
    replace('MATCH_PREFIX, MATCH_SUFFIX };', 'MATCH_PREFIX, MATCH_SUFFIX, MATCH_PINYIN, MATCH_SKIP };')
    replace('typedef struct {\n  Dictionary table;\n} Engine;',
            'typedef struct PinyinData PinyinData;\ntypedef struct PinyinMatch PinyinMatch;\n'
            'typedef struct {\n Dictionary table;\n PinyinData *pinyin;\n} Engine;')
    replace('uint32_t width; /* Input byte length + 1. */',
            'PinyinMatch *pinyin;\n uint32_t nsyllables;\n uint32_t width; /* Input byte length + 1. */')
    replace('  Slice codes;\n  const char *input;',
            '  Slice codes;\n PinyinData *syllables;\n const PinyinMatch *pinyin;\n uint32_t nsyllables;\n  const char *input;')
    replace('  Dictionary *dictionary = &instance->table;',
            '  instance->pinyin = NULL;\n  Dictionary *dictionary = &instance->table;')
    replace('mode > MATCHER_TAG + MATCH_SUFFIX', 'mode > MATCHER_TAG + MATCH_SKIP')
    replace('mode > MATCH_SUFFIX', 'mode > MATCH_SKIP')
    replace('''      lua_rawgeti(L, -1, 2);
      luaL_checktype(L, -1, LUA_TSTRING);''', '''      lua_rawgeti(L, -1, 2);
      if (mode == MATCH_PINYIN) {
        int id = luaL_checkint(L, -1);
        if (id < 0 || id >= 16384) return luaL_error(L, "invalid syllable ID");
        char encoded[2] = {(char)(id >> 7), (char)(id & 127)};
        lua_pop(L, 1);
        lua_pushlstring(L, encoded, 2);
      }
      luaL_checktype(L, -1, LUA_TSTRING);''')
    replace('''      while (p < limit && *p < 128) {
        ++p;
      }''', '''      while (p < limit && (*p < 128 || (mode == MATCHER_TAG + MATCH_SKIP && *p == 0xA0))) {
        if (*p == 0xA0) {
          if (p + 1 == limit || p[1] >= 128) return luaL_error(L, "invalid optional byte");
          p += 2;
        } else ++p;
      }
      if (mode == MATCHER_TAG + MATCH_PINYIN && p - code != 2)
        return luaL_error(L, "invalid syllable ID");''')
    replace('''        if ((unsigned char)code[k] >= MATCHER_TAG) {
          return luaL_error(L, "binary codes must be ASCII");
        }''', '''        if (mode == MATCH_SKIP && (unsigned char)code[k] == 0xA0 && k + 1 < length &&
            (unsigned char)code[k + 1] < 128) ++k;
        else if ((unsigned char)code[k] >= MATCHER_TAG) return luaL_error(L, "binary codes must be ASCII");''')
    replace('static void match_codes(MatchContext *context) {',
            '#include "prototype_pinyin.h"\nstatic void match_codes(MatchContext *context) {')
    replace('''    while (p < end && *p < 128) {
      ++p;
    }
    uint32_t length = (uint32_t)(p - code);''', '''    while (p < end && (*p < 128 || (mode == MATCH_SKIP && *p == PY_SKIP))) {
      p += *p == PY_SKIP ? 2 : 1;
    }
    uint32_t length = (uint32_t)(p - code);
    if (mode == MATCH_PINYIN) {
      pinyin_match(context, ((unsigned)code[0] << 7) | code[1]);
      continue;
    }
    if (mode == MATCH_SKIP) {
      pinyin_skip_match(context, code, length);
      continue;
    }''')
    replace('  context.input = input;',
            '  context.syllables = instance->pinyin;\n context.pinyin = requests->pinyin;\n context.nsyllables = requests->nsyllables;\n context.input = input;')
    replace('  Requests requests = {0};',
            '  Requests requests = {0};\n requests.pinyin = pinyin_query(L, instance->pinyin, input, (uint32_t)length);\n'
            ' requests.nsyllables = instance->pinyin ? instance->pinyin->count : 0;')
    replace('{"new_state", new_state}, {"has", has_lines}',
            '{"pinyin", pinyin_attach}, {"new_state", new_state}, {"has", has_lines}')
    replace('  lua_newtable(L);\n  lua_pushcfunction(L, load_binary);',
            '  lua_newtable(L);\n lua_pushcfunction(L, pinyin_pack);\n lua_setfield(L, -2, "pack_pinyin");\n  lua_pushcfunction(L, load_binary);')
    replace('  integer_field(L, "suffix", MATCH_SUFFIX);',
            '  integer_field(L, "suffix", MATCH_SUFFIX);\n integer_field(L, "pinyin", MATCH_PINYIN);\n'
            ' integer_field(L, "skip", MATCH_SKIP);')
    return code


def run(nvim, output, *args):
    env = dict(os.environ, NVIM_LOG_FILE=str(output / "nvim.log"))
    result = subprocess.run([nvim, "--clean", "-l", str(ROOT / "scripts/bench_pinyin.lua"),
                             str(output), *args], cwd=ROOT, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return json.loads(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-native", type=Path, required=True, help="v7 native.c before shared-syllable integration")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--nvim", default="nvim")
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix="flash-any-pinyin-"))
    print(output, flush=True)
    os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
    source = output / "native.c"
    source.write_text(patch_native(args.baseline_native))
    command = ["cc", "-O3", "-std=c99", "-fPIC", "-shared", "-Wall", "-Wextra", "-Werror",
               "-I" + str(ROOT / "vendor/luajit"), "-I" + str(ROOT / "src"),
               "-I" + str(ROOT / "scripts"), str(source), "-o", str(output / "native.so")]
    (output / "compile_commands.json").write_text(json.dumps([
        dict(directory=str(ROOT), file=str(source), arguments=command)]))
    subprocess.run(command, check=True)
    sizes = run(args.nvim, output, "build")
    for suffix in ("", "-unicode"):
        assert (output / ("syllables-plain" + suffix + ".bin")).read_bytes() == (
            output / ("syllables-fuzzy" + suffix + ".bin")).read_bytes(), "fuzzy settings changed per-character data"
    print(json.dumps(sizes), flush=True)
    checked = run(args.nvim, output, "check")
    print(json.dumps(checked), flush=True)
    rows = []
    for fuzzy in ("plain", "fuzzy"):
        for line_count in (1, 40):
            for sample in range(args.samples):
                modes = ["expanded", "shared", "syllables", "ondemand", "skip"]
                if sample % 2:
                    modes.reverse()
                for mode in modes:
                    rows.append(run(args.nvim, output, "scan", mode, fuzzy, str(line_count)))
            (output / "raw.json").write_text(json.dumps(rows, indent=2))
            group = [r for r in rows if (r["fuzzy"], r["lines"]) == (fuzzy, line_count)]
            assert len({tuple(r["counts"]) for r in group}) == 1, "benchmark match counts differ"
            print("done", fuzzy, line_count, flush=True)
    summary = []
    for fuzzy in ("plain", "fuzzy"):
        for line_count in (1, 40):
            for mode in ("expanded", "shared", "syllables", "ondemand", "skip"):
                selected = [r for r in rows if (r["fuzzy"], r["lines"], r["mode"]) == (fuzzy, line_count, mode)]
                row = dict(fuzzy=fuzzy, lines=line_count, mode=mode)
                for key in ("cold_cpu_ms", "typing_cpu_ms", "cold_wall_ms", "typing_wall_ms", "load_cpu_ms", "profile_memory"):
                    row[key] = statistics.median(r[key] for r in selected)
                summary.append(row)
                print(json.dumps(row), flush=True)
    (output / "summary.json").write_text(json.dumps(dict(sizes=sizes, checked=checked, rows=summary), indent=2))


if __name__ == "__main__":
    main()

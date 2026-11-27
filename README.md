# ⚡ flash-any.nvim

[简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

> **Migration in progress — currently unstable.** `main` uses the C matching core and a new configuration API.
> For the previous version, see the [master branch README](https://github.com/dirichy/flash-any.nvim/blob/master/README.old.md).

Jump with Latin variants, Chinese pinyin, Japanese romaji, Korean keyboard strokes, icon names or custom encodings.
Built on [flash.nvim](https://github.com/folke/flash.nvim), with runtime matching handled entirely in C.

![s jumps, shared-code f repeats, remote delete and offscreen mixed search](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[HD MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [Playback verification](https://github.com/dirichy/flash-any.nvim/releases/download/demos/verification.json)

The demo starts with `s` label jumps for Chinese, Korean and icons, then `fz` and repeated `f` jumps,
`dr` remote deletion, and incremental mixed search beyond the screen. Continue typing to skip near matches.

## Installation and setup

Requires Neovim **0.11+**, flash.nvim, and make with a C toolchain (GCC or Clang)
for the initial build and updates.
Public Lua/C headers are bundled. Linux and macOS have been verified; Windows is not currently supported.

The core includes Unicode literal matching (the literal matching functionality of flash.nvim)
and the optional `latin` source. `sources = {}` enables literal matching alone;
`sources = { "latin" }` also matches Latin letter variants. Other tables are provided by external plugins:

- [`dirichy/flash-any-pinyin.nvim`](https://github.com/dirichy/flash-any-pinyin.nvim) — Chinese pinyin and double pinyin
- [`dirichy/flash-any-tiger.nvim`](https://github.com/dirichy/flash-any-tiger.nvim) — Chinese Tiger shape codes
- [`dirichy/flash-any-japanese.nvim`](https://github.com/dirichy/flash-any-japanese.nvim) — Japanese romaji for kana, kanji and dictionary words
- [`dirichy/flash-any-korean.nvim`](https://github.com/dirichy/flash-any-korean.nvim) — Korean Dubeolsik keyboard strokes
- [`dirichy/flash-any-nerdfont.nvim`](https://github.com/dirichy/flash-any-nerdfont.nvim) — Nerd Font icons

A lazy.nvim configuration for the demo sources, including `f/F/t/T`:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  lazy = false,
  dependencies = {
    "folke/flash.nvim",
    "dirichy/flash-any-pinyin.nvim",
    "dirichy/flash-any-japanese.nvim",
    "dirichy/flash-any-korean.nvim",
    "dirichy/flash-any-nerdfont.nvim",
  },
  build = "make",
  opts = { sources = { "latin", "pinyin", "japanese", "korean", "nerdfont" }, char = true },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
    { "<leader>/", function() require("flash-any").search() end, desc = "Flash Any search" },
  },
}
```

Keep only the external sources you need, removing both their dependency and source
name. Tiger users can add dirichy/flash-any-tiger.nvim and select tiger instead of
pinyin. The built-in latin source needs no extra plugin. Displaying icons requires
a Nerd Font in your terminal.

With other managers, configure an install/update hook to run `make` in the plugin
directory. vim-plug uses `{'do': 'make'}` and packer.nvim uses `run = "make"`.
Without a build hook, run `make` in the plugin directory after installation and updates,
then load the dependencies and call:

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

The plugin loads the prebuilt C module and asks you to run `make` if it is missing or
cannot be loaded. Setup caches the dictionary for reuse on later startups.
Other Flash jump options, such as `labels`, `search` and `jump`,
can still be passed to setup. `jump(opts)`, `remote(opts)` and `search(opts)` merge
single-call Flash options with setup and reuse its dictionary. Configure `sources`,
`binary` and `char` only in setup; runtime calls never build another dictionary.

## Usage

Press `s`, type a query, then choose a displayed label. The same source configuration
accepts all of these examples, including the final query as one continuous search:

| Example | Buffer text | Query |
| --- | --- | --- |
| Latin accents | café | `cafe` |
| Chinese pinyin | 中文 | `zhongwen` |
| Japanese romaji | 食べる | `taberu` |
| Korean Dubeolsik | 한글 | `gksrmf` |
| Nerd Font icon |  | `vim` |
| Mixed input | café 中文 한글 食べる  | `cafe zw gksrmf taberu vim` |

In the mixed query, zw uses Chinese initials; the spaces are literal ASCII. Full
pinyin and initials can mix too. Initials use the first letter: 输 is s, not sh.
Other code tables and double-pinyin schemes are documented by their source plugins.
If no label appears at the expected position, keep typing.

Jump searches display non-overlapping matches on each line so trailing labels have
clear ranges. Earlier endings win; matches with the same end prefer the shorter
range. Hidden alternatives still participate when you continue typing.

In operator-pending mode, press `dr`, search for the target and select a label, then
type `iW` to delete the remote word and return to the original position, as shown in the demo.
Use `yr` to copy instead. `iW` selects the whole nonblank word, including mixed kanji/kana.

ASCII literal text and the built-in latin table follow Neovim's `ignorecase` and
`smartcase` settings, including in `f/F/t/T`. Enabling `ignorecase` ignores letter
case; with `smartcase` also enabled, a query containing an uppercase letter becomes
case-sensitive. Option changes take effect on the next match.

With `sources = { "latin" }`, `e` matches `é` and `é`, `o` matches `ø`, `ae` matches
`æ`, and `ss` matches `ß`. Capital letters retain capital codes (`É` → `E`, `Æ` → `AE`),
following the `ignorecase` / `smartcase` settings above. Combining suffixes after a
letter are consumed with the entire grapheme. See [Latin coverage and data sources](docs/latin.md).

Korean matching uses keyboard positions rather than romanization: `gksrmf → 한글`.
Keep English input active; `rk → 가` and `Rk → 까` stay distinct regardless of
`ignorecase` / `smartcase`. See the [Korean source](https://github.com/dirichy/flash-any-korean.nvim).

### Search mode

`search()` uses the same sources to find the next match in the current buffer,
wrapping at the end and including offscreen results. Typing previews the target;
Enter confirms, Esc restores the original position, and Backspace edits the query.
There are no labels or automatic confirmation when only one match remains.
Preview and highlighting run asynchronously in batches; editing cancels the old query.
Enter finishes any pending work synchronously. Batches yield after about 2 ms, but
matching a single very long line cannot be interrupted and may still pause input.

The plugin provides the `search()` API without registering default mappings.
The lazy.nvim example above maps `<leader>/` to search; change or remove that entry
as needed. With other plugin managers, add a mapping after setup:

```lua
vim.keymap.set("n", "<leader>/", function() require("flash-any").search() end, { desc = "Flash Any search" })
```

For example, with pinyin configured, `zhongwen` finds 中文. ASCII punctuation is
literal, with no regex syntax. `search(opts)` accepts Flash options, for example
`search({ search = { forward = false, wrap = false } })`. These options override setup
for this call while retaining its dictionary. This separate entry point leaves
native `/`, its search register, and native `n`/`N` unchanged.

### Character motions f/F/t/T

Set `char = true` in flash-any's setup to connect all `f/F/t/T` motions automatically:

```lua
require("flash-any").setup({ sources = { "latin", "pinyin" }, char = true })
```

`char` is a boolean, default `false`, configured only in setup.
Character motions use setup's sources.
`fz` matches codes beginning with z and literal z. Flash owns keys, labels, counts,
`;`/`,` repeats and operators. Existing Flash options such as `multi_line`, `jump_labels`
and custom keys are preserved; `modes.char.enabled = false` still disables Flash's character mode.
Configure Flash before flash-any: a later `require("flash").setup()` can replace the matcher.
Calling flash-any setup again with `char = false` (or omitting it) restores the previous matcher
if this plugin still owns it. The low-level `require("flash-any").char` callback remains available
for manual integration. In lazy.nvim, enabling `char` also requires loading the plugin at startup
(`lazy = false`), so f works before the first s jump.


## Configure tables

Select sources in setup. Latin is built in; Chinese, Japanese, Korean and icon sources
come from the plugins listed above and must load before setup:

```lua
require("flash-any").setup({
  sources = {
    "latin",
    "pinyin",
    "japanese",
    "korean",
    "nerdfont",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
  },
})
```

Use `binary = "/path/flash-any.bin"` to specify a fixed output path. If the file is
missing, it is built from sources; specifying only binary loads an existing file.
Failed builds retain the old output, and existing searches continue using their
snapshot.

Missing dictionaries are built asynchronously in a headless Neovim process, keeping the
editor responsive. Setup and `:FlashAnyBuildTable` notify when construction starts.
Searches during construction use the previous dictionary,
or literal matching if none exists, and notify once per search. Each query keeps one
immutable dictionary snapshot across all batches and Enter. After a successful build,
the next change to query input or a new search uses the new dictionary; unchanged input
keeps its current snapshot. Source factories/converters must be available on runtimepath;
the worker does not load your init.lua or inherit in-memory Lua state.

Named sources use author-provided versions for cache invalidation (default `0`);
package files are no longer scanned. Authors must bump the version after dictionary or
conversion changes; restart Neovim after updating source modules. After manual edits, use:

```lua
require("flash-any").rebuild()
```

This asynchronously rebuilds the latest setup's sources, retaining its Flash options
and current query snapshots. Each setup configuration runs at most one build at a time;
repeated calls during construction reuse that task without queuing another. If data
changes during construction, call rebuild again after it finishes. Setup must include
`sources`; a binary-only setup cannot be rebuilt. See the [source version contract](docs/sources.md#工厂--factory).

The v14 format requires regenerating older explicit binaries; automatic caches rebuild.
Run make after updating and restart Neovim to load the new native module.
`require("flash-any.build").binary()` remains available for explicit exports and development tools.

| Source | Contents / default behavior |
| --- | --- |
| `latin` | Latin letter variants, `letter` |
| `pinyin` | Full pinyin, accepting full codes and initials; defaults to full codes when a scheme is configured |
| `japanese` | Kana and dictionary kanji/word readings, romaji spelling groups, `full_code` |
| `korean` | Modern Hangul via Dubeolsik keyboard strokes, case-sensitive `full_code` |
| `nerdfont` | Nerd Font icon names, `prefix` |
| `tiger` | Tiger codes, with optional selection keys assigned by weight: space for the first candidate and semicolon for the second by default |

Double pinyin, fuzzy spelling and default selection keys are configured by the
corresponding source and documented with it.

Each source's `matcher` can use one of four built-in modes: `full_code`, `initial`,
`prefix` or `letter`. All ordinary sources participate in matching. A source with
`fallback = true` only provides codes for graphemes not recognized by earlier sources.
An empty code array also counts as recognized and blocks later fallbacks.

Sources can share spelling groups and combine them into syllable sequences. Each
syllable independently accepts full codes, initials or prefixes according to the
chosen matcher; see [group sequences and converters](docs/sources.md#内部编码组--internal-spelling-groups).

### Custom tables

Use `data` for punctuation and a few custom symbols; use `file` for dictionaries.
Automatic cache checks warn once per process when explicit `data` sources total
more than 200 text entries; multiple codes for one entry count once. This is a
performance hint, not a usage limit.

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent", ["中国"] = "zhongguo" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- Optional build-time code conversion
    -- converter = "/path/converter.lua",
  },
}
```

Third-party projects can directly provide Rime, TSV, CSV, whitespace-separated,
Fcitx or IBus tables, without sorting, a Lua common-character table or a source
module. Tab-separated tables use one code per row; repeat rows for multiple codes.
An optional `converter` points to a Lua file returning a code conversion function
that runs only at build time. See [integration and converters](docs/sources.md) ·
[third-party recording and README templates](demos/README.md#第三方码表--third-party-tables).

`data` accepts a single code string or an array of codes; codes must be nonempty
ASCII strings without NUL, or valid group references/sequences with Unicode names.
Group spellings remain ASCII. Lua factories and build-time conversions can generate tables.
For your first extension, follow the [step-by-step source guide](docs/writing-sources.md)
for local installation, verification and demo publication. See the
[table development reference](docs/sources.md) for complete options.

Keys may be complete Unicode 17 graphemes or phrases, such as `á`, `👩‍💻` or 中国.
Single characters and overlapping phrases of different lengths all participate;
input can continue into the following text after consuming a phrase's code.
Matches start and end at grapheme boundaries, stay within one line, and apply no Unicode normalization.
Byte positions follow Neovim conventions; highlighting covers the last codepoint
of a complex grapheme.

### Convert existing dictionaries

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Only the input and Lua output paths are required. format is
auto/rime/tsv/tab/csv/space/fcitx/ibus, and encoding defaults to utf-8. TSV uses one
text/code pair per row; repeat rows for multiple codes. Commas are preserved
literally, and duplicate entries are merged. The converter preserves original
phrase keys and reports their count; they can be compiled directly without filtering.
Codes cannot contain tabs or
newlines or NUL; supplementary direct Lua tables allow other non-NUL ASCII bytes.
Matching text or queries containing NUL has undefined behavior.

## Development and measurement

[Current implementation and validation](docs/development.md) · [Benchmarks](docs/benchmarks.md).
Run `make` to compile the C module and `make clean` to remove the shared library.
The Makefile uses GNU make 3.81-compatible syntax and does not invoke Neovim;
`CC`, `CPPFLAGS`, `CFLAGS` and `LDFLAGS` can be overridden. The Unicode header
`src/grapheme_data.h` is committed with the source and only needs to be generated
when maintainers update the data. clangd uses `compile_flags.txt` directly;
no compilation database needs to be generated.

## License

Project code is [MIT](LICENSE). Unicode data retains its upstream license; see
[THIRD_PARTY.md](THIRD_PARTY.md). Each independent source provides its own table
provenance and license. [Demo recording](demos/README.md).

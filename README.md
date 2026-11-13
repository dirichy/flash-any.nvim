# ⚡ flash-any.nvim

[简体中文](README.zh-CN.md)

> **Migration in progress — currently unstable.** `main` uses the C matching core and a new configuration API.
> For the previous version, see the [master branch README](https://github.com/dirichy/flash-any.nvim/blob/master/README.old.md).

Jump with pinyin, double pinyin, shape codes, icon names or custom encodings.
Built on [flash.nvim](https://github.com/folke/flash.nvim), with runtime matching handled entirely in C.

![Full pinyin, initials and continuous mixed input](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

## Installation and setup

Requires Neovim **0.11+**, flash.nvim, and make with a C toolchain (GCC or Clang)
for the initial build and updates.
Public Lua/C headers are bundled. Linux and macOS have been verified; Windows is not currently supported.

The core includes Unicode literal matching (the literal matching functionality of flash.nvim)
and the optional `latin` source. `sources = {}` enables literal matching alone;
`sources = { "latin" }` also matches Latin letter variants. Other tables are provided by external plugins:

- [`dirichy/flash-any-pinyin.nvim`](https://github.com/dirichy/flash-any-pinyin.nvim) — Chinese pinyin and double pinyin
- [`dirichy/flash-any-tiger.nvim`](https://github.com/dirichy/flash-any-tiger.nvim) — Chinese Tiger shape codes
- [`dirichy/flash-any-nerdfont.nvim`](https://github.com/dirichy/flash-any-nerdfont.nvim) — Nerd Font icons

A lazy.nvim configuration for Chinese users:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = { "folke/flash.nvim","dirichy/flash-any-pinyin.nvim" }, -- Tiger users: replace pinyin with tiger
  build = "make",
  opts = { sources = {
       "latin", -- Optional Latin letter variants
       "pinyin", -- Full pinyin; see the source plugin's README for options. Tiger users: replace pinyin with tiger and refer to its README.
    } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
  -- Enable character motions (f mode) with the following configuration
  -- config=function(_,opts)
  --   require("flash").setup({
  --   modes = {
  --       char = {
  --       matcher = function(win, state, range)
  --           return require("flash-any").char(win, state, range)
  --       end,
  --       -- multi_line = false,
  --       },
  --   },
  --   })
  --   require("flash-any").setup(opts)
  -- end
}
```

With other managers, configure an install/update hook to run `make` in the plugin
directory. vim-plug uses `{'do': 'make'}` and packer.nvim uses `run = "make"`.
Without a build hook, run `make` in the plugin directory after installation and updates,
then load the dependencies and call:

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

The plugin loads the prebuilt C module and asks you to run `make` if it is missing or
cannot be loaded. Setup immediately builds the dictionary binary when it is missing;
later startups reuse it. Other Flash jump options, such as `labels`, `search` and `jump`,
can still be passed to setup. `jump(opts)` / `remote(opts)` use separate, complete
configurations containing `sources` or `binary`; they do not inherit setup fields.

## Usage

Press `s`, type literal text or codes, then select a label to jump. Continuously mix
literal text, full pinyin, initials and other compiled encodings. For example,
`zhongguo` / `zg` matches 中国; with the Unicode table configured, `grin` matches 😀.
Initials use the first letter: 输 is `s`, not `sh`. If no label appears at the expected
position, keep typing.

In operator-pending mode, press `yr`, search for the target and select a label, then
type `iw` to copy a remote word and return to the original window. Use `dr` to delete.

ASCII literal text and the built-in latin table follow Neovim's `ignorecase` and
`smartcase` settings, including in `f/F/t/T`. Enabling `ignorecase` ignores letter
case; with `smartcase` also enabled, a query containing an uppercase letter becomes
case-sensitive. Option changes take effect on the next match.

With `sources = { "latin" }`, `e` matches `é` and `é`, `o` matches `ø`, `ae` matches
`æ`, and `ss` matches `ß`. Capital letters retain capital codes (`É` → `E`, `Æ` → `AE`),
following the `ignorecase` / `smartcase` settings above. Combining suffixes after a
letter are consumed with the entire grapheme. See [Latin coverage and data sources](docs/latin.md).

### Character motions f/F/t/T

After this plugin's setup, add this to **Flash's configuration**:

```lua
require("flash").setup({
  modes = {
    char = {
      matcher = function(win, state, range)
        return require("flash-any").char(win, state, range)
      end,
      -- multi_line = false,
    },
  },
})
```

`fz` matches characters whose codes begin with `z` and literal `z`; with flypy double
pinyin, `fv` matches 中 and `v`. Flash handles F/t/T, counts, `;`/`,` repeats, operators
and labels. Remove `modes.char.matcher` to restore Flash's native character matching.
This callback only bridges to Flash; it is not a custom code matcher.

## Configure tables

Select sources in setup. `latin` is built in; pinyin and Tiger come from the source
plugins listed above:

```lua
require("flash-any").setup({
  sources = {
    "latin",
    "pinyin",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
  },
})
```

Use `binary = "/path/flash-any.bin"` to specify a fixed output path. If the file is
missing, it is built from sources; specifying only binary loads an existing file.
Failed builds retain the old output, and existing searches continue using their
snapshot. Initial compilation runs synchronously during setup.
The v13 format requires regenerating older explicit binaries; automatic caches rebuild.
Run make after updating and restart Neovim to load the new native module.
`require("flash-any.build").binary()` remains available for explicit exports and development tools.

| Source | Contents / default behavior |
| --- | --- |
| `latin` | Latin letter variants, `letter` |
| `pinyin` | Full pinyin, accepting full codes and initials; defaults to full codes when a scheme is configured |
| `tiger` | Tiger codes, with optional selection keys assigned by weight: space for the first candidate and semicolon for the second by default |

Double pinyin, fuzzy spelling and default selection keys are configured by the
corresponding source and documented with it.

Each source's `matcher` can use one of four built-in modes: `full_code`, `initial`,
`prefix` or `letter`. All ordinary sources participate in matching. A source with
`fallback = true` only provides codes for graphemes not recognized by earlier sources.
An empty code array also counts as recognized and blocks later fallbacks.

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
ASCII strings without NUL. Lua factories and build-time conversions can generate tables.
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

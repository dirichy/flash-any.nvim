# ⚡ flash-any.nvim

[简体中文](README.zh-CN.md)

Jump with pinyin, double pinyin, shape codes, icon names and custom encodings.
Built on [flash.nvim](https://github.com/folke/flash.nvim), with a C-only matching core.

![Pinyin and mixed input](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

## Installation and setup

Requires Neovim **0.11+**, flash.nvim, Python 3, a C compiler, GNU make **4.3+**,
`pkg-config` and LuaJIT development files. Currently tested on Linux.

Configure lazy.nvim; no manual build commands are needed:

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = { sources = { "pinyin", "nerdfont", "unicode" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
}
```

Without lazy.nvim, load the dependencies and call:

```lua
require("flash-any").setup({ sources = { "pinyin", "unicode" } })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

Setup automatically checks/builds the C module and immediately compiles a missing
dictionary. Later startups reuse the binary. Other Flash options such as `labels`,
`search` and `jump` pass through. `jump(opts)` / `remote(opts)` use standalone complete
options containing `sources` or `binary`, without inheriting setup fields.
Custom Lua matchers remain unsupported.

## Usage

Press `s`, type codes, then select a label. Mix ASCII, full pinyin, initials and
other compiled encodings. For example `zhongguo` / `zg` matches 中国; with the
Unicode source, `grin` matches 😀. Initials use the first letter (`s`, not `sh`).
ASCII literal matching is automatic.

In operator-pending mode, `yr`, a search and label, then `iw` yanks a remote word
and restores the original position. Use `dr` to delete. Flash owns operators,
restoration and rendering.

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

`fz` matches characters whose codes begin with z and literal z; with flypy, `fv`
includes 中 and v. Flash owns counts, repeats, operators and labels. Remove
`modes.char.matcher` to restore its original character matching. This callback is
only a Flash bridge, not a custom code matcher.

## Sources

Configure the selected sources in setup:

```lua
require("flash-any").setup({
  sources = {
    "pinyin",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger", append_space_below = 4 },
    "nerdfont",
    "unicode",
  },
})
```

Source order, scopes, fallback, schemes, fuzzy spelling and padding resolve when
building. Automatic packages live under `stdpath("cache")/flash-any/`, keyed by source
configuration and the C package/Unicode version. Changing source configuration selects
its own package. Editing an external table or factory at the same path requires clearing
the generated cache and calling setup again; file contents are not watched.

An optional `binary = "/path/flash-any.bin"` selects a fixed package: it is built from
`sources` only when missing. `binary` alone loads an existing package. Failed builds
retain the old output and already-running searches keep their snapshot. First-time
compilation runs synchronously during setup. `require("flash-any.build").binary()`
remains available for explicit exports and development tools.

| Source | Contents / default mode |
| --- | --- |
| `pinyin` | Full pinyin and initials; schemes default to full codes |
| `tiger` | Tiger codes, full_code |
| `wubi86` | Wubi86, full_code |
| `nerdfont` | Icon-name prefixes; requires a Nerd Font for display |
| `unicode` | Unicode-name prefixes, fallback by default |

Schemes: `flypy`, `pyjj`, `natural`, `abc`, `mspy`, `st`.
`fuzzy = true` uses built-in equivalence groups; custom `initials` / `finals`
groups are supported. `append_space_below = 4` appends one space to codes shorter
than four bytes; that space is part of the code.

`matcher` selects only `full_code`, `initial` or `prefix`. Ordinary sources all
participate. A fallback contributes only when no earlier source recognized that
grapheme; a recognized empty code list also blocks later fallbacks.

### Custom tables

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent" }, matcher = "prefix" },
  { lua = "/path/common.lua", tsv = "/path/full.tsv", matcher = "full_code" },
}
```

`data` accepts a code string or array per key; codes must be nonempty ASCII.
Scopes accept names (`all`, `ascii`, `chinese`, `unicode`, `private_use`) or mixed
character/range declarations, such as `{ { "a", "z" }, a = false, ["👩‍💻"] = true }`.
Scopes filter only during compilation. Matcher/scope functions and custom lazy
loaders are unsupported. Lua factories and build-time converters can generate
tables; see the [table author guide](docs/sources.md).

**Each key must contain exactly one complete Unicode17 grapheme**, such as á or
👩‍💻. Multi-grapheme keys such as 中国 are rejected; continuous input can still
match 中国 one grapheme at a time. No normalization is applied. Positions follow
Neovim byte conventions; highlighting includes a compound grapheme's last scalar.

### Convert dictionaries

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Only input and Lua output are required. Formats: auto/rime/tsv/tab/csv/space;
encoding defaults to utf-8. TSV uses tabs between text/codes and commas between
codes; duplicates merge. Conversion preserves and reports multi-grapheme keys;
filter these before compiling the current binary format. Imported codes cannot
contain commas, tabs or newlines; direct Lua tables allow other ASCII bytes.

## Development

[Implementation and validation](docs/development.md) · [Benchmarks](docs/benchmarks.md).
`make` also generates `build/grapheme_data.h` and `compile_commands.json` for
clangd. These and native.so are untracked build artifacts; rerun make if missing.

## License

Code: [MIT](LICENSE). Bundled dictionaries retain their upstream licenses; see
[THIRD_PARTY.md](THIRD_PARTY.md). [Demo recording](demos/README.md).

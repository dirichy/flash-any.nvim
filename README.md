# ⚡ flash-any.nvim

[简体中文](README.zh-CN.md)

> **Migration in progress — unstable.** The `main` branch is the new C implementation.
> APIs and configuration may change without compatibility with the old interface.
> Use `master` for the legacy version; select `main` explicitly to try this migration.

Jump with pinyin, double pinyin, shape codes, icon names and custom encodings.
Built on [flash.nvim](https://github.com/folke/flash.nvim), with a C-only matching core.

![Pinyin and mixed input](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

## Installation and setup

Requires Neovim **0.11+**, flash.nvim, make, and a C toolchain (GCC or Clang) for initial
builds and updates. No Python, CMake, pkg-config or separate LuaJIT development package
is needed. Public Lua/C headers are bundled. Linux is tested; the macOS build path
is prepared but has not yet been verified on a Mac.

The core includes ASCII literal matching only; `sources = {}` works on its own.
Pinyin, Tiger, Wubi, icon names and Unicode names are separate optional plugins.
Install only the sources you need and load them before setup. These five source
packages have not yet been publicly released during this migration.
For a local package, add `{ dir = "/path/to/flash-any-pinyin.nvim" }` as a dependency
and set `sources = { "pinyin" }`. Source packages contain Lua/data and need no make.

Configure lazy.nvim; no manual build commands are needed:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = { "folke/flash.nvim" },
  build = "make",
  opts = { sources = {} },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
}
```

With other managers, configure an install/update hook to run `make` in the plugin
directory. For example, vim-plug uses `{'do': 'make'}` and packer.nvim uses
`run = "make"`. Without a build hook, run `make` there after installation and updates,
then load the dependencies and call:

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

The plugin loads the prebuilt C module; missing or unloadable modules report an
error asking you to run `make`. Setup immediately compiles a missing dictionary. Later startups reuse the binary. Other Flash options such as `labels`,
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

After installing their separate plugins, select sources in setup:

```lua
require("flash-any").setup({
  sources = {
    "pinyin",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
    "nerdfont",
    "unicode",
  },
})
```

Source order, fallback, schemes, fuzzy spelling and padding resolve when
building. Automatic packages live under `stdpath("cache")/flash-any/`, keyed by source
configuration and the C package/Unicode version. Changing source configuration selects
its own package. External dictionary, Rime import, Lua/TSV companion and converter
files are tracked by absolute path, size and modification time (including nanoseconds).
Installed Lua/TSV files under lua/flash-any are tracked once per process; restart
Neovim after package updates. Changes select a new cache without reading entire tables
for content hashing. Edits preserving both size and modification time require manual
rebuilding. Arbitrary dependencies loaded by user Lua outside this namespace are not tracked.

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

Each source above lives in a separate `flash-any-NAME.nvim` plugin. Scheme, fuzzy
spelling and source defaults are documented by the corresponding source package.

`append_space_below = 4` appends one space to codes shorter
than four bytes; that space is part of the code.

`matcher` selects only `full_code`, `initial` or `prefix`. Ordinary sources all
participate. A fallback contributes only when no earlier source recognized that
grapheme; a recognized empty code list also blocks later fallbacks.

### Ranked selection keys

Any weighted file can assign optional suffixes without a Tiger source:

```lua
{ file = "/path/to/table.dict.yaml", selection = { keys = { " ", ";" } } }
```

Candidates are ranked by weight, then original order. Bare codes remain valid;
following text can consume leftover keys. Requires full_code and currently cannot
combine with converter, append_space_below or shared groups.
See [file selection and source factories](docs/sources.md).

### Custom tables

Use `data` for punctuation and a few custom symbols; use `file` for dictionaries. Automatic
cache setup warns once per process when explicit `data` sources total more than
200 text entries; multiple codes for one entry count once. This is advisory,
not a size limit.

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- Optional build-time conversion
    -- converter = "/path/converter.lua",
  },
}
```

Third-party projects need only a dictionary file (Rime, TSV, CSV, space, Fcitx or IBus) and a
built-in matcher ID. No sorting, Lua companion or source factory is required.
An optional `converter` file returns a build-time code-list conversion function.
See [integration and converters](docs/sources.md) and
[recording / README templates](demos/README.md#第三方码表--third-party-tables).

`data` accepts a code string or array per key; codes must be nonempty ASCII.
Runtime Lua matchers and custom loaders are unsupported. Lua factories and build-time
converters can generate
tables. Follow the [step-by-step source guide](docs/writing-sources.md) for local
installation, verification and demo publication; see the [reference](docs/sources.md)
for complete options.

**Each key must contain exactly one complete Unicode17 grapheme**, such as á or
👩‍💻. Multi-grapheme keys such as 中国 are rejected; continuous input can still
match 中国 one grapheme at a time. No normalization is applied. Positions follow
Neovim byte conventions; highlighting includes a compound grapheme's last scalar.

### Convert dictionaries

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Only input and Lua output are required. Formats: auto/rime/tsv/tab/csv/space/fcitx/ibus;
encoding defaults to utf-8. TSV uses one text/code pair per row; repeat rows for multiple codes. Commas are
literal code characters; duplicates merge. Conversion preserves and reports multi-grapheme keys;
file sources filter these automatically, while direct Lua/data inputs remain strict. Imported codes cannot
contain tabs or newlines; direct Lua tables allow other ASCII bytes.

## Development

[Implementation and validation](docs/development.md) · [Benchmarks](docs/benchmarks.md).
Run `make` to compile the C module, or `make clean` to remove it. The Makefile uses
GNU make 3.81-compatible syntax and does not invoke Neovim. `CC`, `CPPFLAGS`,
`CFLAGS` and `LDFLAGS` can be overridden. Unicode data is committed as
`src/grapheme_data.h`; updating it is a maintainer task, not an installation step.
`compile_flags.txt` supplies clangd with portable flags; no generated database is needed.

## License

Code: [MIT](LICENSE). Unicode data keeps its upstream license; see
[THIRD_PARTY.md](THIRD_PARTY.md). Each optional source ships its own data notices. [Demo recording](demos/README.md).

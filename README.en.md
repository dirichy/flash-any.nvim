# flash-any.nvim

[中文](README.md)

Jump with full pinyin, double pinyin, shape codes, or custom encodings using
[flash.nvim](https://github.com/folke/flash.nvim).

Requires Neovim 0.11+ and `folke/flash.nvim`. ASCII literal matching is included;
Chinese, emoji, and other characters use your configured sources.

## Installation

With lazy.nvim:

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = {
    sources = {
      { name = "pinyin", scheme = "flypy" },
      -- For Tiger, replace the pinyin source above with:
      -- { name = "tiger", strategy = "top_force", max_length = 4 },
    },
  },
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function() require("flash-any").jump() end,
      desc = "Flash any",
    },
  },
}
```

Without lazy.nvim, load the dependency and call:

```lua
require("flash-any").setup({ sources = { "pinyin" } })
vim.keymap.set({ "n", "x", "o" }, "s", function()
  require("flash-any").jump()
end)
```

## Configuration and jumping

`setup(opts)` validates and stores the complete default configuration.
`jump()` / `jump(nil)` uses it and reuses its source data and lazy lookup caches.

`jump` returns the Flash jump state. `jump(opts)` uses an independent
configuration without inheriting setup fields.
You must supply `sources`:

```lua
require("flash-any").jump({
  sources = { { name = "pinyin", scheme = "natural" } },
  labels = "asdfghjkl",
})
```

Other Flash options pass through. Source matchers define matching behavior;
the plugin owns Flash's top-level `matcher` and `labeler`. Options such as
`labels` use Flash's own defaults.

Configuration prepends a regular ASCII `literal` source before user sources.
It recognizes ASCII even when the input does not match; non-ASCII characters
return "unknown". Thus `sources = {}` matches ASCII only. Unicode name matching
is never enabled automatically.

## Built-in sources

Use a name string or a configuration object with `name`:

| Name | Purpose | Default matcher |
|---|---|---|
| `pinyin` | Full or double pinyin | `initial` for full, `full_code` for double |
| `tiger` | Tiger shape codes | `full_code` |
| `wubi86` | Wubi 86 codes | `full_code` |
| `unicode` | Short English Unicode names | `prefix`, with `fallback = true` |
| `nerdfont` | Short English Nerd Fonts icon names | `prefix` |

For 中国, full pinyin accepts `zg`, and Flypy accepts `vsgo`. ASCII and encodings
can mix: with `sources = { "pinyin" }`, `ag` matches `a国`.

### Pinyin and fuzzy spelling

Full pinyin and six double-pinyin schemes share one source. Configure at most
one pinyin source. Omit `scheme` for full pinyin:

| scheme | Layout |
|---|---|
| `flypy` | Xiaohe / Flypy |
| `pyjj` | Pinyin Jiajia |
| `natural` | Natural Code |
| `abc` | Intelligent ABC |
| `mspy` | Microsoft |
| `st` | Stone |

`scheme` belongs to the source, not to the top-level configuration. Both full
and double pinyin support `fuzzy = true`: `zh/z`, `ch/c`, `sh/s`, `ang/an`,
`eng/en`, and `ing/in`. Custom groups are also supported:

```lua
sources = {
  {
    name = "pinyin",
    scheme = "flypy", -- omit for full pinyin
    fuzzy = {
      initials = { { "zh", "z" }, { "ch", "c" } },
      finals = { { "ang", "an" } },
    },
  },
}
```

If groups overlap, the first containing a component wins. Scheme-specific
whole-syllable exceptions, including zero-initial rules, take precedence over
fuzzy conversion.

### Matchers and fallback

Code-table matchers support three modes:

- `full_code`: prefixes show candidates; only a complete code advances to the next text character.
- `initial`: either a full code or its first ASCII letter can advance.
- `prefix`: any nonempty code prefix can advance.

```lua
sources = {
  { name = "pinyin", scheme = "flypy", matcher = "prefix" },
  "unicode",
}
```

Ordinary sources all participate. A source with `fallback = true` runs only if
all earlier sources returned "unknown" for the character. A recognized character
blocks fallback even when its input failed. Unicode defaults to fallback; set
`fallback = false` explicitly to disable that policy.

The prepended literal source follows the same rule, so later fallback sources
do not process ASCII characters.

### Top-force codes

```lua
sources = {
  { name = "tiger", strategy = "top_force", max_length = 4 },
}
```

For Tiger, set `strategy = "top_force", max_length = 4` to enable top-force codes;
use just `"tiger"` without this behavior.
Codes shorter than `max_length` gain a trailing space; full-length codes do not.
`max_length` must be a positive integer.

## Custom sources

`data` maps a single UTF-8 character to an ASCII encoding or array of encodings:

```lua
sources = {
  {
    data = { ["中"] = { "vs", "ds" }, ["国"] = "go" },
    matcher = "full_code",
  },
}
```

A Lua common-character table can be paired with a complete TSV:

```lua
sources = {
  {
    lua = "/path/to/common.lua",
    tsv = "/path/to/full.tsv", -- optional
  },
}
```

Lua files return the same structure as `data`. Sort TSV rows by UTF-8 bytes,
with one character per row and comma-separated codes; LF and CRLF are supported. Paths may be relative to
the current directory, absolute, or start with `~`.

`loader = function(char) ... end` may return a code array or nil on a miss.
Both hits and misses are cached. A custom loader replaces the source's existing
TSV miss loader; it does not chain with it.

A custom matcher does not need a table. It receives `char, stream, args`, where
`args.source` is the runtime source. For example, match 中 with `x`:

```lua
sources = {
  {
    matcher = function(char, stream)
      if char ~= "中" then return nil end
      if stream == "" then return { { next = { x = true } } } end
      if stream:sub(1, 1) == "x" then return { { consumed = 1 } } end
      return {}
    end,
  },
}
```

Nil means unknown character; `{}` means recognized without a matching branch.
Successful results are branch arrays. Each branch has either `consumed` (a byte
count) or `next` (all remaining input matched; a set of possible next ASCII keys).
An empty stream queries starting keys only.

Every character prefix of a successful input must also succeed. Failed branches
are not retried after appends. Implementations own the dynamic return contract;
see `:help flash-any-matchers` and the [development notes](docs/development.md).

## Building tables and checking installation

```vim
:FlashAnyBuildTable source.dict common.lua full.tsv [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Input supports Rime, TSV, CSV, and whitespace-separated text. `format` accepts
`auto` (default), `rime`, `tsv`, `tab`, `csv`, or `space`; `encoding` defaults to
`utf-8`. Only single-character entries are included; duplicate codes are merged.

Without argument four, Lua contains all characters. An existing Lua table there
selects common characters for Lua output; TSV always contains the full set. Use
`-` when specifying format/encoding without selecting common characters:

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
```

Output codes must be ASCII without commas, tabs, or newlines. Output files are
overwritten; choose paths different from the input.

Text is processed as Unicode codepoints, not complete grapheme clusters such as
ZWJ emoji or combining sequences.

## License and sources

Project code is [MIT licensed](LICENSE). Bundled data retains its upstream
licenses and attribution; see [THIRD_PARTY.md](THIRD_PARTY.md). Tiger table source:
[the Tiger website](https://www.tiger-code.com/).

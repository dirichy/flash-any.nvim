# ⚡ flash-any.nvim

[简体中文](README.zh-CN.md)

Jump to Chinese, symbols, emoji, and other characters with familiar encodings.
`flash-any.nvim` adds common Chinese input-method codes, Nerd Fonts icon names,
Unicode names, and custom encodings to [flash.nvim](https://github.com/folke/flash.nvim).

![Full pinyin, initials, and mixed input](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[HD MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [Record the demo](demos/README.md)

## ✨ Features

- **Common Chinese encodings**: full pinyin, initials, six double-pinyin schemes, Tiger, and Wubi 86.
- **Mix inputs freely**: full pinyin, initials, ASCII, icon names, and Unicode names in one search.
- **Large character sets**: uncommon characters load on demand.
- **Fuzzy pinyin**: built-in fuzzy sounds and custom initial/final groups.
- **Bring your own codes**: custom tables and matchers; convert Rime, TSV, CSV, or whitespace-separated dictionaries.

## 📋 Requirements

- Neovim **0.11+**
- [folke/flash.nvim](https://github.com/folke/flash.nvim)

## 📦 Installation

With lazy.nvim:

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = {
    sources = {
      "pinyin", -- Full pinyin and initials
      -- For double pinyin, replace "pinyin" above with:
      -- { name = "pinyin", scheme = "flypy" }, -- Xiaohe / Flypy
      -- For shape codes, replace "pinyin" above with:
      -- { name = "tiger", append_space_below = 4 },
      -- Append one space to codes shorter than 4, matching short-code input habits.
      -- Omit append_space_below to use the original codes.
      "nerdfont", -- Icon names (requires a Nerd Font to display icons)
      "unicode", -- Unicode name fallback
    },
    -- Other Flash jump options can go here:
    -- labels = "asdfghjkl", -- Use these letters as jump labels
  },
  -- Uncomment to enable f mode.
  -- config = function(_, opts)
  --   require("flash").setup({
  --     modes = {
  --       char = {
  --         matcher = function(win, state, range)
  --           return require("flash-any").char(win, state, range)
  --         end,
  --         -- multi_line = false, -- Current line only
  --       },
  --     },
  --   })
  --   require("flash-any").setup(opts)
  -- end,
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function() require("flash-any").jump() end,
      desc = "Flash any",
    },
    {
      "r",
      mode = "o",
      function() require("flash-any").remote() end,
      desc = "Remote Flash any",
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

## 🚀 Usage

Press `s`, type a search, then press the label beside a match. Full pinyin and
initials work together by default; no search configuration changes are needed.

| Input | Matches | How |
| --- | --- | --- |
| `quanpin` | 全拼 | `quan` + `pin` |
| `jp` | 简拼 | First letter of each syllable: `j` + `p` |
| `hunsasciigrin` | 混输ascii😀 | `hun` + `s` + `ascii` + `grin` |

The mixed example uses `sources = { "pinyin", "unicode" }`. ASCII matches
literally, and `grin` is a prefix of the emoji's Unicode name.
An initial is the **first letter**, so 输 uses `s`, not `sh`.

### First-code jumps with `f/F/t/T`

![First-code matching and repeated jumps with f](https://github.com/dirichy/flash-any.nvim/releases/download/demos/char.gif)

[HD MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/char.mp4) · [Record the demo](demos/README.md)

First-code matching is **disabled by default**; `flash-any.setup()` alone does not
enable it. After calling `flash-any.setup()` as above, add this matcher to your
**flash.nvim configuration**:

```lua
require("flash").setup({
  modes = {
    char = {
      matcher = function(win, state, range)
        return require("flash-any").char(win, state, range)
      end,
      -- multi_line = false, -- Current line only
    },
  },
})
```

To disable first-code matching, remove `modes.char.matcher` from your Flash
configuration and restart Neovim; Flash resumes its literal character matching.
To disable Flash's entire character mode, set `modes.char.enabled = false` instead.
Neither change affects `s` searches. There is no separate `disable()` API.

Press `f` followed by one letter to match characters whose configured codes start
with that letter, plus the literal ASCII character. With full pinyin, `fz` matches
中, 这, 字, and `z`; with Flypy, `fv` matches 中 and `v`.
This shares sources, pinyin schemes, fuzzy spelling, and fallback rules with `s`,
but matches only one text character at a time. Custom sources retain their matchers.

Flash's character mode handles `F/t/T`, counts, `;`/`,`, operators, and optional
labels; no extra keymaps are needed. `t/T` stop at the previous/next grapheme
boundary, including around combining sequences and ZWJ emoji. It uses Flash's native labeler; `s` keeps
its existing label rules. Only the visible range is scanned for labels; offscreen
targets are scanned line by line when needed, stopping once the requested count
is found. Set `multi_line = false` to stay on the current line.

### Remote operators with `r`

Remote mode uses the same sources and search rules as `s`. The lazy.nvim
installation example includes the operator-pending `r` mapping. For manual
configuration, add this mapping after setup:

```lua
vim.keymap.set("o", "r", function()
  require("flash-any").remote()
end, { desc = "Remote Flash any" })
```

Press `yr`, type a search such as `zg` for 中国, select its label, then type `iw`.
Flash yanks the word at that target and restores your original window and cursor.
Use `dr` instead to delete the remote word. Remove the mapping to disable this entry.

`remote()` reuses the configuration and table caches saved by `setup()`.
Like `jump(opts)`, `remote(opts)` accepts a complete standalone configuration
including `sources`, and returns the Flash state. Flash handles the remote
operator and position restoration through its native `remote()` API.

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

`pinyin` (including double pinyin), `tiger`, and `wubi86` also match Chinese
punctuation by keyboard key: `,` matches `，`, `.` matches `。`, `/` or `\` matches `、`,
and `; : ? !` match `；：？！`. Quotes match `“”‘’`; `() [] <>` match `（）【】《》`.
Use `^` for `…`, `_` for `—`, a backtick for `·`, and `$` for `￥`.
For example, full pinyin `zg,a.` matches `中国，a。`.

Configuration automatically prepends ASCII literal matching before all sources;
you do not need to add it manually. Other ordinary sources still participate.
The plugin manages Flash's top-level `matcher` and `labeler`; configure character
matching through each source's `matcher`.

### Pinyin and fuzzy spelling

```lua
sources = {
  {
    name = "pinyin",
    scheme = "flypy", -- Double-pinyin scheme; omit for full pinyin
    fuzzy = { -- Custom groups; use fuzzy = true for the defaults
      initials = { { "zh", "z" }, { "ch", "c" } },
      finals = { { "ang", "an" } },
    },
  },
}
```

Full pinyin and six double-pinyin schemes share one `pinyin` source. Configure
at most one pinyin source. Omit `scheme` for full pinyin:

| scheme | Layout |
|---|---|
| `flypy` | Xiaohe / Flypy |
| `pyjj` | Pinyin Jiajia |
| `natural` | Natural Code |
| `abc` | Intelligent ABC |
| `mspy` | Microsoft |
| `st` | Stone |

Both full and double pinyin support fuzzy spelling. `fuzzy = true` enables the
default groups: `zh/z`, `ch/c`, `sh/s`, `ang/an`, `eng/en`, and `ing/in`.
If groups overlap, the first containing an initial or final wins.

### Matchers and fallback

Code-table matchers support three modes:

- `full_code`: prefixes show candidates; only a complete code advances to the next text character.
- `initial`: either a full code or its first ASCII letter can advance.
- `prefix`: any nonempty code prefix can advance.

Using the full-pinyin codes for 中国, compare which inputs match both characters
completely:

| Input | `full_code` | `initial` | `prefix` |
| --- | --- | --- | --- |
| `zhongguo` | ✓ | ✓ | ✓ |
| `zguo` | — | ✓ | ✓ |
| `zhguo` | — | — | ✓ |

`z` is the first letter of 中's code; `zh` is a prefix. All three matchers can
show candidates before a character's code is complete. They differ in when input
can advance to the next character.

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

### Spaces after short codes

```lua
sources = {
  { name = "tiger", append_space_below = 4 },
}
```

Codes shorter than `append_space_below` gain exactly one trailing space; codes
at or above the threshold stay unchanged. The threshold must be a positive integer.
Omit it to leave codes unchanged. This option also works with other code tables.
It suits shape-code users accustomed to confirming short codes with a space.

## 💡 Custom sources

`data` maps nonempty UTF-8 text to an ASCII encoding or array of encodings:

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
    matcher = "prefix",
  },
}
```

Lua files return the same structure as `data`. Sort TSV rows by UTF-8 bytes,
with one text entry per row and comma-separated codes; LF and CRLF are supported. Paths may be relative to
the current directory, absolute, or start with `~`.

A custom matcher does not need a table. It receives `text, stream, source, emit`. Both `text` and `stream` are `Cursor` objects. Read
all remaining content with `get()`, or up to n graphemes with `get(n)`; `source` is the runtime source. For example, match 中 with `x`:

```lua
sources = {
  {
    matcher = function(text, stream, source, emit)
      if text:get(1) ~= "中" then return false end
      if stream:get() == "" then
        emit("x")
      elseif stream:get(1) == "x" then
        emit(1)
      end
      return true
    end,
  },
}
```

Return `true` for a recognized position, even if the input does not match; return
`false` for an unknown position. Emit matching branches synchronously:

- `emit(bytes, chars?)` consumes input bytes and matches a text span.
- `emit(keys, chars?)` matches all remaining input; the ASCII string lists possible
  next keys. `emit("")` is success with no further keys.

`chars` defaults to 1. For example, `emit(3, 2)` consumes 3 input bytes and matches
2 buffer graphemes. An empty stream only queries next keys; it must not consume
input. Do not retain `emit` or call it after the matcher returns.

`get()` returns all remaining content, including an empty string at the end.
`get(n)` returns all remaining content when fewer than n graphemes remain. `text` holds a buffer
line; `stream` holds the complete input and points at its unconsumed portion.
Reads share cached boundaries and strings without moving the cursor. Sources may
only call `get`; `shift` (default 1 grapheme) and `set_offset` belong to the scanner. See the
[source author guide](docs/sources.md#文本读取--text-access) for the full contract.

Every character prefix of a successful input must also succeed. Failed branches
are not retried after appends. Implementations own the dynamic return contract;
see `:help flash-any-matchers` and the [development notes](docs/development.md).

## Third-party source plugins

See [dirichy/flash-any-gemoji.nvim](https://github.com/dirichy/flash-any-gemoji.nvim)
for an emoji source and an example of writing a third-party source. Installation,
configuration, and authoring instructions are in that project's README.

### Character scope

`scope` checks the current position before the matcher or lazy lookup. An excluded
source counts as unknown and does not block fallback. Declare it in a factory or
source configuration; explicit user configuration wins:

```lua
sources = {
  {
    name = "japan",
    scope = {
      { "ぁ", "ヿ" }, -- character bounds, inclusive
      ["あ"] = false, -- hash entries take precedence over ranges
      ["漢"] = true,  -- include a character outside the range
    },
  },
}
```

Strategy names are `"ascii"`, `"chinese"`, `"unicode"`, and `"private_use"`; `"all"`
removes the restriction. Numeric codepoint bounds also work, for example
`{ { 1, 10000 }, a = false }`. Numeric bounds convert once during initialization.
String keys and string bounds must each contain one grapheme.
Character hash values use Lua truthiness: false excludes, while code strings and
arrays include, so a single-grapheme extra table can also serve directly as scope.
Matching checks the complete grapheme hash first, then compares complete UTF-8
strings. Ranges use byte order: `{ { "a", "z" } }` includes `á` but excludes `ź`;
`{ ["a"] = true }` only includes the exact grapheme `a`. Custom functions receive the text cursor,
e.g. `scope = function(text) return text:get(2) == "きゃ" end`. An empty table accepts
nothing. Passing scope does not claim recognition; the matcher still decides.

## 🛠️ Building tables and checking installation

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Only the input and Lua output paths are required. Omit argument three to generate
Lua only; use `-` in its place when supplying later arguments. The Lua API also
accepts `build.table({ source = "source.tsv", lua = "out.lua" })` without `tsv`.

```vim
:FlashAnyBuildTable source.tsv out.lua
:FlashAnyBuildTable source.tsv out.lua - - tsv utf-8
```

Input supports Rime, TSV, CSV, and whitespace-separated text. `format` accepts
`auto` (default), `rime`, `tsv`, `tab`, `csv`, or `space`; `encoding` defaults to
`utf-8`. Single- and multi-codepoint entries are retained; duplicate codes are merged.

TSV input (`tsv`, `tab`, or tab-separated rows detected by `auto`) accepts
comma-separated codes in the second column, as well as one code per row:

```text
中	zhong,chong
中	zhong
国	guo
```

List items are trimmed, empty items ignored, and duplicates merged across rows.
The builder's output TSV can be used as input again. This list syntax applies to
TSV; CSV, Rime and whitespace-separated records retain their single-code fields.

Multi-codepoint text such as `中国`, `きゃ`, combining sequences, and ZWJ emoji is
retained. After a successful build, the command emits one warning with the count
of distinct multi-grapheme entries in the complete input, with or without TSV output. Lua output always wraps encodings in `codes` and carries
`prefixes`, `max_chars`, and `scope`; built-in matchers infer word support from this
metadata without source flags or length options. The bound counts text graphemes
in the complete input, even when the common Lua subset is empty. Lua-only prefixes
are a separate set of extendable keys, including keys with codes; omit leaves.
The generated scope spans the minimum and maximum first graphemes of all input
entries, providing a coarse filter before matching or TSV reads. Explicit source
scopes take precedence. The loader also accepts direct encoding maps. TSV must
contain all Lua code entries. Text keys cannot contain tabs or newlines.

`common-from.lua` specifies a Lua table used to select common entries. The
built-in `lua/flash-any/tables/tiger.lua` is one possible set (about 3,500 characters).
Without argument four, Lua output contains all entries. With an existing Lua
table, Lua output includes only entries whose keys appear in that table; when
requested, TSV contains the full set. Keep large character sets in TSV: loading a very large Lua
table slows startup.

Use `-` for argument four when specifying `format` / `encoding` without selecting
common characters:

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
:FlashAnyBuildTable source.tsv common.lua full.tsv - tsv utf-8
```

Individual codes must be ASCII without commas, tabs, or newlines. Output files are
overwritten; choose paths different from the input.

Text and input use Unicode 17 extended grapheme clusters: ZWJ emoji and combining
sequences each count as one grapheme. Matching starts only at grapheme boundaries;
byte offsets remain compatible with Neovim. No Unicode normalization is applied.

## 📄 License and sources

Project code is [MIT licensed](LICENSE). Bundled data retains its upstream
licenses and attribution; see [THIRD_PARTY.md](THIRD_PARTY.md). Tiger table source:
[the Tiger website](https://www.tiger-code.com/).

Demo scripts and recording instructions: [demos/README.md](demos/README.md).

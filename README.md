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
labels; no extra keymaps are needed. It uses Flash's native labeler; `s` keeps
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
    matcher = "prefix",
  },
}
```

Lua files return the same structure as `data`. Sort TSV rows by UTF-8 bytes,
with one character per row and comma-separated codes; LF and CRLF are supported. Paths may be relative to
the current directory, absolute, or start with `~`.

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

## 🛠️ Building tables and checking installation

```vim
:FlashAnyBuildTable source.dict common.lua full.tsv [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

Input supports Rime, TSV, CSV, and whitespace-separated text. `format` accepts
`auto` (default), `rime`, `tsv`, `tab`, `csv`, or `space`; `encoding` defaults to
`utf-8`. Only single-character entries are included; duplicate codes are merged.

`common-from.lua` specifies a Lua table used to select common characters. The
built-in `lua/flash-any/table/tiger.lua` is one possible set (about 3,500 characters).
Without argument four, Lua output contains all characters. With an existing Lua
table, Lua output includes only characters present in that table; TSV always
contains the full set. Keep large character sets in TSV: loading a very large Lua
table slows startup.

Use `-` for argument four when specifying `format` / `encoding` without selecting
common characters:

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
```

Output codes must be ASCII without commas, tabs, or newlines. Output files are
overwritten; choose paths different from the input.

Text is processed as Unicode codepoints, not complete grapheme clusters such as
ZWJ emoji or combining sequences.

## 📄 License and sources

Project code is [MIT licensed](LICENSE). Bundled data retains its upstream
licenses and attribution; see [THIRD_PARTY.md](THIRD_PARTY.md). Tiger table source:
[the Tiger website](https://www.tiger-code.com/).

Demo scripts and recording instructions: [demos/README.md](demos/README.md).

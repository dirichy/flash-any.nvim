# Provide a source for flash-any

[简体中文](writing-sources.zh-CN.md)

This tutorial targets the `main` branch. Start with a small dictionary and turn it into
an installable `flash-any-mycodes.nvim` plugin with a recorded demo. You need data and
a short Lua factory; you do not need to change the core or write C.

Local testing requires Neovim 0.11+, flash.nvim and flash-any.nvim built with `make`.
The source package itself needs no native build.

## 1. Create the package

Start with two files:

```text
flash-any-mycodes.nvim/
└── lua/flash-any/
    ├── sources/mycodes.lua
    └── tables/mycodes.tsv
```

`mycodes` is the name users put in `sources`. Keep the factory filename and its
`codetable` value consistent. Choose a name describing the language or encoding in
your actual project.

## 2. Prepare the dictionary

Save the following as UTF-8 in `lua/flash-any/tables/mycodes.tsv`. Separate text and
code with a real Tab; the example below can be copied directly:

```tsv
中	zhong
文	wen
重	zhong
重	chong
```

Each row contains one text key and one code. Repeat rows for multiple codes rather
than joining codes with commas. Commas are literal code characters. No sorting or
separate common-character cache is needed.

Keys can be complete graphemes, such as “中”, `á` or `👩‍💻`, or phrases such as “中文”.
Single characters and phrases participate together, only at grapheme boundaries and within one line.
Codes should be nonempty
ASCII without Tabs, newlines or NUL. Optional suffixes and group spellings must also exclude NUL.

For an existing Rime, CSV, Fcitx or similar dictionary, see
[file integration and conversion](sources.md#直接读取码表--dictionary-files).
You do not need a plugin just to use your own dictionary; a separate package makes it
convenient to distribute to others.

## 3. Provide the factory

Save this as `lua/flash-any/sources/mycodes.lua`:

```lua
return function()
  return {
    codetable = "mycodes",
    matcher = "full_code",
  }
end
```

`codetable` refers to the TSV from step 2. The factory returns configuration; the
core reads the data and matches it. No registration call is needed. You can also
start from the [factory template](../demos/templates/source.lua).

Choose the matching mode for your source:

| matcher | Accepted input |
| --- | --- |
| `full_code` | Complete code, such as `zhong` |
| `initial` | First letter or complete code, such as `z` or `zhong` |
| `prefix` | Any nonempty prefix, such as `z`, `zh` or `zhong` |

Keep `full_code` for this tutorial. A factory can process source-specific options
and build-time conversions; runtime Lua matchers are unsupported. See the
[factory reference](sources.md#工厂--factory) for further options.

## 4. Install locally

Add your local package as a lazy.nvim dependency and enable `mycodes`:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    { dir = "/absolute/path/to/flash-any-mycodes.nvim" },
  },
  build = "make",
  opts = { sources = { "mycodes" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
  },
}
```

Change `dir` to your package directory. Load the source before setup; the source
itself needs no `build` hook. The core's `make` builds its C module, and setup
compiles dictionary data when needed.

## 5. Check single-character and mixed input

Start a fresh Neovim with this configuration and open a buffer containing:

```text
中 文 重
中文 with flash
```

Press `s` and type `zhong`. Labels should appear for both “中” and “重”; select a
label to jump. Press `s` again and type `zhongwen with flash` to match the complete
second line. Ordinary ASCII works directly and need not be added to the dictionary.

Restart Neovim after editing the factory or dictionary. If it reports a missing
source, check runtimepath, the `sources/mycodes.lua` path and the configured name.
Use `:checkhealth flash-any` to check the environment. Cache behavior and cases
requiring manual rebuilds are covered in the [reference](sources.md).

## 6. Write the user-facing README

Copy the [English](../demos/templates/README.md) and
[Chinese](../demos/templates/README.zh-CN.md) templates. Replace `OWNER/TABLE`,
`SOURCE` and the input examples; `SOURCE` is `mycodes` here. Focus on installation,
what to type and how to jump. Keep maintenance commands in a separate document.
Document every user-facing option, default, enum value, practical example and
combination constraint. For pinyin, include every scheme, default fuzzy groups and
whether custom groups replace defaults. Keep common settings in the README and link
a reference for other user settings. Do not present factory-generated build metadata
as installation options.

For a language-specific source, use that language for the `README.md` homepage and
link the English translation as `README.en.md`. For a Chinese source, save the
Chinese template as `README.md` and the English template as `README.en.md`.
Language-neutral packages may keep an English homepage; update both language links.

Save the [maintenance template](../demos/templates/maintenance.md) as
`docs/maintenance.md`. Choose a license for your code and record the dictionary's
upstream provenance and terms separately; the code license does not license the data.

## 7. Record and publish a demo

Copy these templates into the source package:

| Template | Destination |
| --- | --- |
| [table-demo.lua](../demos/templates/table-demo.lua) | `demo.lua` |
| [table-demo.yml](../demos/templates/table-demo.yml) | `.github/workflows/demo.yml` |

Replace `SOURCE` with `mycodes` in `demo.lua`. The main fields for this example are:

```lua
return {
  file = "lua/flash-any/tables/mycodes.tsv",
  matcher = "full_code",
  text_name = "Chinese",
  text = "中",
  mixed_text = "中文 with flash",
  comment = "Flash can match Chinese: type a code, then choose a label.",
  mixed_comment = "Mix Chinese codes with ASCII in the same search.",
}
```

The template explains every field. Query codes come from the dictionary automatically.
Use `sample` for your own short sample file; paths are relative to `demo.lua`.
Omitting `text` chooses a font-covered random entry. The first scene demonstrates
multiple labels for one grapheme; the second mixes codes and ASCII and may also
have several labels. Keep the factory and demo modes consistent if you change them.

The workflow passes only `config: demo.lua`. Pin its `uses` reference and
`flash-any-ref` to the same tested commit published on the core's `main`, then push
your source repository to its GitHub `main` branch. Users can replace the local
`dir` dependency with `"OWNER/flash-any-mycodes.nvim"` after publication.

Every main push or manual dispatch records and verifies two actual jumps. On success,
it replaces GIF, MP4, cover and reports in the dedicated `demos` prerelease. README
links use stable asset URLs; generated media is never committed. Recording uses
read permissions; publishing alone receives `contents: write`.

After the first run, open the README to view the GIF and inspect the Actions report
and rendered frames. Edit `demo.lua` and push again to change targets, narration or
sample text. See the [recording guide](../demos/README.md) for local commands,
dependencies and font checks.

# My code table

<!-- Replace the title, OWNER/TABLE and TSV path. No Lua source module is needed. -->

Single-grapheme encodings for search and jump in Neovim with
[flash-any.nvim](https://github.com/dirichy/flash-any.nvim).

## Install

Requires Neovim 0.11+, plus make and a C toolchain for the initial native build.

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = { "folke/flash.nvim", "OWNER/TABLE" },
  build = "make",
  opts = function()
    local tsv = assert(vim.api.nvim_get_runtime_file("table.tsv", false)[1])
    return {
      sources = {
        { file = tsv, matcher = "full_code" },
      },
    }
  end,
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
  },
}
```

Press `s`, type the code, then select a label. ASCII literal matching is automatic.
Optionally set `converter = "/path/converter.lua"` on the source. The file returns
a code-list conversion function that runs only during compilation, never matching.

## Format

UTF-8 TSV: grapheme, Tab, then one code. Repeat rows for multiple codes.
Commas in codes are literal; sorting is unnecessary. Rime/CSV/Fcitx/IBus are also supported.
Each key must be one complete grapheme. Converted codes must be nonempty ASCII.

```text
中<TAB>zhong
中<TAB>chong
文<TAB>wen
```

## Demo

<!-- Download table.gif from the table-demo artifact into docs/table.gif first. -->
![Code-table search and jump](docs/table.gif)

Record against the unchanged project using flash-any's recording tools:

```sh
# Run in the flash-any.nvim checkout; see its demos/README.md for recording tools.
TABLE_FILE=/path/to/this-project/table.tsv sh demos/record.sh table
```

Alternatively copy flash-any's `demos/templates/table-demo.yml` to
`.github/workflows/demo.yml`, adjust the TSV path / matcher and run it manually.
The workflow uploads GIF, MP4, cover and live playback reports as an artifact.
It does not publish a release.

## License

<!-- State the actual project and upstream table licenses and provenance. -->

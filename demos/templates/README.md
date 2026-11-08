# My code table

[简体中文](README.md)

<!-- Replace OWNER/TABLE, SOURCE, and the usage examples with your source's values.
     For Chinese sources, save this English template as README.en.md.
     For English-primary packages, keep README.md and change the language link to README.zh-CN.md.
     Copy maintenance.md to docs/maintenance.md for contributor instructions. -->

Search and jump using this code table with
[flash-any.nvim](https://github.com/dirichy/flash-any.nvim/tree/main).

![Search and jump](https://github.com/OWNER/TABLE/releases/download/demos/table.gif)

[HD MP4](https://github.com/OWNER/TABLE/releases/download/demos/table.mp4)

## Install

Requires Neovim 0.11+, make and a C compiler. Add this to your lazy.nvim configuration:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = { "folke/flash.nvim", "OWNER/TABLE" },
  build = "make",
  opts = { sources = { "SOURCE" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
  },
}
```

## Use

1. Press `s` and enter a character's code.
2. Choose a displayed label to jump there.
3. Keep typing to match a longer phrase, mixing codes and ordinary ASCII text.

For example, with `中 → zhong` and `文 → wen`, type `zhong` to find “中”,
or `zhongwen with flash` to find “中文 with flash”. ASCII text also works on its own.

## Configuration

The default matcher is `full_code`. To allow any code prefix, use:

```lua
opts = { sources = { { name = "SOURCE", matcher = "prefix" } } }
```

Document the settings users need for this source below; keep build metadata in maintainer documentation.

<!-- Before publishing, document every user-facing source option: type, default,
     all enum values, manual configuration examples and incompatible combinations.
     Do not list internal builder fields just because the factory accepts them. -->

## More

- [flash-any configuration](https://github.com/dirichy/flash-any.nvim/blob/main/README.md)
- [Updating the table and recording demos](docs/maintenance.md)

## License

<!-- State this project's license and link the upstream data notices. -->

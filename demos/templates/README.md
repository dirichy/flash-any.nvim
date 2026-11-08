# My code table

<!-- Replace OWNER/TABLE, the table path, and the usage examples with your source's values.
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

## Use

1. Press `s` and enter a character's code.
2. Choose a displayed label to jump there.
3. Keep typing to match a longer phrase, mixing codes and ordinary ASCII text.

For example, with `中 → zhong` and `文 → wen`, type `zhong` to find “中”,
or `zhongwen with flash` to find “中文 with flash”. ASCII text also works on its own.

## More

- [flash-any configuration](https://github.com/dirichy/flash-any.nvim/blob/main/README.md)
- [Updating the table and recording demos](docs/maintenance.md)

## License

<!-- State this project's license and link the upstream data notices. -->

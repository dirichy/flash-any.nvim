# 我的码表

<!-- 替换 OWNER/TABLE、码表路径和使用示例；将 maintenance.md 复制到 docs/maintenance.md。 -->

配合 [flash-any.nvim](https://github.com/dirichy/flash-any.nvim/tree/main)，
在 Neovim 中输入本码表的编码搜索跳转。

![搜索跳转](docs/table.gif)

## 安装

需要 Neovim 0.11+、make 和 C 编译器。在 lazy.nvim 配置中添加：

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

## 使用

1. 按 `s`，输入要找的字的编码。
2. 按屏幕上显示的标签跳转。
3. 继续输入可以匹配更长的文本，编码与普通 ASCII 可以混输。

例如码表中 `中 → zhong`、`文 → wen`，输入 `zhong` 找“中”，
输入 `zhongwen with flash` 找“中文 with flash”。也可以直接搜索 ASCII 文本。

## 更多

- [flash-any 配置说明](https://github.com/dirichy/flash-any.nvim/blob/main/README.zh-CN.md)
- [更新码表与录制演示](docs/maintenance.md)

## 许可

<!-- 填写项目许可，并链接上游码表来源及许可。 -->

# 我的码表

[English](README.en.md)

<!-- 替换 OWNER/TABLE、SOURCE 和使用示例；中文 source 将本文件放到 README.md，英文模板放到 README.en.md。
     若英文为主页，本文件放到 README.zh-CN.md，并将英文链接改为 README.md。
     将 maintenance.md 复制到 docs/maintenance.md。 -->

配合 [flash-any.nvim](https://github.com/dirichy/flash-any.nvim/tree/main)，
在 Neovim 中输入本码表的编码搜索跳转。

![搜索跳转](https://github.com/OWNER/TABLE/releases/download/demos/table.gif)

[高清 MP4](https://github.com/OWNER/TABLE/releases/download/demos/table.mp4)

## 安装

需要 Neovim 0.11+、make 和 C 编译器。在 lazy.nvim 配置中添加：

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

## 使用

1. 按 `s`，输入要找的字的编码。
2. 按屏幕上显示的标签跳转。
3. 继续输入可以匹配更长的文本，编码与普通 ASCII 可以混输。

例如码表中 `中 → zhong`、`文 → wen`，输入 `zhong` 找“中”，
输入 `zhongwen with flash` 找“中文 with flash”。也可以直接搜索 ASCII 文本。

## 配置

默认使用 `full_code` 完整码推进。若要允许任意编码前缀，可配置：

```lua
opts = { sources = { { name = "SOURCE", matcher = "prefix" } } }
```

在这里说明使用本 source 需要的配置；构建元数据放在维护文档。

<!-- 发布前补齐所有面向使用者的 source 选项：类型、默认值、全部枚举值、手动设置示例与组合限制。
     不要因为工厂接受某个内部字段，就把它列成用户配置。 -->

## 更多

- [flash-any 配置说明](https://github.com/dirichy/flash-any.nvim/blob/main/README.zh-CN.md)
- [更新码表与录制演示](docs/maintenance.md)

## 许可

<!-- 填写项目许可，并链接上游码表来源及许可。 -->

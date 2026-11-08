# 我的码表

<!-- 替换项目名称、OWNER/TABLE 和 TSV 路径；不需要增加 Lua source 模块。 -->

为 [flash-any.nvim](https://github.com/dirichy/flash-any.nvim) 提供单字素编码，
使用本码表在 Neovim 中搜索跳转。

## 安装

需要 Neovim 0.11+，首次构建需要 make 和 C 工具链。

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

按 `s`，输入编码，再按标签跳转。ASCII 字面匹配自动启用。
若需要编码转换，可在 source 中添加 `converter = "/path/converter.lua"`；
转换器只在构建时运行，返回编码数组，不参与运行时匹配。

## 码表格式

TSV 每行一个字素、Tab、编码，多编码重复写行；逗号原样保留，无需排序。
也可直接提供 Rime、CSV、Fcitx 或 IBus 文件。
每个键须恰好一个完整字素，编码在转换后须为非空 ASCII。

```text
中<TAB>zhong
中<TAB>chong
文<TAB>wen
```

## 演示

<!-- 从 table-demo artifact 下载 table.gif，放到 docs/table.gif 后保留下面一行。 -->
![编码搜索跳转](docs/table.gif)

无需改码表项目即可用 flash-any 的录制工具：

```sh
# 在 flash-any.nvim 仓库中执行；录制依赖见其 demos/README.md。
TABLE_FILE=/path/to/this-project/table.tsv sh demos/record.sh table
```

也可复制 flash-any 的 `demos/templates/table-demo.yml` 到
`.github/workflows/demo.yml`，修改 TSV 路径和 matcher 后手动运行。
工作流上传 GIF、MP4、封面及回放验证报告，不自动发布 Release。

## 许可

<!-- 填写本项目及上游码表的实际许可和来源。 -->

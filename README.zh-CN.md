# ⚡ flash-any.nvim

[English](README.md)

用拼音、双拼、形码、图标名或自定义编码进行 Flash 跳转。
基于 [flash.nvim](https://github.com/folke/flash.nvim)，运行时匹配核心全部使用 C。

![全拼、简拼与连续混输](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

## 安装与配置

需要 Neovim **0.11+**、flash.nvim、Python 3、C 编译器、GNU make **4.3+**、
`pkg-config` 和 LuaJIT 开发文件。目前验证环境为 Linux。

在 lazy.nvim 中配置即可，无需手动执行构建命令：

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = { sources = { "pinyin", "nerdfont", "unicode" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
}
```

不用 lazy.nvim 时，加载依赖后调用：

```lua
require("flash-any").setup({ sources = { "pinyin", "unicode" } })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

setup 会自动检查/编译 C 模块，并在码表二进制不存在时立即构建；后续启动直接
复用二进制。其他 Flash 跳转选项，例如 `labels`、`search`、`jump`，仍可传给 setup。
`jump(opts)` / `remote(opts)` 使用独立完整配置，包含 `sources` 或 `binary`，
不会继承 setup 字段。不支持自定义 Lua matcher。

## 用法

按 `s`，输入编码，再按标签跳转。可连续混用 ASCII、全拼、简拼和其他已构建编码。
例如全拼/简拼 `zhongguo` / `zg` 匹配“中国”；配置 Unicode 表后 `grin` 匹配 😀。
简拼取首字母，例如“输”是 `s`，不是 `sh`。ASCII 字面匹配自动启用。

操作符等待模式下按 `yr`，搜索目标并选择标签，再输入 `iw`，可复制远处单词并
返回原窗口；`dr` 用于删除。操作、光标恢复和绘制仍由 Flash 管理。

### 字符模式 f/F/t/T

先 setup 本插件，再在 **Flash 的配置**中添加：

```lua
require("flash").setup({
  modes = {
    char = {
      matcher = function(win, state, range)
        return require("flash-any").char(win, state, range)
      end,
      -- multi_line = false,
    },
  },
})
```

`fz` 匹配编码以 `z` 开头的字符及字面 `z`；小鹤双拼下 `fv` 匹配“中”及 `v`。
F/t/T、计数、`;`/`,`、操作符和标签由 Flash 负责。删除 `modes.char.matcher`
即可恢复 Flash 原生字符匹配。该回调只是 Flash 桥接，不是自定义编码 matcher。

## 配置码表

在 setup 中选择 source：

```lua
require("flash-any").setup({
  sources = {
    "pinyin",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger", append_space_below = 4 },
    "nerdfont",
    "unicode",
  },
})
```

源列表的顺序、scope、fallback、双拼、模糊音和补空格均在构建时处理。自动产物
保存在 `stdpath("cache")/flash-any/`，按 sources 配置及 C 格式/Unicode 版本区分，
修改 sources 配置会使用对应的新缓存。原路径下的外部码表或工厂内容修改不会被
监控；清除生成的缓存后再次 setup 即可自动重建。

可选 `binary = "/path/flash-any.bin"` 指定固定产物路径，文件缺失时使用 sources
构建；仅提供 binary 则加载现有文件。构建失败保留旧输出，已有搜索继续使用原
快照。首次编译在 setup 中同步完成。`require("flash-any.build").binary()` 仍可用于
显式导出及开发工具。

| source | 内容 / 默认规则 |
| --- | --- |
| `pinyin` | 全拼，接受完整编码及首字母；配置 scheme 后默认完整编码 |
| `tiger` | 虎码，完整编码 |
| `wubi86` | 五笔86，完整编码 |
| `nerdfont` | 图标名称前缀，显示图标需要 Nerd Font |
| `unicode` | Unicode 名称前缀，默认 fallback |

双拼 scheme 支持 `flypy`、`pyjj`、`natural`、`abc`、`mspy`、`st`。
`fuzzy = true` 使用内置常见模糊音，也可配置 `initials` / `finals` 等价分组。
`append_space_below = 4` 给短于4字节的编码追加空格，空格是编码的一部分。

每项的 `matcher` 只能是 `full_code`、`initial`、`prefix` 三种内置模式。
普通源均参与；`fallback = true` 的源只为之前尚未认识的字素提供编码。
空编码数组也算已认识，会屏蔽后面的 fallback。

### 自定义码表

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent" }, matcher = "prefix" },
  { lua = "/path/common.lua", tsv = "/path/full.tsv", matcher = "full_code" },
}
```

`data` 接受单编码字符串或编码数组；编码必须为非空 ASCII 字符串。scope 支持
预定义名称（`all`、`ascii`、`chinese`、`unicode`、`private_use`）和字符/区间表，
例如 `{ { "a", "z" }, a = false, ["👩‍💻"] = true }`。scope 只在构建时过滤。
不支持 matcher 函数、scope 函数或自定义按需 loader；可通过 Lua 工厂及构建时
转换生成码表，详见 [码表开发说明](docs/sources.md)。

**每个键必须恰好是一个 Unicode 17 完整字素**，例如 `á` 或 `👩‍💻`；当前不接收
“中国”这类多字素键。连续输入仍可逐字素匹配“中国”。不做 Unicode 归一化。
字节位置保持 Neovim 约定，复杂字素的高亮覆盖最后一个码点。

### 转换已有词典

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

只必需输入及 Lua 输出路径。format 为 auto/rime/tsv/tab/csv/space，encoding 默认
utf-8。TSV 以 Tab 分隔文本和编码、逗号分隔多个编码；合并重复条目。转换器保留
原始词组键并报告数量，生成当前二进制前需要筛选为单字素。编码中不能含逗号、
Tab 或换行；补充的直接 Lua 码表允许其他 ASCII 字节。

## 开发与测量

[当前实现及验证](docs/development.md) · [性能对照](docs/benchmarks.md)。
`make` 同时生成 `build/grapheme_data.h` 和 `compile_commands.json`，供 clangd 使用。
这些文件及 native.so 不提交；缺少任一构建产物时重新 make 即可。

## 许可

项目代码为 [MIT](LICENSE)。码表保留上游许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。
[演示录制](demos/README.md)。

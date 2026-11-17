# ⚡ flash-any.nvim

[English](README.md) · [日本語](README.ja.md)

> **正在迁移，暂不稳定。** `main` 分支使用 C 匹配核心和新版配置 API。
> 旧版请查看 [master 分支 README](https://github.com/dirichy/flash-any.nvim/blob/master/README.zh-CN.old.md)。

用拉丁字母变体、中文拼音、日语罗马音、图标名或自定义编码进行 Flash 跳转。
基于 [flash.nvim](https://github.com/folke/flash.nvim)，运行时匹配核心全部使用 C。

![Latin、中文、日文、Nerd Font 和混输](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[高清 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [回放验证](https://github.com/dirichy/flash-any.nvim/releases/download/demos/verification.json)

## 安装与配置

需要 Neovim **0.11+**、flash.nvim，以及首次构建和升级时使用的 make 和 C 工具链
（GCC 或 Clang）。
公共 Lua/C 头文件已随插件提供。Linux 与 macOS 已验证；Windows 暂不支持。

核心内置 Unicode 字面匹配（即原 flash.nvim 的字面匹配功能）和可选的 `latin` source。`sources = {}` 只启用字面匹配，
`sources = { "latin" }` 可匹配拉丁字母变体。其他码表支持由外部插件提供：

- [`dirichy/flash-any-pinyin.nvim`](https://github.com/dirichy/flash-any-pinyin.nvim) —— 中文拼音和双拼
- [`dirichy/flash-any-tiger.nvim`](https://github.com/dirichy/flash-any-tiger.nvim) —— 中文虎码
- [`dirichy/flash-any-japanese.nvim`](https://github.com/dirichy/flash-any-japanese.nvim) —— 假名、汉字和词典词组的日语罗马音
- [`dirichy/flash-any-nerdfont.nvim`](https://github.com/dirichy/flash-any-nerdfont.nvim) —— Nerd Font 图标

下面的 lazy.nvim 配置可以运行 demo 中的全部五个例子：

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    "dirichy/flash-any-pinyin.nvim",
    "dirichy/flash-any-japanese.nvim",
    "dirichy/flash-any-nerdfont.nvim",
  },
  build = "make",
  opts = { sources = { "latin", "pinyin", "japanese", "nerdfont" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
}
```

按需保留外部 source，同时删去不用的依赖和 source 名称。虎码用户可添加
`dirichy/flash-any-tiger.nvim` 并把 pinyin 换成 tiger；内置 latin 不需要另装插件。
终端显示 Nerd Font 图标需要使用对应字体。

其他管理器可配置安装/更新钩子，在插件目录执行 `make`：vim-plug 使用
`{'do': 'make'}`，packer.nvim 使用 `run = "make"`。没有构建钩子时，安装及
更新后手动在插件目录执行 `make`，然后加载依赖并调用：

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

插件直接加载预先构建的 C 模块，缺失或加载失败时提示执行 `make`。setup 在
码表二进制不存在时立即构建，后续启动直接复用码表。其他 Flash 跳转选项，例如 `labels`、`search`、`jump`，仍可传给 setup。
`jump(opts)` / `remote(opts)` 使用独立完整配置，包含 `sources` 或 `binary`，
不会继承 setup 字段。

## 用法

按 `s`，输入查询，再按标签跳转。同一份配置可以匹配以下全部例子，最后一行只开启
一次搜索，连续混用四种 source 和字面 ASCII：

| 例子 | 缓冲区文字 | 查询 |
| --- | --- | --- |
| 拉丁字母变体 | café | `cafe` |
| 中文拼音 | 中文 | `zhongwen` |
| 日语罗马音 | 食べる | `taberu` |
| Nerd Font 图标 |  | `vim` |
| 混输 | café 中文 食べる  | `cafe zw taberu vim` |

混输中的 zw 是中文简拼，空格按 ASCII 原样输入。也可以混用完整拼音和首字母；
简拼只取首字母，例如“输”是 s，不是 sh。双拼及其他码表选项见对应 source 文档。
如果预期位置还没有标签，可以继续输入。

跳转搜索在每行只显示互不重叠的匹配，便于辨认后置标签对应的范围。优先保留最早结束的匹配，
终点相同时保留更短的范围。继续输入时，被隐藏的其他分支仍参与匹配。

操作符等待模式下按 `yr`，搜索目标并选择标签，再输入 `iw`，可复制远处单词并
返回原窗口；`dr` 用于删除。


ASCII 字面文本和内置 latin 码表遵循 Neovim 的 `ignorecase`、`smartcase` 设置，`f/F/t/T` 也一样。
开启 `ignorecase` 后忽略字母大小写；同时开启 `smartcase` 时，查询含大写字母则
区分大小写。修改选项在下次匹配时生效。

配置 `sources = { "latin" }` 后，`e` 可匹配 `é`、`é`，`o` 匹配 `ø`，`ae` 匹配
`æ`，`ss` 匹配 `ß`。大写字母保留大写编码（`É` → `E`、`Æ` → `AE`），遵循上述
`ignorecase` / `smartcase` 设置。字母后的组合后缀随整个字素一起消耗。
收录范围和数据来源见 [Latin 说明](docs/latin.md)。

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

在 setup 中选择 source；latin 已内置，中文、日文和图标 source 来自上面列出的插件，
必须在 setup 前加载：

```lua
require("flash-any").setup({
  sources = {
    "latin",
    "pinyin",
    "japanese",
    "nerdfont",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
  },
})
```

可用 `binary = "/path/flash-any.bin"` 指定固定产物路径，文件缺失时使用 sources
构建；仅提供 binary 则加载现有文件。构建失败保留旧输出，已有搜索继续使用原
快照。首次编译在 setup 中同步完成。`require("flash-any.build").binary()` 仍可用于
显式导出及开发工具。
当前 v14 格式需要重新导出旧的显式 binary；自动缓存会重建。
更新后运行 make，并重启 Neovim 加载新模块。

| source | 内容 / 默认规则 |
| --- | --- |
| `latin` | 拉丁字母变体，`letter` |
| `pinyin` | 全拼，接受完整编码及首字母；配置 scheme 后默认完整编码 |
| `japanese` | 假名及词典中的汉字、词组读音，罗马音拼写组，`full_code` |
| `nerdfont` | Nerd Font 图标名称，`prefix` |
| `tiger` | 虎码，按权重分配可选选键，默认首选空格、次选分号 |

双拼、模糊音和默认选键属于相应 source 的配置，说明随 source 发布。

每项的 `matcher` 可选 `full_code`、`initial`、`prefix`、`letter` 四种内置模式。
普通 source 均参与匹配；`fallback = true` 的 source 只为之前尚未识别的字素提供编码。
空编码数组也算已识别，会屏蔽后面的 fallback。

source 可以共享拼写组并组合成音节序列。每个音节独立按所选 matcher 接受完整编码、
首字母或前缀，详见[组序列与 converter](docs/sources.md#内部编码组--internal-spelling-groups)。

### 自定义码表

`data` 用于标点和少量自定义符号，码表建议使用 `file`。自动缓存检查发现显式 `data`
合计超过 200 个文本条目时，每进程警告一次；同一条目的多个编码不重复计数。
这只是性能提示，不限制使用。

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent", ["中国"] = "zhongguo" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- 可选的构建时编码转换
    -- converter = "/path/converter.lua",
  },
}
```

第三方可直接提供 Rime、TSV、CSV、空白分隔、Fcitx 或 IBus 码表，
无需排序、Lua 常用字表或 source 模块。Tab 分隔的码表每行一个编码，多个编码分行重复写入。可选 `converter` 指向返回编码转换函数的 Lua 文件，
只在构建时执行。[接入与 converter 说明](docs/sources.md) ·
[第三方录制及 README 模板](demos/README.md#第三方码表--third-party-tables)。

`data` 接受单编码字符串或编码数组；编码可以是不含 NUL 的非空 ASCII，或有效的组引用/序列。
组名可用 Unicode，组内实际拼写仍为 ASCII。
可通过 Lua 工厂及构建时转换生成码表。首次编写扩展可按[分步 source 教程](docs/writing-sources.zh-CN.md)
完成本地安装、验证和演示发布；完整选项见[码表开发说明](docs/sources.md)。

键可以是 Unicode 17 完整字素或词组，例如 `á`、`👩‍💻` 或“中国”。
同一位置的单字和不同长度词组都参与匹配，编码之后可以继续匹配后面的文字。
匹配只从字素边界开始和结束，不跨行，不做 Unicode 归一化。
字节位置保持 Neovim 约定，复杂字素的高亮覆盖最后一个码点。

### 转换已有词典

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

只需提供输入路径及 Lua 输出路径。format 为 auto/rime/tsv/tab/csv/space/fcitx/ibus，encoding 默认
utf-8。TSV 每行一对文本和编码，多个编码分行重复写入；逗号原样保留，重复条目合并。转换器保留
原始词组键并报告数量，可直接生成二进制文件，无需过滤词组。编码中不能含 Tab、换行或 NUL；补充的直接 Lua 码表允许其他非 NUL ASCII 字节。
文本或查询含 NUL 时，匹配行为不作保证。

## 开发与测量

[当前实现及验证](docs/development.md) · [性能对照](docs/benchmarks.md)。
运行 `make` 即可编译 C 模块，`make clean` 清理动态库。Makefile 使用兼容
GNU make 3.81 的语法，不调用 Neovim；可覆盖 `CC`、`CPPFLAGS`、`CFLAGS` 和
`LDFLAGS`。Unicode 头文件 `src/grapheme_data.h` 随源码提交，只有维护者更新数据
时才需要生成。clangd 直接使用 `compile_flags.txt`，无需生成编译数据库。

## 许可

项目代码为 [MIT](LICENSE)。Unicode 数据保留上游许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。
各独立 source 自行附带码表来源和许可。
[演示录制](demos/README.md)。

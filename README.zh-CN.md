# ⚡ flash-any.nvim

[English](README.md)

> **正在迁移，暂不稳定。** `main` 分支是新版 C 实现，API 和配置仍可能变化，
> 不兼容旧接口。旧版用户请使用 `master`；试用迁移版本需显式选择 `main`。

用拼音、双拼、形码、图标名或自定义编码进行 Flash 跳转。
基于 [flash.nvim](https://github.com/folke/flash.nvim)，运行时匹配核心全部使用 C。

![全拼、简拼与连续混输](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

## 安装与配置

需要 Neovim **0.11+**、flash.nvim，以及首次构建和升级时使用的 make 和 C 工具链
（GCC 或 Clang）。不需要 Python、CMake、pkg-config 或单独的 LuaJIT 开发包，
公共 Lua/C 头文件已随插件提供。Linux 已验证；macOS 构建路径已适配，尚未实机验证。

核心仅内置 ASCII literal 匹配，`sources = {}` 即可使用。拼音、虎码、五笔、图标和
Unicode 名称码表均为独立可选插件，只安装需要的 source，并在 setup 前加载。
迁移中的五个 source 包尚未公开发布；本地安装可把依赖写成
`{ dir = "/path/to/flash-any-pinyin.nvim" }`，然后配置 `sources = { "pinyin" }`。
source 插件只提供 Lua 和数据，无需执行 make。

在 lazy.nvim 中配置即可，无需手动执行构建命令：

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = { "folke/flash.nvim" },
  build = "make",
  opts = { sources = {} },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
  },
}
```

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
    -- { name = "tiger" },
    "nerdfont",
    "unicode",
  },
})
```

源列表的顺序、fallback、双拼、模糊音和补空格均在构建时处理。自动产物
保存在 `stdpath("cache")/flash-any/`，按 sources 配置及 C 格式/Unicode 版本区分，
修改 sources 配置会使用对应的新缓存。外部词典、Rime 导入、Lua/TSV 伴随文件及
converter 按绝对路径、大小和修改时间（含纳秒）跟踪，不为计算内容哈希读取完整码表。
lua/flash-any 下安装的 Lua/TSV 文件每个进程检查一次，插件更新后需重启 Neovim。
同时保留大小和修改时间的内容变化需要手动重建；用户 Lua 自行加载的命名空间外依赖不自动跟踪。

可选 `binary = "/path/flash-any.bin"` 指定固定产物路径，文件缺失时使用 sources
构建；仅提供 binary 则加载现有文件。构建失败保留旧输出，已有搜索继续使用原
快照。首次编译在 setup 中同步完成。`require("flash-any.build").binary()` 仍可用于
显式导出及开发工具。

| source | 内容 / 默认规则 |
| --- | --- |
| `pinyin` | 全拼，接受完整编码及首字母；配置 scheme 后默认完整编码 |
| `tiger` | 虎码，按权重分配可选选键，默认首选空格、次选分号 |
| `wubi86` | 五笔86，完整编码 |
| `nerdfont` | 图标名称前缀，显示图标需要 Nerd Font |
| `unicode` | Unicode 名称前缀，默认 fallback |

上表各 source 对应独立的 `flash-any-NAME.nvim` 插件。双拼、模糊音和默认选键
属于相应 source 的配置，说明随 source 发布。

`append_space_below = 4` 给短于4字节的编码追加空格，空格是编码的一部分。

每项的 `matcher` 只能是 `full_code`、`initial`、`prefix` 三种内置模式。
普通源均参与；`fallback = true` 的源只为之前尚未认识的字素提供编码。
空编码数组也算已认识，会屏蔽后面的 fallback。

### 加权码表选键

任意加权文件都可以使用可选后缀，无需虎码 source：

```lua
{ file = "/path/to/table.dict.yaml", selection = { keys = { " ", ";" } } }
```

按权重、原始顺序分配选键。裸码始终有效，后续文字可消费剩余按键。
要求 full_code，暂不能与 converter、append_space_below 或共享编码组同时使用。
[共享编码组、选键与 source 工厂](docs/sources.md)。

### 自定义码表

`data` 用于标点和少量自定义符号，码表建议使用 `file`。自动缓存检查发现显式 `data`
合计超过 200 个文本条目时，每进程警告一次；同一条目的多个编码不重复计数。
这只是性能提示，不限制使用。

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- 可选的构建时编码转换
    -- converter = "/path/converter.lua",
  },
}
```

第三方可直接提供 Rime、TSV、CSV、空白分隔、Fcitx 或 IBus 码表，
无需排序、Lua 常用字表或 source 模块。Tab 表每行一个编码，多编码重复写行。可选 `converter` 指向返回编码转换函数的 Lua 文件，
只在构建时执行。[接入与 converter 说明](docs/sources.md) ·
[第三方录制及 README 模板](demos/README.md#第三方码表--third-party-tables)。

`data` 接受单编码字符串或编码数组；编码必须为非空 ASCII 字符串。
不支持运行时 Lua matcher 或自定义按需 loader；可通过 Lua 工厂及构建时
转换生成码表。首次编写扩展可按[分步 source 教程](docs/writing-sources.zh-CN.md)
完成本地安装、验证和演示发布；完整选项见[码表开发说明](docs/sources.md)。

**每个键必须恰好是一个 Unicode 17 完整字素**，例如 `á` 或 `👩‍💻`；当前不接收
“中国”这类多字素键。连续输入仍可逐字素匹配“中国”。不做 Unicode 归一化。
字节位置保持 Neovim 约定，复杂字素的高亮覆盖最后一个码点。

### 转换已有词典

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

只必需输入及 Lua 输出路径。format 为 auto/rime/tsv/tab/csv/space/fcitx/ibus，encoding 默认
utf-8。TSV 每行一对文本和编码，多个编码重复写行；逗号原样保留，重复条目合并。转换器保留
原始词组键并报告数量，生成当前二进制前需要筛选为单字素。编码中不能含 Tab 或换行；补充的直接 Lua 码表允许其他 ASCII 字节。

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

# ⚡ flash-any.nvim

[English](README.md)

用熟悉的编码，跳转到中文、符号、emoji 和其他字符。
`flash-any.nvim` 为 [flash.nvim](https://github.com/folke/flash.nvim) 添加常用中文输入法编码、Nerd Fonts 图标名称、Unicode 名称和自定义编码匹配。

![全拼、简拼与连续混输](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[高清 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [重新录制](demos/README.md)

## ✨ 特性

- **支持各种常用中文编码**：全拼、简拼、六种双拼，以及虎码、五笔 86。
- **自由混输**：同一次搜索可以混用全拼、简拼、ASCII、图标名称和 Unicode 名称。
- **覆盖大字符集**：生僻字按需加载。
- **模糊拼音**：内置常见模糊音，也可自定义声母、韵母等价分组。
- **自定义编码**：支持码表和 matcher，可转换 Rime、TSV、CSV 和空白分隔词典。

## 📋 依赖

- Neovim **0.11+**
- [folke/flash.nvim](https://github.com/folke/flash.nvim)

## 📦 安装

使用 lazy.nvim：

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = {
    sources = {
      "pinyin", -- 全拼与简拼
      -- 使用双拼时，将上面的 "pinyin" 替换为：
      -- { name = "pinyin", scheme = "flypy" }, -- 小鹤双拼
      -- 使用形码时，将上面的 "pinyin" 替换为：
      -- { name = "tiger", append_space_below = 4 },
      -- 短于 4 码的编码追加一个空格，更接近输入法打单的习惯。
      -- 不需要补空格时，省略 append_space_below 即可。
      "nerdfont", -- 图标名称（显示图标需要 Nerd Font）
      "unicode", -- Unicode 名称 fallback
    },
    -- 其他 Flash 跳转选项也可放在这里：
    -- labels = "asdfghjkl", -- 使用这些字母作为跳转标签
  },
  -- 如果要开 f mode 就解除注释。
  -- config = function(_, opts)
  --   require("flash").setup({
  --     modes = {
  --       char = {
  --         matcher = function(win, state, range)
  --           return require("flash-any").char(win, state, range)
  --         end,
  --         -- multi_line = false, -- 只匹配当前行
  --       },
  --     },
  --   })
  --   require("flash-any").setup(opts)
  -- end,
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function() require("flash-any").jump() end,
      desc = "Flash any",
    },
    {
      "r",
      mode = "o",
      function() require("flash-any").remote() end,
      desc = "Remote Flash any",
    },
  },
}
```

不使用 lazy.nvim 时，在加载依赖后调用：

```lua
require("flash-any").setup({ sources = { "pinyin" } })
vim.keymap.set({ "n", "x", "o" }, "s", function()
  require("flash-any").jump()
end)
```

## 🚀 用法

按 `s` 开始搜索，输入编码，再按候选旁的标签跳转。默认同时接受全拼和简拼，无需切换搜索配置。

| 输入 | 匹配文本 | 拆分 |
| --- | --- | --- |
| `quanpin` | 全拼 | `quan` + `pin` |
| `jp` | 简拼 | 每个音节的首字母：`j` + `p` |
| `hunsasciigrin` | 混输ascii😀 | `hun` + `s` + `ascii` + `grin` |

混输示例使用 `sources = { "pinyin", "unicode" }`。ASCII 按字面匹配，`grin` 是 emoji 的 Unicode 名称前缀。
简拼取**首字母**，因此“输”用 `s`，不是 `sh`。

### `f/F/t/T` 首码跳转

![f 首码匹配与连续跳转](https://github.com/dirichy/flash-any.nvim/releases/download/demos/char.gif)

[高清 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/char.mp4) · [重新录制](demos/README.md)

首码匹配**默认不开启**，仅调用 `flash-any.setup()` 不会启用。
先按上文调用 `flash-any.setup()`，再在 **flash.nvim 的配置**中加入 matcher：

```lua
require("flash").setup({
  modes = {
    char = {
      matcher = function(win, state, range)
        return require("flash-any").char(win, state, range)
      end,
      -- multi_line = false, -- 只匹配当前行
    },
  },
})
```

关闭首码匹配：从 Flash 配置中删除 `modes.char.matcher`，重启 Neovim 后恢复
Flash 原生的字面字符匹配。若要关闭 Flash 整个字符模式，设置
`modes.char.enabled = false`。两种方式均不影响 `s` 搜索，没有单独的 `disable()` API。

`f` 后输入一个字母，匹配所配置编码以该字母开头的所有字符，以及该 ASCII
字符本身。例如全拼下 `fz` 匹配“中、这、字”和 `z`；小鹤双拼下 `fv` 匹配“中”和 `v`。
与 `s` 共用 sources、双拼、模糊音及 fallback 规则，但每次只匹配一个文本字符。
自定义 source 继续使用自己的 matcher。

`F/t/T`、计数、`;`/`,`、操作符和可选标签由 Flash 字符模式处理，无需另设按键。
标签使用 Flash 原生 labeler；`s` 的标签规则保持不变。
只扫描可见区域来显示标签；需要屏幕外目标时，再沿跳转方向逐行扫描，找到指定数量后停止。
`multi_line = false` 将范围限制在当前行。

### `r` 远程操作

remote 模式与 `s` 共用 sources 和搜索规则。lazy.nvim 安装示例已包含操作符等待模式的
`r` 映射；手动配置时，在 setup 后添加：

```lua
vim.keymap.set("o", "r", function()
  require("flash-any").remote()
end, { desc = "Remote Flash any" })
```

按 `yr`，输入 `zg` 搜索“中国”，选择标签，再输入 `iw`，即可复制目标位置的单词，
随后回到原窗口和光标位置。改用 `dr` 则删除远处单词。删除映射即可关闭此入口。

`remote()` 复用 setup 保存的配置和码表缓存；`remote(opts)` 与 `jump(opts)` 一样
使用独立完整配置，必须包含 `sources`，并返回 Flash state。
远程操作与位置恢复直接使用 Flash 原生的 `remote()` API。

## 内置 source

source 可写成名称字符串或带 `name` 的配置对象：

| 名称 | 用途 | 默认 matcher |
|---|---|---|
| `pinyin` | 全拼或指定双拼方案 | 全拼 `initial`，双拼 `full_code` |
| `tiger` | 虎码 | `full_code` |
| `wubi86` | 五笔 86 | `full_code` |
| `unicode` | Unicode 字符的英文短名称 | `prefix`，默认 `fallback = true` |
| `nerdfont` | Nerd Fonts 图标的英文短名称 | `prefix` |

例如全拼输入 `zg` 可以匹配“中国”；小鹤双拼输入 `vsgo` 可以匹配“中国”。ASCII 可以和编码混输，`sources = { "pinyin" }` 时，`ag` 可以匹配 `a国`。

`pinyin`（含双拼）、`tiger`、`wubi86` 也支持用键盘符号匹配中文标点：
`,` 匹配 `，`，`.` 匹配 `。`，`/` 或 `\` 匹配 `、`，`; : ? !` 匹配 `；：？！`。
单双引号匹配 `“”‘’`，`() [] <>` 匹配 `（）【】《》`；`^` 匹配 `…`，`_` 匹配 `—`，反引号匹配 `·`，`$` 匹配 `￥`。
例如全拼 `zg,a.` 可以匹配 `中国，a。`。

配置会自动在所有 source 前加入 ASCII 字面匹配，无需手动添加；其他普通 source 仍参与匹配。
插件管理 Flash 顶层的 `matcher` 和 `labeler`；字符匹配规则通过 source 的 `matcher` 配置。

### 拼音与模糊音

```lua
sources = {
  {
    name = "pinyin",
    scheme = "flypy", -- 双拼方案，省略则使用全拼
    fuzzy = { -- 自定义模糊音；也可用 fuzzy = true 启用默认分组
      initials = { { "zh", "z" }, { "ch", "c" } },
      finals = { { "ang", "an" } },
    },
  },
}
```

全拼和六种双拼是同一个 `pinyin` source 的不同编码方式，同一次配置只允许一个拼音 source。省略 `scheme` 使用全拼：

| scheme | 方案 |
|---|---|
| `flypy` | 小鹤双拼 |
| `pyjj` | 拼音加加 |
| `natural` | 自然码 |
| `abc` | 智能 ABC |
| `mspy` | 微软双拼 |
| `st` | 四通双拼 |

全拼和双拼都支持模糊音。`fuzzy = true` 启用默认分组：`zh/z`、`ch/c`、`sh/s`、`ang/an`、`eng/en`、`ing/in`。
重叠分组采用第一个包含该声母或韵母的分组。

### matcher 与 fallback

码表有三个内置 matcher：

- `full_code`：输入前缀可显示候选，完整编码才进入下一个文本字符。
- `initial`：完整编码或首个 ASCII 字母都可进入下一个字符。
- `prefix`：任意非空编码前缀都可进入下一个字符。

以全拼码表中的“中国”为例，比较哪些输入能完整匹配两个字：

| 输入 | `full_code` | `initial` | `prefix` |
| --- | --- | --- | --- |
| `zhongguo` | ✓ | ✓ | ✓ |
| `zguo` | — | ✓ | ✓ |
| `zhguo` | — | — | ✓ |

`z` 是“中”的首字母，`zh` 是它的编码前缀。三种 matcher 都能在单字编码尚未输完时显示候选；区别在于何时可以进入下一个字符。

```lua
sources = {
  { name = "pinyin", scheme = "flypy", matcher = "prefix" },
  "unicode",
}
```

普通 source 都参与匹配；`fallback = true` 的 source 只在前面的 source 全都不认识当前字符时参与，即使前面的 source 认识字符但输入不匹配，它也不会运行。`unicode` 默认开启 fallback，可显式设为 `false`。

默认前置的字面 source 也遵守这条规则，所以后面的 fallback source 不处理 ASCII 字符。

### 短码补空格

```lua
sources = {
  { name = "tiger", append_space_below = 4 },
}
```

短于 `append_space_below` 的编码在末尾追加一个空格，达到或超过阈值的编码保持不变。
阈值必须是正整数；省略此项不追加空格。其他码表也可使用此选项。
这适合习惯用空格确认短码的形码单字输入用户。

## 💡 自定义 source

`data` 是“非空 UTF-8 文本 → ASCII 编码或编码数组”，支持一条文本多个编码：

```lua
sources = {
  {
    data = { ["中"] = { "vs", "ds" }, ["国"] = "go" },
    matcher = "full_code",
  },
}
```

也可从 Lua 常用字表和完整 TSV 加载：

```lua
sources = {
  {
    lua = "/path/to/common.lua",
    tsv = "/path/to/full.tsv", -- 可省略
    matcher = "prefix",
  },
}
```

Lua 文件返回与 `data` 相同结构的表；TSV 按 UTF-8 字节序排序，每条文本一行，编码用逗号分隔，支持 LF 和 CRLF。路径相对于当前工作目录，也可使用绝对路径或 `~`。

自定义 `matcher` 可以没有码表。回调接收 `text, stream, source, emit`；`text` 和 `stream` 都是 `Cursor`，`get()` 读取当前位置到末尾的全部内容，`get(n)` 最多读取 n 个码点，`source` 是运行时 source。例如用 `x` 匹配“中”：

```lua
sources = {
  {
    matcher = function(text, stream, source, emit)
      if text:get(1) ~= "中" then return false end
      if stream:get() == "" then
        emit("x")
      elseif stream:get(1) == "x" then
        emit(1)
      end
      return true
    end,
  },
}
```

认识当前位置返回 `true`，即使输入没有匹配；不认识返回 `false`。成功分支同步输出：

- `emit(bytes, chars?)`：消费指定输入字节，匹配指定文本跨度。
- `emit(keys, chars?)`：剩余输入全部匹配，ASCII 字符串列出后续可用键；`emit("")` 表示成功但没有后续键。

`chars` 默认 1。例如 `emit(3, 2)` 消费 3 个输入字节，匹配 2 个文本码点。
空 stream 只查询起始键，不能消费输入。不可保存 emit 或在 matcher 返回后调用。

`get()` 在末尾返回空字符串，`get(n)` 不足 n 个码点时返回剩余全部内容；读取不移动位置。
text 保存当前行，stream 保存完整输入并指向尚未消费的位置。两者完整复用同一种游标和缓存。
source 只允许调用 `get`，`shift`（默认移动一个码点）和 `set_offset` 由扫描器使用。详见 [source 开发说明](docs/sources.md#文本读取--text-access)。

matcher 必须满足：长输入能成功，则其字符前缀也能成功；失败分支不会在追加输入后重试。动态返回值由实现者保证，详见 `:help flash-any-matchers` 和[开发文档](docs/development.md)。

## 第三方 source 插件

[dirichy/flash-any-gemoji.nvim](https://github.com/dirichy/flash-any-gemoji.nvim)
提供 emoji 码表，也可作为编写第三方 source 的示例。安装、配置和编写说明见该项目的 README。

### 字符范围 scope

`scope` 在 matcher 和懒加载之前检查当前位置；未通过时跳过 source，并视为不认识，
不阻止后续 fallback。可在工厂返回值或用户 source 配置中声明，用户配置优先：

```lua
sources = {
  {
    name = "japan",
    scope = {
      { "ぁ", "ヿ" }, -- 区间端点可直接写字符
      ["あ"] = false, -- 哈希优先：排除区间内的字符
      ["漢"] = true,  -- 也可加入区间外的字符
    },
  },
}
```

也可传策略名 `"ascii"`、`"chinese"`、`"unicode"`、`"private_use"`；`"all"` 取消范围限制。
区间还支持数字码点，例如 `{ { 1, 10000 }, ["a"] = false }`。数字端点只在初始化时
转成字符；运行时先查字符哈希，再按 UTF-8 字符串顺序比较区间，不逐次转码点。
自定义函数接收 text 游标，例如 `scope = function(text) return text:get(2) == "きゃ" end`。
空表不接受任何字符。范围检查通过后，仍由 matcher 决定是否认识及如何匹配。

## 🛠️ 生成码表与检查

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

仅输入文件和 Lua 输出路径必填。省略第三个参数时只生成 Lua；需要指定后续参数时，
第三个位置填 `-`。Lua API 同样可省略 `tsv`：`build.table({ source = "source.tsv", lua = "out.lua" })`。

```vim
:FlashAnyBuildTable source.tsv out.lua
:FlashAnyBuildTable source.tsv out.lua - - tsv utf-8
```

输入支持 Rime、TSV、CSV 或空白分隔文本。`format` 可为 `auto`（默认）、`rime`、`tsv`、`tab`、`csv`、`space`；`encoding` 默认为 `utf-8`。保留单码点和多码点条目，同一条文本的编码会合并、去重。

TSV 输入（`tsv`、`tab` 或 `auto` 识别的制表符行）的第二列支持逗号分隔的多编码，也可每行只写一个编码：

```text
中	zhong,chong
中	zhong
国	guo
```

编码两侧空白会去掉，空项忽略，同字跨行编码合并去重。生成的完整 TSV 可以再次作为输入。
逗号列表只适用于 TSV；CSV、Rime 和空白分隔记录保持单编码列的语义。

多码点文本（如 `中国`、`きゃ`、组合音标或 ZWJ emoji）也会写入输出。
命令构建成功后，若完整输入含多码点条目，会发出一次 warning 并报告去重后的条目数，是否输出 TSV 不影响统计。
多码点 Lua 输出自动携带 `codes`、`prefixes`、`max_chars`，内置 matcher 根据这些
元数据匹配长短词，source 无需配置多码点开关或长度。`max_chars` 按完整输入的
最长文本码点数计算，常用 Lua 子集为空也会保留。纯 Lua 表的 `prefixes` 是独立的
可加长键集合，包括自身也有编码的键；叶子省略。普通单码点 Lua 表维持原格式。
TSV 应包含全部 Lua 编码条目。文本列不可包含制表符或换行。

`common-from.lua` 指定用于筛选常用条目的 Lua 表。可使用内置的 `lua/flash-any/tables/tiger.lua` 作为常用字集，约 3500 字。
省略第四个参数时，Lua 输出包含全部条目；提供已有 Lua 字表时，Lua 输出只包含该表中已有的文本键，若输出 TSV，它始终包含全部条目。
大 Lua 码表加载较慢，建议将大字符集保留在 TSV 中，Lua 只存常用字。

需要指定 `format` / `encoding` 而不筛选常用字时，第四个参数填 `-`：

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
:FlashAnyBuildTable source.tsv common.lua full.tsv - tsv utf-8
```

单个编码必须是 ASCII，且不能包含逗号、制表符或换行；文件会覆盖输出路径，请选择与输入不同的路径。

当前按 Unicode 码点处理文本，不合并完整 grapheme cluster（例如 ZWJ emoji 和组合音标）。

## 📄 许可与来源

项目代码采用 [MIT](LICENSE)。内置码表保留各自的上游许可与来源，见 [THIRD_PARTY.md](THIRD_PARTY.md)。虎码码表来源：[虎码官网](https://www.tiger-code.com/)。

演示脚本与录制说明：[demos/README.md](demos/README.md)。

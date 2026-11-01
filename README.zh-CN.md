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
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function() require("flash-any").jump() end,
      desc = "Flash any",
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

`data` 是“单个 UTF-8 字符 → ASCII 编码或编码数组”，支持一字多码：

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

Lua 文件返回与 `data` 相同结构的表；TSV 按 UTF-8 字节序排序，每个字符一行，编码用逗号分隔，支持 LF 和 CRLF。路径相对于当前工作目录，也可使用绝对路径或 `~`。

自定义 `matcher` 可以没有码表。回调接收 `char, stream, args`，其中 `args.source` 是运行时 source。例如用 `x` 匹配“中”：

```lua
sources = {
  {
    matcher = function(char, stream)
      if char ~= "中" then return nil end
      if stream == "" then return { { next = { x = true } } } end
      if stream:sub(1, 1) == "x" then return { { consumed = 1 } } end
      return {}
    end,
  },
}
```

`nil` 表示不认识字符，`{}` 表示认识但没有匹配分支。成功时返回分支列表，每个分支只有 `consumed`（消费字节数）或 `next`（剩余输入已全部匹配，可继续输入的 ASCII 键集合）之一。空 stream 只查询起始 next。

matcher 必须满足：长输入能成功，则其字符前缀也能成功；失败分支不会在追加输入后重试。动态返回值由实现者保证，详见 `:help flash-any-matchers` 和[开发文档](docs/development.md)。

## 🛠️ 生成码表与检查

```vim
:FlashAnyBuildTable source.dict common.lua full.tsv [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

输入支持 Rime、TSV、CSV 或空白分隔文本。`format` 可为 `auto`（默认）、`rime`、`tsv`、`tab`、`csv`、`space`；`encoding` 默认为 `utf-8`。只收录单字符条目，同一字符的编码会合并、去重。

`common-from.lua` 指定用于筛选常用字的 Lua 表。可使用内置的 `lua/flash-any/table/tiger.lua` 作为常用字集，约 3500 字。
省略第四个参数时，Lua 输出包含全部字符；提供已有 Lua 字表时，Lua 输出只包含该表中已有的字符，完整 TSV 始终包含全部字符。
大 Lua 码表加载较慢，建议将大字符集保留在 TSV 中，Lua 只存常用字。

需要指定 `format` / `encoding` 而不筛选常用字时，第四个参数填 `-`：

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
```

输出编码必须是 ASCII，且不能包含逗号、制表符或换行；文件会覆盖输出路径，请选择与输入不同的路径。

当前按 Unicode 码点处理文本，不合并完整 grapheme cluster（例如 ZWJ emoji 和组合音标）。

## 📄 许可与来源

项目代码采用 [MIT](LICENSE)。内置码表保留各自的上游许可与来源，见 [THIRD_PARTY.md](THIRD_PARTY.md)。虎码码表来源：[虎码官网](https://www.tiger-code.com/)。

演示脚本与录制说明：[demos/README.md](demos/README.md)。

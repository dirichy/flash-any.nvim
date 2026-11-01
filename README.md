# flash-any.nvim

[English](README.en.md)

使用全拼、双拼、形码或自定义编码，在 [flash.nvim](https://github.com/folke/flash.nvim) 中跳转。

需要 Neovim 0.11+ 和 `folke/flash.nvim`。默认支持 ASCII 字面匹配；中文、emoji 等字符通过配置的 source 匹配。

![小鹤双拼与 Unicode 名称跳转演示](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[高清 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [重新录制](demos/README.md)

## 安装

使用 lazy.nvim：

```lua
{
  "dirichy/flash-any.nvim",
  dependencies = { "folke/flash.nvim" },
  opts = {
    sources = {
      { name = "pinyin", scheme = "flypy" },
      -- 使用虎码时，将上面的拼音 source 替换为：
      -- { name = "tiger", strategy = "top_force", max_length = 4 },
      "unicode", -- Unicode 名称 fallback，不需要时可删除这一行
    },
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

## 配置与跳转

`setup(opts)` 校验并保存整份默认配置。`jump()` / `jump(nil)` 使用它，复用码表及懒加载缓存。

`jump` 返回 Flash 的跳转 state。`jump(opts)` 使用完整的独立配置，不继承 `setup` 的任何字段；`sources` 必须提供：

```lua
require("flash-any").jump({
  sources = { { name = "pinyin", scheme = "natural" } },
  labels = "asdfghjkl",
})
```

其余 Flash 选项直接传递；匹配规则由 source 的 `matcher` 决定，Flash 的顶层 `matcher` 和 `labeler` 由插件管理。`labels` 等选项由 Flash 自身提供默认值。

配置层会在所有 source 前面加入普通的 ASCII `literal` source，用户无需传入。它只认识 ASCII 字符，匹配失败仍算认识；非 ASCII 返回“不认识”。`sources = {}` 因此只匹配 ASCII。Unicode 名称匹配不自动启用。

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

### 拼音与模糊音

全拼和六种双拼是同一个 `pinyin` source 的不同编码方式，同一次配置只允许一个拼音 source。省略 `scheme` 使用全拼：

| scheme | 方案 |
|---|---|
| `flypy` | 小鹤双拼 |
| `pyjj` | 拼音加加 |
| `natural` | 自然码 |
| `abc` | 智能 ABC |
| `mspy` | 微软双拼 |
| `st` | 四通双拼 |

`scheme` 是 source 属性，不是顶层配置。全拼和双拼都支持 `fuzzy = true`，默认混淆 `zh/z`、`ch/c`、`sh/s`、`ang/an`、`eng/en`、`ing/in`；也可指定等价分组：

```lua
sources = {
  {
    name = "pinyin",
    scheme = "flypy", -- 省略则使用全拼
    fuzzy = {
      initials = { { "zh", "z" }, { "ch", "c" } },
      finals = { { "ang", "an" } },
    },
  },
}
```

重叠分组采用第一个包含该声母或韵母的分组。双拼方案的完整音节特例（如零声母规则）优先于模糊音转换。

### matcher 与 fallback

码表支持三个 matcher：

- `full_code`：输入前缀可显示候选，完整编码才进入下一个文本字符。
- `initial`：完整编码或首个 ASCII 字母都可进入下一个字符。
- `prefix`：任意非空编码前缀都可进入下一个字符。

```lua
sources = {
  { name = "pinyin", scheme = "flypy", matcher = "prefix" },
  "unicode",
}
```

普通 source 都参与匹配；`fallback = true` 的 source 只在前面的 source 全都不认识当前字符时参与，即使前面的 source 认识字符但输入不匹配，它也不会运行。`unicode` 默认开启 fallback，可显式设为 `false`。

默认前置的字面 source 也遵守这条规则，所以后面的 fallback source 不处理 ASCII 字符。

### 顶功

```lua
sources = {
  { name = "tiger", strategy = "top_force", max_length = 4 },
}
```

虎码通过 `strategy = "top_force", max_length = 4` 开启顶功；不需要顶功时只写 `"tiger"` 即可。短于 `max_length` 的编码追加一个空格，达到最大码长的不追加。`max_length` 必须是正整数。

## 自定义 source

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
  },
}
```

Lua 文件返回与 `data` 相同结构的表；TSV 按 UTF-8 字节序排序，每个字符一行，编码用逗号分隔，支持 LF 和 CRLF。路径相对于当前工作目录，也可使用绝对路径或 `~`。

`loader = function(char) ... end` 可按字符返回编码数组或 `nil`。它只在当前表未命中时调用，结果及未命中都会缓存；它会替换该 source 原有的 TSV 未命中加载器。

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

## 生成码表与检查

```vim
:FlashAnyBuildTable source.dict common.lua full.tsv [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

输入支持 Rime、TSV、CSV 或空白分隔文本。`format` 可为 `auto`（默认）、`rime`、`tsv`、`tab`、`csv`、`space`；`encoding` 默认为 `utf-8`。只收录单字符条目，同一字符的编码会合并、去重。

省略第四个参数时 Lua 输出包含全部字符；提供已有 Lua 字表时只把其中的字符写入 Lua 常用表，完整 TSV 始终包含全部字符。需要指定 format/encoding 而不筛选常用字时，第四个参数填 `-`：

```vim
:FlashAnyBuildTable source.csv common.lua full.tsv - csv utf-8
```

输出编码必须是 ASCII，且不能包含逗号、制表符或换行；文件会覆盖输出路径，请选择与输入不同的路径。

当前按 Unicode 码点处理文本，不合并完整 grapheme cluster（例如 ZWJ emoji 和组合音标）。

## 许可与来源

项目代码采用 [MIT](LICENSE)。内置码表保留各自的上游许可与来源，见 [THIRD_PARTY.md](THIRD_PARTY.md)。虎码码表来源：[虎码官网](https://www.tiger-code.com/)。

# 为 flash-any 提供一个 source

[English](writing-sources.md)

本教程面向 `main` 分支。从一个最小码表开始，制作一个可独立安装、录制演示的
`flash-any-mycodes.nvim` 插件。只需准备数据和一个简短的 Lua 工厂，不需要修改核心或编写 C。

本地测试需要 Neovim 0.11+、flash.nvim，以及已执行 `make` 的 flash-any.nvim。
source 包本身不需要构建动态库。

## 1. 建立目录

创建一个插件目录，先放两个文件：

```text
flash-any-mycodes.nvim/
└── lua/flash-any/
    ├── sources/mycodes.lua
    └── tables/mycodes.tsv
```

`mycodes` 是用户配置 `sources` 时使用的名称。工厂文件名和下面的 `codetable`
使用同一名称，方便维护。实际项目应选择能表明语言或编码用途的名称。

## 2. 准备码表

将以下内容保存为 UTF-8 的 `lua/flash-any/tables/mycodes.tsv`。
文字和编码之间使用一个真正的 Tab，下面的示例可以直接复制：

```tsv
中	zhong
文	wen
重	zhong
重	chong
```

每行一段文字和一个编码；多个编码重复写行，不使用逗号拼接。逗号本身可以是编码。
无需排序，也无需另做常用字缓存。

键可以是完整字素，例如“中”、`á` 或 `👩‍💻`，也可以是“中文”这样的词组。
同一位置的单字与词组都参与匹配，只在字素边界输出，不跨行。
编码应为非空 ASCII，不能包含 Tab、换行或 NUL；选键后缀和组内拼写也不能含 NUL。

若已有 Rime、CSV、Fcitx 等文件，可先参考[文件接入和转换](sources.md#直接读取码表--dictionary-files)。
不必为了自己使用现有码表而发布一个插件；本教程的独立包适合分发给其他用户。

## 3. 提供工厂

将以下代码保存为 `lua/flash-any/sources/mycodes.lua`：

```lua
return function()
  return {
    codetable = "mycodes",
    matcher = "full_code",
  }
end
```

`codetable` 指向第二步的同名 TSV；工厂返回配置，由核心负责读取数据和匹配。
不需要注册函数。也可以从[工厂模板](../demos/templates/source.lua)开始。

按用途选择匹配模式：

| matcher | 用户可以输入 |
| --- | --- |
| `full_code` | 完整编码，例如 `zhong` |
| `initial` | 首字母或完整编码，例如 `z`、`zhong` |
| `prefix` | 任意非空前缀，例如 `z`、`zh`、`zhong` |

这里先用 `full_code`。自定义选项或构建时转换可在工厂中处理；
运行时 Lua matcher 不受支持。更多配置见[工厂参考](sources.md#工厂--factory)。

## 4. 在本地安装

在 lazy.nvim 中把本地包作为依赖，并启用 `mycodes`：

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    { dir = "/absolute/path/to/flash-any-mycodes.nvim" },
  },
  build = "make",
  opts = { sources = { "mycodes" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
  },
}
```

把 `dir` 改为第一步的目录。source 必须在 setup 前加载；无需为 source 配置 `build`。
安装核心时执行的 `make` 构建 C 模块，setup 会在需要时自动编译码表。

## 5. 检查单字与混输

用上述配置启动一个新的 Neovim，打开包含以下文本的缓冲区：

```text
中 文 重
中文 with flash
```

按 `s` 后输入 `zhong`，应同时看到“中”和“重”的候选标签，选择标签即可跳转。
再次按 `s`，输入 `zhongwen with flash`，应匹配第二行的完整文本。
普通 ASCII 仍可直接输入，不需要加进码表。

修改工厂或码表后，重启 Neovim 再测。若提示 source 未安装，先检查
runtimepath、`sources/mycodes.lua` 路径和配置中的名称；可用 `:checkhealth flash-any` 检查环境。
缓存和需要手动重建的特殊情况见[缓存说明](sources.md)。

## 6. 编写面向用户的 README

复制[README 模板](../demos/templates/README.md)及[中文模板](../demos/templates/README.zh-CN.md)，
替换 `OWNER/TABLE`、`SOURCE` 和输入示例。本例中 `SOURCE` 为 `mycodes`。
README 主要说明安装、输入什么以及怎样跳转，维护命令放到独立文档。
列全面向使用者的选项、默认值、枚举值、手动设置示例和组合限制；例如拼音需要说明全部双拼
方案及 fuzzy 的默认分组、自定义是否替换默认值。常用配置放 README，其他用户配置可另设示例文档。工厂生成的内部构建数据不要暴露为安装选项。

语言类 source 用对应语言作 `README.md` 主页，英文版保存为 `README.en.md` 并互相链接。
例如中文包将中文模板保存为 `README.md`、英文模板保存为 `README.en.md`。
非单一语言包可以保留英文主页，但要相应调整语言导航链接。

将[维护模板](../demos/templates/maintenance.md)保存为 `docs/maintenance.md`。
为自己的代码选择许可，并记录码表的上游来源和条款；不要把项目代码许可当作数据许可。

## 7. 录制并发布演示

复制以下模板到 source 包：

| 模板 | 保存位置 |
| --- | --- |
| [table-demo.lua](../demos/templates/table-demo.lua) | `demo.lua` |
| [table-demo.yml](../demos/templates/table-demo.yml) | `.github/workflows/demo.yml` |

在 `demo.lua` 中将 `SOURCE` 换为 `mycodes`，本例的主要字段如下：

```lua
return {
  file = "lua/flash-any/tables/mycodes.tsv",
  matcher = "full_code",
  text_name = "Chinese",
  text = "中",
  mixed_text = "中文 with flash",
  comment = "Flash can match Chinese: type a code, then choose a label.",
  mixed_comment = "Mix Chinese codes with ASCII in the same search.",
}
```

字段的详细注释在模板里；编码由码表推导，不必再填查询串。
可用 `sample` 指向自己的短样本文件，路径相对 `demo.lua`。
省略 `text` 时会随机抽取字体覆盖的条目；演示第一段单字多标签，第二段混输，允许多个标签。
若修改匹配模式，记得同步工厂和 `demo.lua`。

工作流只传 `config: demo.lua`。将 `uses` 引用和 `flash-any-ref` 固定到同一个
已发布到核心 `main` 的测试提交，然后把 source 仓库推送到自己的 GitHub `main` 分支。
用户安装配置中的本地 `dir` 可替换为 `"OWNER/flash-any-mycodes.nvim"`。

每次推送 `main` 或手动运行工作流，都会录制并验证两次真实跳转。
成功后自动替换 `demos` prerelease 的 GIF、MP4、封面及报告，README 使用固定附件链接；
生成媒体不提交到 Git。录制任务只读，发布任务单独获得 `contents: write`。

首次运行后打开 README 查看 GIF，并检查 Actions 的验证报告和画面。
修改目标、旁白或样本，只需编辑 `demo.lua` 后再次推送。
本地录制命令、依赖和字体检查见[录制说明](../demos/README.md)。

# 为 flash-any 提供一个 source

[English](writing-sources.md)

本教程面向核心 `main` 分支，按“本地可用 → 录制 → 发布”走完一个独立 source。
普通码表只需一个工厂和一份数据，不需要修改核心、编写 C 或实现运行时 matcher。
下面的最小例子可直接执行；换成自己的正确码表后，保留同样的目录和名称即可。

## 1. 先让最小包跑起来

需要 Neovim 0.11+、make、C 编译器，以及 flash-any.nvim 和 flash.nvim 的本地 checkout。
以下命令用于 Linux/macOS。已有 checkout 时直接进入核心仓库；尚未下载时可以先执行：

```sh
git clone --branch main https://github.com/dirichy/flash-any.nvim.git "$HOME/flash-any.nvim"
git clone https://github.com/folke/flash.nvim.git "$HOME/flash.nvim"
cd "$HOME/flash-any.nvim"
```

source 包本身不需要 `make`、Python、VHS 或下载词典的安装钩子。

从 **flash-any.nvim 仓库根目录**执行下面的代码块。`FLASH_NVIM_PATH` 改为已有的
flash.nvim 路径，`FLASH_ANY_SOURCE_ROOT` 选择一个空目录；这两个目录均不要求位于核心仓库内。

```sh
# Create the minimal source package.
export FLASH_ANY_ROOT="$PWD"
export FLASH_NVIM_PATH="${FLASH_NVIM_PATH:-$HOME/flash.nvim}"
export FLASH_ANY_SOURCE_ROOT="${FLASH_ANY_SOURCE_ROOT:-$HOME/flash-any-mycodes.nvim}"

mkdir -p "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/sources" "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/tables"
sed 's/SOURCE/mycodes/g' demos/templates/source.lua > "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/sources/mycodes.lua"
sed 's/"SOURCE"/"mycodes"/g' demos/templates/minimal.lua > "$FLASH_ANY_SOURCE_ROOT/minimal.lua"
cp demos/templates/source.gitignore "$FLASH_ANY_SOURCE_ROOT/.gitignore"
printf '中\tzhong\n文\twen\n重\tzhong\n重\tchong\n' > "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/tables/mycodes.tsv"
printf '中 文 重\n中文 with flash\n' > "$FLASH_ANY_SOURCE_ROOT/sample.txt"

make -C "$FLASH_ANY_ROOT"
NVIM_LOG_FILE="$FLASH_ANY_SOURCE_ROOT/nvim.log" nvim --clean -l "$FLASH_ANY_SOURCE_ROOT/minimal.lua"
```

最后一条命令成功退出，表示 **按名称发现工厂、加载码表、setup 构建二进制**已经通过，
不只是 Lua 文件能被解析。`minimal.lua` 是隔离个人配置的开发入口，模板在
[minimal.lua](../demos/templates/minimal.lua)。保持上述环境变量，在同一终端运行：

```sh
nvim --clean -u "$FLASH_ANY_SOURCE_ROOT/minimal.lua" "$FLASH_ANY_SOURCE_ROOT/sample.txt"
```

按 `s` 输入 `zhong`，应出现“中”和“重”的标签；选择一个标签确认光标落点。
再次按 `s` 输入 `zhongwen with flash`，应匹配第二行。普通 ASCII 不必加入码表。
遇到问题先用这份配置复现，不先加载个人配置或依赖录制器排查。

最小包现在包含：

```text
flash-any-mycodes.nvim/
├── .gitignore
├── minimal.lua
├── sample.txt
└── lua/flash-any/
    ├── sources/mycodes.lua
    └── tables/mycodes.tsv
```

## 2. 换成自己的码表和名称

`mycodes` 是 `sources = { "mycodes" }` 使用的名称，不是仓库名。仓库可以叫
`flash-any-mycodes.nvim`。工厂路径、`codetable` 和用户配置中的名称须一致：

```lua
-- lua/flash-any/sources/mycodes.lua
return function()
  return {
    codetable = "mycodes",
    matcher = "full_code",
  }
end
```

把完整 UTF-8 码表放到 `lua/flash-any/tables/mycodes.tsv`，每行是文字、**真正的 Tab**、编码。
第一步的 `printf` 会生成真正的 Tab，不会把两个字符 `\t` 写进文件。
一个文本有多个编码就重复写行，逗号是普通编码字符，不用于拼接编码。
无需排序、常用字副本或单独注册。

文字可以是单字素、组合字符或词组，例如 `中`、`á`、`👩‍💻`、`中文`。
普通编码必须是非空 ASCII，不含 Tab、换行或 NUL；组引用可以用 Unicode 名称。
同一文字位置的单字和词组均参与匹配，只在字素边界输出，不跨行。
若只收词组，不会自动推导每个汉字的读音；不在表里的读音也不会从前后文猜测。

| matcher | 接受的输入 |
| --- | --- |
| `full_code` | 完整编码，例如 `zhong`，本教程默认 |
| `initial` | 首字母或完整编码，例如 `z`、`zhong` |
| `prefix` | 任意非空前缀，例如 `z`、`zh`、`zhong` |
| `letter` | 完整编码，遵循 ignorecase/smartcase，可按字素首码点查表 |

如果改名，同时更新工厂文件名、`codetable`、`minimal.lua` 中的 source 名称、README 和 demo。
修改工厂或码表后，**重启 Neovim** 再运行第一步的验证；只重跑 setup 不会清掉 Lua require 缓存。
`:checkhealth flash-any` 可检查环境；缓存及显式 binary 的重建规则见[参考](sources.md)。

## 3. 现有码表、converter 和 groups

如果已有受支持的文件，可由工厂返回 `file`，不用为安装者重复导出一份格式：

```lua
return function()
  return {
    file = assert(vim.api.nvim_get_runtime_file("lua/flash-any/tables/mycodes.tsv", false)[1]),
    format = "tsv",
    matcher = "full_code",
  }
end
```

工厂中的文件路径用 `nvim_get_runtime_file` 定位，不能依赖 shell 当前目录或作者的绝对路径。
默认文本列在前、编码列在后；反向列序须显式声明 `columns = { "code", "text" }`。
Rime、CSV、Fcitx、IBus、编码和权重等选项见[文件接入](sources.md#直接读取码表--dictionary-files)。

- **ASCII 编码已经正确**：直接读表，不需要 converter。
- **读音需要转换或分音**：使用 `file` 加 `converter`，工厂返回转换器的绝对路径。
  converter 接收同一个文本条目的去重编码数组，返回 ASCII 编码或有效组引用/序列数组；
  `nil` 或空数组略过对应条目。它只在构建时执行，不读取缓冲区上下文，也不解析 XML。
  不受支持的原始格式须先由维护脚本提取成受支持的表；安装时不应再下载原始词典。
- **同一音节有多种拼写**：工厂提供 `groups`。例如码表保存 `寿司<Tab>す し`，
  `groups = { ["す"] = { "su" }, ["し"] = { "shi", "si" } }` 可接受 `sushi` 和 `susi`。
  `full_code/initial/prefix/letter` 逐组生效。连写读音 `すし` 可以由 converter 分成 `す し`；
  没有收录的完整组名或组序列不会自动分音。

不要把原始读音、组名和用户实际输入的拼写混为一谈，也不要把元数据或符号释义当作发音。
维护脚本应报告无法转换的读音及过滤数量，保留同一文本的其他有效读音。
普通 source 仍只需第二步的工厂；完整接口见[构建参考](sources.md)。

## 4. 本地安装与公开安装分别写清楚

开发时，lazy.nvim 可以加载本地 source：

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

source 必须在核心 setup 前加载。测试未发布的核心功能时，核心也应使用对应本地 checkout，
而不是以为远端 `main` 已经包含工作区修改。第三方安装者的配置则使用真实的
`"OWNER/flash-any-mycodes.nvim"` 依赖；**公开 README 不能保留作者的 dir、HOME 或 .dev 路径**。
用户只运行核心的 `build = "make"`，source 不需要另一个安装构建步骤。

## 5. 一次补齐 README、许可和忽略规则

从核心仓库根目录复制模板：

```sh
mkdir -p "$FLASH_ANY_SOURCE_ROOT/docs" "$FLASH_ANY_SOURCE_ROOT/.github/workflows"
cp demos/templates/README.zh-CN.md "$FLASH_ANY_SOURCE_ROOT/README.md"
cp demos/templates/README.md "$FLASH_ANY_SOURCE_ROOT/README.en.md"
cp demos/templates/maintenance.md "$FLASH_ANY_SOURCE_ROOT/docs/maintenance.md"
sed 's/SOURCE/mycodes/g' demos/templates/table-demo.lua > "$FLASH_ANY_SOURCE_ROOT/demo.lua"
cp demos/templates/table-demo.yml "$FLASH_ANY_SOURCE_ROOT/.github/workflows/demo.yml"
```

将 README 中的 `OWNER/TABLE` 换为实际仓库，例如 `OWNER/flash-any-mycodes.nvim`，
`SOURCE` 换为 `mycodes`。语言类 source 用对应语言的 README.md 作主页，并链接英文版；
中文包可以直接用上述布局，其他语言另写主页，非单一语言包可保持英文主页。
说明所有使用者选项、默认值、枚举值、示例和组合限制；内部构建数据放在维护文档。

添加代码许可及 `THIRD_PARTY.md`，记录上游版本、数据许可、输入哈希和转换方式；代码许可
不能代替数据许可。第一步复制的 `.gitignore` 已排除生成媒体、Neovim 日志和 Python 缓存。
提交前用 `git status --short` 检查文件列表，不把本地依赖、词典下载缓存或录制产物加入 Git。

## 6. 先生成场景，再录制

普通码表只需修改刚复制的 `demo.lua` 中的语言名称、目标文字和旁白：

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

**有 converter、groups 或自定义默认 matcher 的 source**，改用下面的完整配置，复用实际工厂，
不要另写一份只演示普通码的转换器：

```lua
-- demo.lua: reuse the source factory
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.runtimepath:append(root)
local source = require("flash-any.sources.mycodes")()
return vim.tbl_extend("force", source, {
  file = source.file or "lua/flash-any/tables/mycodes.tsv",
  text_name = "Chinese",
  text = "中",
  mixed_text = "中文 with flash",
  comment = "Type a code, then choose a label to jump.",
  mixed_comment = "Mix codes and ASCII in the same search.",
})
```

`file` 工厂复用实际文件；`codetable` 工厂用同名 TSV 作为录制输入。
所有 demo 相对路径以 demo.lua 所在目录为基准；工厂模块的 require 则需要上面的 runtimepath。
目标编码自动从真实码表及拼写组推导，不必手填查询或标签。

当前模板第一段要求 `text` 是表中有编码的**一个完整字素**，会补两个副本形成多个标签；
第二段 `mixed_text` 要包含码表文字与 ASCII，且其中每个非 ASCII 字素都须能单独查码。
词组支持不等于自动生成了单字读音；只含词组的表目前不适用这个单字录制模板。
可用 `sample` 提供短样本，但必须包含完整 mixed_text，所有字符须有字体覆盖。
省略 text 时才从字体覆盖的单码点条目抽样；text_name 只是语言类别，不是对目标字的翻译。

本地场景准备也需要 fontconfig（fc-match/fc-query）和录制字体：JetBrainsMono Nerd Font Mono、
Noto CJK、Noto Color Emoji。完整录制另需 VHS、ttyd、Chromium/Chrome、FFmpeg/ffprobe、
Python 3 和 Tokyo Night 主题，详见[依赖说明](../demos/README.md#录制--record)。
缺少本地录制工具时，可以先验证 source，再用第 7 步的 CI 环境录制；CI 会安装录制依赖。

具备字体后，从核心仓库根目录执行不启动浏览器的准备步骤：

```sh
nvim --clean -l demos/prepare-table.lua "$FLASH_ANY_SOURCE_ROOT/demo.lua"
```

应看到 `Prepared 2 jumps for table`；它已经读表、执行 converter、编译真实组数据，并验证
两段目标和可用标签。失败先修目标、路径、缺字字体或核心版本。录制时继续使用第一步的
FLASH_NVIM_PATH；为已有主题设置 TOKYONIGHT_PATH，没有主题时可先执行
`git clone https://github.com/folke/tokyonight.nvim.git "$HOME/tokyonight.nvim"`。准备成功后录制：

```sh
export TOKYONIGHT_PATH="${TOKYONIGHT_PATH:-$HOME/tokyonight.nvim}"
sh demos/record.sh table "$FLASH_ANY_SOURCE_ROOT/demo.lua"
```

本地端口或 Chromium 被沙箱阻止时，应允许录制器在相应环境运行，不改 tape 掩盖错误。

输出统一在**核心仓库**的 `demos/output/`：`table.gif`、`table.mp4`、`table.png`、
`table-verification.json`、`table-media.json` 和 `README.local.md`。
检查 `verified: true`、两次实际落点、样本未修改，并打开 GIF/MP4 检查字体和裁切。
本地预览只使用这个目录的 README.local.md；复制媒体到 source 并不会自动发布。

## 7. 配置远端录制，确认核心版本

模板默认 `uses: ...table-demo.yml@main`、`flash-any-ref: main`，每次新运行跟随已发布核心；
`table-ref: ${{ github.sha }}` 固定当前 source 提交，工作流只传 `config: demo.lua`。

| 配置 | 控制什么 |
| --- | --- |
| `uses` 后的 `@ref` | 调用哪个版本的录制工作流 |
| `flash-any-ref` | 实际 checkout 哪个版本的核心和录制代码 |
| `table-ref` | checkout 哪个版本的 source 及字表 |

需要复现时才将前两处同时固定到一个**已发布、已用本 source 验证过**的核心 SHA。
“两处 SHA 相同”不等于功能足够：旧提交即使能下载，也可能缺少 converter/groups/组序列支持。
必须用目标核心跑过本地 source 和场景准备；本地未提交或未推送的改动不在远端 ref 中。

把 source 仓库发布到 main 后，push 或 Actions 的 Run workflow 会开始录制。
仅更新核心不会触发 source 工作流，核心更新后应在 source 的 main 发起一次**新运行**。
修改 workflow 引用后也不要只重跑旧的失败 job：它可能继续使用第一次尝试的工作流提交，
见 [GitHub 的复用工作流重跑规则](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)。
模板的发布 job 只在 main 运行；使用其他默认分支时同步修改 push 和发布条件。

录制 job 只读；发布 job 的 `contents: write` 已写在模板中，用当前仓库的 GITHUB_TOKEN
创建或替换 `demos` prerelease，不需要另写上传脚本。录制成功但发布权限失败时，仍可先
查看 `table-demo` artifact；artifact 成功不等于 README 的 Release URL 已存在。

## 8. 发布结束后让新用户验证

首次媒体尚未发布时，README 可以先链接
`https://github.com/OWNER/TABLE/actions/workflows/demo.yml`。首次发布成功后，**所有语言 README**
都要换成模板中的固定 GIF、MP4 和验证报告链接，不能停留在 Actions 入口或被忽略的本地路径：

```markdown
![Search and jump](https://github.com/OWNER/TABLE/releases/download/demos/table.gif)

[MP4](https://github.com/OWNER/TABLE/releases/download/demos/table.mp4) · [Verification report](https://github.com/OWNER/TABLE/releases/download/demos/table-verification.json)
```

后续成功录制会替换同名附件，不必再改链接。首次发布后打开这三个地址，核对报告的
`verified` 和实际画面；再用 README 的远程依赖配置，从一个新 checkout 安装并跑单字及混输。
这一步应只依赖已发布的核心和 source，不依赖作者机器上的本地目录或未发布改动。

完成意味着：**按名称安装能跳转、录制报告通过、发布附件可访问、各语言 README 能直接看 demo**。
本地成功、Actions artifact 成功和 Release 发布成功是三个不同结果，不能相互替代。

## 常见问题

| 现象 | 先检查 |
| --- | --- |
| source is not installed | factory 路径、source 名称、setup 前的 runtimepath；用 minimal.lua 重测 |
| Tab、列序、Unicode 编码报错 | 真正的 Tab、text/code 顺序、文件格式；原始读音是否还缺 converter 或组定义 |
| 工厂或 converter 找不到文件 | 工厂用 runtime 文件定位；demo 相对路径以配置目录为基准 |
| 更新后仍是旧效果 | make 后重启；source Lua/TSV 也需重启；显式 binary 按参考重建 |
| 本地成功，CI 缺少 groups 等能力 | 对照两处核心 ref 的实际功能；发布新核心并触发新运行 |
| demo 目标没有编码或字体 | text 单字素、mixed_text 单字覆盖、converter 输出及实际字体 |
| GIF 本地存在，GitHub README 仍无图 | 确认 publish job、demos Release 附件及 README 的远端地址 |

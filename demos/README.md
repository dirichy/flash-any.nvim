# Demo recordings / 演示录制

一段连续演示使用同一套 `sources = { "pinyin", "unicode" }` 配置，真实输入查询并按 Flash 标签跳转：

| 场景 / Scene | 输入 / Input | 目标 / Target |
| --- | --- | --- |
| 全拼 / Full pinyin | `s` → `quan` → `pin` → `a` | 全拼 |
| 简拼 / Initials | `s` → `j` → `p` → `a` | 简拼 |
| 连续混输 / Mixed input | `s` → `hun` → `s` → `ascii` → `grin` → `a` | 混输ascii😀 |

混输只开启一次搜索：`hun` 是“混”的全拼，`s` 是“输”的简拼首字母，`ascii` 按字面匹配，
`grin` 是 😀 的 Unicode 名称前缀。分段停顿仅用于阅读，不切换输入模式。

`f` 模式单独录制，使用 `sources = { "pinyin" }` 和 Flash 原生字符按键：

| 场景 / Scene | 输入 / Input | 目标 / Target |
| --- | --- | --- |
| 首码 / First code | `fz` | 中、这、字、z 全部高亮，落在“中” |
| 连跳 / Repeat | `f` → `;` → `;` | 这 → 字 → z |
| 反向 / Previous | `,` | 字 |

`char.tape` 使用真实 `f`、`;`、`,` 映射；不替换原生按键。录制进程观察每次落点
和全部四个候选，并在退出前验证样例未修改。

The separate character-mode clip shows `fz`, repeated forward jumps with `f` and
`;`, and a backward jump with `,`. Live playback verifies every cursor position
and all four first-code candidates without replacing Flash's keymaps.

## 录制 / Record

从仓库根目录运行：

```sh
sh demos/record.sh       # s: 全拼、简拼、混输
sh demos/record.sh char  # f: 首码与连跳
```

需要 Neovim、VHS、ttyd、Chromium/Chrome、FFmpeg（含 ffprobe）、Python 3、fontconfig，
以及 JetBrainsMono Nerd Font Mono、Noto CJK 和 Noto Color Emoji 字体。
录制脚本先执行make构建C模块，setup仅自动构建码表；需make和C工具链，无需pkg-config或LuaJIT开发包。
码表二进制缺失时从上面的sources配置自动构建，无需手动make或导出码表。
Flash 默认位于 `.dev/flash.nvim`，Tokyo Night 默认位于 `.dev/tokyonight.nvim`，可指定已有安装：

```sh
FLASH_NVIM_PATH=/path/to/flash.nvim \
TOKYONIGHT_PATH=/path/to/tokyonight.nvim \
sh demos/record.sh
```

录制通过 `init.lua` 和 `sample.lua` 隔离个人配置。样式由 [common/style.tape](common/style.tape) 共用。
[demo.tape](demo.tape) 录制三次 s 搜索；[char.tape](char.tape) 单独录制 f 模式，
使用 `char-init.lua` 和 `char-sample.txt`。每段各启动一次 Neovim。
本地产物、config/state/cache、日志、调色板及验证报告都保存在已忽略的 `demos/output/`，
脚本不上传文件。内置两段分别生成 `demo.*` 与 `char.*`；
`demos/output/README.local.md` 提供本地 GIF 和 MP4 链接。

Requires Neovim, VHS, ttyd, Chromium/Chrome, FFmpeg/ffprobe, Python 3, fontconfig,
JetBrainsMono Nerd Font Mono, Noto CJK, and Noto Color Emoji. Run from the repository
root. Set `FLASH_NVIM_PATH` and `TOKYONIGHT_PATH` to override local plugin paths.
Initial setup automatically builds the native core and missing dictionaries using
make and a C toolchain. Python remains a recording-tool dependency only.
The isolated configuration never loads personal dotfiles. Local recording does not publish.

## 第三方码表 / Third-party tables

码表仓库不用修改。克隆本插件，准备上述录制依赖后，直接指向现有码表：

```sh
TABLE_FILE=/path/to/another-project/table.tsv sh demos/record.sh table
```

所有文件格式均复用 build.read；多编码用重复行，逗号不再作为列表分隔符。
内置 Lua 模板读取带权重和词组的 Rime 文件，并使用熟悉的“中”和“中文 with flash”演示。

只提供码表时，脚本用固定种子随机选取字体覆盖的单码点条目。
可选环境变量包括 `TABLE_FORMAT`（默认 auto）、`TABLE_COLUMNS`（JSON 列标签数组）、
`TABLE_ENCODING`（默认 UTF-8）、`TABLE_MATCHER`（默认 full_code）、
`TABLE_CONVERTER`（Lua 文件路径）和 `TABLE_TITLE`。
若要选熟悉的目标、命名和样本文件，复制 [Lua 模板](templates/table-demo.lua)：

```sh
sh demos/record.sh table demos/templates/table-demo.lua
```

CSV 标题行可在 Lua 中设置 `header = true`。所有相对路径以 Lua 配置所在目录为基准；
环境变量可覆盖对应的码表选项。目标编码自动推导，原码表文件不会被写入。
具体演示字段见下方“自动码表场景”。

本地文件为 `table.gif`、`table.mp4`、`table.png`、`table-verification.json`、
`table-media.json`、`table-config.json` 和 `table.tape`，均在 `demos/output/`。
`README.local.md` 同时链接已经录制的各段媒体。converter 示例见
[converter.lua](templates/converter.lua)；它只转换构建时编码，不是自定义 matcher。

### GitHub Actions

有两种方式：

1. **码表仓库零改动**：在有 Actions 运行权限的 flash-any 仓库或 fork 中，手动运行
   [Code-table demo](../.github/workflows/table-demo.yml)，填写 `table-repository`、
   `table-ref`、`file` 和可选 format/columns/converter/matcher/config。路径相对码表仓库。
2. **在码表仓库运行**：复制 [调用模板](templates/table-demo.yml) 为
   `.github/workflows/demo.yml`，修改码表路径、matcher 和可选的 config；推送 main 自动录制，也可手动运行。

```sh
gh workflow run table-demo.yml --repo dirichy/flash-any.nvim --ref main \
  -f table-repository=OWNER/TABLE -f table-ref=main -f file=table.tsv \
  -f matcher=full_code
```

模板通过 `workflow_call` 复用录制环境。固定工作流 uses 引用与 `flash-any-ref`
到同一发布提交，并固定 `table-ref`，可以复现同一配置；main 为开发分支。
功能发布到相应远程 ref 后才能调用，本地修改不会改变 GitHub 上的工作流。
核心可复用工作流只需 contents:read，只上传 `table-demo` artifact。调用模板另有
contents:write 发布任务，验证成功后替换 `demos` prerelease 的 GIF、MP4、封面与报告，
并用认证下载核对附件。README 引用固定 Release 地址，不提交生成媒体；
旧提交的录制不会覆盖新 main。失败时保留本轮 artifact 和日志。可使用
[中文](templates/README.zh-CN.md) / [English](templates/README.md) README 模板；
将[维护模板](templates/maintenance.md)放到码表仓库的 `docs/maintenance.md`。

Point `TABLE_FILE` at an unchanged repository, or supply the optional Lua template.
The recorder chooses a converted single-grapheme example automatically; set
the optional Lua fields described below to demonstrate familiar text. Dictionary,
converter and sample paths in Lua are relative to that Lua file. The same live candidate, label, cursor and
fixture assertions used by the built-in demo apply to third-party recordings.

The reusable workflow accepts repository/ref, dictionary path, format, columns, optional converter, matcher ID
and an optional Lua configuration path. Run it in a repository where you have Actions permissions,
or copy the tiny caller workflow into the table project to record on main pushes
or manual dispatches. Pin both the workflow ref
and flash-any-ref to the same published commit. It uploads the table-demo artifact
without writing to the caller repository. The caller template adds a contents:write
job that replaces the dedicated demos prerelease assets after verification, then
checks authenticated downloads. README links use stable release URLs; generated
media is never committed. Outdated runs skip publication. Unpushed workflow changes cannot be called
from GitHub. The README templates focus on installation and use. Copy the maintenance template
to docs/maintenance.md for table updates and recording instructions.

## 画质与验证 / Quality and verification

原始 MP4 为 1920×1080、36 号字，单窗口采用 56px 渐变外边框、圆角和 Colorful 窗口栏。
背景与样式参考 vimoi.nvim 录制脚本；背景原样来自
[chezmoi-template.nvim](https://github.com/dpezto/chezmoi-template.nvim/blob/670ba83095ba6571f3125a5e5fd4118505a2c3c6/assets/tapes/style.tape)，
保留 [MIT 许可](common/backdrop.LICENSE)。

VHS 设置抓帧 30fps，本机 H.264 输出实测 25fps，以 ffprobe 报告为准。
GIF 从 MP4 两遍转换，保留 1920×1080、20fps，变化区域调色板与固定 Bayer 抖动可减少渐变闪烁。
输入速度为 120ms/键，语义分段后停留 0.8 秒，跳转后停留 1.8 秒。

同一次 TUI 回放记录中间查询候选、实际标签和最终落点，确认样例未修改且没有 Neovim 错误。
预期行列由原始样例中的目标位置确定，使用字节列；码表演示从真实匹配中选择落点。
每轮清空旧验证文件，异常写入本轮 JSON；验证成功才转换 GIF、检查 codec/尺寸/实际帧率并提取封面。
生成后仍须目视检查关键帧的字体、emoji、裁切和标签。

The recording produces `demo.mp4`, `demo.gif`, `demo.png`, `verification.json`,
and `media.json`; character-mode files use the `char` prefix, including
`char-verification.json` and `char-media.json`. `README.local.md` links locally
recorded clips without release URLs. Live TUI assertions check intermediate matches, the selected label,
all three final queries and cursor positions, and the unchanged fixture. Media checks verify
1920×1080 output and actual codecs/frame rates. The MP4 retains full color; the
20fps GIF uses a separate palette pass and stable Bayer dithering.
Expected byte positions come from the original fixture; table recordings select
a target from real matcher results.

## CI 与发布 / CI and publishing

[工作流](../.github/workflows/demos.yml) 在 `master` 的插件、录制素材、README 和相关测试变化时
自动运行，也可手动运行。工具与插件版本统一固定在 setup-demo composite action 中，字体包括 CJK 和 emoji fallback。
分别录制 s、f 和第三方 Rime 模板三段，保存 GIF、MP4、PNG 和 JSON artifact。验证成功后才更新独立 `demos` prerelease 的同名媒体附件，
最后检查附件 URL。不提交生成媒体，不将 demo Release 标为 latest。
验证失败时也保存已生成的媒体和 JSON，便于检查实际查询、落点及预期位置；失败不发布。

README 引用 `releases/download/demos/demo.gif` 和 `demo.mp4`；
f 模式附件为 `char.gif` 和 `char.mp4`。本地录制不更新远端附件，提交后 CI 才会发布新版演示。

The workflow records the continuous demo, verifies playback and media, saves artifacts,
and updates the `demos` prerelease on the default branch. README media URLs become
available after the updated workflow publishes them. Local files and release assets
are separate; no generated media enters Git history.
Failed runs also save available media and verification JSON for diagnosis; they do not publish.


## 独立 source / Optional sources

默认拼音和字符演示需要另行安装 pinyin/unicode source。开发环境可设置
FLASH_ANY_SOURCE_PATH 为包含五个独立插件目录的路径；普通外部 file 录制不需要它们。
默认演示 CI 在发布独立 source 仓库并设置仓库变量 FLASH_ANY_SOURCE_OWNER 后启用，
从该所有者的 flash-any-NAME.nvim main 分支安装依赖；核心 CI 不依赖 source 仓库。

Default pinyin/char recordings require separately installed sources. Set
FLASH_ANY_SOURCE_PATH to their parent directory. External file recordings need no
source plugins. Set repository variable FLASH_ANY_SOURCE_OWNER after publishing the
separate source repositories to enable default demo CI. Core CI runs independently.


## 自动码表场景 / Automatic table scenes

可复制 [Lua 模板](templates/table-demo.lua) 和 [样本模板](templates/table-sample.lua)，
填写熟悉的文本，再运行 `sh demos/record.sh table /path/demo.lua`。例如虎码可以用：

```lua
return {
  file = "table.tsv",
  text_name = "Chinese",
  text = "虎",
  mixed_text = "虎码 with flash",
  comment = "Flash can match Chinese: type a code, then choose a label.",
  mixed_comment = "Mix Chinese codes with ASCII in the same search.",
  -- sample = "sample.lua",
}
```

`text_name` 是旁白里的文本名称，默认 `any text`；`text` 是第一段的单字素目标；
`mixed_text` 是第二段的码表文字与 ASCII 混输目标，默认 `text .. " with flash"`。
编码从转换后的码表推导，不再重复填写 query。`sample` 可省略，脚本会围绕目标生成可读样本。
所有路径相对 Lua 配置文件；GitHub 调用模板用 `config: demo.lua` 指定它，路径相对码表仓库。
工作流显式填写的 file/format/columns/converter/matcher 会覆盖 Lua 配置中对应项。

`comment` 和 `mixed_comment` 是两段可自由修改的旁白，支持多行字符串，录制时显示为注释。
省略时根据 `text_name` 生成。自备样本按原文复制，前面加旁白；让样本保持简短、一屏可见，
并包含混输目标。脚本在独立的小区域补两个单字目标，让第一次有多个真实标签。
第二次尽量使用独特的混输短语，但允许多个标签；脚本读取真实标签完成跳转，不强制唯一。
未提供 `text` 时，才从码表用固定种子随机抽样；不依据权重或 Unicode 区段筛选。

字体来自 common/style.tape 的 FontFamily。fonts.lua 用 Fontconfig 找 fallback，
再用 fc-query 读取实际字体文件及 face 的字符集，缺字时随机条目被跳过，显式样本则报错。
自动抽样只选单码点；字符集覆盖不等同于验证复杂字素的 shaping，成片仍需目视检查。
固定种子在同一码表和字体集合下可复现；seed、条目和覆盖字体会写入本轮 JSON。
参考：[Fontconfig 字符集与字体匹配说明](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-devel/)。

Copy the [Lua](templates/table-demo.lua) and [sample](templates/table-sample.lua) templates.
Set `text_name` (default `any text`), `text` (one grapheme) and `mixed_text`
(default: `text .. " with flash"`). Codes are inferred from the converted table.
Optionally supply `sample`; otherwise a readable fixture is generated around your targets.
Run `sh demos/record.sh table /path/demo.lua`, or set `config: demo.lua` in the
caller workflow. Paths in Lua are relative to that file; the workflow's config path
is relative to the table repository. Explicit workflow file/format/columns/converter/matcher
inputs override Lua values.

The two scenes match a single grapheme among multiple labels, then combine codes and
ASCII in the same search. Editable `comment` and `mixed_comment` strings provide the
narration; multiline strings are supported, with defaults based on `text_name`.
Keep custom samples short enough to fit on screen and include the mixed phrase.
The recorder adds two copies of the single-grapheme target in a separate small area.
Prefer a distinct mixed phrase, but multiple labels are allowed. Actual labels,
candidate counts, cursors and the unchanged fixture are verified in the live TUI.

Only omitted targets use seeded random sampling. Font coverage is confirmed with
fc-query against actual font files/faces in the configured fallback chain, including
custom sample text. Missing explicit glyphs fail; random ones are skipped. Automatic
samples use single scalars because cmap coverage does not prove ligature/ZWJ shaping.
The seed, samples and covering fonts are captured in verification JSON; reproducibility
depends on both the table and installed fonts. Inspect the rendered frames as well.

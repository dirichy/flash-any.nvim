# Demo recordings / 演示录制

主 demo 由 [demo.lua](demo.lua) 配置，同一份 `sources = { "latin", "pinyin", "japanese", "korean", "nerdfont" }`
按 `s → f → remote → search` 的顺序展示：

| 场景 / Scene | 操作 / Input | 效果 / Result |
| --- | --- | --- |
| 标签跳转 / Label jumps | `s` → `zhongwen` / `gksrmf` / `vim` → 标签 / label | 依次跳到中文、한글 和 Vim 图标 |
| 多 source 首码 / Shared first code | `fz`，再连续按 `f` | 依次跳到 ź、中、字、ず、코、zip 图标和字面 z |
| 远程删除 / Remote delete | `dr` → `taberu` → 标签 / label → `iW` | 删除食べる，返回操作起点 |
| 屏幕外混输 / Offscreen mixed search | `<Space>/` → `cafe zw gksrmf taberu vim` → Enter | 输入时跳过干扰项，滚到最终目标 |

`fz` 的七个候选来自 Latin、拼音、日语、韩文、图标和字面匹配，首码都是 z；
后续 `f` 使用 Flash 原生连跳，不重输查询。录制器先用原生行移动定位到该场景，
再观察真实 `f` 按键进入验证阶段，不替换 Flash 的字符映射。
远程删除使用 `iW` 选择完整非空白词，避免原生 `iw` 将汉字与假名分开。
回放验证删除寄存器中的目标词、实际操作符 `d`、删除后的缓冲区和返回位置；磁盘样本不能改变。

search 段不选标签，只开启一次搜索；依次在 `cafe`、`cafe zw`、`cafe zw gksrmf`、
`cafe zw gksrmf taberu` 和完整查询停顿，越过四处相似文本，滚动到初始屏幕之外的目标。
空格按 ASCII 字面匹配，zw 是中文简拼，gksrmf 是韩文 두벌식 键位。
状态栏实时回显实际按键。

The main clip shows `s` label jumps for Chinese, Korean and icons, native repeated
`f` motions, `dr` remote deletion and label-free incremental search, in that order.
Seven spaced first-code candidates share z across all five sources and literal text.
The recorder moves to the character example with native line motions, then observes
real `f` input without replacing Flash's character mappings. Remote delete uses
`iW` to select the entire Japanese word. Playback verifies the delete operator,
register contents, changed buffer, restored origin and unchanged fixture on disk.
The continuous mixed search skips four near matches as the query grows and scrolls
to a target outside the initial viewport. The status line echoes actual keys.

修改 demo.lua 的 sources 和 examples 即可更换例子。每个例子包含 title、text 和 pattern；
mode 默认为 `jump`，可选 `char`、`remote` 或 `search`。`char` 的 pattern 为单字素，
alternatives 在同一行追加有间隔的词组；候选和连跳次数从真实首码匹配推导。
`remote` 使用 `dr` 和 `iW`，只删除目标词，不写回样本。屏幕外 `search` 放在末段，
decoys 按查询前缀排列；checkpoints 每项对应一个干扰项，最后一项对应目标。
可选 checkpoints 是逐步增长的查询前缀，最后一项必须等于 pattern，用来安排输入停顿。
不指定时按第一个完整字素和完整查询停顿。可选 comment 控制单行旁白，默认用 title。
查询显式填写以固定多音字及图标别名，候选、标签和落点均从真实匹配计算。

Edit sources and examples in demo.lua. Each example supplies title, text and pattern;
mode defaults to jump. A char example uses a single-grapheme pattern and appends
spaced alternatives to its row; real first-code matches determine the repeat count.
Remote scenes use dr plus iW and delete only the target without saving the fixture.
An offscreen search scene comes last, with decoys ordered by query prefix and one
checkpoint per decoy plus the final target. Optional checkpoints must be increasing
prefixes ending at the full pattern; comment supplies single-line narration.
Explicit queries select the intended readings and icon aliases. Empty sources
support literal-only examples. Samples and tapes are generated in demos/output.

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
sh demos/record.sh       # f、s、r、屏幕外 search 混输
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

主 demo 和 table-demo 都通过 prepare-table.lua 生成样本、编译字典、推导实际标签和 tape，
由 init.lua 回放；不再维护另一套固定的主 demo tape、样本或查询配置。
样式由 [common/style.tape](common/style.tape) 共用。[char.tape](char.tape) 单独录制 f 模式，
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
使用组引用或组序列时，在 Lua 配置中提供 `groups`。录制器从每组选择一个可打印
拼写并连接成演示查询；编译时保留全部组拼写，不预先展开所有组合。
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
   `.github/workflows/demo.yml`，用 `config: demo.lua` 读取 Lua 配置；推送 main 自动录制，也可手动运行。

```sh
gh workflow run table-demo.yml --repo dirichy/flash-any.nvim --ref main \
  -f table-repository=OWNER/TABLE -f table-ref=main -f file=table.tsv \
  -f matcher=full_code
```

模板通过 `workflow_call` 复用录制环境，两处核心引用默认跟随 main；需要复现时将
工作流 uses 引用与 `flash-any-ref` 同时固定到本 source 已测试、包含所需功能的
已发布核心提交。`table-ref` 固定为 source 提交；不能只因旧 SHA 可下载就认定它支持新接口。
功能发布到相应远程 ref 后才能调用，本地修改不会改变 GitHub 上的工作流。
核心可复用工作流只需 contents:read，只上传 `table-demo` artifact。调用模板另有
contents:write 发布任务，验证成功后替换 `demos` prerelease 的 GIF、MP4、封面与报告，
并用认证下载核对附件。README 引用固定 Release 地址，不提交生成媒体；
旧提交的录制不会覆盖新 main。失败时保留本轮 artifact 和日志。
默认引用跟随 main 不代表核心推送会自动重录 source；核心更新后请在 source main
发起一次新运行。首次发布前可以用工作流入口作 README 占位；发布后所有语言 README
须切换到固定 GIF、MP4、验证报告附件地址，不链接被忽略的 demos/output。
可使用[中文](templates/README.zh-CN.md) / [English](templates/README.md) README 模板；
将[维护模板](templates/maintenance.md)放到码表仓库的 `docs/maintenance.md`。

Point `TABLE_FILE` at an unchanged repository, or supply the optional Lua template.
The recorder chooses a converted single-grapheme example automatically; set
the optional Lua fields described below to demonstrate familiar text. Dictionary,
converter and sample paths in Lua are relative to that Lua file. The same live candidate, label, cursor and
fixture assertions used by the built-in demo apply to third-party recordings.

Lua configurations may supply groups for shared names and sequences. The recorder
joins one printable spelling from each group to derive a query, while retaining
all group alternatives in the compiled dictionary without expanding their product.

The reusable workflow accepts repository/ref, dictionary path, format, columns, optional converter, matcher ID
and an optional Lua configuration path. Run it in a repository where you have Actions permissions,
or copy the tiny caller workflow into the table project to record on main pushes
or manual dispatches. Both core refs follow main by default; for reproduction,
pin them to the same published commit tested with the source's required features.
It uploads the table-demo artifact without writing to the caller repository.
The caller template adds a contents:write
job that replaces the dedicated demos prerelease assets after verification, then
checks authenticated downloads. README links use stable release URLs; generated
media is never committed. Outdated runs skip publication. Unpushed workflow changes cannot be called
from GitHub. Core pushes alone do not trigger the source workflow; start a new source
main run after core updates instead of only retrying an old failed job. Before the
first release, a workflow link can stand in for the README media. After publication,
every language README must use stable release GIF/MP4/report URLs, not ignored local
output links. The README templates focus on installation and use. Copy the maintenance template
to docs/maintenance.md for table updates and recording instructions.

## 画质与验证 / Quality and verification

原始 MP4 为 1920×1080、36 号字，单窗口采用 56px 渐变外边框、圆角和 Colorful 窗口栏。
背景与样式参考 vimoi.nvim 录制脚本；背景原样来自
[chezmoi-template.nvim](https://github.com/dpezto/chezmoi-template.nvim/blob/670ba83095ba6571f3125a5e5fd4118505a2c3c6/assets/tapes/style.tape)，
保留 [MIT 许可](common/backdrop.LICENSE)。

VHS 设置抓帧 30fps，本机 H.264 输出实测 25fps，以 ffprobe 报告为准。
GIF 从 MP4 两遍转换，保留 1920×1080、20fps，变化区域调色板与固定 Bayer 抖动可减少渐变闪烁。
输入速度为 120ms/键，语义分段后停留 0.8 秒，跳转后停留 1.8 秒。

同一次 TUI 回放记录中间查询候选、实际标签和最终落点，确认只有预期的远程删除、磁盘样例未改变且没有 Neovim 错误。
预期行列由原始样例中的目标位置确定，使用字节列；码表演示从真实匹配中选择落点。
每轮清空旧验证文件，异常写入本轮 JSON；验证成功才转换 GIF、检查 codec/尺寸/实际帧率并提取封面。
生成后仍须目视检查关键帧的字体、emoji、裁切和标签。

The recording produces `demo.mp4`, `demo.gif`, `demo.png`, `verification.json`,
and `media.json`; character-mode files use the `char` prefix, including
`char-verification.json` and `char-media.json`. `README.local.md` links locally
recorded clips without release URLs. Live TUI assertions check intermediate matches, the selected label,
all configured final queries and cursor positions, native f repeats, remote deletion/return,
per-prefix search cursors and viewports, exact expected buffer edits and the unchanged fixture on disk. Media checks verify
1920×1080 output and actual codecs/frame rates. The MP4 retains full color; the
20fps GIF uses a separate palette pass and stable Bayer dithering.
Expected byte positions come from the original fixture; table recordings select
a target from real matcher results.

## CI 与发布 / CI and publishing

[工作流](../.github/workflows/demos.yml) 在 `main` 的插件、录制素材、README 和相关测试变化时
自动运行，也可手动运行。工具与插件版本统一固定在 setup-demo composite action 中，字体包括 CJK 和 emoji fallback。
分别录制主 demo（f / s / r / search）、独立 f 和第三方 Rime 模板三段，保存 GIF、MP4、PNG 和 JSON artifact。验证成功后才更新独立 `demos` prerelease 的同名媒体及验证报告附件，
最后检查附件 URL。不提交生成媒体，不将 demo Release 标为 latest。
验证失败时也保存已生成的媒体和 JSON，便于检查实际查询、落点及预期位置；失败不发布。

README 引用 `releases/download/demos/demo.gif`、`demo.mp4` 和 `verification.json`；
f 模式附件为 `char.gif` 和 `char.mp4`。本地录制不更新远端附件，提交后 CI 才会发布新版演示。

The workflow records the continuous demo, verifies playback and media, saves artifacts,
and updates the `demos` prerelease on the default branch. README media URLs become
available after the updated workflow publishes them. Local files and release assets
are separate; no generated media enters Git history.
Failed runs also save available media and verification JSON for diagnosis; they do not publish.


## 独立 source / Optional sources

主 demo 需要 pinyin、japanese、korean、nerdfont 四个外部 source，latin 已内置；字符演示只需要
pinyin。将 FLASH_ANY_SOURCE_PATH 设置为这些插件目录的父目录，例如它们都位于家目录时：

```sh
FLASH_ANY_SOURCE_PATH="$HOME" sh demos/record.sh
```

目录名应为 flash-any-pinyin.nvim、flash-any-japanese.nvim、flash-any-korean.nvim、flash-any-nerdfont.nvim。
也可以使用 `.dev/source-packages` 或插件管理器的目录，录制入口不会加载个人 init.lua。
只检查配置及匹配、不启动浏览器时，从核心仓库根目录运行：

```sh
FLASH_ANY_SOURCE_PATH="$HOME" nvim --clean -l demos/prepare-table.lua demos/demo.lua demo
```

默认演示 CI 从当前仓库所有者（可用仓库变量 FLASH_ANY_SOURCE_OWNER 覆盖）的
flash-any-NAME.nvim main 分支安装 source，包括 japanese 和 korean；核心基础测试使用小型 fixture，
不依赖这些 source 仓库。普通外部 file 录制无需安装上述插件。

The main demo needs external pinyin, japanese, korean and nerdfont sources; latin is built
in. Character recordings need pinyin only. Set FLASH_ANY_SOURCE_PATH to the parent
of the source checkouts (for example HOME), without loading personal configuration.
The same preparation entry accepts demo.lua plus the demo output name; record.sh
also accepts `demo /path/config.lua` for a different examples configuration.
Recording CI installs published source dependencies, including japanese and korean, from the
repository owner; set FLASH_ANY_SOURCE_OWNER to use a different owner. Core tests use small fixtures;
ordinary file-based table recordings do not need the optional packages.


## Source 包模板 / Source package templates

[维护模板](templates/maintenance.md#package-layout--包结构)列出完整包结构。
复制 [source 工厂](templates/source.lua)、中英文 README、demo.lua 和工作流，替换
同一 SOURCE 名称即可按 source 名安装。语言类 source 将对应语言放到 README.md，
英文版放到 README.en.md；非单一语言包可保留英文主页。工作流仅传 config，字表路径与模式由 Lua 文件负责。

The [maintenance template](templates/maintenance.md#package-layout--包结构) lists the package layout.
Copy the factory, bilingual READMEs, Lua demo config and workflow; replace SOURCE
consistently. Language-specific packages use the supported language for README.md
and link to README.en.md for English; language-neutral packages may keep English as
the homepage. Installation uses the named source. The workflow passes config only,
so dictionary paths and matching modes stay in the Lua file.

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

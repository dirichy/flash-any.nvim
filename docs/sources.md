# 构建码表 / Building dictionaries

首次编写 source，先看[分步教程](writing-sources.zh-CN.md)；本文面向 source 作者，供查阅构建接口；安装配置见各 source 的 README。
Start with the [step-by-step guide](writing-sources.md) when writing your first
source; this is the author-facing build reference. For installation settings, use
the source package's README.

扩展只提供构建时数据，不再提供运行时 Lua matcher、Cursor 或按需
loader。运行时统一使用 C；setup 接收 `sources`，缺失二进制时自动调用构建器。

Extensions provide build-time data, not runtime Lua matchers, cursors
or lazy loaders. Setup accepts `sources` and builds missing packages; matching is C-only.

## 直接读取码表 / Dictionary files

直接提供现有码表路径及内置 matcher，不需要另导出 flash-any 专用格式：

```lua
require("flash-any").setup({
  sources = {
    { file = "/path/table.dict.yaml", matcher = "full_code" },
  },
})
```

`file`、`build.table()` 和录制工具共用 `build.read()`。`format` 默认 auto，
根据 Rime 文件头、Fcitx/IBus 数据段或首条数据的分隔符选择格式。无头数据默认
文本在前、编码在后；不根据汉字/ASCII 猜测列序。反向列序请明确配置：

```lua
{ file = "/path/table.tsv", format = "tsv", columns = { "code", "text", "weight" } }
```

| format | 输入 / Input |
| --- | --- |
| `auto` | 根据文件结构、首条数据选择 / Detect from structure or first row |
| `rime` | `.dict.yaml` 文件头 + Tab 数据；读取 columns、import_tables |
| `tsv` / `tab` | Tab 分列，默认 text、code；忽略其他列 |
| `space` | 空白分列，默认 text、code；忽略其他列 |
| `csv` | 逗号分列，支持双引号字段及双引号转义 |
| `fcitx` | `[数据]` 段中的编码、文本 |
| `ibus` | BEGIN_TABLE / END_TABLE 段中的编码、文本、词频 |

**每行一个编码，多编码重复写行。逗号是编码本身的一部分。**
最终写入二进制的编码必须是非空 ASCII，编码、选键后缀和组内拼写均不能含 NUL。

```text
中<TAB>zhong<TAB>100
中<TAB>chong<TAB>50
，<TAB>,<TAB>10
文<TAB>w,en<TAB>5
```

权重列不参与匹配，不要求排序。支持空行、UTF-8 BOM、CRLF；普通表和 Rime 跳过 `#` 注释。
Fcitx 数据段的 `#` / `;` 是普通编码，IBus 只跳过 `###` 注释。CSV 中的逗号码要按 CSV 规则加引号，例如 `"文","w,en"`。
普通空白表不能表达字段内部空白；编码首尾空白会去除，可用 append_space_below
构建时补空格。默认 UTF-8，其他编码可指定 `encoding = "gb18030"` 或 `"utf-16le"`，先解码再分行。
CSV 有标题行时配置 `header = true`。Fcitx 支持英文/中文数据段标记、引号及转义，
跳过 Prompt / ConstructPhrase 条目和需要自动造码的 Phrase 段。

外部文件、直接 `data` 和 Lua 码表都保留词组，无需维护单字副本。
同一文本起点的不同长度词条一起参与匹配，只在完整字素边界输出候选，不跨行。
Rime 支持普通 columns 和 import_tables
的块列表、内联列表；导入路径相对当前词典，循环或缺失导入报错。此处读取显式
码表条目，不执行 Rime schema、拼写代数、造词规则或预设词汇编码推导。

Point `file` at an existing dictionary. Direct sources, exports and recordings share
`build.read()`. Supported formats are auto, rime, tsv/tab, space, csv, fcitx and ibus.
Headerless files default to text/code order; use columns to specify code/text/weight.
Extra fields such as frequency are ignored. There is **one encoding per row**;
repeat text rows for multiple encodings. Commas in codes are literal; CSV codes
containing commas must be quoted. No sorting or Lua companion is required.
Compiled codes must be nonempty ASCII; codes, optional suffixes and group spellings must exclude NUL.

The reader handles BOM, CRLF and blank lines. Ordinary tables/Rime skip # comments;
Fcitx data preserves # and ; codes, while IBus skips only ### comments. Fcitx supports
English/Chinese section names, quoted values and escapes; prompt/construction rows
and the unencoded Phrase section are excluded. Use header=true for CSV headings.
UTF-8 is the default; encoding can select GB18030, UTF-16LE or another host encoding.
Decoding happens before line splitting. Leading/trailing field whitespace is trimmed;
use append_space_below for intentional padding. File sources and direct Lua/data
inputs preserve phrase entries; overlapping word lengths participate at each text start.
Matches start/end on complete grapheme boundaries and do not cross lines. Rime supports ordinary
block/inline columns and import_tables lists, with relative recursive imports and
cycle detection. It reads explicit entries, not schema spelling, rule-based encoding
or preset-vocabulary inference. Ambiguous auto-detection can be overridden with format.

## 内置匹配规则 / Built-in matcher IDs

| matcher | 规则 / Behavior |
| --- | --- |
| `full_code` | 完整编码 / Complete code |
| `initial` | 首字母或完整编码 / First byte or complete code |
| `prefix` | 编码的任意非空前缀 / Any nonempty code prefix |
| `letter` | 首码点查表，完整编码，遵循大小写选项 / Head codepoint, complete code, case options |

`letter` 按完整编码消费输入，遵循 Neovim 的 `ignorecase` / `smartcase`，并允许
用字素首码点的条目匹配整个字素，适合 extra latin 等字母转换。例如：

```lua
{ data = { e = "e", E = "E", ["é"] = "e", ["æ"] = "ae" }, matcher = "letter" }
```

此时 `é` 可按 `e` 匹配，`æ̈` 可按 `ae` 匹配。完整字素自己的条目仍参与匹配，
首码点查询只接受 `letter` 规则。码点到编码的映射由码表提供，不自动做 Unicode
大小写转换或规范化；大小写选项只控制 ASCII 编码比较。其他码表模式始终精确比较。

`letter` consumes complete codes, follows Neovim’s `ignorecase` / `smartcase`, and
allows a head-codepoint entry to consume an entire grapheme. The example matches
`é` with `e` and `æ̈` with `ae`. Exact whole-grapheme entries still participate;
head lookups accept only `letter` rules. Tables supply codepoint mappings; there is
no automatic Unicode case conversion or normalization. Case options affect ASCII
code comparison only. Other code-table modes always compare codes exactly.

默认 full_code。标识使用字符串，不暴露 C 内部数字，不接受 Lua matcher。

## 加权选键 / Ranked selection

```lua
{ file = "/path/to/table.dict.yaml", selection = { keys = { " ", ";" } } }
```

此能力适用于任意 file source。按数值权重降序，同权按原始顺序，最后按文本排序。
直接 file 必须指定 keys；各 source 可自行设置默认值。未分配键的候选保留裸码。
键可为不同的非空 ASCII
字符串，最长 127 字节。C 同时保留裸码与带后缀的分支，部分后缀产生 next。
剩余输入无人消费时自然失败；后续字面文本可以消费相同按键。

selection=false 关闭。要求 full_code，不能和 converter、append_space_below
或同一编码的 groups 引用结合。加权文件只支持 text、code、weight 三列（标点可省略 weight）；
同权直接保留文件行序，不接受第四列或 order 列；静态权重不写入二进制，也不会同步输入法动态词频。
工厂只需返回带权重的 file、format/columns 和默认 selection；读表、排序和后缀
分配由核心统一完成，工厂不生成 rank/selectors。未提供权重的条目仅保留裸码，不参与排序、也不占选键；
显式数值 0 仍参与排序。标点条目省略 weight 即可。

```lua
return function()
  return {
    file = assert(vim.api.nvim_get_runtime_file("lua/flash-any/tables/example.tsv", false)[1]),
    format = "tsv",
    columns = { "text", "code", "weight" },
    selection = { keys = { " ", ";" } },
  }
end
```

用户可覆盖 file、selection.keys 或设 selection=false；selection={} 保留工厂默认键。
改用 data/lua 时须关闭选键，因为这些数据没有文件权重。随插件分发的词典放在
lua/flash-any 下，让现有文件元数据缓存机制覆盖更新。

Any file source can assign optional ASCII suffix strings by weight and stable input
order. Direct file configurations must supply keys; source factories own defaults.
Weighted rows have exactly text/code/weight columns; unweighted rows may omit weight.
Fourth columns and order columns are rejected. Ties follow file row order.
All bare codes remain valid; unassigned
candidates get no suffix. Suffixes can be 1..127 ASCII bytes and must be distinct.
Requires full_code; converter, padding and group references on the same record are
not supported together. Ranking is static and never serialized. Factories declare
file, format/columns and default selection, as above. The core reads weights, ranks
candidates and assigns suffixes; factories do not construct ranks or selectors.
Rows without a weight keep bare codes and take no selector rank; explicit zero
weights still participate. Omit weights for punctuation. Users may override the
file or keys, disable selection, or use selection={} to retain default keys. Data/Lua
overrides require selection=false because they have no file weights. Ship files under
lua/flash-any so the existing metadata cache tracks package updates.

## 内部编码组 / Internal spelling groups

以下是 source 工厂提供给构建器的数据，不是安装使用者需要配置的选项。
Source factories provide this data to the builder; it is not an installation setting.
Factories may declare file/groups without loading character data. The core reads
the file, preserving standard codes as group references. Full and double pinyin use
this same path, with scheme conversion performed once per syllable.

```lua
{
  data = { ["か"] = "ka", ["が"] = "ga" },
  groups = { ka = { "ka", "ca" }, ga = { "ga", "gha" } },
  matcher = "initial",
}
```

source 工厂可返回 file/groups，无需自行读表；也可提供 data/groups。码表中
出现在 groups 的编码是组名，
未出现的编码按普通 ASCII 字符串匹配；每组可以有零个或多个拼写。
每个拼写先取最长公共前缀，再按 full_code、initial 或 prefix 产生匹配和 next，
所有分支均保留。拼写必须是 1..255 字节 ASCII，组名也必须是非空 ASCII。

组名只在所属 source 内有意义。构建时按排序、去重后的拼写内容共享，跨 source
同名但不同内容的组互不覆盖；同内容不同名字的组可以共用。append_space_below
只改变实际匹配的拼写，保留组名。不能为引用附加可选后缀。
这是通用编码集合，不要求是音节；如何产生拼写是各 source 的构建策略。

Factories and direct configurations may supply groups, mapping local code names to
ASCII spelling arrays. Names are local to each source; the builder interns groups by
normalized contents across sources. Unlisted codes stay inline. All alternatives
retain their full/initial/prefix matches and next bytes. Empty groups match nothing.
Spellings are 1..255 ASCII bytes; suffix metadata on a group reference is unsupported.
This is independent of pinyin or any particular writing system.

## 可选 converter / Optional converter

```lua
{ file = "/path/table.dict.yaml", converter = "/path/converter.lua", matcher = "full_code" }
```

converter 文件返回函数，接收一个字素合并去重后的全部编码，返回新的编码数组：

```lua
return function(codes)
  local result = {}
  for _, code in ipairs(codes) do
    result[#result + 1] = code:lower()
  end
  return result
end
```

返回 nil 或空数组略过该字素。converter 仅在构建时执行，转换结果必须为非空 ASCII
编码；输入编码可以是 Unicode。它不解析文件格式，也不转换运行时查询。

自动缓存按路径、大小和修改时间（含纳秒）跟踪根词典、Rime 导入、lua/tsv 和 converter；
修改后下次 setup 使用新快照。缓存命中时不执行 converter。lua/flash-any 下安装的
Lua/TSV 每进程检查一次，更新后需重启 Nvim。大小和修改时间均未变的编辑、命名空间外
自行加载的 Lua 依赖需手动重建。显式 binary 存在时直接加载，缺失时才构建。

The optional converter file returns a function accepting all deduplicated encodings
for one grapheme. Return an ASCII code array, or nil/empty array to omit that grapheme.
It runs only during compilation; raw input encodings may be Unicode. Automatic cache
keys include paths, sizes and nanosecond mtimes of dictionaries, recursive Rime
imports, Lua/TSV companions and converters. Cached startup never executes the converter.
Installed Lua/TSV files under lua/flash-any are checked once per process; restart
after updates. Edits preserving size and mtime, and arbitrary Lua dependencies outside
this namespace, require manual rebuilding. Explicit binary paths rebuild only when missing.

## 录制与 README / Recording and README

见 [录制说明](../demos/README.md#第三方码表--third-party-tables)、
[Lua 示例](../demos/templates/table-demo.lua)、
[工作流模板](../demos/templates/table-demo.yml)、
[中文 README 模板](../demos/templates/README.zh-CN.md) 和
[English README template](../demos/templates/README.md)。

可用 `config` Lua 文件 填写 `text_name`、单字素 `text`、`mixed_text` 和可选 `sample` 文件。
第一段补少量单字作为多个标签候选，第二段展示混输（允许多个标签）；
`comment` 和 `mixed_comment` 可编辑注释旁白；编码从码表推导，
缺省目标才随机抽样。调用模板自动替换 `demos` prerelease 的媒体与报告，
README 引用固定附件地址，生成媒体不提交。详见上述模板与录制说明。

Local recording works against an unchanged dictionary repository. An optional Lua file
selects format, column order and converter. Targets and codes are sampled automatically
from font-covered table entries when no target is supplied. An optional `config` Lua file
sets `text_name`, single-grapheme `text`, `mixed_text` and a `sample` file. Two narrated
scenes demonstrate multiple labels for one grapheme and mixed input (multiple labels
are allowed). Narration is editable through `comment` and `mixed_comment`. The reusable workflow
supports private callers and uploads verified media as an artifact. The caller template
automatically replaces media and reports in the dedicated demos prerelease. README
links use stable release URLs; generated media is never committed.

## 工厂 / Factory

核心内置完整 Unicode 字素的 literal 和可选的 latin；其他 source 分别安装，在 setup 前加载对应插件。

The core ships whole-grapheme Unicode literal and optional latin matching. Install other source plugins before setup.

在 runtimepath 中提供 `lua/flash-any/sources/japan.lua`：

```lua
return function(opts)
  return {
    data = { ["あ"] = { "a" }, ["い"] = { "i" } },
    matcher = "full_code",
    fallback = false,
  }
end
```

也可用 `codetable = "japan"` 代替 data，加载一份完整 `lua/flash-any/tables/japan.tsv`，或独立 Lua 表。表名与工厂名不必相同。需要转换时可在工厂调用
`require("flash-any.table").load(name, {convert = fn, extra = map})`；这些 Lua
函数仅在构建时执行。工厂接收名称配置对象，名称简写传空表。

A factory may return `codetable = "japan"` instead of data to load the corresponding
complete TSV or standalone Lua table under `flash-any/tables`. It can call `table.load(name, {convert = fn,
extra = map})` for build-time transformations. Custom factory options pass through;
a name-only specification supplies an empty options table. No callbacks run during
searches.

```lua
require("flash-any").setup({
  sources = { "pinyin", { name = "japan", matcher = "prefix" }, "unicode" },
})
```

## 数据与规则 / Data and rules

- 每个 key 须为一个完整 Unicode17 字素；`á`、`👩‍💻` 合法，`中国` 是两个字素，
  当前会报错。非法 UTF8 字节分别作为独立单元处理。不做 Unicode 归一化。
- 编码为非空 ASCII 字符串或数组。空数组表示已认识但没有匹配，可屏蔽 fallback。
- `matcher` 只能是 `full_code`、`initial`、`prefix`、`letter`。前者接受完整编码，initial
  同时接受首字母和完整编码，prefix 接受任意非空前缀。
- 普通源都贡献编码；fallback 仅在此前源未认识时贡献。码表内容决定覆盖范围。
- 相同 matcher 模式和编码自动去重，不保留 source 归属。

Each key is exactly one complete Unicode17 grapheme. Codes are nonempty ASCII strings
or arrays; an empty array recognizes without matching. Modes cover full codes,
initial/full codes, arbitrary nonempty code prefixes, and letter head-codepoint
matching with case options. Dictionary contents
define coverage. Ordinary sources contribute independently; fallbacks contribute only
for previously unknown graphemes. Duplicate mode/code pairs merge without source IDs.

每轮输入独立匹配，不以之前的候选集限制本轮搜索。literal 接受字素原文及其
前缀；未输完的字素仅预览，返回空 next，不推进到下一字素。完整字素后的 next
包含下一字素可输入的前缀。Unicode 标签可能与预览中未输入的后缀冲突。
编码前缀是否有效由所选 matcher 决定，而不是所有匹配规则的共同约定。

Queries match independently of previous candidate sets. Literal accepts grapheme
text and its prefixes. An unfinished glyph previews with empty next keys, without
advancing to the following glyph. Completed glyphs expose the next glyph's literal
prefixes. Unicode labels may conflict with untyped preview suffixes. Code-prefix
acceptance belongs to the chosen matcher, not a shared requirement for all rules.

## 覆盖与文件 / Overrides and files

`name` 调用工厂取得默认值；显式 `data` 或 `lua`/`tsv` 覆盖数据，显式 matcher、
fallback 覆盖默认规则，包括 `fallback = false`。`append_space_below` 在
主构建器应用，工厂不要重复补空格。独立 source 使用一份完整 TSV；用户显式提供
Lua 覆盖项或 extra 时仍保持优先。每次构建读取完整数据，不依赖先前搜索命中过什么字。

Named factories supply defaults. Explicit data/files and matcher/fallback
options override them. Padding is applied by the host, not repeated by factories.
Optional sources use a single complete TSV. Explicit Lua overrides/extras win. Compilation
reads the complete table, independently of previous searches.

```text
中<TAB>zhong
中<TAB>chong
国<TAB>guo
```

`:FlashAnyBuildTable` 可从 Rime/CSV/TSV/空白分隔词典生成 Lua/TSV。转换器保留
多字素条目并报告数量；file 和 Lua/data 接入均可直接编译词组。格式详见
[开发说明](development.md)；测试参考实现不属于插件 API。

The export command preserves multi-grapheme entries; file and Lua/data sources compile them directly.
See [development notes](development.md)
for binary layout. The frozen Lua oracle under tests is not a plugin API.

## 真实码表验证 / Real dictionary checks

固定上游版本、全量对照结果及复现命令见 [真实码表测试](dictionary-tests.md)。
Pinned upstream versions, full-data comparisons and reproduction commands are documented there.


独立 source 包仅保留完整 TSV，不再携带常用字 Lua 缓存。拼音、虎码、五笔的标点
直接存入各自 TSV；双拼转换原样保留非音节编码，虎码只给含字母的编码分配选键。
维护脚本统一为每个包的 scripts/build.py，仅输出完整 TSV。

Optional source packages ship one complete TSV and no common Lua subset. Chinese
punctuation is embedded in pinyin/Tiger/Wubi tables. Double-pinyin conversion leaves
non-syllable codes intact; Tiger ranks only codes containing ASCII letters. Each
package uses scripts/build.py to regenerate its complete TSV.

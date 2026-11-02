# Source 开发 / Source author guide

扩展插件提供 Lua source 工厂。Neovim 按 `runtimepath` 加载，主插件没有注册步骤。

An extension provides a Lua source factory on Neovim's `runtimepath`. No registration
step is needed.

```text
flash-any-japan.nvim/
└── lua/flash-any/
    ├── tables/
    │   ├── japan.lua
    │   └── japan.tsv
    └── sources/
        └── japan.lua
```

## 工厂 / Factory

```lua
-- lua/flash-any/sources/japan.lua
return function(opts)
  return {
    codetable = "japan",
    matcher = "full_code",
    fallback = false,
  }
end
```

`require("flash-any.sources." .. name)` 必须返回函数。函数接收配置对象，名称简写
传入空表；自定义选项原样传递，例如 `{ name = "japan", romanization = "hepburn" }`。
工厂返回的表提供码表声明与默认行为：

- `codetable`：`flash-any.tables` 下的码表名，由主插件加载 Lua 表和可选 TSV。
  与 `data` 互斥，码表名不必与 source 同名。
- `data`：已经规范化的“非空 UTF-8 文本 → 非空 ASCII 编码数组”。可带懒加载元表；
  不使用码表的 matcher 可省略此项。
- `matcher`：`full_code`、`initial`、`prefix` 或函数；省略为 `full_code`。
- `scope`：策略名、混合字符/区间表或函数；省略时不额外限制。
- `fallback`：布尔值；省略时不开启。

`require("flash-any.sources." .. name)` must return a function. It receives the
configuration table, or an empty table for a name-only specification. Custom
options pass through unchanged. The returned table supplies these defaults:

- `codetable`: a name under `flash-any.tables`; the host loads Lua data and optional
  TSV. Mutually exclusive with `data`; the source and table names may differ.
- `data`: normalized nonempty UTF-8 text → array of nonempty ASCII codes.
  Lazy metatables are supported. Table-free matchers may omit it.
- `matcher`: `full_code`, `initial`, `prefix`, or a matcher function; defaults to `full_code`.
- `scope`: a strategy name, mixed character/range table, or function; unrestricted when omitted.
- `fallback`: boolean; disabled when omitted.

声明的码表在调用工厂后加载，再应用 `append_space_below`；缓存生命周期与
直接返回 `data` 相同。需要 `convert`、`extra` 等转换时，工厂仍可用 `table.load`
构建 `data`。matcher 收到的运行时 source 统一使用 `source.data`，不解析声明字段。

Declared tables load after the factory returns, before space padding, with the same
cache lifetime as prepared data. Factories needing `convert` or `extra` can still
construct `data` with `table.load`. Runtime matchers always read `source.data`.

用户的 `data` 或 `lua`/`tsv` 可覆盖工厂数据；`matcher`、`scope`、`fallback` 显式值优先，
包括 `fallback = false`。指定 `name` 时仍会调用工厂取得默认行为。
`loader` 替换数据的未命中加载器；`append_space_below` 由主插件应用，工厂不要重复处理。
matcher 函数协议见 [开发记录](development.md#matcher-协议) 和 `:help flash-any-matchers`。

Explicit user data/files replace factory data; explicit matcher/scope/fallback values
win, including `fallback = false`. Named sources still invoke the factory for
its defaults. A user loader replaces the data's miss loader. The host applies
`append_space_below`; do not apply it again in the factory. See the matcher
contract in [development notes](development.md#matcher-协议) or `:help flash-any-matchers`.

## 字符范围 / Scope

scope 在初始化时解析为函数，匹配时在任何 matcher、码表读取或 loader 之前检查。
它只依赖当前 text，不接收 stream；不通过时等价于当前位置不认识，通过后仍须由
matcher 返回 true 才算认识。s 和 f/F/t/T 共用该行为，fallback 顺序保持一致。

Scopes compile during setup and run before matchers, table reads, or lazy loaders.
They depend only on text, not input. Exclusion means unknown; passing scope still
requires matcher recognition. Search and native character motions share dispatch
and fallback ordering.

```lua
scope = "chinese"
-- Or combine ranges with character overrides:
scope = {
  { "ぁ", "ヿ" },
  { 0x4E00, 0x9FFF },
  ["あ"] = false,
  ["🙂"] = true,
}
-- Or inspect context through the read-only cursor:
scope = function(text) return text:get(2) == "きゃ" end
```

| 策略 / Strategy | 范围 / Coverage |
| --- | --- |
| `all` | 不设预检限制，覆盖工厂默认 scope / No restriction; overrides factory scope |
| `ascii` | U+0000–U+007F |
| `chinese` | 内置拼音/形码覆盖的汉字范围及共用中文标点 / Bundled CJK ideograph ranges and Chinese punctuation |
| `unicode` | U+00A0–U+10FFFF |
| `private_use` | Unicode 三段私用区 / Unicode private-use areas |

表格中的数值键是区间条目，每项必须为两个端点；端点可为单个字符或数字码点，
闭区间，起点不可大于终点。字符串键必须是单个字符，值必须为布尔值。
先查哈希：true 直接接受，false 直接拒绝，只有没有该键时才查区间；没有匹配则拒绝。
空表拒绝全部。声明会复制，不在运行时读取调用方修改的表。

Numeric table keys contain two-bound inclusive ranges. Bounds may be single
characters or numeric codepoints, with start <= end. String keys are single
characters with boolean values. Hash entries win: true accepts and false rejects;
only absent keys fall through to ranges. No match rejects, as does an empty table.
Declarations are copied rather than consulted dynamically after setup.

数字端点只在初始化时转换成 UTF-8；字符端点原样使用。有效 UTF-8 字节顺序与码点
顺序一致，因此区间运行时比较字符串，不需要 char2nr。预置策略复用已编译函数；
自定义函数直接调用，参数为只读 Cursor，不能移动游标。scope 只限制尝试范围，
不能让 matcher 识别原本不支持的字符。

Numeric bounds convert to UTF-8 once; character bounds are used directly. Valid
UTF-8 byte order follows codepoint order, so range matching compares strings
without per-call char2nr conversion. Presets share compiled predicates; custom
functions run directly with a read-only Cursor. Do not move it. Scope only limits
where a matcher is attempted; it does not expand the matcher's capabilities.

未声明 scope 时沿用工厂默认值；用户设置 `"all"` 可清除该默认限制。
内置码表通过同一协议声明默认范围，codetable matcher 不再根据 source.name 推断。

Omitted scope inherits the factory default; explicit `"all"` removes it. Built-in
code-table sources use the same declarations. The code-table matcher never infers
scope from source.name.

## 文本读取 / Text access

matcher 签名为 `matcher(text, stream, source, emit)`。`text` 持有当前完整行和匹配起点；
`text` 和 `stream` 都是 `FlashAnyCursor`；后者保存完整输入，指向尚未消费的位置，`source` 是运行时 source。

The matcher receives `text, stream, source, emit`: two `Cursor` objects positioned at
the buffer candidate and unconsumed input, the runtime source, and a synchronous emitter.

```lua
matcher = function(text, stream, source, emit)
  if text:get(2) ~= "きゃ" then return false end
  local code = "kya"
  local input = stream:get()
  if #input < #code and code:sub(1, #input) == input then
    emit(code:sub(#input + 1, #input + 1), 2)
  elseif stream:get(#code) == code then
    emit(#code, 2)
  end
  return true
end
```

| 接口 / API | 约定 / Contract |
| --- | --- |
| `cursor:get()` | 读取当前位置到末尾，末尾返回空字符串 / Read all remaining content; empty string at the end |
| `cursor:get(n)` | 最多读取 n 个码点，不足返回全部剩余内容 / Read up to n codepoints; return the available suffix if shorter |
| `cursor.value` | 完整字符串，只读 / Complete string, read-only |
| `cursor.offset` | 当前 0-based 字节偏移，只读 / Current 0-based byte offset, read-only |
| `cursor:set_offset(offset)` | 扫描器专用，移动到字节边界 / Scanner only; move to a byte boundary |
| `cursor:shift(n?)` | 扫描器专用，默认前移 1 个码点；成功 true，否则 false 且不移动 / Scanner only; default 1 codepoint; false leaves cursor unchanged |

构造方法为 `require("flash-any.cursor").new(value)`。text 和 stream 使用同一个类，
没有输入专用的包装层或 ASCII 特判。显式 n 必须为正整数；get() 默认读取全部，
shift() 默认移动一个码点。仅足额读取的 get(n) 额外返回片段之后的字节偏移和最后码点的起始偏移；
不足时只返回字符串。空字符串表示没有剩余内容，shift(n) 不足时仍保持位置不变。
get() 直接截取并缓存后缀，只返回字符串，不解码码点。Unicode 码点不等于字素。

Construct with `require("flash-any.cursor").new(value)`. Text and stream use the
same class without input-specific wrappers or ASCII fast paths. Explicit counts
must be positive. get() reads all remaining content; shift() moves one codepoint.
Only complete get(n) reads additionally return byte offsets after the span and at its
last codepoint. Short reads return only the available string, including an empty string
at the end. shift(n) still leaves the position unchanged when too few codepoints remain.
get() slices and caches the suffix directly, returns only the string, and never decodes
codepoints. Codepoints are not graphemes.

每条缓存行只有一个 text 游标，输入改变时保留，行快照失效时替换。每份输入只有
一个 stream 游标，跨位置、行和窗口复用，输入改变时替换。get、shift 共用已解码
边界和字符串缓存；get() 与 get(n) 读取相同片段时也共享结果。source 对两个游标
**只允许调用 get**，不允许移动、修改或保存对当前 offset 的假设。

Each cached line owns one text cursor, retained across input changes until its
snapshot expires. Each input owns one stream cursor, shared across positions,
lines and windows and replaced when the input changes. Reads and moves share
boundaries and strings; get() and get(n) share results for identical spans. Sources
**may only call get** on either cursor; never move or mutate them or retain an
assumption about their current offsets.

输出协议：

- `emit(bytes, chars?)`：bytes 为消费的输入字节数，必须是 1..#stream:get() 的整数，且消费后必须位于输入码点边界。
- `emit(keys, chars?)`：输入前缀全部匹配，keys 是后续可用 ASCII 键的字符串，
  例如 `emit("au", 2)` 表示后续可用 a 或 u，显示范围覆盖 2 个文本码点。
  空字符串也表示匹配成功，只是没有后续键。

chars 为正整数，默认 1，决定文本跨度和消费后的后继位置。行内不足指定码点的
分支会忽略。扫描器合并重复分支和键；空 stream 只查询起始键，不可消费输入。
matcher 返回 true 表示认识当前位置；认识但不匹配时不 emit，仍返回 true。
返回 false 表示不认识。认识与否必须与 stream 无关，决定后续 fallback 是否运行。
不可保存 emit、异步输出或在 matcher 返回后调用；不支持返回旧结果表。
source 直接作为第三参传入，不再包装成 args.source。

Output protocol:

- `emit(bytes, chars?)`: consume an integer number of input bytes in 1..#stream:get(), ending at a codepoint boundary.
- `emit(keys, chars?)`: all remaining input matched; an ASCII string lists possible
  next keys. For example, `emit("au", 2)` allows a or u over 2 text codepoints.
  An empty string still means success, with no further keys.

chars is a positive integer, default 1, defining the text span and successor position.
Spans beyond the line are ignored. The scanner merges duplicate branches and keys.
Empty stream only queries starting keys; it cannot consume input. Return true for a
recognized position, even without emissions on a mismatch. Return false for unknown.
Recognition must be independent of stream and determines fallback eligibility.
Do not retain emit, emit asynchronously, or call it after returning. Legacy result
tables are unsupported. The third argument is the source directly, without args.source.

已消费的文本边界在追加输入时必须保持有效；失败分支不会追加重试。
字符模式仍只跳到匹配起点，不把多码点跨度扩成原生字符 motion 的范围。

Committed text boundaries must remain valid after input appends; failed branches
are not retried. Native character mode targets only the start position.

## 数据 / Data

```lua
-- lua/flash-any/tables/japan.lua
return { ["あ"] = { "a" } }
```

```text
あ<Tab>a
い<Tab>i
```

TSV 中 `<Tab>` 是真实制表符；行按 UTF-8 字节序排序，每条文本一行，多编码用逗号
分隔，支持 LF/CRLF。Lua 表可以只存常用字，TSV 保存完整字集；TSV 可省略。
纯算法 source 可以不提供 tables 目录。

Use actual tabs in TSV, sort rows by UTF-8 bytes, and separate multiple codes with
commas. LF/CRLF are supported. Lua can contain only common entries while TSV
contains the full set. TSV is optional; algorithmic sources need no tables directory.

多码点 Lua 文件返回 `codes`、`prefixes` 和 `max_chars`，单码点表仍直接返回编码映射：

```lua
-- lua/flash-any/tables/japan.lua（示意）
return {
  codes = { ["中"] = { "zhong" }, ["中国"] = { "country" } },
  prefixes = { ["中"] = true },
  max_chars = 2,
}
```

`codes` 只存编码。`prefixes` 列出所有可继续加长的文本键，值为 true；即使这个键
自身有编码，也应列入。叶子和不存在的前缀均省略，不存 false。纯 Lua 查询直接
读这两张 hash 表，不在运行时扫描或生成前缀，也不因编码数组存在而继续试探。
`max_chars` 是完整码表（包括 TSV）的最长文本码点数，与 ASCII 编码长度无关。
可省略时从 Lua 编码键和前缀长度计算；若 TSV 含更长条目，必须显式给出完整上限。
加载器复制编码、前缀和元数据，运行时 source.data 仍只包含编码映射。

Multi-codepoint Lua files return `{ codes, prefixes, max_chars }`. Compact maps
remain the single-codepoint format. `codes` contains only encodings; `prefixes`
contains every extendable text key with value true, including keys that also have
codes. Omit terminal prefixes rather than storing false. Lua-only lookup reads
the two hash tables directly, without building a prefix index or probing past
leaves. `max_chars` bounds Unicode text codepoints in the complete table,
including TSV; it is independent of ASCII code length. When omitted, it is
inferred from Lua code keys and prefix lengths, so providers must supply the full
bound if TSV includes longer entries. Loading copies the codes, prefixes and
metadata; runtime source.data remains an encoding map.

source 只需声明 `codetable = "japan"` 和编码匹配模式，无需 multi_code 或长度配置。
三种内置 matcher 根据码表元数据自动查询文本前缀，保留所有长短词分支；
`matcher = "prefix"` 仍表示 ASCII 编码前缀匹配，与文本前缀查询独立。
单码点简表默认 max_chars=1，继续直接查询一个码点。
builder 自动生成独立的 prefixes 和完整输入的 max_chars，不计入编码条目数；
可省略 TSV 路径，仅生成 Lua。
即使常用 Lua 子集为空，也保留完整 TSV 的最大长度。公共 normalize 同样接受此结构，
可用于用户的 `data = { codes = ..., prefixes = ..., max_chars = ... }`。

Sources only declare the table name and encoding match mode; no multi_code or
length options are required. Built-in matchers infer word support from table
metadata and retain all matching word lengths. `matcher = "prefix"` still selects
ASCII code-prefix matching independently of text-prefix lookup. Compact maps
default to max_chars=1 and retain direct single-codepoint reads. The builder optionally emits TSV; Lua-only output retains
independent prefixes and the full input's maximum length, including with an empty
common subset; prefix entries do not count as code entries. normalize also accepts
this structure, including inline user `data` configuration.

自定义 loader 的前缀查询可返回 `codes, continuation`：数字表示更长文本键的 TSV
继续位置，true 表示无文件位置的可继续状态，false（或省略）表示不能加长。
无编码的中间前缀也可继续。参数为 `(key, offset?, prefix_lookup?)`，第三参为 true
时需要提供前缀信息；普通单码点读取只传 key。`table.lookup` 使用同样的返回协议，
文件查询缓存未命中和终止结果。存在 TSV 时，约定它完整包含 Lua 编码条目，
其前缀查询结果是唯一依据，不和 Lua 前缀集合合并。码表应视为只读，替换时创建新表。

Prefix-aware custom loaders return `codes, continuation`: a number is a TSV
continuation position, true continues without a file offset, and false or an
omitted continuation stops extension. Prefixes without codes may continue.
Loader arguments are `key, offset?, prefix_lookup?`; the third argument is true
for prefix-aware reads. Ordinary single-codepoint reads pass only key.
`table.lookup` follows the same protocol and caches negative and terminal file
queries. TSV is assumed to contain every Lua code entry; its prefix state is
authoritative and never merged with the Lua prefix set. Treat maps as immutable
and create a new map when replacing data.

公共工具在 `require("flash-any.table")`：

| API | 用途 / Purpose |
| --- | --- |
| `load(name, opts?)` | 加载 `tables/<name>.lua` 与可选 TSV / Load runtime Lua data and optional TSV |
| `from_files(lua, tsv?)` | 加载指定路径 / Load explicit file paths |
| `normalize(map)` | 复制、校验编码映射或多码点结构 / Copy and validate compact maps or multi-codepoint descriptors |
| `max_chars(data)` | 读取完整码表的文本长度上限 / Read the full table’s text-codepoint bound |
| `lookup(data, key, offset?)` | 查询编码和继续位置，false 表示剪枝 / Codes and continuation offset, false prunes |
| `lazy(data, loader)` | 缓存命中与未命中 / Cache both hits and misses |

`load` 的可选 `convert(codes)` 转换常用表和 TSV 的编码，返回编码数组或 nil。
`extra` 是转换后加入的额外字符映射，覆盖常用表中的同名字符；适合标点等不应参与
转换的数据。`load` 不缓存整个表，每次创建私有副本，不能再用它选择双拼方案；
方案属于 `source.load("pinyin", opts)`。

`load` accepts `convert(codes)`, returning converted codes or nil, for both common
and TSV entries. Its `extra` map merges after conversion and overrides common
entries, useful for punctuation that should bypass conversion. Every call creates
private data. Pinyin scheme selection belongs to `source.load("pinyin", opts)`,
not `table.load`.

## 生命周期 / Lifetime

`require("flash-any.source").load(name)` 缓存无选项的默认 source；传入配置对象时
每次调用工厂。工厂应返回独立状态，不修改 `require` 共享的原始数据。
`table.load`、`normalize`、`from_files` 提供私有数据边界；`lazy` 统一持有查询结果缓存，
TSV loader 持有文件句柄。setup 构建的 sources 在 jump/remote 间复用，重新 setup
时替换；无选项的默认 source 仍可复用模块级缓存。

`source.load(name)` caches the default source; calls with an options table invoke
the factory each time. Factories should return independent state without mutating
shared module data. Table helpers establish private data ownership. `lazy` owns
lookup results, while the TSV loader owns its file handle. Setup-built sources
are reused across jump/remote calls and replaced by setup; option-free defaults
can still share the module cache.

`source.available()` 只发现 `sources/*.lua` 名称，不执行工厂或加载码表，供健康检查
使用。插件必须在 setup 前进入 runtimepath。名称唯一性由 source 维护者负责。

`source.available()` discovers `sources/*.lua` names without executing factories
or loading data, for health checks. Load the extension before setup. Source
maintainers are responsible for unique names.

## 迁移 / Migration

内置数据从 `flash-any.table.<name>` 迁到 `flash-any.tables.<name>`。
原先 `table.load(name, source_opts)` 的 source 加载用途改为
`require("flash-any.source").load(name, source_opts)`，返回 source 定义，码表位于 `.data`。
`table.available()` 改为 `source.available()`；它现在也列出 literal 与第三方 source。
自定义 matcher 的首参由 char 字符串改为文本对象：原先使用 char 的位置改为 text:get(1)。
普通用户的 setup/jump 配置方式不变。

Bundled data modules move from `flash-any.table.<name>` to `flash-any.tables.<name>`.
Replace source-loading uses of `table.load(name, source_opts)` with
`require("flash-any.source").load(name, source_opts)` and read `.data` for the table.
`table.available()` becomes `source.available()`, including literal and extensions.
Custom matcher callbacks now receive a text object instead of a char string;
replace char reads with text:get(1). Existing setup/jump configurations keep their syntax.

Text 类和模块统一改名为 Cursor / flash-any.cursor，完整字符串字段由 line 改为 value。
stream 不再是字符串，而是同类游标；旧字符串操作可用 stream:get() 取得剩余字符串。
get() 默认返回全部剩余内容；旧的默认单码点调用改为 get(1)。

The Text class/module is renamed Cursor / flash-any.cursor, with value replacing line.
Stream is now the same cursor type; use stream:get() for remaining input strings.
get() now reads all remaining content; replace implicit single-codepoint reads with get(1).

# 开发记录

## 模块布局

- `flash-any.match`（`lua/flash-any/match/init.lua`）：搜索与单字扫描器、增量候选、缓存和搜索标签。
- `flash-any.match.codetable`（`lua/flash-any/match/codetable.lua`）：码表匹配及其三个模式。
- `flash-any.sources.literal`（`lua/flash-any/sources/literal.lua`）：配置层默认前置的 ASCII 字面 source，遵守统一协议。

码表的三个模式共用查询、前缀比较、next 生成、完整编码消费和去重。额外消费边界
显式区分：full_code 只接受完整编码，initial 还接受首码点，prefix 还接受任意非空
码点前缀；这些边界规则全部留在 codetable，扫描器不参与判断。
码表编码约定为 ASCII，因此码点边界就是字节边界：initial 可消费 1 字节，
prefix 直接遍历已匹配前缀的字节位置，codetable 无需调用 UTF-8 函数。
该约定也适用于自定义码表；buffer 字符仍使用 UTF-8；内置 literal source 只认识 ASCII。

The scanner and incremental cache live in `flash-any.match`. Code-table modes
live in `flash-any.match.codetable` and share code lookup, prefix comparison, next-key
generation, full-code consumption and deduplication. Their additional consumption
boundaries are explicit: first byte for initial, every matched byte for prefix.
All code-table encodings (including custom tables) are ASCII, so codepoint and
byte boundaries coincide; code-table matching needs no UTF-8 calls. Buffer text
uses UTF-8; the built-in literal source recognizes ASCII only.
`flash-any.sources.literal` is a regular ASCII source prepended by configuration. Code-table
modes never fall back to the character itself.

## Flash 字符模式

`flash-any.char(win, state, range)` 接入 Flash 的 `modes.char.matcher`，共用 setup
构建的 sources。顶层 `match.get` 负责 s 的跨字符推进、next 和标签；`match.char`
只用一键查询每个字符，不建立 continuation、不查询下一字符，也不分配标签。
两者共用底层 match_text 的 source 顺序、fallback 与 matcher 协议。s 缓存范围内的
文本和增量分支；f 按需缓存访问过的行，各扫描器维护自己的缓存生命周期。

`flash-any.char` 适配器在 `lua/flash-any/char.lua`。get() 只查询 Flash 请求的可见
行范围；find() 从起点沿方向逐行查询，计数满足即停止。匹配结果按行缓存，buffer、
changedtick、pattern 或 sources 变化时由单字扫描器统一失效；无匹配的空列表也缓存。
未访问的行不读取、不查码表。无目标时仍可能查到文件末尾，wrap 时也可能遍历全文。
t/T 按 UTF-8 字符边界平移，不跨行；其余按键、计数、操作符及标签交给 Flash。

HACK：Flash 的公开 matcher 回调经 Matcher.from() 包装后，find() 只能查询上次
生成的列表。适配器在回调首次执行时，通过 State:get_matcher(win) 取得当前实例，
替换其 find()，保留外层 get/filter/labels。依赖 flash.state 的实例创建顺序，以及
flash.search.matcher 的 get/find 协议；升级 Flash 后应跑 tests/char.lua 验证。
不修改全局方法。

`flash-any.char` adapts Flash's visible-range get() and directional find(). The
latter scans lines only until the requested count is found, including offscreen
targets. Single-character scanning owns per-line caches and their invalidation.
No-match searches and wrapping can still visit the whole buffer.

HACK: the callback replaces only the current window matcher's find() method.
This depends on State:get_matcher(), instance initialization order, and the
get/find protocol in flash.search.matcher. Run the real Flash integration tests
when upgrading Flash. Native key handling, filtering, and labeling remain in place.

## Matcher 协议

匹配函数为 `known = matcher(text, stream, source, emit)`。运行时 source 直接传入，
只保留 data、matcher、max_chars、name、scope、fallback，配置选项在初始化时消费。
matcher 返回 true 表示认识当前位置，false 表示不认识；认识与否不随 stream 改变。
认识但输入不匹配时不输出，仍返回 true。fallback 仅在前面都返回 false 时运行。

分支直接输出，不创建结果数组、分支表或 source 参数包装：

- `emit(bytes, chars?)` 消费 bytes 个输入字节，越过 chars 个文本码点。
- `emit(keys, chars?)` 输入前缀全部匹配，字符串 keys 给出可继续的 ASCII 键。
  空串仍是成功。chars 默认 1，消费字节数必须为 1..#stream:get() 的整数，末尾必须是输入码点边界。

空 stream 仅用于起始键查询，不可消费输入。source 同步调用 emit，不保存回调，
不在返回后调用。每次行扫描只创建一个 emitter，捕获当前 col、输入 offset、
stream、起点与候选状态；跨位置和 source 复用。字符模式一次查询共用一个 emitter，
只记录当前位置是否成功。动态协议由 source 实现及测试保证，不增加热路径验证。

内置 literal 和码表 matcher 不创建临时结果表。码表直接输出完整编码及后续键；
prefix 模式的消费区间都从 1 开始，只需最大公共前缀长度即可输出区间并集。
重复输出允许存在，由扫描器的请求和终点索引合并，不要求 source 创建去重集合。
范围预检在统一 match_text 分发中执行，所有 source 均可声明 scope；
未通过时不调用 matcher，不触发数据读取，也不标记 known。通过不代表认识，
仍以 matcher 的布尔返回值决定是否阻止 fallback。配置层用 scope.resolve 将
策略、混合表或函数归一为 predicate；源名称不参与匹配规则。

Matchers synchronously emit numeric input consumption or string next keys, with an
optional codepoint span. Return true for recognized positions and false for unknown;
fallback depends on recognition, independently of the input. Empty-string emissions
are successful branches with no next keys. Do not retain or defer the emitter.

A line scan creates one emitter and reuses it across positions, offsets and sources.
Character searches share one emitter per call. No temporary result arrays, branch
records or source argument wrappers are created. Prefix consumption intervals share
a lower bound of 1, so their union needs only the maximum matching prefix length.
Duplicate emissions are allowed and merged by scanner indexes. Matchers own the
dynamic protocol; the scanner does not validate it in the hot path.

扫描请求记录文本字节列、输入 offset 和最早起点，相同下一位置与输入 offset 的
请求合并。成功分支按末尾码点字节列合并显示范围，起点取最小值，next 取并集。
多码点分支可提前产生远处终点，等待表在后继位置到达时查询其起始键。

数字输出仅累计输入字节 offset；扫描器将同一个 stream 游标移动到该位置。
stream 的字符串和码点缓存由 Cursor 自身持有，跨起点、行和窗口共用，输入变化时替换。
字符串输出在原匹配位置保存待续请求；恰好消费完输入则在文本跨度之后保存请求。
追加输入仅恢复这些请求，不重试失败位置或重新消费已提交文本；不同 offset 的
进度不能被显示范围的最早起点覆盖。结果按起点、终点排序，标签不依赖输出顺序。

buffer、changedtick 或搜索行范围变化时替换行快照；删除、替换输入或 source
变化时重扫缓存文本。追加字节修复旧输入末尾截断码点时也重扫。相同输入复用
匹配结果但重算标签。扫描器分配标签，Flash 外层使用空 labeler。

## Source scope

`flash-any.scope` 编译 scope 声明。预置函数共享，用户函数原样使用；混合表拆为
字符布尔哈希与 UTF-8 字符串区间。声明值按 Lua 真假规范化，因此可直接传单码点
extra 编码表。字符键先查询，显式 false 不能回落到区间。
数值端点只在初始化时 nr2char，运行时利用 UTF-8 有序性比较字符串，不调用 char2nr。
编译时复制声明，调用方不维护过滤缓存。中文范围复用 tables/punctuation.lua 的键，
码表加载仍复用同一标点数据。scope = "all" 编译为 nil，运行层没有额外 predicate。

Scope declarations compile into predicates before scanning. Mixed tables split
into a character boolean hash and UTF-8 string ranges. Hash declaration values
use Lua truthiness, allowing single-codepoint extra encoding maps directly. Explicit hash entries win,
including false. Numeric bounds convert once via nr2char; the hot path compares
strings without char2nr. Presets share functions, user functions pass through, and
compiled tables own their copies. All source kinds share the same dispatch check;
no per-source matcher wrapper or name-based scope registry is used.

## 行文本缓存

`flash-any.cursor` 的每个对象持有完整字符串 value、当前字节 offset、按需扩展的码点边界数组、
字节边界到数组下标的索引，以及“长度 → 起始码点下标 → 字符串”的读取缓存。
按长度分桶，常见的 get(1) 在所有位置共用一个子表，不再为每个位置建表。
每个边界最多解码一次；get 的长度增长只扩展缺失边界，移动到后续位置复用同一数组。
`get(n)` 返回字符串、片段之后的字节列、最后一个码点的起始字节列；不足 n 个
码点时返回剩余全部内容，不返回边界；shift(n) 仍要求足额才移动。get() 直接 sub 并按当前位置缓存后缀，不解码
码点、只返回字符串，末尾返回空串；缓存中的长度 0 专门表示整个后缀。
shift() 仍默认移动 1 个码点。shift(n) 用 get(n) 的结果移动，set_offset 校验字节边界。
text 与 stream 完全复用 Cursor，不做 ASCII 特判。每个 pattern 在 state 上持有一个
stream 游标，输入变化时替换；后缀缓存并入 Cursor。source 对两者只允许 get；移动由扫描器完成，不保存恢复 source 位置，不创建只读包装。

搜索窗口行快照保留对象，输入追加、删除、替换和 sources 变化只重新匹配。
buffer、changedtick 或搜索行范围变化时替换快照。字符扫描器按需读取并保存行对象，
pattern/sources 改变只清理候选列表；buffer 或 changedtick 改变才替换行对象。
两种扫描器分别拥有快照，不额外建立全局缓存。

Both buffer text and input streams use FlashAnyCursor. Each cached line owns one
text cursor; each state/pattern owns one shared input cursor. get() reads all remaining
content with a direct cached substring and no codepoint decoding; it returns only
the string. get(n) reads up to n codepoints, returning the available suffix when short.
Only complete reads include boundary metadata; shifts still require the full count. shift()
defaults to one codepoint.
There is no ASCII fast path. Each cached line owns one mutable text object. All positions share lazily decoded
codepoint boundaries, reverse byte indexes, and requested strings. String caches
are grouped by requested length, then start index, so many positions reading a few
lengths share the same bucket tables; length 0 holds whole suffixes. Repeated reads
reuse strings; longer reads extend only missing boundaries. Sources may only call
get; the scanner owns shift/set_offset. There are no per-source wrappers or cursor
save/restore steps. Text snapshots outlive pattern changes and are replaced when
their owning buffer snapshot becomes invalid. Character searches retain loaded
line objects across pattern changes while discarding only their match lists.

## 字面匹配规则

literal 由配置层默认加在所有 source 前面，不属于扫描器特例。它只认识 ASCII buffer 字符，空 stream
emit 字符自身作为起始键，首字节匹配则 emit(1)。ASCII 始终返回 true，
输入未匹配时不输出；非 ASCII 一律返回 false。所有 source 使用同一顺序和 fallback 规则，普通 source 在前项成功后
仍参与，fallback source 仅在前项均不认识字符时参与。配置的空 source 列表仍包含默认 literal；运行层只处理构建好的列表。
位置统一使用 Neovim 的 0-based byte column；相同终点的结果合并为最早起点。

## 第一版范围

第一版按 Unicode codepoint 处理文本。完整 grapheme cluster（特别是 ZWJ
emoji 和组合音标）记录在仓库根目录的 `TODO.md`，暂不作为发布阻塞项。

## UTF-8 行扫描

`utf8.iter_char(str, offset?)` 返回 Lua 通用 for 三元组：固定的迭代函数、原字符串、
初始字节 offset（默认 0）。迭代函数签名为 `iter(str, offset) -> next_offset, char`，
无闭包、无预建位置表。next_offset 指向当前字符结束之后，当前字符的起始列为
`next_offset - #char`。从指定 offset 原样开始解析，不向前对齐字符边界。

扫描器把新起点和上个字符余下的输入放进同一请求队列，每个 buffer 字符单趟处理。
完成匹配时先记录当前范围，再由下一轮字符补充起始 next，不前瞻解码。追加输入可
直接从最早待续请求的字节列开始迭代，处理完所有待续请求和 next 查询后停止。
匹配只保留起止字节列，不再引用整行字符数组。

首字节长度和续字节检查遵循 Neovim 的 utf8len_tab / utf_ptr2len_len 规则，包括
历史的 5/6 字节序列；错误续字节只前进一字节，行尾截断序列保留剩余字节。这是
原生字节结构处理，不是严格的 Unicode 标量值校验，也不合并 grapheme cluster。

`utf8.iter_char(str, offset?)` returns `(iter, str, offset or 0)` without closures
or position arrays. `iter(str, offset)` yields the following byte offset and the
current character. Its starting column is `next_offset - #char`. The scanner
decodes each visited character once, combines new starts and remaining streams,
and retains only byte positions for matches and incremental continuation.

## 码表所有权

中文 source 的标点键位统一保存在 `tables/punctuation.lua`。`table.load` 在拼音
转换完成后加入标点，通用 chinese scope 也读取同一份映射，避免标点
触发 TSV 查询或参与双拼、模糊音转换。`append_space_below` 仍统一作用于所有编码。

Chinese sources share `tables/punctuation.lua`. File loading adds punctuation
after pinyin conversion; the chinese scope uses the same map. Punctuation
avoids TSV lookups and pinyin transformations. Space padding applies to all codes.

`require("flash-any.tsv").loader(path, opts)` 创建按字符查询的加载函数，可配置
separator 和 decode。它打开并持有文件句柄，返回编码数组或 nil，不缓存查询结果；
命中与未命中缓存由 `table.lazy` 统一管理。loader 按需缓存二分树前 6 层的
比较键、行起点和下一行位置；额外保留深层精确命中节点，与文件句柄同生命周期。
剩余区间不超过 64 字节时，从已对齐的下界顺序扫描，避免按字节二分反复跳到同一行。
模块级 `read_at(file, position, aligned)`
接收文件句柄，不为每个 loader 额外创建辅助闭包。

`flash-any.tsv.loader(path, opts)` replaces the former `open` factory. It returns
a character lookup function that owns an open file handle, not the handle itself.
The loader does not cache results; `table.lazy` owns positive and negative caches.
It lazily caches comparison keys, row starts and next-row offsets for the first
six binary-search levels and deeper exact-hit nodes, with the same lifetime as
its file handle. Remaining intervals of at most 64 bytes are scanned from the aligned
lower bound, avoiding repeated reads of the same row near the end of a search.
The shared `read_at` helper takes the file explicitly instead of capturing it.

`require` 返回的原始码表、方案规则以及 `load(name)` 的默认缓存均可能共享。
`normalize` 复制输入 map 和编码数组，建立私有边界；`append_space` 生成独立
编码数组与派生缓存，防止追加的空格污染调用方或默认方案。

全拼模糊音与双拼转换共用 `sources/pinyin.lua`：全拼直接拼接展开的声母、韵母，
双拼按方案转换；不启用模糊音的全拼直接加载原表。

拼音转换在文件 source 的私有副本上原地替换编码，不再保留一整份原始拼音副本
与另一份转换 map。常用字和 TSV 解码共用转换函数，懒加载缓存只存最终编码。
方案规则只读，模糊音分组保存在该次转换的闭包中，不深拷贝规则或向其写入配置。

Raw module tables and default caches may be shared. Normalize at the ownership
boundary, transform the private source map in place, and cache converted TSV
entries directly. Scheme rules remain read-only; space-appending results stay isolated
from their input tables.

## 双拼规则

双拼 scheme 只保存声母和韵母规则，不枚举完整音节：

```lua
{
  syllables = { ["a"] = { "aa", "oa" } }, -- 完整音节特例
  initials = { ["zh"] = { "v" } },
  finals = { ["ong"] = { "s" } },
}
```

运行时先查 `syllables[syllable]`；未命中时才从统一拼音表得到音节，拆分最长声母，分别查表并拼接。多个候选编码会做笛卡尔组合。

Full-pinyin fuzzy expansion and double-pinyin conversion share `sources/pinyin.lua`.
Full pinyin joins expanded initials and finals directly; double-pinyin schemes
map them to keys. Full pinyin without fuzzy options loads the original table.

source 统一通过 `source.load(name, opts)` 加载；工厂在 `sources/<name>.lua`，
数据在 `tables/`。工厂可返回 `codetable = "name"`，由 source.load 统一加载为 data
并应用补空格策略；与预先构建的 data 互斥。需要转换时仍可直接提供 data。
无 opts 时按名称缓存 source，有 opts 时调用工厂构建独立实例。
`table.load(name, opts)` 只加载数据，每次创建独立的常用字副本与 TSV 懒加载缓存；
`convert` 同时用于常用字和 TSV，`extra` 在转换后合入。
扩展协议见 [source 开发说明](sources.md)。

Sources load through `source.load(name, opts)` with factories in `sources/` and
data in `tables/`. A factory may declare `codetable = "name"`; source.load resolves
it to data before applying padding. Prepared data remains available for custom
transformations; the two fields are mutually exclusive. Only option-free source
instances are cached by name.
`table.load` creates private data and lazy caches on every call. Its `convert`
option applies to both common and TSV entries; `extra` merges after conversion.
See the [source author guide](sources.md).

## UTF-8 调用边界

buffer 行文本和自定义 matcher 输入可以是 UTF-8；内置 literal source、码表编码、拼音声母
韵母和保留给 Flash 的 next 键是 ASCII。UTF-8 文本的字节前缀比较、CSV/TSV 的
ASCII 分隔符识别无需解码；字符遍历使用 iter_char；builder 用 iter_offset 遍历去重后的键，统计多码点条目和完整码表的最大词长，
不为每个编码新建 Cursor。
字符范围在初始化时规范为 UTF-8 区间，运行时直接比较字符串。utf8.len/sub/byteidx 保留原生随机访问语义，
同时作为迭代器测试的独立对照，不用于生产代码的逐字符遍历。

Buffer text and custom matcher input may be UTF-8; the built-in literal source,
code-table encodings, pinyin components, and reserved next keys use ASCII. Byte-prefix
comparisons and ASCII CSV/TSV delimiter parsing preserve UTF-8 without decoding.
Use iter_char for traversal. The builder traverses distinct keys with iter_offset to count multi-codepoint
entries and the full table’s maximum word length, without creating a Cursor per code.
Range checks compare precompiled UTF-8 strings. Native len/sub/byteidx helpers retain their
random-access behavior and serve as independent iterator test references.

旧 `table.from_flypy` 及其方括号字符列表解析已移除；所有双拼均由统一拼音表转换。
The unused `table.from_flypy` entry point and bracket-list parser have been
removed; all double-pinyin schemes derive from the shared pinyin table.

## 拼音 source 与编码方案

内置 source 与第三方 source 共用工厂协议；主插件不维护名称注册表。
拼音工厂读取 opts.scheme/fuzzy，提供全拼 initial、双拼 full_code 的默认值；
Unicode 工厂提供 prefix 与 fallback，Nerd Font 工厂提供 prefix。
配置层保留同一次配置只能选择一个 pinyin source 的约束，显式 matcher 优先。

Built-in and third-party sources use the same factory protocol, without a name
registry. The pinyin factory consumes scheme/fuzzy options and supplies initial
or full_code defaults. Unicode supplies prefix/fallback defaults; Nerd Font
supplies prefix. Configuration still rejects duplicate pinyin entries, and
explicit matcher options take precedence.

## 模糊音索引

每次加载拼音 source 时，将 initials/finals 分组各自构建为“声母或韵母 → 候选数组”
的哈希表。重叠分组保留第一次出现的分组；未分组的已知声母、韵母各建一个自身候选
数组。常用字转换和 TSV 懒加载共享这两个只读索引，不在每个读音上扫描分组或分配
自身候选数组。声母、韵母仍用 ASCII 字符串表示，无需另行维护整数枚举。

Each pinyin load builds reverse hash indexes from initials/finals to candidate
arrays. The first group wins when groups overlap; ungrouped known components
get singleton candidates once per load. Common and lazy conversions share the
read-only indexes. Components remain ASCII strings, without integer enums.

`FlashAnySource` describes the runtime object: data, matcher, max_chars, name,
scope and fallback. Initialization consumes scheme/fuzzy options. fallback=true makes a
source run only when every earlier configured source returned false.

配置层的 matcher 可为模式名或函数；初始化后统一为 FlashAnyMatcher 函数，
扫描器不再解析字符串模式名。
Matcher configuration accepts a mode name or function. Initialization resolves
names to FlashAnyMatcher functions; the scanner only calls functions.

## 配置与运行时边界

FlashAnySourceConfig/FlashAnySourceSpec 定义在插件入口，只描述用户配置；
FlashAnySource 定义在 match/init.lua，只描述编译后的运行时对象。setup 时构建
默认配置并保存，jump 的完整独立配置则在启动 Flash 前构建。配置校验和模式名解析
不进入扫描路径。默认 source 在多次跳转间共享码表及其懒加载缓存，setup 替换配置
时自然替换所属对象。matcher 的动态输出是受信任的协议，不通过热路径断言
验证；合法消费范围、同步 emit 和前缀约定由实现及测试保证。

Configuration types live at the plugin entry point; runtime source types live
in match/init.lua. Setup builds the complete defaults once, while complete
per-jump configurations are built before Flash starts. The scanner neither parses configuration nor
validates dynamic matcher branches. Implementations and tests own the emission
contract. Repeated jumps reuse source data and lazy caches; setup replaces their
owner when configuration changes.

配置选择以整份 opts 为单位：build_opts 要求 sources 并创建 Flash 参数，setup 保存
其构建结果；jump 仅选择传入配置的构建结果或已保存默认值，不逐字段兜底。labels
由 Flash 自身处理，顶层 table 简写不再支持。
Configuration selection is whole-object: build_opts requires sources and produces
Flash options; setup stores the result. Jump selects a complete explicit config
or saved defaults, with no field inheritance or plugin labels fallback. The
legacy top-level table shorthand is removed.

Unicode 名称匹配只在显式配置 unicode source 时启用，不自动追加 source。
Unicode name matching requires an explicit unicode source; none is appended
automatically. Configuration prepends the literal source before user sources; an empty
configured source list therefore still matches ASCII.

## Remote 操作

`remote(opts)` 与 `jump(opts)` 使用相同的配置选择、扫描器和标签规则。nil 复用 setup
已构建的 sources 及缓存，显式 opts 构建独立配置；只将最终配置传给 Flash 的公开
remote() API，不维护另一套远程操作状态或光标恢复机制。remote 默认不创建按键映射。

`remote(opts)` shares configuration selection and matching with jump(). It passes
the compiled options to Flash's public remote() API, which owns operator execution
and restoration. No keymap is installed automatically.

## 发布检查

用户安装入口为 dirichy/flash-any.nvim；Neovim 最低版本为 0.11（UTF-8 原生辅助
函数使用 0.11 新增签名）。跳转直接返回 Flash state。sources 必须为列表，配置
校验覆盖静态码表、模糊音分组及策略参数；动态 matcher/loader 仍由实现者保证协议。
TSV 二分时上界使用 middle，避免跳到下一行后的 position 不变而遗漏中间字符。
TSV 行支持 LF/CRLF，码表生成支持空常用字子集，不通过正则解析 Lua 字表。
Builder 的 TSV/tab/auto-Tab 解析标记值列为编码列表，按逗号拆分后复用 add 的
清理、校验及去重；Rime columns 和 CSV 保留单编码语义。生成 TSV 可无损回读。
Builder 保留非空多码点键，从完整输入统计去重后的多码点条目数，作为
第三个返回值。build.table 负责写文件与计数；command 在成功后发一次 WARN 汇总，
普通构建为 INFO，失败为 ERROR。仅 source、lua 路径必填；tsv 可省略，命令第三位置
支持 - 占位。不输出 TSV 时仍返回完整输入计数，通知只列实际输出。常用 Lua 筛选
不影响完整输入和 warning 计数。
Rime 的 --- / ... 头部区间不作为数据解析，避免名称、版本等被误收录为词条。
normalize 接受 {codes, prefixes, max_chars}，运行层根据码表元数据开启文本前缀查询。
单码点 source 保持直接 data[text:get(1)]，不构建前缀索引。

Release API: dirichy/flash-any.nvim, Neovim 0.11+, setup with a complete sources
list, and jump returning the native Flash state. Static source data is validated
during construction. TSV upper-bound updates shrink by byte midpoint; LF and
CRLF are supported. Builder TSV values accept comma-separated codes, with
per-code cleanup/validation/deduplication shared with single-code rows. Rime/CSV
fields retain single-code semantics; generated TSV round-trips through the builder.
Nonempty multi-codepoint keys are preserved and counted after deduplication in
the complete input. build.table returns Lua/full-input/multi-input counts; TSV
output is optional without changing these counts. The command supports a - TSV
placeholder and reports only outputs actually written. The command owns
INFO/WARN/ERROR notifications. Rime header sections are excluded from data rows.
Normalization accepts {codes, prefixes, max_chars}; table metadata selects built-in
text-prefix lookup; single-codepoint sources retain direct map reads. Builder common subsets are read as Lua tables, including an
empty subset, rather than inferred from source formatting.

测试（独立 Neovim 进程；Flash checkout 放在 .dev/flash.nvim，可用指向安装目录的
符号链接，或为 tests/flash.lua 显式传入路径）：

```sh
for test in tests/init.lua tests/source.lua tests/scope.lua tests/cursor.lua tests/table.lua tests/utf8.lua tests/tsv.lua tests/build.lua tests/health.lua tests/match/*.lua; do
  NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l "$test" || exit
done
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/flash.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/char.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/remote.lua
nvim --clean --headless '+helptags doc' '+qa'
```

LuaLS 保留真实 Neovim runtime 和 .dev/flash.nvim/lua，检查全部诊断，不关闭类别。

### 多码点缓存 / Multi-codepoint caches

Builder 总是输出 {codes, prefixes, max_chars, scope}，包括单码点表和空表。
normalize 也接受仅带 codes 的结构，以及直接编码映射。prefixes 复制进独立
continuation 缓存；max_chars/scope 存在同一码表所有的 metadata 中，由 metadata(data)
只读访问，避免调用方管理生命周期。source
初始化只从数据推导运行时 max_chars，不接收 multi_code/长度选项。编码数组不携带前缀
语义；纯 Lua 缓存中 true 表示可加长，缺失表示终止，无须显式 false 或运行时建索引。
TSV 缓存中 nil 表示未查询，数字是继续的文件位置，false 缓存终止结果。
完整 TSV 应包含 Lua 编码条目，挂接 loader 时清空 Lua 前缀副本，以文件结果为准。
单码点简表默认上限 1，保留直接 hash 读取。补空格和规范化复制会保留独立元数据。
builder 按完整输入计算 max_chars，即使 Lua 常用子集为空也输出此元数据；
只从选中的 Lua 编码条目生成真前缀集合，包含自身也有编码的可继续键。
前缀不计入 common/full 数量，不为每个匹配查询构造结果 table。

TSV 二分节点缓存与前缀缓存分开：前 6 层节点无条件保留，深层精确命中节点也保留，
记录 key、position、after，供其他查询比较。offset = false 只作用于前缀加长，
不会删除二分节点。带 offset 的查询从该行开始，必要时在后续范围二分，
不使用对应整份文件划分的节点编号，避免错误复用节点。

The builder always emits {codes, prefixes, max_chars, scope}, including empty and
single-codepoint tables. normalize also accepts codes-only descriptors and direct
maps. Prefix sets have a private continuation cache; max_chars/scope are owned by
the same code map and exposed through read-only metadata(data).
Runtime source metadata is inferred from the table, without multi_code or length
configuration. Lua-only continuation sets contain true for extendable keys and
omit terminal ones. Code arrays have no continuation semantics; no runtime prefix
index is built. TSV caches use nil for unqueried, numeric file offsets to continue,
and false to prune. Full TSV data includes every Lua code entry, so attaching a
loader discards the static Lua prefix copy instead of merging it. Compact maps
default to a one-codepoint bound. Normalization and padding preserve metadata.
The builder computes the full table's bound even with an empty Lua subset, and
generates proper prefixes only for selected Lua codes, including keys with codes.
Prefixes do not count as code entries; queries allocate no temporary result table.
The first six binary-search levels are cached regardless of continuation, together
with deeper exact-hit nodes. These comparison nodes retain key/position/after
independently of prefix pruning. Searches starting from a saved offset do not use
whole-file heap indices because their binary partitions differ.

生成的 scope 使用完整输入首码点的最小、最大 UTF-8 字符，直接作为既有 scope 区间表，
不增加运行时策略。UTF-8 字节排序同时给出首码点边界；无需转换数值码点。空输入为
空范围。用户声明优先于工厂声明，再优先于文件元数据；显式 all 可取消初筛。
补空格保留私有 metadata；extra 插入的首码点会作为 hash=true 加入文件范围，
不扩大其他码表实例的 scope。

Generated scopes use the complete input's minimum and maximum first-codepoint
characters with the existing range-table compiler. UTF-8 byte ordering supplies
the bounds without numeric codepoint conversion. Empty input emits an empty set.
User declarations override factory declarations, then file metadata; explicit all
clears the filter. Padding preserves metadata. Extra entries add first-codepoint
hash inclusions to the owning map's scope without changing other instances.

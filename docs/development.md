# 开发记录

## 模块布局

- `flash-any.match`（`lua/flash-any/match/init.lua`）：搜索与单字扫描器、增量候选、缓存和搜索标签。
- `flash-any.match.codetable`（`lua/flash-any/match/codetable.lua`）：码表匹配及其三个模式。
- `flash-any.match.literal`（`lua/flash-any/match/literal.lua`）：配置层默认前置的 ASCII 字面 source，遵守统一协议。

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
`flash-any.match.literal` is a regular ASCII source prepended by configuration. Code-table
modes never fall back to the character itself.

## Flash 字符模式

`flash-any.char(win, state, range)` 接入 Flash 的 `modes.char.matcher`，共用 setup
构建的 sources。顶层 `match.get` 负责 s 的跨字符推进、next 和标签；`match.char`
只用一键查询每个字符，不建立 continuation、不查询下一字符，也不分配标签。
两者共用底层 match_char 的 source 顺序、fallback 与 matcher 协议。s 缓存范围内的
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

匹配函数为 `results = matcher(char, stream, { source = source })`。source 可以没有
码表；`args.source` 是构建完成的运行时对象，只保留 data、matcher、name 和
fallback。scheme、fuzzy 等配置在初始化时消费，不存入运行时 source。
只有内置 matcher 自行读取 `source.data`。扫描器不读取 codes，不判断编码
长度，也不识别 full_code/initial/prefix 的完成条件，只按 matcher 返回的分支推进。

每个分支恰有一个字段：

- `{ consumed = n }`：当前字符消耗 n 字节，进入下一个字符。必须消耗正整数个
  字节且不超过当前 stream 长度；恰好消耗完时只查询后一个字符的起始 next。
- `{ next = keys }`：当前 stream 已全部匹配，keys 为后续 ASCII 键集合，可以为空。

`nil` 表示不认识字符，空列表表示认识但 stream 不匹配。是否认识只由字符决定，
不随 stream 改变。列表允许一字多码与前缀策略产生多个消费边界；消费字节
数相同的内置分支在 matcher 内去重。空 stream 只用于起始键查询，不能再消费。
`consumed` 与 `next` 互斥；旧 `complete` 和 `args.codes` 已移除。

matcher 必须满足前缀约定：长输入能成功，则其短输入字符前缀也必须成功；
失败不能在追加输入后变为成功。consumed 提交的字符边界在追加时保持有效。
若同一字符还能接受更长编码，必须同时保留 next 分支，供后续输入继续该字符。

`fallback = true` 只在前面的配置 source 均返回 nil 时才参与；返回空列表
也表示字符已被覆盖。空 stream 查询遵守同一规则。内置 source 的字符范围预检
由码表 matcher 在读取 data 前完成，避免无关字符触发懒加载；不再保留 table.filter
入口或为每个 source 创建范围包装闭包。扫描器不处理 filter。
自定义函数自行返回 nil 判断范围。literal 与码表 source 遵守相同的顺序和覆盖规则。

A matcher returns nil for an unknown character, an empty list for a recognized
character with no matching branches, or a nonempty list for success. Recognition
must be independent of the stream. A source with `fallback = true` runs
only if all previous configured sources returned nil, including on empty-input
queries. Code-table matchers check built-in character scopes before reading data; there
is no table.filter entry point or per-source scope wrapper. The scanner has no
separate filter. The literal source follows the same coverage policy.

扫描请求记录起点与完整 pattern 中的 byte offset。matcher 返回 n 后只累计
`offset + n`；只有实际调用下一个 matcher 时才获取后缀。后缀缓存由 `M.get`
管理，按当前 pattern 与 offset 保存，跨起点、行和窗口共用；输入变化时替换。
相同下一字符、相同 offset 的请求未来行为相同，保留最早起点，防止分支膨胀。
扫描当前字符时，所有成功分支当场合成一个同终点的显示结果：起点取最小值，next
取并集，不建立按起止位置索引的去重表。不同 offset 的待续状态仍独立保留，不能
用显示结果的最早起点覆盖其他进度的起点。扫描后只按起点、终点排序，标签不受
分支枚举顺序影响。matcher 直接分配 label，外层使用空 labeler。

每个窗口保存原始行文本、匹配结果和可继续的请求，按行、buffer 字节列、输入 offset
记录最早起点。next 分支保存当前字符的请求；恰好消费完输入的分支保存下一个
字符、offset=#pattern 的请求。追加时只恢复这些请求，不重试失败位置，也不
重做已提交的字符消费。多个消费边界与继续当前字符的请求可同时保留。

buffer 身份、changedtick 或行范围变化时重新读取行文本；删除、替换输入或 source
列表变化时重新扫描缓存文本。新字节修复了之前截断的非法码点时也重建
匹配，避免沿用已变化的字符边界。相同输入复用匹配结果，但重算 label。

## 字面匹配规则

literal 由配置层默认加在所有 source 前面，不属于扫描器特例。它只认识 ASCII buffer 字符，空 stream
返回字符自身作为 next，首字节匹配则消费 1 字节，否则返回空列表；非 ASCII 字符
一律返回 nil。所有 source 使用同一顺序和 fallback 规则，普通 source 在前项成功后
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

中文 source 的标点键位统一保存在 `table/punctuation.lua`。`file_source` 在拼音
转换完成后加入标点，码表 matcher 的中文范围预检也读取同一份映射，避免标点
触发 TSV 查询或参与双拼、模糊音转换。`append_space_below` 仍统一作用于所有编码。

Chinese sources share `table/punctuation.lua`. File loading adds punctuation
after pinyin conversion; matcher scope checks use the same map. Punctuation
avoids TSV lookups and pinyin transformations. Space padding applies to all codes.

`require("flash-any.tsv").loader(path, opts)` 创建按字符查询的加载函数，可配置
separator 和 decode。它打开并持有文件句柄，返回编码数组或 nil，不缓存查询结果；
命中与未命中缓存由 `table.lazy` 统一管理。loader 按需缓存二分树前 6 层的
比较键、行起点和下一行位置，最多 63 个节点，与文件句柄同生命周期。
剩余区间不超过 64 字节时，从已对齐的下界顺序扫描，避免按字节二分反复跳到同一行。
模块级 `read_at(file, position, aligned)`
接收文件句柄，不为每个 loader 额外创建辅助闭包。

`flash-any.tsv.loader(path, opts)` replaces the former `open` factory. It returns
a character lookup function that owns an open file handle, not the handle itself.
The loader does not cache results; `table.lazy` owns positive and negative caches.
It lazily caches comparison keys, row starts and next-row offsets for the first
six binary-search levels (at most 63 nodes), with the same lifetime as its file
handle. Remaining intervals of at most 64 bytes are scanned from the aligned
lower bound, avoiding repeated reads of the same row near the end of a search.
The shared `read_at` helper takes the file explicitly instead of capturing it.

`require` 返回的原始码表、方案规则以及 `load(name)` 的默认缓存均可能共享。
`normalize` 复制输入 map 和编码数组，建立私有边界；`append_space` 生成独立
编码数组与派生缓存，防止追加的空格污染调用方或默认方案。

全拼模糊音与双拼转换共用 `from_pinyin`：全拼直接拼接展开的声母、韵母，
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

Full-pinyin fuzzy expansion and double-pinyin conversion share `from_pinyin`.
Full pinyin joins expanded initials and finals directly; double-pinyin schemes
map them to keys. Full pinyin without fuzzy options loads the original table.

码表统一通过 `table.load(name, opts)` 加载，移除单独的 `table.flypy(opts)` 入口。
`loaders` 只保存加载函数；无 opts 时按名称缓存，有 opts 时构建独立实例。
常用字在加载方案时读入，TSV 生僻字在首次按字符查询时读取并缓存。

Use `table.load(name, opts)` for all schemes; the separate `table.flypy(opts)`
entry point has been removed. The loader registry holds functions only. Calls
without options cache by name; calls with options build independent instances.
Common entries load with the scheme; TSV entries load and cache on first lookup.

## UTF-8 调用边界

buffer 行文本和自定义 matcher 输入可以是 UTF-8；内置 literal source、码表编码、拼音声母
韵母和保留给 Flash 的 next 键是 ASCII。UTF-8 文本的字节前缀比较、CSV/TSV 的
ASCII 分隔符识别无需解码；字符遍历使用 iter_char，单码点字段检查使用 iter_offset。
字符范围判断仍需 char2nr 获取码点。utf8.len/sub/byteidx 保留原生随机访问语义，
同时作为迭代器测试的独立对照，不用于生产代码的逐字符遍历。

Buffer text and custom matcher input may be UTF-8; the built-in literal source,
code-table encodings, pinyin components, and reserved next keys use ASCII. Byte-prefix
comparisons and ASCII CSV/TSV delimiter parsing preserve UTF-8 without decoding.
Use iter_char for traversal and iter_offset to check a single-codepoint field.
Range checks still require char2nr. Native len/sub/byteidx helpers retain their
random-access behavior and serve as independent iterator test references.

旧 `table.from_flypy` 及其方括号字符列表解析已移除；所有双拼均由统一拼音表转换。
The unused `table.from_flypy` entry point and bracket-list parser have been
removed; all double-pinyin schemes derive from the shared pinyin table.

## 拼音 source 与编码方案

码表注册表包含 pinyin、tiger、wubi86、unicode、nerdfont；literal source 不需要码表。全拼和双拼共用 pinyin
source，通过 opts.scheme 选择一种编码；省略为全拼。from_pinyin 直接作为 pinyin
loader，不再为每种双拼注册独立入口。无 opts 的全拼复用默认缓存，有 opts 的加载
各自持有转换后的常用字与 TSV 缓存；不同方案不会共用转换结果。
初始化 source 列表时拒绝重复的 pinyin source。全拼默认 initial，双拼默认 full_code，
显式 matcher 优先；scheme 只属于 pinyin source，没有顶层简写入口。

The registry exposes one pinyin source, with opts.scheme choosing one encoding
and omission selecting full pinyin. Standalone double-pinyin source names are
removed. Each configured load owns its converted data and lazy cache. Source
loading rejects duplicate pinyin entries. Full pinyin defaults to initial and
double pinyin to full_code; explicit matcher options take precedence. The scheme
option belongs only to the pinyin source, without a top-level shorthand.

## 模糊音索引

每次加载拼音 source 时，将 initials/finals 分组各自构建为“声母或韵母 → 候选数组”
的哈希表。重叠分组保留第一次出现的分组；未分组的已知声母、韵母各建一个自身候选
数组。常用字转换和 TSV 懒加载共享这两个只读索引，不在每个读音上扫描分组或分配
自身候选数组。声母、韵母仍用 ASCII 字符串表示，无需另行维护整数枚举。

Each pinyin load builds reverse hash indexes from initials/finals to candidate
arrays. The first group wins when groups overlap; ungrouped known components
get singleton candidates once per load. Common and lazy conversions share the
read-only indexes. Components remain ASCII strings, without integer enums.

`FlashAnySource` describes the runtime object: data, matcher, name, and
fallback. Initialization consumes scheme/fuzzy options. fallback=true makes a
source run only when every earlier configured source returned nil.

配置层的 matcher 可为模式名或函数；初始化后统一为 FlashAnyMatcher 函数，
扫描器不再解析字符串模式名。
Matcher configuration accepts a mode name or function. Initialization resolves
names to FlashAnyMatcher functions; the scanner only calls functions.

## 配置与运行时边界

FlashAnySourceConfig/FlashAnySourceSpec 定义在插件入口，只描述用户配置；
FlashAnySource 定义在 match/init.lua，只描述编译后的运行时对象。setup 时构建
默认配置并保存，jump 的完整独立配置则在启动 Flash 前构建。配置校验和模式名解析
不进入扫描路径。默认 source 在多次跳转间共享码表及其懒加载缓存，setup 替换配置
时自然替换所属对象。matcher 的动态分支返回值是受信任的协议，不通过热路径断言
验证；合法消费范围、consumed/next 互斥和前缀约定由实现及测试保证。

Configuration types live at the plugin entry point; runtime source types live
in match/init.lua. Setup builds the complete defaults once, while complete
per-jump configurations are built before Flash starts. The scanner neither parses configuration nor
validates dynamic matcher branches. Implementations and tests own the return
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

Release API: dirichy/flash-any.nvim, Neovim 0.11+, setup with a complete sources
list, and jump returning the native Flash state. Static source data is validated
during construction. TSV upper-bound updates shrink by byte midpoint; LF and
CRLF are supported. Builder common subsets are read as Lua tables, including an
empty subset, rather than inferred from source formatting.

测试（独立 Neovim 进程；Flash checkout 放在 .dev/flash.nvim，可用指向安装目录的
符号链接，或为 tests/flash.lua 显式传入路径）：

```sh
for test in tests/init.lua tests/table.lua tests/utf8.lua tests/tsv.lua tests/build.lua tests/health.lua tests/match/*.lua; do
  NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l "$test" || exit
done
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/flash.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/char.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/remote.lua
nvim --clean --headless '+helptags doc' '+qa'
```

LuaLS 保留真实 Neovim runtime 和 .dev/flash.nvim/lua，检查全部诊断，不关闭类别。

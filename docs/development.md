# 实现与验证 / Implementation and validation

## 边界 / Boundaries

setup 只允许成功初始化一次，重复或重入时在触及构建与 Flash 前报错。同步初始化
失败可重试；配置和 char 接入都成功后才发布默认状态。异步构建失败不重开 setup，
由 rebuild 重试。jump/remote/search/char/rebuild 和构建工具均可重复调用。

Setup commits once; duplicate/reentrant calls fail before touching builds or Flash.
Synchronous failures can be retried; options publish only after preparation and char
integration succeed. Background failures retry through rebuild. Runtime operations and
build tools remain repeatable.

运行时只有 C 后端。只有 `setup` 接收 `sources` 或 `binary`；
缺失二进制时自动构建，码表工厂和转换仅在构建阶段执行。不提供 Lua matcher、输入/文本 Cursor 或按需 loader 扩展。
jump/remote/search 只合并单次 Flash 选项并复用 setup matcher，拒绝 sources/binary/char，
不创建独立字典生命周期。键支持完整字素和词组，连续输入可以连接多个词条。
词组只从字素边界开始和结束，不跨行。

Runtime is C-only. Setup builds a missing package from sources or loads an existing
binary. Jump/remote/search merge per-call Flash options with setup, reusing its
matcher; they reject sources/binary/char and never prepare a dictionary.
Lua factories/converters execute only while building. Keys can be complete
graphemes or phrases; input can consume several entries. Phrase boundaries must be
grapheme boundaries, and entries cannot span buffer lines.

字表内容决定收录范围，构建器不另做字符范围过滤。需要删条目时更新码表，或由
converter 返回 nil/空数组。fallback 按完整文字key合并，空编码列表也阻止后续同key的fallback。
Dictionary contents define coverage; the builder applies no separate character-range
filter. Remove entries in the dictionary or return nil/an empty array from a converter.
Fallback merges by exact text key; empty lists also block later fallback codes for that key.

## 模块 / Modules

码表入口统一返回完整的 `text -> string[]` 普通 map，不附加 metatable、prefixes、
max_chars、offset 或命中/缺失缓存。Lua 覆盖 TSV，extra 最后覆盖；空数组保留为已识别
条目，仍会阻止后续 fallback。`source.resolve` 保证工厂（含 prepared）与直接输入
都已规范化；`build.binary` 直接枚举 data，不再 materialize。Lua/TSV 导出只生成 codes，
多字素数量仅用于完成通知，不生成未被运行层消费的前缀或最大长度。

Table inputs become complete plain `text -> string[]` maps, with no lookup metatable,
prefix/length metadata or offset/miss cache. Lua overrides TSV, then extra wins. Empty
arrays remain recognized and suppress fallback. Source resolution normalizes factories,
prepared data and direct inputs; the binary compiler iterates data directly. Lua exports
contain only codes. Grapheme counts remain solely for build completion messages.


- `reader.lua`：外部字典解析及递归导入的 metadata fingerprint，不依赖构建器或 source。
- `table.lua`：码表规范化、转换、Lua/TSV 覆盖、补空格和选键排名，只依赖 reader 读取外部数据。
- `source.lua`：工厂及默认实例缓存；resolve 依次解析配置、准备数据、解析匹配规则，依赖 table。
- `build.lua`：Lua/TSV 导出、二进制合并编译、异步任务及命令；保留 read/fingerprint/selectors
  原入口，分别直接引用 reader 和 table 的实现。

The build-time dependency chain is `build → source → table → reader`. Reader owns
external dictionary parsing and imported-file fingerprints; table owns normalization,
conversion, overlays, padding and ranked selectors. Source owns factory instance caches
and resolves configuration, complete data and matching rules in that order. Build owns
exports, binary compilation and workers; its existing read/fingerprint/selectors helpers
remain aliases to their implementations. No reverse dependency on build remains in
source, table or reader.
- `src/text.h`：严格UTF8解码及Unicode17扩展字素分段，只保留当前分段状态；没有
  文本索引数组、Cursor方法或Lua逐字素回调。
- `src/binary.c`：二进制序列化、共享编码组、索引构建、完整校验、文件读取与原子写入。
- `src/scan.c`：单趟字素扫描、编码匹配、请求推进、候选合并、下一输入键收集与构建时字素枚举。
- `src/trie.c`：构建普通码点双数组Trie；宽节点优先放置，临时树和空闲链只在构建时存在。
- `src/native.c`：Lua入口、窗口行/结果缓存、标签分配与f/F/t/T位置转换。
  状态/临时存储由Lua userdata拥有，避免额外malloc生命周期。
- `src/native.h`：内部共享类型、格式常量与内联字典查询；匹配上下文只在`scan.c`内定义。
- `native.lua`、`init.lua`、`matcher.lua`、`search.lua`：Neovim文本IO及Flash桥接，Flash仍管理按键、
  操作符、窗口、remote恢复和绘制。Flash要求的Lua matcher回调只是C入口。

已有二进制时不加载source或字素模块；外部file的依赖检查只加载 reader。
缺失时按sources构建。Lua的grapheme.lua只封装C的each/len，UTF-8解码和UAX #29
规则仅在text.h中实现；构建和扫描共用同一实现。
`tests/autobuild.lua`和`tests/source_cache.lua`在独立进程中验证构建与缓存复用。

Cached external files load only reader for dependency checks,
without grapheme/source modules. Build-time grapheme counting and enumeration call
the same C decoder and boundary rules used by scanning. The Lua grapheme module
is a thin adapter. Bundled Unicode input data lives under scripts/data.
Explicit binaries and cached built-in sources load without Lua builders or scanners. Fresh-process tests
cover automatic native compilation/repair, Flash fallback, dictionary compilation
and persistent-cache reuse. Native compilation directly launches the compiler; dictionary compilation uses a Neovim worker.

Review C时，可先读`text.h`的`decode`/`grapheme_break`，再沿`scan.c`的
`scan_line → scan_grapheme → match_codes → emit/request`阅读。二进制读写单独看
`binary.c`的`write_binary`和`load_data`；`native.c`的`scan`负责Lua参数、缓存及GC根。
`scan_line`是匹配扫描的唯一跨文件入口：结果扩容时替换指定Lua栈槽并返回新指针，
调用方继续持有该栈槽；行间复用请求工作区，每行开始重置。
字典读取函数放在内部头中供校验和扫描共用，保留内联机会。源文件中的短注释
说明跨调用的状态、位置单位和借用指针约束；`.clang-format`统一C排版。

`binary.c` owns package encoding, shared groups, index construction, validation and
file reads and atomic writes. `scan.c` owns forward grapheme matching, request advancement and
build-time grapheme enumeration, keeping Unicode boundary table use in one translation unit;
`native.c` owns Lua bindings, window caches, labels and motion positions. Shared
types and inline dictionary lookups live in `native.h`; matching context stays
private to `scan.c`. UTF-8 decoding and grapheme boundaries remain in `text.h`.
For review, follow `scan_line → scan_grapheme → match_codes → emit/request`.
`scan_line` is the only matching entry point: result growth replaces
the caller-pinned Lua stack slot and returns the new address. Request storage is
reused across rows and reset at each row's start. `native.c` keeps Lua stack roots
and caches alive. Format production C with
`clang-format -i src/native.c src/binary.c src/scan.c src/native.h src/text.h`.

## 构建 / Build

C 编译统一归 `lua/flash-any/compiler.lua`，只需要 Neovim 和 C 编译器，不依赖 make、
Python、pkg-config 或系统 LuaJIT 开发包。平台分支只处理共享库参数和 Windows 的
`lua51.dll` 路径，源文件列表和公共参数共用。`CC` 指定一个编译器可执行文件；
`CPPFLAGS`、`CFLAGS`（默认 `-O3`）、`LDFLAGS` 按空白拆为参数，不做 shell 解析。
Windows 需要与 Neovim 架构一致的原生 MinGW-w64 GCC；Unix 使用 GCC 或 Clang。
`vendor/luajit` 内置公开 Lua/C 头文件，Windows 链接当前 Neovim 旁的 `lua51.dll`。

`compiler.load(callback)` 在产物缺失、C 源文件/头文件/构建模块 mtime 新于产物，或
动态库加载失败时自动编译。同一进程的并发请求共享一个编译器任务。直接用 `vim.system`
启动编译器，不创建 Neovim 子进程。输出先写入唯一临时文件，成功后替换产物；失败
清理临时文件并保留旧产物。不传 callback 的工具调用等待同一个任务完成。
模块加载后本进程不再检查源码或热重载，插件更新后重启。
Windows 其他进程持有旧 DLL 时替换可能失败，报错要求关闭这些实例再重试。
独立 Neovim 进程各自构建临时文件，不实现跨进程锁。

`native.lua` 延迟加载 C。setup 使用异步入口；等待首次 C 编译时，jump/remote
保留 Flash 默认 matcher 和 labeler，search/char 复用 Flash 原生搜索。C 就绪后后续
调用切到 C；码表仍在构建时使用 C 字面快照。构建工具访问 modes/grapheme/write 时
同步确保 C 可用。`compiler.build(callback)` 供显式强制重建；无 callback 时等待完成。

Native compilation is owned by `compiler.lua`: source/header/builder mtimes determine
freshness, load failures trigger repair, concurrent requests share one compiler process,
and failed builds preserve existing outputs. First-compile matching uses Flash's native
search. Setup does not wait; build tools and callback-free explicit builds wait for completion.
There is no hot reload or cross-process build lock. Windows needs native MinGW-w64 GCC
and links Neovim's own `lua51.dll`; loaded DLLs may require closing other Neovim instances.
Environment flags are whitespace-separated arguments without shell interpretation.

Windows 码表 IO 将 UTF-8 路径转为 UTF-16 后使用宽字符 API，临时文件排他创建，
关闭后通过 `MoveFileExW(MOVEFILE_REPLACE_EXISTING)` 替换目标，失败清理临时文件。
Windows binary IO converts UTF-8 paths to UTF-16 and replaces completed temporary
files with `MoveFileExW`; snapshots remain owned by Lua userdata.

Unicode 数据在 `scripts/data/grapheme_data.lua`，生成的 `src/grapheme_data.h` 随源码
提交；更新数据后运行 `nvim --clean -l scripts/generate_grapheme.lua`。
clangd 使用 `compile_flags.txt`，无需生成编译数据库。

native.load统一拥有码表缓存路径和构建：未指定binary时，按sources的稳定inspect
表示、所选source版本、核心CACHE_VERSION和C导出的格式/Unicode版本计算SHA256，放入stdpath("cache")/flash-any/。
存在时直接打开；setup 缺失时通过 build.async 启动 nvim --clean -l 子进程，
传递 MessagePack 构建参数、runtimepath 和当前窗口 cwd。同一路径在本进程内合并构建请求。
工厂、读取、合并与写入在子进程执行；回调打开新快照。等待时保留旧 matcher，首次使用
轻量字面快照，每次搜索通知一次。失败保留回退并通知。显式binary优先使用固定路径。
build.binary/table 和不传回调的 native.load 供开发工具同步使用。缓存指纹检查及最终
binary 的读取/校验仍在主线程；并非所有 setup 工作都迁移到后台。

Setup compiles missing dictionaries in a headless Nvim worker, sharing runtimepath and
cwd but no init.lua or in-memory Lua state. Requests for the same path share one worker.
While waiting, searches keep their previous matcher or use a literal-only snapshot;
notifications are emitted at build start and once per search using a fallback. Failures
retain that fallback. Build helpers remain synchronous for exports. Cache fingerprinting
and opening/validating the finished binary still run on the main thread.
用户 sources 显式声明的外部词典、Rime 导入、lua/tsv 及 converter 按绝对路径、
大小和 mtime（秒/纳秒）生成缓存键。保留大小/mtime 的编辑无法检测。
`factory.lua` 统一用 loadfile（或 package.preload）读取模块的工厂和可选版本，
在进程内缓存，并将工厂放入 package.loaded，保留普通 require 取得函数的用法。
require 本身丢弃模块的第二返回值，因此核心不能用它读取版本。缺省版本为 0，
允许有限数字及非空字符串；只读取配置中的 source，不遍历其他包或跟踪隐式依赖。
作者更新构建依赖时负责改版本，source 模块更新后需重启。核心 Lua 构建规则变化且
不改变原生格式时，推进 native.lua 的 CACHE_VERSION。
`rebuild()` 使用 setup 的 sources 异步强制重建，不重设 Flash 配置。book 统一
管理 pending 状态，已有任务时不再发起加载请求；即使文件元数据变化导致缓存路径变化，
也不会并行或排队重建。任务完成或失败后才允许下次重建，无需结果代次或乱序保护。
保留失败回退和按查询固定字典的机制。显式 binary 也可重建，但需要 sources。

The unified builder uses committed Unicode headers and bundled public Lua/C headers.
No local LuaJIT development package is needed. clangd uses compile_flags.txt.
The dictionary loader owns cache paths. Explicit file inputs retain metadata/Rime-import
checks; named sources use the factory module's second return value, defaulting to zero.
`factory.lua` loads declarations once per process and preserves both return values,
while package.loaded exposes the factory to ordinary require callers. Factories are
invoked only while compiling. No package-wide file scanning or dependency manifest is
used. Authors bump source versions for dependency changes; restart after module updates.
Core Lua compilation changes bump CACHE_VERSION if the native wire version stays fixed.
`rebuild()` forces an asynchronous rebuild from setup's sources. Each book owns
its pending state and admits only one task, even when file metadata changes the cache
path. Requests during that task do not enqueue another. Completion or failure allows a
new rebuild; no generation or out-of-order result guard is needed. Flash options, failure
fallback and query snapshots are retained.

## 码表 / Dictionary

按source顺序处理fallback，再合并`(matcher模式, 编码)`。空编码集合
也算认识，会屏蔽后续fallback但不产生匹配。ASCII literal构建为127个非NUL键，普通源
仍可为ASCII附加编码。非 ASCII 或多码点字素不依赖码表，直接比较原文；
fallback 的码表合并规则不因原文字面匹配而改变。运行时不保留source身份或fallback状态。

当前格式为`FANYBIN\x0E`（v14）。单码点页表和按节点取模的码点DAT共享编码池：

- 单码点：4352个u32页目录，每个实际页256个u32槽。页目录存页序号+1，
  槽存编码列表offset+1；0表示不存在，不保存key或条目记录。
- DAT每单元8字节，低到高依次为有符号base24、入边商13、父节点编号+1占23位、
  出边模数指数标记4位。普通标记0..13表示指数8..21，即每节点模数256..2^21。
  标记14保留，15表示终点；终点低32位改存编码列表offset+1，位32..36必须为0。
- `next = base[state] + (cp & (2^k - 1))`，先校验父节点，再校验入边商等于
  `cp >> k`；这里k来自父节点。0标签边必须指向终点，普通边不得指向终点。
  父节点校验确定归属，槽位确定余数，商确定高位；不要求base唯一。
- 空单元全0；根在state0，父节点和入边商为0，出边指数仍正常存放。非法UTF-8
  字节用`0x110000+原字节`作为标签。单元数最多8,388,607，构建或加载超限时失败。
- 不存文本key、文本记录或hash槽，不合并根页表，不复用空base，不用多区域偏移。

构建时将每组兄弟标签反转二进制位后排序，只检查相邻标签的共同低位长度，直接
得到最小无冲突指数，最低取8。终点标签0参与计算。不枚举模数或反复试建DAT。
临时树和空槽搜索仍由C实现；模数只改变寻址标签，不增加运行时侧表。

40字节头为magic8及8个little-endian u32：Unicode版本17、总大小、文本key数、
DAT单元数、码点页数、编码池字节数、编码组区字节数、单码点数。后续依次为
页目录/页槽、DAT、编码池及编码组；没有单码点时不存页目录，没有文本key时不存DAT。

编码列表为`[标记][编码或参数]...[NUL]`。0x80 literal、0x81 full_code、
0x82 initial、0x83 prefix、0x84 suffix、0x85 letter；0x89/0x8A/0x8B/0x8D
是对应模式的组ID序列。每个ID为高字节在前的u16，ID边界上的单字节0xFF结束
序列；低字节允许0xFF。有效ID为0..65279，每包最多65280组。其他字段仍为小端。
普通编码标记兼作模式与分隔，不保存逐编码长度。编码、后缀和组内拼写禁止NUL；
组内拼写保留u8长度。单组同样存为一个ID加0xFF，不保留旧格式分支。
文本或查询含NUL时，匹配行为不作保证，不增加专门的扫描分支。

加载时校验页表归属与占用、DAT父节点及标签、终点数、环引用、终点不能有子节点，
并校验编码偏移、列表语法及组引用。父链深度用临时数组记忆，每个单元最多遍历
两次；同时求最长key码点数。加载后只保留原始只读字节，不重建索引或保留校验数组。
输出前复用完整加载校验，之后原子替换文件。自动缓存因v14版本变化重建；显式
binary需要重新导出，make后重启Nvim。

Version 14 retains v13's scalar offsets in a two-level page table and text keys in a
codepoint DAT with per-node power-of-two moduli. Each LE u64 packs signed base24,
incoming quotient13, parent-plus-one23 and an outgoing exponent tag4, low to high.
Normal tags 0..13 encode exponents 8..21; tag14 is reserved and tag15 denotes a
terminal with code-list offset-plus-one in its low32 bits. Terminal bits32..36
must be zero. The root has no parent/incoming quotient; empty units are all zero.
Queries check the exact parent and the quotient using the parent's exponent.
Bases need not be unique. Reversed-label sorting computes the smallest allowed
modulus for each node once, including terminal label zero, without trial builds.
The 40-byte header and section order remain scalar pages, DAT, code pool and groups.
There are no text strings, hash slots, merged roots, vacancy reuse or region flags.
The 23-bit parent limit supports up to 8,388,607 units. Bounds, labels, chains,
terminals and groups are validated before use. Explicit binaries need regeneration
for v14; automatic caches rebuild and Nvim must restart after updating.

Group-tagged records contain a nonempty sequence of big-endian u16 IDs, terminated
by one 0xFF byte at an ID boundary. A low byte of 0xFF remains valid. IDs range from
0 to 65279; other fields remain little-endian. Single groups use the same sequence
format. C validates every ID and the terminator, rejecting empty, truncated and
out-of-range sequences. Lua supplies ID arrays rather than binary bytes.

Lua仅传递排序后的文字key及`{模式, 编码}`列表，C负责标记编码、共享池、偏移、索引、
文件头和写入；二进制规则不在Lua重复实现。完整输出先复用读取端校验，再在目标
目录创建临时文件、写入、关闭并rename；失败清理临时文件，保留原输出。

Lua supplies sorted text keys and mode/code pairs. C owns serialization and file IO,
including tagged lists, shared pools, indexes and headers. The loader validates the
complete package before writing; replacement uses a temporary file in the output directory.

`open`用fread直接读入冻结userdata，避免Lua IO的额外完整字符串和mmap原地改写
问题。不同Flash state共享只读码表，分别拥有行/查询缓存；按buffer/changedtick
失效，随state回收。rebuild加载新快照，不改变已有查询。

Each snapshot owns both immutable tables and their tagged ASCII code lists. Bounds, tags and
index reachability are validated at load time. Package replacement is atomic. Existing
states pin their snapshot; per-state line/result caches expire with their buffer tick.

## 扫描 / Scanning

单字素与词组共用一次前向扫描，不再维护单字素hash快路径。每解码一个码点，
同步更新Unicode字素边界，并推进所有活动Trie状态；失败即移除。每个字素起点
加入根状态，字素内部不启动新前缀。预读的码点直接用于下一字素，不重复解码。
单码点规则查页表，其他终点从DAT的0标签边读取编码，仅在完整字素边界匹配；转移校验父节点和商。

请求按后续文字位置和输入字节偏移合并，保留最晚起点。环形工作区为最长key码点数+1，
至少两槽；词条完成后把消费请求发往下一字素。完成输入的候选保留结果编号，后续
单字或词组补充next键；结果扩容后通过编号重新取址。候选只在实际命中时增长。
文字、字面输入、普通编码、initial/prefix、letter、共享编码组沿用同一匹配逻辑。
组序列逐组应用matcher，每步合并相同输入偏移，不展开拼写笛卡尔积。只有整条
序列完成后才推进文本；未完成的组保留next。单组沿用直接匹配路径；多组使用
本次scan持有的两份输入长度字节集合，跨词条和行复用，不保留跨查询状态。
跨行状态不保留；f/F/t/T认可词组时使用第一个字素及其相邻位置。

同一终止字素的候选合并next，保留最晚起点；后续行为相同的请求也保留最晚起点，
使范围尽量短。普通跳转结果按行、终点排序，再从左到右保留互不重叠的范围；
该贪心选择保留最多个独立匹配。同终点偏好短范围是确定性的取舍，不生成新的区间。
标签排除键先从全部候选汇总，包括被隐藏范围的ASCII和Unicode字面续码；缓存保留
完整候选，以便更换标签时重新应用排除规则。每轮查询重新匹配，被隐藏的分支仍可继续输入。

相同输入复用结果；输入改变时重新扫描缓存原始行，不从旧候选筛选，不保留跨输入
的前缀推进状态。临时活动状态、请求环与结果由本次扫描的Lua userdata管理。

Single graphemes and phrases share one forward scanner. Each decoded codepoint
advances every live DAT state; failed states are removed. A new root starts only at
a grapheme boundary, and terminals are evaluated only at complete boundaries.
Scalar rules retain page lookup. A bounded ring keeps the input states at every
live text start; completions schedule work at the terminal's successor. Completed
results are referenced by index while following entries contribute next keys.
Scratch state resets between lines. Character motions use the first grapheme and
its native neighboring positions. Changed queries rescan saved lines; identical
queries reuse results. There is no separate hash fast path or runtime index choice.

Requests at the same successor/input offset retain the latest start; their futures
are identical, and a shorter range leaves more room for preceding matches. Candidates
ending at the same grapheme also retain the latest start and union their next keys.
Full-search results are ordered by row and end, then greedily filtered into disjoint
ranges. This maximizes the number of displayed matches, with shorter ranges winning
end ties. Labels reserve next keys from all candidates before filtering, including
Unicode literal continuations. Cached candidates retain hidden keys; changed queries
rescan every branch rather than extending only the displayed ranges.

Group sequences apply the matcher independently at each step and merge equal input
offsets instead of expanding spelling products. Only a completed sequence advances
the text entry; partial spellings still contribute next keys. Single groups retain
direct matching. Multi-group matching reuses two input-width byte sets owned by the
current scan across entries and rows, without cross-query state.

v11的hash、排序区间、全局取模DAT、页表根和平行数组/空位复用方案均保留为历史实验。
`bench_phrases.py`要求通过`--source-root`指定v11 C源码快照，避免旧格式实验误用
当前加载器；不属于正式运行时选项。本轮快照位于`/tmp/flash-any-native-v11`。

The v11 representations remain historical benchmark variants. The phrase benchmark
requires a v11 C source snapshot via --source-root; it does not patch current code into
an older-format experiment. None of these variants is a production runtime option.

各轮输入独立按当前规则判定，不以之前的候选集约束下一轮输入，也不要求所有
matcher 遵循统一的输入前缀约定。

Each query is evaluated independently under its matching rules. Previous candidates
do not constrain the next query, and matchers have no shared input-prefix contract.

Lua 适配器每次匹配读取 `ignorecase`/`smartcase`，将有效策略传给 C；C 对 ASCII
字面输入及 `letter` matcher 逐字节折叠大小写，其余码表规则精确比较。
码表仍保留原始编码。结果缓存键包含有效策略，
选项切换复用原始行并重新匹配；仅大小写忽略规则的 next-key 同时保留两种大小写，避免标签抢占输入。

The Lua adapter reads `ignorecase`/`smartcase` on each match and passes the effective
policy to C. Only literal and `letter` rules fold ASCII case; other rules stay exact.
The result cache includes that policy; changing it rescans saved lines. Next-key sets
reserve both cases only for insensitive rules so labels cannot consume valid input.

## 字符模式接入 / Character-mode integration

`setup({ char = true, ... })` 用 `flash.config.get()` 取得当前完整配置，再通过 Flash 的
公开 setup 接入 `M.char`，不直接改内部配置或接管按键。初始化只执行一次，
不保存重复 setup 才需要的旧 matcher 恢复状态。默认关闭，单次运行时调用不接受 char。
Flash 的 enabled、multi_line、keys 等设置保留。

Setup's boolean char option defaults to false. Enabling it passes Flash's current
configuration back through its public setup with M.char as the character matcher.
Initialization happens once, so no previous-matcher restoration state is retained.
Per-call options cannot configure char. Existing Flash options remain in place;
Flash owns mappings, counts and repeats.

## 异步搜索 / Asynchronous search

`init.lua` owns dictionary selection: each state pins the selected immutable dictionary
by configuration identity and query text. `book.engine` is only the latest available
dictionary; replacing it never changes an existing query's snapshot. Both ordinary and
char scans read the pinned dictionary, so coroutine resumes and Enter use the same data.
A new query or state selects the latest dictionary. The search job key intentionally does
not track the latest dictionary identity: completed builds wait for new input instead of
invalidating running jobs. Buffer/range/case changes may restart jobs for unchanged input,
but still use that query's pinned dictionary.

`init.lua` 统一选择字典：state 按配置身份及查询文本持有不可变字典快照，
`book.engine` 只代表最新可用字典。普通匹配和 char 扫描共用快照；异步分批恢复、
Enter 同步完成时都不切换字典。新查询或新 state 才选择最新字典。job key 无需跟踪
最新字典身份，因为构建完成采用等待输入变化的策略，不主动失效旧 job。
同一输入因 buffer/range/大小写规则变化而重新建 job 时，也继续使用固定快照。

`search.lua` owns the pending preview coroutine, its snapshot and published results.
Both visible highlighting and directional lookup reuse `matcher.lua`, yielding between
lines once a 2 ms batch budget expires. A 1 ms timer resumes work so input can run
between batches. Query, buffer identity, changedtick and case options invalidate old
work; hidden states cannot publish results. Harmless previous highlights remain until
replacement results arrive. Enter refreshes input/buffer state while retaining the query's
dictionary, then drains the same coroutine without yielding and restores the origin
before committing the target.

`search.lua` 统一管理预览任务、快照和已发布结果。可见高亮和目标查找都分批执行；
查询、缓冲区、changedtick 或大小写选项变化时旧任务失效，隐藏后不再发布结果。
新结果就绪前保留无害旧高亮。Enter 刷新输入及缓冲区状态，保留查询的字典快照，
同步完成当前协程，再从原位置提交跳转。
这是主线程协作式异步，单行 C 匹配不能中断；不提供线程并行或严格的延迟上限。

`search.lua` also owns the last confirmed query and its scan configuration, not the
old state, buffer or result list. Each repeat constructs a fresh state and uses the
shared matcher synchronously. Explicit `search.wrap` is retained; otherwise repeats
read the current `'wrapscan'`. There are no installed mappings or input listeners.
The native register is the dispatch boundary, including on operator redo because
`.` replays a mapping's `<Cmd>` without rerunning its expression callback.

For `gn/gN`, the shared matcher resolves the target and count first. A single
position-bounded regex then delegates selection and operator semantics to native
`gn/gN`; it never expands code-table alternatives. The register, direction,
highlight flag and wrapping option are restored synchronously, including on errors.

上次查询和重复查找也由 `search.lua` 管理，不保留旧 state、buffer 或结果列表。
重复操作新建 state、同步复用 matcher；显式 wrap 保留，否则读取当前 'wrapscan'。
不安装映射或监听器。@/ 决定搜索归属，API 内也检查，以覆盖绕过表达式映射的点重复。
gn/gN 先由 matcher 按次数确定目标，再用单个位置范围模式交给原生命令选择和执行
操作符，不展开字库。寄存器、方向、高亮标记和回绕选项在成功或出错后同步恢复。

Local measurement (2026-11-18, separate clean Neovim processes per mode/scenario):
100,000 ASCII lines, roughly 4 MB, built-in literal matching, one run per case.
The synchronous baseline uses the same shared matcher and native scanner.
Times below are wall time for `state:update()` / first preview completion, excluding
buffer construction and dictionary setup. They are local observations, not a latency guarantee.

| Case | Synchronous update | Async update return | Async preview completion |
| --- | --- | --- | --- |
| Match on line 2 | 0.18 ms | 0.03 ms | 1.3 ms |
| Match on line 100,000 | 303 ms | 0.04 ms | 306 ms |
| No match | 591 ms | 0.04 ms | 653 ms |
| One 5 MB target line | 74 ms | 0.05 ms | 75 ms |

分批改善输入响应，不减少总扫描工作；无匹配场景的调度会增加总耗时。
5 MB 单行案例中的约 74 ms C 扫描仍会阻塞一个批次，需另行支持行内中断才能消除。

## 测试与 LSP / Tests and LSP

每项测试应能说明它防止的具体问题：用户可能执行的操作、文件或运行时安全、
明确的性能退化，或容易写错的算法规则。不要按函数、分支或字段逐一配套断言，
也不要验证普通 Lua table 的读写行为。优先检查操作产生的匹配结果或错误；
converter 接收整组还是单行等扩展接口约定，可以直接检查其输出。
相同风险已有覆盖时合并用例，不为每个配置组合复制一次完整流程。

异步构建测试负责首次构建时编辑器仍能响应、等待通知和查询快照；重建测试负责
手动更新、并发请求合并及失败后保留旧文件并允许重试。C 的损坏二进制、边界、
GC 生命周期与官方 Unicode 边界测试保留，用于防止越界、悬空引用
和匹配算法错误；这些用例的理由是具体风险，而不是与实现代码一一对应。

Each test needs a concrete reason: plausible user behavior, file or runtime safety,
a known performance risk, or an error-prone algorithmic rule. Assert observable
results or extension contracts rather than mirroring functions, branches, fields,
or ordinary Lua table operations. Merge overlapping scenarios instead of repeating
whole workflows for every option combination. Background-build tests cover responsiveness,
notices and query snapshots; rebuild tests cover manual updates, concurrent requests,
file preservation and retry. Corrupt binary, boundary, GC and Unicode tests protect
against memory errors and incorrect matching.

码表按功能验证，不逐个安装或扫描外部 source。`tests/matcher.lua`用三张固定种子的
随机表，连续验证 matcher、输入编辑、大小写与字面混输、共享组和词组歧义；
`tests/binary.lua`负责损坏文件、写入失败、组编号边界和快照生命周期。
旧 Lua matcher、Cursor、查表引擎及其自测已删除，不再维护第二套匹配实现。

Demos verify successful jump, char repeat, remote deletion and offscreen search.
Flash regression tests retain only cases outside those recordings: label placement,
codepoint input, counted/operator motions, cancellation, buffer edits and dictionary
changes between asynchronous batches. Generator/tutorial checks run with demo CI,
not the default core suite.

Matching is tested by feature using three reproducible generated maps, with explicit
expected results and small independent group expansion / interval-selection checks.
No external dictionaries or legacy Lua matcher are required. The old Lua matcher,
Cursor and lookup implementation, including their self-tests, have been removed.

```sh
nvim --clean -l lua/flash-any/compiler.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/run.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/flash.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/char.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/search.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/search_repeat.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/search_repeat.lua .dev/flash.nvim preserve
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/search_async.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/search_input.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/remote.lua
CFLAGS='-O1 -g -fsanitize=undefined -fno-sanitize-recover=undefined' nvim --clean -l lua/flash-any/compiler.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/text.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/binary.lua
nvim --clean -l lua/flash-any/compiler.lua
lua-language-server --check=. --checklevel=Hint
```

核心测试在 Linux 的 Neovim 0.11.0 与 0.12.6 上验证；历史 make 版本对照不再适用。
测试使用隔离的插件副本，覆盖首次编译、失效重编译、损坏修复、失败保留旧产物、
并发请求合并、主循环响应及首次 Flash 原生回退。
The core suite covers native compilation and fallback in isolated plugin copies;
run it with both the minimum supported and current Neovim versions.

Flash checkout放在.dev/flash.nvim。`tests/text.lua`用官方Unicode测试数据校验C的
字素边界与非法字节。demo生成与教程命令单独运行：
`nvim --clean -l tests/demo.lua`、`nvim --clean -l tests/source_guide.lua`。
历史性能数字保留在benchmarks文档中；当前入口见[scripts说明](../scripts/README.md)。
LuaLS配置包含真实Neovim/Flash库与测试模块路径，保留全部诊断级别。

clangd的`--check`还自测代码动作；本机SwapBinaryOperands对Lua宏有重叠替换错误。
使用`--tweaks=ExtractFunction`避开这个动作自测，但保留全部源文件诊断；项目未
配置诊断抑制。分别检查src/native.c、src/binary.c、src/scan.c、src/native.h及src/text.h，
确认生成头和随附公开Lua/C头可解析。

Tests cover generated dictionary behavior, Unicode boundaries, Flash regressions,
malformed packages and GC lifetimes. Full LuaLS checks
use the real Neovim/Flash libraries. Clangd's macro code-action self-test issue is
separate from source diagnostics; no project diagnostic suppression is installed.

历史性能对照见 [benchmarks](benchmarks.md)，当前架构以后续C-only收敛记录为准。

历史上游码表验证结果见[记录](dictionary-tests.md)。逐表测试工具已移除；
当前由通用格式导入测试和生成码表的功能测试覆盖核心行为，source 特有转换由各包维护。

Upstream dictionary results are historical. Per-dictionary runners were removed;
core tests cover import formats and generated-table behavior. Source-specific
conversion belongs to the corresponding source packages.

以下版本小节记录各功能引入时的格式；当前布局以上文v14为准。
The versioned sections below describe historical introductions; v14 above defines the current layout.

## 可选后缀与二进制 v7 / Optional suffixes and binary v7

Lua 按每个编码的权重和原始顺序分配选键，默认首选空格、次选分号。
每个编码只存一份，分配选键的记录使用 suffix matcher：标签、参数长度、ASCII
后缀、原始编码。没有选键的候选继续使用完整码 matcher。C 不读取权重或排名。
后缀匹配始终保留原码消费分支，匹配后缀时再增加一个消费长度；部分后缀产生 next。
不维护全组选键的拒绝集合，后续文字可正常消费与选键相同的输入。

字节编号规划（未分配的编号当前均拒绝，不代表已经实现）：

| 范围 | 用途 |
| --- | --- |
| 0x00–0x7F | ASCII 编码或参数；参数由长度界定 |
| 0x80–0x9F | matcher 标签；目前 0x80 literal、0x81 full、0x82 initial、0x83 prefix、0x84 suffix |
| 0xA0–0xBF | 预留的小模式操作码，目前未使用 |
| 0xC0–0xFF | 后续扩展保留 |

格式 v7 的自动缓存会重建；显式旧 binary 需重新导出。更新后重启 Nvim 加载新模块。

Lua assigns suffixes at build time; weights and ranks are not serialized. A suffix
record stores its matcher tag, parameter byte count, ASCII suffix and original code.
The C matcher always retains base-code consumption, optionally consumes the suffix,
and emits next for a partial suffix. Following glyphs may consume identical keys;
there is no global selector rejection set. Base codes are never expanded into aliases.
Matcher tags occupy 0x80–0x9F (currently five modes); 0xA0–0xBF is reserved for future
pattern operators and 0xC0–0xFF for later extensions. All unassigned tags currently
fail validation. Version 7 invalidates automatic caches; rebuild explicit old binaries
and restart Nvim after updating.


## 共享音节与二进制 v8 / Shared syllables and binary v8

全拼字表保存标准读音，构建时为读音分配 u16 ID；每个音节的所有模糊拼写只存一次。
用户仍选 full_code、initial、prefix。标签低位 0x08 表示音节引用：0x89、0x8A、0x8B
分别对应这三种模式，后接两字节 little-endian ID；普通编码仍使用 0x81–0x83。
六种组合复用 match_spelling，不维护六套 matcher。literal、suffix 不能设置引用标志。

40 字节文件头的偏移 32 保存音节区字节数，偏移 36 仍为零；音节区紧跟字符串池。
音节区为 u16 音节数，各音节为 u16 拼写数，再逐项保存 u8 长度和 ASCII 拼写。
C 负责写入、验证和解码；Lua 只组织 ID 与拼写数组，不拼装二进制字段。
音节的运行时视图由引擎持有并在 new_state 间共享，与底层字节一同保活。
扫描只在遇到引用时比较该音节的拼写，保留每个拼写的匹配和 next；不预建输入图，
不保存跨输入匹配缓存。全拼和双拼均使用共享音节组，工厂只生成 groups 并声明
文件路径，逐字数据统一由核心构建器读取。

Full pinyin stores canonical readings and shares fuzzy spellings per syllable.
A 0x08 flag in the matcher tag selects a u16 syllable reference instead of inline
ASCII: 0x89/0x8A/0x8B use the same full/initial/prefix implementation as 0x81/0x82/0x83.
Literal and optional-suffix records cannot carry the flag. Header offset 32 stores
the byte size of the profile appended after the string pool; offset 36 remains zero.
C owns its codec and validates every reference. Immutable spelling views and backing
bytes belong to the engine and are retained by child states. Spellings are matched
on demand, preserving all alternatives and next bytes without an input graph or
cross-input match cache. Both full and double pinyin now share syllable groups.
Factories generate groups and declare file paths; the core reads character data.

v8 会使自动缓存重新构建；显式旧 binary 需重新导出，更新后重启 Nvim。
Version 8 rebuilds automatic caches; regenerate explicit old binaries and restart
Nvim after updating. Previous format descriptions above document their original revisions.


## Source 外置与通用组 / External sources and shared groups

核心 Lua/C 不再识别拼音或虎码名称。groups.h 保存通用编码组视图和 codec，
GROUP_FLAG=0x08 与 full/initial/prefix 正交；二进制布局仍为 v8，无格式迁移。
组名只在 source 内解析，构建器按排序去重后的拼写内容分配全局 ID，避免多个
source 使用相同组名时互相覆盖。选键排名由 table.selectors 负责，build.selectors 保留原入口，C 只认识后缀。
source 自行维护数据、分音/模糊音/键位转换、默认选键及字符覆盖。

五个独立插件根目录在独立的 source checkout，未纳入核心仓库，尚未发布远程。
只有安装到 runtimepath 的工厂才参与发现；核心可用 sources={} 单独运行。
更新 source 数据时推进 source 版本号，使自动缓存失效。
核心不负责下载、更新 source；source 插件无 C 编译步骤。

The core has no pinyin/Tiger name dispatch. groups.h owns the generic v8 spelling
codec; local names are resolved before groups are interned by normalized contents.
Ranking belongs to table.selectors (also exposed as build.selectors); the C engine sees only optional suffix metadata.
Source packages own tables, conversions and defaults. They are separately installed
runtimepath plugins and have no compilation step. Local publication-ready directories
are under .dev/source-packages; public source releases are not yet available.

```
nvim --clean -l lua/flash-any/compiler.lua
nvim --clean -l tests/run.lua
FLASH_ANY_SOURCE_PATH="$PWD/.dev/source-packages" nvim --clean -l tests/run.lua
```

The default suite needs no source tables. The opt-in integration suite requires
pinyin, japanese, tiger and nerdfont; it also checks wubi86 and unicode when installed.
Demo CI installs the four published source repositories from the repository owner
by default; FLASH_ANY_SOURCE_OWNER overrides that owner. Core CI uses fixtures.


Demo generator tests also need fontconfig (fc-match/fc-query) and JetBrainsMono Nerd Font Mono plus CJK/emoji fonts;
these are developer/recording dependencies, not plugin install dependencies.
录制生成器测试需要 fontconfig、JetBrainsMono Nerd Font Mono 与 CJK/emoji 字体；不增加插件安装依赖。

## 字母规则 / Letter rules

格式 v10 的 `letter` matcher（内部 ID 5，共享拼写 ID 13）合并首码点匹配和
大小写策略。完整字素照常查表；含多码点时，额外查一次首码点，仅执行其中的
`letter` 规则，消费整个字素。两路共用原有候选、消费请求和标签避让，不增加
独立扫描或缓存。码表不含 `letter` 时跳过额外查询，是否包含由 C 加载时记录。

输入按完整编码消费，大小写策略由 Lua 读取 Neovim 选项后交给 C；literal 同样
遵循该策略。其他规则保持精确比较。自动缓存会重建，显式旧 binary 需重新导出；
更新后重启 Neovim。

Version 10's `letter` matcher (internal ID 5, shared spelling ID 13) combines head
codepoint matching and case policy. Whole graphemes retain their dictionary lookup;
compound graphemes also look up their first codepoint, using only its `letter` rules.
Both paths consume the entire glyph and share candidate/request/label handling.
C records whether the loaded dictionary contains letter rules and skips the extra
lookup otherwise. There is no separate scan or cache.

Input consumes full codes and follows the effective Neovim case policy, as literal
does. Other rules remain exact. Automatic caches rebuild; regenerate explicit older
binaries and restart Neovim after updating.

## Unicode 字面匹配 / Unicode literal matching

匹配结果仍只有两种语义：消费输入 byte 数，或返回 next 键集合（可以为空）。
C 内部的 PREVIEW 是“空 next”的表示，不是第三种匹配结果。

literal 比较输入与完整文本字素的 byte 前缀。输入较短且是字素前缀时，通过
PREVIEW 事件生成整字素候选，next 为空，不消费剩余字素、不推进到下一文本字素。
不额外校验输入的 UTF-8 完整性。输入覆盖完整字素时按原文字节数消费。
ASCII 延用字典内快路径，其他字素直接比较，不扩大字典、不预建输入索引。
文本仍单次前向扫描。ASCII 字面匹配遵循大小写选项，其他字素不做大小写折叠或规范化。

next 是标签避让信息，与输入消费事件分开。完整匹配的下一字素可作为后续原文
输入：ASCII key 使用位集；其他字素保留行内 offset/length，从现有行快照恢复，
物化所有码点前缀。预览不预留剩余后缀，因此 Unicode 标签可能抢占后续输入；
常见重音和 emoji 后缀不是 ASCII，默认 ASCII 标签可正常输入这些序列。
完成消费的 letter/码表分支仍可独立贡献 next，与 literal 预览的空 next 合并。

冻结 Lua 扫描器通过测试内 literal 适配器对照 ASCII 输入和码表分支；Unicode
输入在 `tests/literal.lua` 单独覆盖，真实 Flash 输入循环验证逐码点输入组合字符。
二进制数据格式和缓存所有权不变。

Matching retains two result semantics: consume an input byte count, or return a
possibly empty next-key set. The internal PREVIEW event represents empty next keys,
not a third kind of matching result.

Literal compares byte prefixes of input and the complete text grapheme. A shorter
query that prefixes a glyph emits PREVIEW: a whole-glyph candidate with empty next
keys, without consuming the remaining suffix or advancing to the next text glyph.
Input receives no additional UTF-8 validation. Full glyphs consume their byte length.
ASCII retains its dictionary fast path; other glyphs compare text directly without
extra entries or query indexes. Text remains a single forward scan. Case options
apply to ASCII literals; other glyphs have no case folding or normalization.

Next keys reserve labels independently of consumption events. After a completed
match, ASCII keys use a bitset and other glyphs retain row-relative offset/length
slices into the saved lines. Materialization exposes all codepoint prefixes. Preview
suffixes are not reserved, so Unicode labels may steal subsequent input; default
ASCII labels work for common combining marks and emoji suffixes. Consumed letter or
code-table branches contribute next keys independently of the empty literal preview.

A test-local literal adapter lets the frozen scanner check ASCII queries and table
branching. `tests/literal.lua` covers Unicode queries, and real Flash input-loop
tests cover codepoint-by-codepoint entry. Binary layout and cache ownership remain
unchanged.

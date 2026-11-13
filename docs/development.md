# 实现与验证 / Implementation and validation

## 边界 / Boundaries

运行时只有 C 后端。`setup` / `jump(opts)` / `remote(opts)` 接收 `sources` 或 `binary`；
缺失二进制时自动构建，码表工厂和转换仅在构建阶段执行。不提供 Lua matcher、输入/文本 Cursor 或按需 loader 扩展。
键支持完整字素和词组，连续输入可以连接多个词条。词组只从字素边界开始和结束，不跨行。

Runtime is C-only. Setup builds a missing package from sources or loads an existing
binary. Lua factories/converters execute only while building. Keys can be complete
graphemes or phrases; input can consume several entries. Phrase boundaries must be
grapheme boundaries, and entries cannot span buffer lines.

字表内容决定收录范围，构建器不另做字符范围过滤。需要删条目时更新码表，或由
converter 返回 nil/空数组。fallback 按完整文字key合并，空编码列表也阻止后续同key的fallback。
Dictionary contents define coverage; the builder applies no separate character-range
filter. Remove entries in the dictionary or return nil/an empty array from a converter.
Fallback merges by exact text key; empty lists also block later fallback codes for that key.

## 模块 / Modules

- `build.lua`、`source.lua`、`table.lua`、`tsv.lua`：构建时读取完整数据、
  转换、校验、过滤和合并。Lua Unicode 分段器用于构建及测试参考。
- `src/text.h`：严格UTF8解码及Unicode17扩展字素分段，只保留当前分段状态；没有
  文本索引数组、Cursor方法或Lua逐字素回调。
- `src/binary.c`：二进制序列化、共享编码组、索引构建、完整校验、文件读取与原子写入。
- `src/scan.c`：单趟字素扫描、编码匹配、请求推进、候选合并、下一输入键收集与构建时字素枚举。
- `src/trie.c`：构建普通码点双数组Trie；宽节点优先放置，临时树和空闲链只在构建时存在。
- `src/native.c`：Lua入口、窗口行/结果缓存、标签分配与f/F/t/T位置转换。
  状态/临时存储由Lua userdata拥有，避免额外malloc生命周期。
- `src/native.h`：内部共享类型、格式常量与内联字典查询；匹配上下文只在`scan.c`内定义。
- `native.lua`、`init.lua`、`char.lua`：Neovim文本IO及Flash桥接，Flash仍管理按键、
  操作符、窗口、remote恢复和绘制。Flash要求的Lua matcher回调只是C入口。

已有二进制时不加载source或字素模块；外部file的依赖检查只加载构建器的文件读取部分。
缺失时按sources构建。Lua的grapheme.lua只封装C的each/len，UTF-8解码和UAX #29
规则仅在text.h中实现；构建和扫描共用同一实现。旧Lua算法仅在tests/reference中作为独立对照。
`tests/runtime.lua`和`tests/autobuild.lua`在独立进程中验证这两个路径。

Cached external files load only the dependency-reading portion of the builder,
without grapheme/source modules. Build-time grapheme counting and enumeration call
the same C decoder and boundary rules used by scanning. The Lua grapheme module
is a thin adapter; the old Lua algorithm lives only in tests/reference as an
independent oracle. Bundled Unicode input data lives under scripts/data.
Explicit binaries and cached built-in sources load without Lua builders or scanners. Fresh-process tests
cover missing/broken native modules, external make, automatic dictionary compilation
and persistent-cache reuse. Loading/setup never invokes a compiler.

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

用户需要make和C工具链（GCC或Clang）；`make`直接编译C，不调用Neovim、Python、
pkg-config或系统LuaJIT开发包。Makefile使用GNU make 3.81兼容语法，支持CC、
CPPFLAGS、CFLAGS和LDFLAGS覆盖。`vendor/luajit`内置未修改的公开Lua/C头文件，
符号从宿主Neovim解析，不链接第二份LuaJIT。Linux已验证，macOS的
bundle/dynamic_lookup路径待实机验证。

Unicode数据的来源是`scripts/data/grapheme_data.lua`，生成的`src/grapheme_data.h`随源码提交。
维护者更新数据后运行`nvim --clean -l scripts/generate_grapheme.lua`并提交两份数据；
安装构建不会运行生成器。`compile_flags.txt`为clangd提供静态编译参数，无需生成
compile_commands.json；旧的编译数据库可以删除。

native.lua直接加载native.so，不检查源码mtime、不调用编译器；缺失或加载失败时提示
在插件目录执行make。插件管理器或用户负责安装/更新时运行make。Makefile是编译参数
和平台分支的唯一来源；编译到临时文件后原子替换native.so，避免影响已加载的进程。
Lua-owned userdata持有码表快照和匹配结果，状态表持有原始行。

native.load统一拥有码表缓存路径和构建：未指定binary时，按sources的稳定inspect
表示和C导出的格式/Unicode版本计算SHA256，放入stdpath("cache")/flash-any/。
不存在时创建目录并调用build.binary；存在时直接打开。显式binary优先使用固定路径。
外部词典、Rime导入、lua/tsv及converter按绝对路径、大小和mtime（秒/纳秒）生成缓存键，
修改后下次setup生成新快照。UTF-8 Rime只读头部发现导入，其他编码的自动检测/Rime
仍复用整文件解码；显式非Rime格式只需stat。
runtimepath中lua/flash-any下的Lua/TSV同样参与缓存键，每进程检查一次，与require生命周期一致。
更新插件后重启Nvim；无需执行工厂或加载码表即可检查缓存。大小/mtime均未改变的编辑
不能检测；命名空间外的任意Lua间接依赖不自动跟踪。显式binary仅在缺失时构建。

Make directly invokes the C compiler; GNU make 3.81 syntax is sufficient. Unicode
headers are committed, and regeneration is a maintainer-only step. Bundled public
Lua/C headers and compile_flags.txt keep builds and clangd independent of local
LuaJIT development packages. Plugin managers or users run make on installation and
updates; loading native.so never builds it and reports actionable load errors.
The dictionary loader owns cache paths;
external dictionary, Rime import, Lua/TSV companion and converter paths, sizes and
nanosecond mtimes select cache snapshots. UTF-8 Rime dependency discovery reads headers
only; non-UTF-8 auto/Rime input still uses whole-file decoding. Installed Lua/TSV files
under lua/flash-any are checked once per process, requiring a restart after updates.
Changes preserving both size and mtime, and arbitrary Lua dependencies outside this
namespace, require explicit rebuilding.

## 码表 / Dictionary

按source顺序处理fallback，再合并`(matcher模式, 编码)`。空编码集合
也算认识，会屏蔽后续fallback但不产生匹配。ASCII literal构建为127个非NUL键，普通源
仍可为ASCII附加编码。非 ASCII 或多码点字素不依赖码表，直接比较原文；
fallback 的码表合并规则不因原文字面匹配而改变。运行时不保留source身份或fallback状态。

当前格式为`FANYBIN\x0D`（v13）。单码点页表和按节点取模的码点DAT共享编码池：

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
是对应模式的u16组引用。普通编码标记兼作模式与分隔，不保存逐编码长度。
编码、后缀和组内拼写禁止NUL；组内拼写保留u8长度，组ID按固定两字节读取。
文本或查询含NUL时，匹配行为不作保证，不增加专门的扫描分支。

加载时校验页表归属与占用、DAT父节点及标签、终点数、环引用、终点不能有子节点，
并校验编码偏移、列表语法及组引用。父链深度用临时数组记忆，每个单元最多遍历
两次；同时求最长key码点数。加载后只保留原始只读字节，不重建索引或保留校验数组。
输出前复用完整加载校验，之后原子替换文件。自动缓存因v13版本变化重建；显式
binary需要重新导出，make后重启Nvim。

Version 13 stores scalar offsets in a two-level page table and text keys in a
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
for v13; automatic caches rebuild and Nvim must restart after make.

Lua仅传递排序后的文字key及`{模式, 编码}`列表，C负责标记编码、共享池、偏移、索引、
文件头和写入；二进制规则不在Lua重复实现。完整输出先复用读取端校验，再在目标
目录创建临时文件、写入、关闭并rename；失败清理临时文件，保留原输出。

Lua supplies sorted text keys and mode/code pairs. C owns serialization and file IO,
including tagged lists, shared pools, indexes and headers. The loader validates the
complete package before writing; replacement uses a temporary file in the output directory.

`open`用fread直接读入冻结userdata，避免Lua IO的额外完整字符串和mmap原地改写
问题。不同Flash state共享只读码表，分别拥有行/查询缓存；按buffer/changedtick
失效，随state回收。重新setup加载新快照，不改变已有搜索。

Each snapshot owns both immutable tables and their tagged ASCII code lists. Bounds, tags and
index reachability are validated at load time. Package replacement is atomic. Existing
states pin their snapshot; per-state line/result caches expire with their buffer tick.

## 扫描 / Scanning

单字素与词组共用一次前向扫描，不再维护单字素hash快路径。每解码一个码点，
同步更新Unicode字素边界，并推进所有活动Trie状态；失败即移除。每个字素起点
加入根状态，字素内部不启动新前缀。预读的码点直接用于下一字素，不重复解码。
单码点规则查页表，其他终点从DAT的0标签边读取编码，仅在完整字素边界匹配；转移校验父节点和商。

请求按文字起点和输入字节偏移合并，保留最早起点。环形工作区为最长key码点数+1，
至少两槽；词条完成后把消费请求发往下一字素。完成输入的候选保留结果编号，后续
单字或词组补充next键；结果扩容后通过编号重新取址。候选只在实际命中时增长。
文字、字面输入、普通编码、initial/prefix、letter、共享编码组沿用同一匹配逻辑。
跨行状态不保留；f/F/t/T认可词组时使用第一个字素及其相邻位置。

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

## 测试与 LSP / Tests and LSP

```sh
make -B
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/run.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/flash.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/char.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/remote.lua
make -B CFLAGS='-O1 -g -fsanitize=undefined -fno-sanitize-recover=undefined'
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/text.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/native.lua
make -B
lua-language-server --check=. --checklevel=Hint
```

Linux已实测Neovim 0.11.0 + GNU make 3.81，以及系统Neovim 0.12.6 + make 4.4.1。
旧版本工具安装在忽略的.dev目录，不替换系统工具；切换方法：

```sh
export PATH="$PWD/.dev/make-3.81/bin:$PWD/.dev/nvim-0.11.0/bin:$PATH"
make clean
make -j4
nvim --clean -l tests/autobuild.lua
```

Both Neovim 0.11.0 / GNU make 3.81 and Neovim 0.12.6 / GNU make 4.4.1 passed
the full test suite on Linux, including real Flash jump, char and remote integration.
The `.dev` tool installations are local and are not distributed with the plugin.

Flash checkout放在.dev/flash.nvim。`tests/text.lua`直接校验C的官方Unicode字素边界
与非法字节；native测试对照冻结Lua参考实现。`tests/reference/`只作为测试oracle，
不在插件runtimepath，不提供运行时兼容API。旧Cursor及Lua扫描实验脚本已经清理，
历史性能数字保留在benchmarks文档中；当前工具入口见[scripts说明](../scripts/README.md)。
LuaLS配置包含真实Neovim/Flash库与测试模块路径，保留全部诊断级别。

clangd的`--check`还自测代码动作；本机SwapBinaryOperands对Lua宏有重叠替换错误。
使用`--tweaks=ExtractFunction`避开这个动作自测，但保留全部源文件诊断；项目未
配置诊断抑制。分别检查src/native.c、src/binary.c、src/scan.c、src/native.h及src/text.h，
确认生成头和随附公开Lua/C头可解析。

Tests keep the old Lua implementation solely as an independent oracle under tests.
Production does not load it. Unicode boundaries, native/Lua differential behavior,
Flash integration, malformed packages and GC lifetimes are covered. Full LuaLS checks
use the real Neovim/Flash libraries. Clangd's macro code-action self-test issue is
separate from source diagnostics; no project diagnostic suppression is installed.

历史性能对照见 [benchmarks](benchmarks.md)，当前架构以后续C-only收敛记录为准。

## 真实上游码表 / Real upstream dictionaries

可选运行 `python scripts/check_dictionaries.py --download --nvim .dev/nvim-0.11.0/bin/nvim`。
Python 和 iconv 仅用于这套开发测试，不增加插件构建或运行依赖。下载文件和报告位于
忽略的 `.dev/real-tables`，固定版本及校验和在 `tests/data/dictionaries.json`。
见 [测试范围与结果](dictionary-tests.md)。

The optional upstream corpus suite compares every text/code pair using an independent
Python reader and samples C matches. Python/iconv are developer-test dependencies only.
Downloaded data and reports stay in .dev; normal tests and plugin setup require no network.

以下版本小节记录各功能引入时的格式；当前布局以上文v13为准。
The versioned sections below describe historical introductions; v13 above defines the current layout.

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

格式 v7 的自动缓存会重建；显式旧 binary 需重新导出。make 后重启 Nvim 加载新模块。

Lua assigns suffixes at build time; weights and ranks are not serialized. A suffix
record stores its matcher tag, parameter byte count, ASCII suffix and original code.
The C matcher always retains base-code consumption, optionally consumes the suffix,
and emits next for a partial suffix. Following glyphs may consume identical keys;
there is no global selector rejection set. Base codes are never expanded into aliases.
Matcher tags occupy 0x80–0x9F (currently five modes); 0xA0–0xBF is reserved for future
pattern operators and 0xC0–0xFF for later extensions. All unassigned tags currently
fail validation. Version 7 invalidates automatic caches; rebuild explicit old binaries
and restart Nvim after make.


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

v8 会使自动缓存重新构建；显式旧 binary 需重新导出，make 后重启 Nvim。
Version 8 rebuilds automatic caches; regenerate explicit old binaries and restart
Nvim after make. Previous format descriptions above document their original revisions.


## Source 外置与通用组 / External sources and shared groups

核心 Lua/C 不再识别拼音或虎码名称。groups.h 保存通用编码组视图和 codec，
GROUP_FLAG=0x08 与 full/initial/prefix 正交；二进制布局仍为 v8，无格式迁移。
组名只在 source 内解析，构建器按排序去重后的拼写内容分配全局 ID，避免多个
source 使用相同组名时互相覆盖。选键排名由 build.selectors 负责，C 只认识后缀。
source 自行维护数据、分音/模糊音/键位转换、默认选键及字符覆盖。

五个独立插件根目录在独立的 source checkout，未纳入核心仓库，尚未发布远程。
只有安装到 runtimepath 的工厂才参与发现；核心可用 sources={} 单独运行。
更新 source 的 lua/flash-any 下 Lua/TSV 文件会进入已有元数据缓存失效机制。
核心不负责下载、更新 source；source 插件无 C 编译步骤。

The core has no pinyin/Tiger name dispatch. groups.h owns the generic v8 spelling
codec; local names are resolved before groups are interned by normalized contents.
Ranking belongs to build.selectors; the C engine sees only optional suffix metadata.
Source packages own tables, conversions and defaults. They are separately installed
runtimepath plugins and have no compilation step. Local publication-ready directories
are under .dev/source-packages; public source releases are not yet available.

```
make
nvim --clean -l tests/run.lua
FLASH_ANY_SOURCE_PATH="$PWD/.dev/source-packages" nvim --clean -l tests/run.lua
```

The default suite needs no source tables. The opt-in integration suite checks all
five real packages. Demo CI needs published source repositories and repository variable
FLASH_ANY_SOURCE_OWNER; core CI runs independently while that variable is unset.


Demo generator tests also need fontconfig (fc-match/fc-query) and CJK/emoji fonts;
these are developer/recording dependencies, not plugin install dependencies.
录制生成器测试需要 fontconfig 与 CJK/emoji 字体；不增加插件安装依赖。

## 字母规则 / Letter rules

格式 v10 的 `letter` matcher（内部 ID 5，共享拼写 ID 13）合并首码点匹配和
大小写策略。完整字素照常查表；含多码点时，额外查一次首码点，仅执行其中的
`letter` 规则，消费整个字素。两路共用原有候选、消费请求和标签避让，不增加
独立扫描或缓存。码表不含 `letter` 时跳过额外查询，是否包含由 C 加载时记录。

输入按完整编码消费，大小写策略由 Lua 读取 Neovim 选项后交给 C；literal 同样
遵循该策略。其他规则保持精确比较。自动缓存会重建，显式旧 binary 需重新导出；
make 后重启 Neovim。

Version 10's `letter` matcher (internal ID 5, shared spelling ID 13) combines head
codepoint matching and case policy. Whole graphemes retain their dictionary lookup;
compound graphemes also look up their first codepoint, using only its `letter` rules.
Both paths consume the entire glyph and share candidate/request/label handling.
C records whether the loaded dictionary contains letter rules and skips the extra
lookup otherwise. There is no separate scan or cache.

Input consumes full codes and follows the effective Neovim case policy, as literal
does. Other rules remain exact. Automatic caches rebuild; regenerate explicit older
binaries and restart Neovim after make.

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

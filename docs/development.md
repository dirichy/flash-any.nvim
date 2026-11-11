# 实现与验证 / Implementation and validation

## 边界 / Boundaries

运行时只有 C 后端。`setup` / `jump(opts)` / `remote(opts)` 接收 `sources` 或 `binary`；
缺失二进制时自动构建，码表工厂和转换仅在构建阶段执行。不提供 Lua matcher、输入/文本 Cursor 或按需 loader 扩展。每个键须恰好一个完整字素，连续输入
可以跨字素匹配。多字素词条构建时报错，不为未来词组预留运行时兼容层。

Runtime is C-only. Setup builds a missing package from sources or loads an existing
binary. Lua factories/converters execute only while building. Keys are complete
single graphemes; continuous input crosses graphemes. Word entries are rejected.

字表内容决定收录范围，构建器不另做字符范围过滤。需要删条目时更新码表，或由
converter 返回 nil/空数组。fallback 仍按此前码表是否认识该字素判断。
Dictionary contents define coverage; the builder applies no separate character-range
filter. Remove entries in the dictionary or return nil/an empty array from a converter.
Fallback still depends on whether earlier dictionaries recognized the grapheme.

## 模块 / Modules

- `build.lua`、`source.lua`、`table.lua`、`tsv.lua`：构建时读取完整数据、
  转换、校验、过滤和合并。Lua Unicode 分段器用于构建及测试参考。
- `src/text.h`：严格UTF8解码及Unicode17扩展字素分段，只保留当前分段状态；没有
  文本索引数组、Cursor方法或Lua逐字素回调。
- `src/native.c`：二进制序列化、原子写入、加载、统一字素索引查询、请求推进、候选合并、标签避让、
  f/F/t/T识别。状态/临时存储由Lua userdata拥有，避免额外malloc生命周期。
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

Review C时，可先读`text.h`的`decode`/`grapheme_break`，再沿`native.c`的
`scan_line → scan_grapheme → match_codes → emit/request`阅读。二进制读写单独看
`write_binary`和`load_data`；`scan`负责Lua参数、缓存及GC根。源文件中的短注释
说明跨调用的状态、位置单位和借用指针约束；`.clang-format`统一C排版。

For review, start with decoding/boundaries, then follow the scanner into matching
and request emission. Package IO is separate; `scan` owns Lua stack roots and caches.
Format production C with `clang-format -i src/native.c src/text.h`.

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
也算认识，会屏蔽后续fallback但不产生匹配。ASCII literal构建为128个键，普通源
仍可为ASCII附加编码。非 ASCII 或多码点字素不依赖码表，直接比较原文；
fallback 的码表合并规则不因原文字面匹配而改变。运行时不保留source身份或fallback状态。

格式`FANYBIN\x0A`，40-byte头：magic8及little-endian u32的Unicode版本17、总大小、
条目数、哈希容量、页数、pool字节数、编码组区字节数和一个保留0。随后为16-byte条目（key及编码
列表的offset/length）、复杂字素哈希槽、4352个u32页目录及每个实际页的256槽，
随后是共享byte pool及编码组区。槽存条目序号+1，0为空。相同带标记编码列表共享pool片段。

列表为`[标记][ASCII编码][标记][ASCII编码]...`：0x80 literal、0x81 full_code、
0x82 initial、0x83 prefix；组引用为0x89–0x8B，后跟u16 ID，详见末节。
普通编码标记兼作模式与分隔，不需要source ID或结束符，NUL
可以是编码内容。模式映射由C模块统一提供给构建器。加载校验区段/引用边界、
标记、literal内容、排序、占用及索引可达性。输出原子替换；旧格式需要重建。

Lua仅传递排序后的字素及`{模式, 编码}`列表，C负责标记编码、共享池、偏移、索引、
文件头和写入；二进制规则不在Lua重复实现。完整输出先复用读取端校验，再在目标
目录创建临时文件、写入、关闭并rename；失败清理临时文件，保留原输出。

Lua supplies sorted graphemes and mode/code pairs. C owns serialization and file IO,
including tagged lists, shared pools, indexes and headers. The loader validates the
complete package before writing; replacement uses a temporary file in the output directory.

`open`用fread直接读入冻结userdata，避免Lua IO的额外完整字符串和mmap原地改写
问题。不同Flash state共享只读码表，分别拥有行/查询缓存；按buffer/changedtick
失效，随state回收。重新setup加载新快照，不改变已有搜索。

Format v5 has one immutable dictionary and tagged ASCII code lists. Bounds, tags and
index reachability are validated at load time. Package replacement is atomic. Existing
states pin their snapshot; per-state line/result caches expire with their buffer tick.

## 扫描 / Scanning

每行边解码边匹配，不预建字素/码点/byte索引。解码得到一个码点时同步更新字素
边界状态及hash，确认完整字素后立即查表匹配。判断边界需要预读下一个码点，
预读值直接进入下一字素，不重复解码。单码点直接查页，复杂字素使用累计hash：
初值2166136261，每码点`h=(h^cp)*16777619`，uint32回绕。非法字节使用
`0x110000+原字节`作独立token；hash命中仍校验完整原文。

每字素查一次字典，列表复用给该位置的所有输入状态。按字素/输入byte offset
合并请求，保留最早起点，固定两槽工作区推进；C处理完整/首字母/前缀消费、
候选合并及next-key标签避让。每字素只用一个临时候选，命中后追加到按需增长的
结果数组；不为所有字素预分配结果槽。相同输入复用结果；输入改变时重新解码并
匹配缓存的原始行，不从上一轮候选筛选，也不保留跨输入的匹配进度。两槽请求仅
在本轮扫描内推进。跨独立跳转只复用码表。f/F/t/T在前向扫描时
记录相邻字素位置；Lua适配器按需逐行请求屏幕外目标，避免提前扫描整个buffer。

The scanner decodes and matches in one forward traversal, retaining only grapheme
boundary state and the current glyph. It does not build per-line text indexes. Raw
lines and identical-query results are cached. Each changed query decodes and matches
the saved lines afresh, without filtering the previous candidate set or retaining
cross-query matching progress. The two request slots advance only within that scan.
Results grow only when a glyph matches. Lua handles editor/Flash integration.

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
配置诊断抑制。分别检查src/native.c及src/text.h，确认生成头和随附公开Lua/C头可解析。

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

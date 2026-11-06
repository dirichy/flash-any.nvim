# 实现与验证 / Implementation and validation

## 边界 / Scope

运行时只有 C 后端。`setup` / `jump(opts)` / `remote(opts)` 接收 `sources` 或 `binary`；
缺失二进制时自动构建，码表工厂和转换仅在构建阶段执行。不提供 Lua matcher、scope
回调、输入/文本 Cursor 或按需 loader 扩展。每个键须恰好一个完整字素，连续输入
可以跨字素匹配。多字素词条构建时报错，不为未来词组预留运行时兼容层。

Runtime is C-only. Setup builds a missing package from sources or loads an existing
binary. Lua factories/converters execute only while building. Keys are complete
single graphemes; continuous input crosses graphemes. Word entries are rejected.

## 模块 / Modules

- `build.lua`、`source.lua`、`table.lua`、`scope.lua`、`tsv.lua`：构建时读取完整数据、
  转换、校验、过滤和合并。Lua Unicode 分段器用于构建及测试参考。
- `src/text.h`：严格UTF8解码及Unicode17扩展字素分段，只保留当前分段状态；没有
  文本索引数组、Cursor方法或Lua逐字素回调。
- `src/native.c`：二进制序列化、原子写入、加载、统一字素索引查询、请求推进、候选合并、标签避让、
  f/F/t/T识别。状态/临时存储由Lua userdata拥有，避免额外malloc生命周期。
- `native.lua`、`init.lua`、`char.lua`：Neovim文本IO及Flash桥接，Flash仍管理按键、
  操作符、窗口、remote恢复和绘制。Flash要求的Lua matcher回调只是C入口。

已有二进制时不加载Lua构建器、source或字素模块；缺失时按sources构建。
`tests/runtime.lua`和`tests/autobuild.lua`在独立进程中验证这两个路径。

Existing packages load without Lua builders or scanners. Automatic compilation and
persistent-cache reuse are tested in fresh processes, including a missing native.so.

Review C时，可先读`text.h`的`decode`/`grapheme_break`，再沿`native.c`的
`scan_line → scan_grapheme → match_codes → emit/request`阅读。二进制读写单独看
`write_binary`和`load_data`；`scan`负责Lua参数、缓存及GC根。源文件中的短注释
说明跨调用的状态、位置单位和借用指针约束；`.clang-format`统一C排版。

For review, start with decoding/boundaries, then follow the scanner into matching
and request emission. Package IO is separate; `scan` owns Lua stack roots and caches.
Format production C with `clang-format -i src/native.c src/text.h`.

## 构建 / Build

运行 `make`（GNU make4.3+）需要Python3、C编译器、pkg-config、LuaJIT开发文件，
当前验证平台Linux。Unicode C数据由已入库的`grapheme_data.lua`生成，不使用另一个
Unicode规则源。码表快照和匹配结果保存在Lua-owned userdata中，原始行由状态表持有。

构建同时生成三个不入库的产物：

- `lua/flash-any/native.so`
- `build/grapheme_data.h`
- 根目录 `compile_commands.json`

曾经头文件只存在于自动删除的临时目录，导致clangd报找不到文件。现在保留于
build/，编译数据库直接记录实际命令和pkg-config给出的LuaJIT include路径。
native.lua首次加载时同步调用make，由Makefile维护依赖和更新；不硬编码机器库路径、
不关闭诊断。make clean只删除这三个产物。

native.load统一拥有码表缓存路径和构建：未指定binary时，按sources的稳定inspect
表示和C导出的格式/Unicode版本计算SHA256，放入stdpath("cache")/flash-any/。
不存在时创建目录并调用build.binary；存在时直接打开。显式binary优先使用固定路径。
不监控外部码表/工厂内容变化；修改这些文件后清除生成缓存，再次setup自动构建。

The native loader runs make once per process to check dependencies. It owns dictionary
cache paths and missing-package compilation. Automatic paths hash source configuration
and the format/Unicode version exported by C. Explicit binary paths take precedence;
external table/factory file contents are not watched.

The persistent generated header and exact compilation database support clangd. No
machine-specific include path is committed. Compilation does not require a dictionary
binary; dictionary compilation does not require loading Flash or user configuration.

## 码表 / Dictionary

按source顺序过滤scope、处理fallback，再合并`(matcher模式, 编码)`。空编码集合
也算认识，会屏蔽后续fallback但不产生匹配。ASCII literal构建为128个键，普通源
仍可为ASCII附加编码。运行时不保留source身份、scope或fallback状态。

格式`FANYBIN\5`，40-byte头：magic8及little-endian u32的Unicode版本17、总大小、
条目数、哈希容量、页数、pool字节数和两个保留0。随后为16-byte条目（key及编码
列表的offset/length）、复杂字素哈希槽、4352个u32页目录及每个实际页的256槽，
最后是共享byte pool。槽存条目序号+1，0为空。相同带标记编码列表共享pool片段。

列表为`[标记][ASCII编码][标记][ASCII编码]...`：0x80 literal、0x81 full_code、
0x82 initial、0x83 prefix。标记兼作模式与分隔，不需要source ID或结束符，NUL
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
结果数组；不为所有字素预分配结果槽。相同输入复用结果，改变输入重新解码缓存
的原始行，尚未保留增量匹配前沿。跨独立跳转只复用码表。f/F/t/T在前向扫描时
记录相邻字素位置；Lua适配器按需逐行请求屏幕外目标，避免提前扫描整个buffer。

The scanner decodes and matches in one forward traversal, retaining only grapheme
boundary state and the current glyph. It does not build per-line text indexes. Raw
lines and identical-query results are cached; changing input decodes the saved lines
again. Results grow only when a glyph matches. Lua handles editor/Flash integration.

## 测试与 LSP / Tests and LSP

```sh
make
for test in tests/autobuild.lua tests/init.lua tests/runtime.lua tests/source.lua tests/table.lua tests/scope.lua tests/build.lua tests/health.lua tests/text.lua tests/native.lua tests/tsv.lua tests/utf8.lua tests/reference_cursor.lua tests/reference_match/*.lua tests/flash.lua tests/char.lua; do
  NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l "$test" || exit
done
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean --headless -u tests/remote.lua
python scripts/build_native.py --sanitize
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/text.lua
NVIM_LOG_FILE=/tmp/flash-any-test.log nvim --clean -l tests/native.lua
python scripts/build_native.py
lua-language-server --check=. --checklevel=Hint
```

Flash checkout放在.dev/flash.nvim。`tests/text.lua`直接校验C的官方Unicode字素边界
与非法字节；native测试对照冻结Lua参考实现。`tests/reference/`只作为测试oracle，
不在插件runtimepath，不提供运行时兼容API。旧Cursor及Lua扫描实验脚本已经清理，
历史性能数字保留在benchmarks文档中；当前工具入口见[scripts说明](../scripts/README.md)。
LuaLS配置包含真实Neovim/Flash库与测试模块路径，保留全部诊断级别。

clangd的`--check`还自测代码动作；本机SwapBinaryOperands对Lua宏有重叠替换错误。
使用`--tweaks=ExtractFunction`避开这个动作自测，但保留全部源文件诊断；项目未
配置诊断抑制。分别检查src/native.c及src/text.h，确认生成头和真实LuaJIT头可解析。

Tests keep the old Lua implementation solely as an independent oracle under tests.
Production does not load it. Unicode boundaries, native/Lua differential behavior,
Flash integration, malformed packages and GC lifetimes are covered. Full LuaLS checks
use the real Neovim/Flash libraries. Clangd's macro code-action self-test issue is
separate from source diagnostics; no project diagnostic suppression is installed.

历史性能对照见 [benchmarks](benchmarks.md)，当前架构以后续C-only收敛记录为准。

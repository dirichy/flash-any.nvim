# 开发工具 / Development tools

Unicode 原始属性数据位于 `scripts/data/grapheme_data.lua`，不作为插件 Lua 模块加载。
Unicode source properties live in `scripts/data/grapheme_data.lua`, outside runtime modules.

从仓库根目录执行。运行 `make` 编译 C 模块，Makefile 使用兼容 GNU make 3.81
的语法，构建仅需要 make 和 C 工具链。Python 性能脚本使用 Linux CPU affinity，
不是用户安装依赖。维护者更新 Unicode 数据后运行
`nvim --clean -l scripts/generate_grapheme.lua`，提交生成的 `src/grapheme_data.h`。

Run from the repository root. `make` directly invokes the C compiler and uses
GNU make 3.81-compatible syntax. Python benchmark runners use Linux CPU affinity;
Python is not a plugin build dependency. Unicode header regeneration is a
maintainer-only step (`nvim --clean -l scripts/generate_grapheme.lua`).

| 入口 / Entry | 用途 / Purpose |
| --- | --- |
| `check_dictionaries.py [--download] [--nvim PATH]` | 固定版本真实码表全量对照与 C 匹配；默认离线，首次下载需 --download；编码派生测试还需 iconv / pinned upstream dictionary checks, optional download, iconv for derived encodings |
| `bench_scan.py BASELINE --samples 9` | 索引版与当前单趟C扫描对照；BASELINE须包含原版完整lua目录和native.so |
| `bench_cached.py --samples 9` | 原Lua常用字缓存、测试参考实现、当前C后端对照；原Lua版本从git读取 |
| `bench_cache.py --root BASELINE --samples 9` | 历史索引版的文本/结果缓存对照；需要索引版快照，不能使用当前单趟版 |
| `bench_merge.py BASELINE --samples 9` | 合表前后原生后端对照；需要合表前可运行快照 |
| `bench_binary.py` | 当前二进制的局部查询对照，调用bench_binary.c，可选MARISA |
| `bench_code_pool.py PACKAGE.bin ...` | 高频 matcher/编码记录的 1/2 字节字典体积原型；计入索引和字典开销并完整还原校验，输出不可供 C 加载的 .tokens / size-only token dictionary prototype with round-trip checks |
| `bench_pinyin.py --baseline-native V7_NATIVE.c --samples 7 --nvim PATH` | 需要共享音节接入前的 v7 native.c 快照。隔离 C 原型：预建输入图、按需音节 matcher、全拼可选字节，与现有展开码表对照；不修改生产模块 / v7-snapshot based prebuilt/direct syllable and optional-byte C prototypes |
| `bench_grapheme_hash.py` | 多码点字素hash实验，调用bench_grapheme_hash.c，需要Unicode17 emoji测试数据 |
| `bench_lua_matcher.py --samples 9` | 临时C模块调用单字素Lua matcher的成本对照；加`--multiple`比较多个matcher分别跨界和Lua内部批量分派，不增加生产接口 |
| `bench_native.lua` | 单进程Lua参考实现或C扫描测量；独立进程对照优先使用上面的Python入口 |
| `bench_binary_load.lua` | 单进程源数据或二进制加载测量 |
| `bench_tsv.lua` | 构建工具使用的TSV查询测量 |

`bench_merge.lua`、`bench_cached.lua`和`bench_cache.lua`是上述独立进程测试的驱动。
`bench_marisa.cc`仅是可选查询对照，不是生产依赖。具体命令和条件见各脚本头部、
`--help`及[性能记录](../docs/benchmarks.md)。

The Lua drivers support isolated-process comparisons. Snapshot-based experiments
require the original implementation and its compiled library. MARISA is optional
and never a production dependency. See script headers, `--help` and the benchmark
record for conditions and limitations.

## 保留与清理 / Retained references

旧Cursor、紧密码点字符串、预建边界、Lua matcher临时分配实验脚本已删除。
`tests/reference/`有差分测试和Lua/C对照消费者，因此保留为测试参考实现；
生产运行时不会加载它。历史数字保留在文档中，历史命令不代表当前API。

Obsolete Cursor, packed-codepoint, boundary-index and Lua matcher allocation
experiments were removed. The frozen Lua implementation remains under tests as
an oracle consumed by differential tests and benchmarks, outside production loading.

Source-specific table generators now live with their optional source packages;
the core retains only general import/export and Unicode grapheme tools. Historical
source benchmarks need those separate source plugins installed. Developer drivers
accept FLASH_ANY_SOURCE_PATH as the parent directory containing the plugin roots.
专用码表生成脚本已随独立 source 移出；历史 source 性能测试需要额外安装相应插件。
FLASH_ANY_SOURCE_PATH 指向包含这些插件目录的父目录，仅用于开发工具，不是插件配置。

# 开发工具 / Development tools

从仓库根目录执行。C相关工具先运行`make`；Python性能脚本使用Linux CPU affinity，
数据构建脚本沿用各自的`--help`。脚本不会发布或提交文件。

Run from the repository root; build with `make` before native benchmarks. Python
benchmark runners use Linux CPU affinity. Table generators document their arguments
with `--help`. Tools do not publish or commit files.

## 当前性能工具 / Current benchmarks

| 入口 / Entry | 用途 / Purpose |
| --- | --- |
| `bench_scan.py BASELINE --samples 9` | 索引版与当前单趟C扫描对照；BASELINE须包含原版完整lua目录和native.so |
| `bench_cached.py --samples 9` | 原Lua常用字缓存、测试参考实现、当前C后端对照；原Lua版本从git读取 |
| `bench_cache.py --root BASELINE --samples 9` | 历史索引版的文本/结果缓存对照；需要索引版快照，不能使用当前单趟版 |
| `bench_merge.py BASELINE --samples 9` | 合表前后原生后端对照；需要合表前可运行快照 |
| `bench_binary.py` | 当前二进制的局部查询对照，调用bench_binary.c，可选MARISA |
| `bench_grapheme_hash.py` | 多码点字素hash实验，调用bench_grapheme_hash.c，需要Unicode17 emoji测试数据 |
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

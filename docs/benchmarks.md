# Matcher 压力测试

复测日期：2026-11-01。运行命令（在仓库根目录）：

```sh
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_match.lua
```

## 固定场景

- 一行连续 100 个“甲”。
- 每个“甲”的编码为 `a`、`aa`、……、10 个 `a`，共 10 种。
- 输入 20 个 `a`；码表模式为 `full_code`，带默认前置的 ASCII literal source。
- 最终显示目标为 99 个，逐一验证起止位置及 next.a。

按不同起止范围计算共有 1710 种（长度 2 到 20 的所有窗口）；同终点合并后只保留
最早起点，因此显示为 99 个目标。不同输入 offset 的待续状态仍各自保留。

## 测量方式

三个独立 Neovim 进程顺序运行，LuaJIT 和 GC 开启；每个场景预热 20 次，随后
7 轮取中位数。通常先校准批量，使一批至少约 40 ms。单次追加使用 64 个预先
匹配至 19 字节的独立 state，准备和完整 GC 都在计时区间之外。

这里测完整 matcher.get：包含 buffer API、扫描、状态、缓存和结果表分配。
不包含进程启动、source 配置构建或 Flash UI 绘制。默认不分配标签；单独的标签
场景提供固定的 26 个 ASCII 标签。连续输入一行是 20 次调用的总时间，不是一次追加。

环境：Neovim 0.12.6，LuaJIT 2.1.1792527110。

| 场景 | 进程 1 中位数 ms | 进程 2 中位数 ms | 进程 3 中位数 ms |
|---|---:|---:|---:|
| 新 state，直接匹配 20 个 a | 2.898 | 2.864 | 2.864 |
| 相同 pattern，再次查询缓存 | 0.012 | 0.012 | 0.012 |
| 从 1 个 a 连续输入至 20 个 a（总计） | 22.813 | 22.828 | 22.405 |
| 仅第 19 → 20 个 a 的追加 | 1.588 | 1.553 | 1.531 |
| 新 state，匹配并分配标签 | 2.860 | 2.838 | 2.827 |

额外保留 Lua 堆（完整 GC 后，含新 state 与 99 个返回结果，不是进程 RSS）：
三次为约 96.15–96.25 KiB。

## 用户补充的历史记录

> 100 个文本字符；每字符 10 个编码：a 到 aaaaaaaaaa；搜索 20 个 a；
> 结果 864；耗时约 4.3 秒。1000 字符场景仍需优化候选推进，不能宣称性能完成。

该记录由用户补充。当前同终点合并后为 99 个显示目标；旧记录的 864 如何计数、
具体代码版本和计时边界尚未复核，因此不能将 4.3 秒与本次毫秒数作为严格同比，
也不据此宣称全部性能问题已经解决。

此前找到的 4×512 个“甲”、128 个 a 属于另一组测试，不混入本组比较。
原始日志在 /tmp/flash-any-100x20/run1.log、run2.log 和 repro.log。

## 1000 字符扩展

```sh
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_match.lua 1000
```

编码、输入和测量方法不变，只将文本字符数从 100 改为 1000。

两次独立进程，每项仍取 7 轮中位数；显示目标均为 999，逐一验证起止位置和 next。
若区分所有起止范围则为 18810 种，仍由相同终点合并为最早起点。

| 场景 | 进程 1 中位数 ms | 进程 2 中位数 ms |
|---|---:|---:|
| 新 state，直接匹配 20 个 a | 29.050 | 28.102 |
| 相同 pattern，再次查询缓存 | 0.109 | 0.107 |
| 从 1 个 a 连续输入至 20 个 a（总计） | 225.041 | 216.298 |
| 第 19 → 20 个 a 的追加（64 state 批次） | 26.071 | 24.845 |
| 新 state，匹配并分配标签 | 28.702 | 27.422 |

额外保留 Lua 堆约 958.4–958.5 KiB。日志在
/tmp/flash-any-100x20/1000-run1.log、1000-run2.log。

单次追加行保留 64 个预备 state 来隔离准备成本，1000 字符时这会让 GC 扫描比
真实单窗口更大的存活堆；该批次均值不应直接当作 UI 按键延迟。完整匹配均值在
文本扩大 10 倍时也约扩大 10 倍，这只说明固定输入和编码参数下的伸缩性。

当前 1000 字符极限场景的完整匹配仍需约 28–29 ms，连续 20 次输入总计约
216–225 ms（不含 UI）；秒级开销已不在本次测量中出现，但不能据此宣称性能优化
已经全部完成。

## emit 协议对照（2026-11-02）

以下数据测于 stream 仍为字符串的版本。后续 text/stream 统一复用 Cursor 后，按约定
未继续做性能专项对照；这些数字不代表当前 Cursor 版的最新耗时。

对照基线为本轮修改前的工作区快照，已经包含行文本缓存和多码点匹配；不是旧发布版，
不与上面的历史数字混比。仅改动 matcher 输出和对应扫描路径：分支表改为同步 emit，
source 直接作为参数传入，移除结果数组和分发层合并数组；码表 prefix 区间用最大
公共前缀长度输出，不再分配去重集合。最终候选和增量状态仍保留 table。

环境：Neovim 0.12.6、LuaJIT 2.1.1793383622。前后各 3 个独立进程，顺序运行；
使用同一个 `scripts/bench_match.lua`，场景、校准、预热和 GC 设置不变。每个进程
每项 7 轮取中位数；下表是 3 个进程中位数的中位数，括号为进程间范围。

| matcher.get 场景，100 个字符 | 分支表 ms | emit ms |
| --- | ---: | ---: |
| 新 state，20 个 a | 2.923（2.910–3.083） | 1.415（1.408–1.431） |
| 连续输入 1–20 个 a，总计 | 23.167（22.872–23.603） | 19.260（19.230–19.393） |
| 仅追加第 20 个 a | 1.539（1.537–1.580） | 1.095（1.092–1.106） |
| 新 state，含标签分配 | 2.897（2.891–3.035） | 1.425（1.413–1.435） |

完整匹配约减少 52% 耗时，连续输入总计约减少 17%。这是固定压力场景的完整
matcher.get 耗时，包含 buffer API、扫描、增量状态、结果组装；不包含 source 配置、
Neovim 进程启动和 Flash UI 绘制，不能当作用户按键到画面更新的端到端延迟。
相同 pattern 的缓存查询没有调用 matcher，不用它评价 emit 的收益。

GC 后额外保留堆前后均约 109.7 KiB。emit 减少的是临时分配和搬运，不减少最终
显示结果和待续状态的存活内存。

局部临时分配可独立复测：

```sh
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_source.lua
# 若有修改前的快照，使用当前脚本测旧模块：
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_source.lua /path/to/before nested
```

此脚本预先构建文本对象、source 和旧接口的参数包装；仅测 matcher 本身，不包含
扫描器。关闭 JIT 以避免分配消除，完整 GC 后停用 GC，调用 10,000 次，再按 Lua 堆
增长求每次分配字节数。CPU 微测中常量输入可被 JIT 大幅折叠，因此不以局部纳秒数
推断真实速度；耗时收益使用上面的完整 matcher.get 对照。

| 局部调用 | 分支表 B/次 | emit B/次 |
| --- | ---: | ---: |
| literal 完成 | 200 | 0 |
| literal 起始键 | 312 | 0 |
| literal 输入不匹配 | 64 | 0 |
| 单编码完整匹配 | 312 | 0 |
| 单编码输入不匹配 | 64 | 0 |
| 多编码重叠 prefix | 640 | 0 |

0 表示这些已预热固定场景中没有可测的临时 Lua 堆增长，不代表整个扫描器零分配。
维护成本是 matcher 必须同步输出、返回是否认识当前位置，不能保存 emit；每次行
扫描复用一个捕获当前进度的回调。内置 matcher 不再构造临时结果表。

对照原始日志为 `/tmp/flash-any-result-before-scan-{1,2,3}.log`、
`/tmp/flash-any-result-after-scan-{1,2,3}.log` 和对应的 `*-local-*.log`。


## Cursor 缓存转置：保留内存

当前 `_values` 原先为“起点 → 长度 → 字符串”，现改为“长度 → 起点 → 字符串”。
长度为码点数，0 是整段后缀的专用桶。此对照只测缓存子表数量和 GC 后保留的
Cursor 堆，不测 CPU、完整搜索或 UI 延迟。

复测脚本：

```sh
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_cursor.lua
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_cursor.lua . mixed
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_cursor.lua . stream
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_cursor.lua . lengths
# 当前脚本也可加载改动前的模块快照：
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_cursor.lua /path/to/before single
```

前后、各场景分别用独立 Neovim 进程运行，关闭 JIT 以避免分配消除；输入字符串
先构建，随后 GC、记录基线、构建并使用一个 Cursor，再 GC 计算额外 Lua 堆。
字符使用“甲”，逐位置调用 get 后用 shift() 前移。子表数量只统计 `_values` 的桶，
堆增量包含 Cursor 的全部数组和缓存，不是进程 RSS。

| 场景 | 转置前子表 | 转置后子表 | 转置前保留 B | 转置后保留 B |
| --- | ---: | ---: | ---: | ---: |
| 1000 个位置，get(1) | 1000 | 2 | 132632 | 44832 |
| 1000 个位置，get(1/2/4) | 1000 | 4 | 148692 | 61532 |
| 20 个位置，get() 和 get(1) | 20 | 2 | 4172 | 2956 |
| 仅 1 个位置，get(1)..get(20) | 1 | 21 | 2500 | 4388 |

整段后缀使用一个长度 0 的桶，故第一行末尾也会创建第二个桶。
收益来自“位置多、读取长度种类少”的分布；若位置很少而长度种类很多，反而会多建
桶。当前逐字扫描以 get(1) 为主，因此选择按长度分桶。读取、移动和短读语义不变。
实现不引入新抽象，只交换缓存的两级键；不据此推断搜索耗时的变化。
原始日志为 `/tmp/flash-any-cache-{before,after}-{single,mixed,stream,lengths}.log`。

## TSV 前缀 offset / TSV continuation offsets

2026-11-02：`scripts/bench_tsv.lua` 在独立 Neovim 进程对比相同有序 TSV、相同
查询次序，仅切换是否向 loader 传入上一个文本前缀的 offset。4096 个不同首码点，
每组查询首码点及 a、ab、abc 后缀；文件与节点预热一次，3 轮共 49152 次查询，
用 os.clock 测局部 CPU。不缓存解码结果，不包含进程启动、matcher 或 UI。

```sh
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_tsv.lua root
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_tsv.lua offset
```

| 查询方式 / Lookup | CPU ms |
| --- | ---: |
| 每个前缀从文件根查询 / Whole-file lookup | 109.81 |
| 复用前缀 offset / Continue from prefix offset | 69.58 |

本场景耗时约降 37%；同前缀下目标较远时仍需二分，不代表端到端搜索加速比例。
实际 matcher 还会按文本键缓存编码与 continuation offset；offset=false 的终止前缀
不会再次触发文件查询。二分节点的前 6 层无条件缓存，深层精确命中节点也保留；
与前缀剪枝独立。

Independent processes compare identical warmed TSV files and lookup sequences,
changing only reuse of the prior text prefix's offset. This measures local CPU for
49152 loader queries, excluding result caching, startup, matcher and UI. The
fixture saves about 37%; distant siblings still need binary search. Real matchers
also cache codes and continuation offsets per key; false terminates extension.
Binary comparison-node caching remains separate from prefix pruning.

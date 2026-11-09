# 性能记录 / Performance records

本文按实现演进保留历史数据。旧Cursor、Lua匹配器及其12个实验脚本已经清理；
早期章节中的脚本路径和命令仅描述当时测量，不能在当前版本直接执行。
当前可用的测试入口见[scripts说明](../scripts/README.md)，当前扫描架构见本文
“单趟解码匹配替换文本索引”。`tests/reference/`仍供差分测试使用，不是运行时后端。
用户侧构建现已改用Neovim Lua和随附头文件，只需C编译器；下文的旧Python构建及
GNU make4.3要求属于历史实现。Python仍可用于独立性能实验。早期章节的增量匹配
状态也仅描述旧实现；当前 C 版在输入变化时重新扫描缓存原始行，不依赖前缀闭合约定。

Historical results and commands describe their original implementation. Obsolete
Cursor/Lua experiment scripts have been removed. See [current tools](../scripts/README.md)
for supported entry points and the section on sequential decoding/matching for the current scanner.
Native builds now use Neovim Lua, bundled headers and a C compiler; older Python
build commands and GNU make4.3 requirements below are historical. Older incremental
matching states are historical too: the current C scanner rescans saved lines when
the query changes and does not require prefix-closed candidate sets.

## 历史 Matcher 压力测试

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

## 字素 Cursor 对照（2026-11-02）

本节及后续对照测于 scope 仍截取首码点的阶段；当前 scope 已改为完整字素比较，
并同步修改 builder/extra 及 t/T。以下数据保留为历史记录，不代表这些后续改动的最新性能。

**复核说明：以下是多个 fixture/工作负载顺序预热的整套配置对照，不能据此认定普通
中英文正文有稳定的 38% 提速。两版的 emoji source 分别走多码点前缀查询和单字素
直接查询，且隔离执行时 JIT 结果会改变。关闭该 source、每个样本新进程的结果见后文。**

基线是改动前的 `e0bd48e`，对照为本次字素 Cursor 工作区。Neovim 0.12.6，
LuaJIT 2.1.1793383622；固定 CPU 0，前后各三个独立进程，串行交替运行。
每个工作负载清空 JIT traces、预热 100 次，校准至每批至少约 30 ms，7 批取中位数；
下表再取三个进程中位数的中位数，GC 开启。

每个 fixture 为 40 行，每行固定文本重复两次；sources 为 ASCII literal、默认全拼
initial（chinese scope）及脚本内 14 项 emoji prefix 表。前后文本、ASCII 编码、
source 顺序一致；emoji 的 prefixes/max_chars 分别按各版本的计数单位构建。
本次同时改变了分段、扫描终点、scope 首码点读取和码表跨度，数字代表整套改动，
不能全部归因为分段算法。旧版仍允许簇内起点；本次 fresh-c 的显示候选数量相同，
但并非一般情况下语义完全等价的替换。

完整扫描包含 Cursor 创建、buffer API、状态推进、匹配、结果表和标签分配；
不含进程启动、source 配置、首次 TSV 冷加载、UI 绘制或真实键盘事件，不能当作端到端按键延迟。
逐键输入数字为从空 state 输入完整单词的总耗时，每个词分别从新 state 开始。
单位 ms；括号为耗时变化，负数表示减少。

| 40 行场景 | 首次扫描 c：码点 → 字素 | 逐键 shi，总计 | 逐键 coder，总计 |
| --- | ---: | ---: | ---: |
| 纯 ASCII | 1.541 → 1.764（+14.5%） | 1.967 → 2.561（+30.2%） | 3.139 → 2.998（-4.5%） |
| 中英文正文 | 4.272 → 2.655（-37.8%） | 5.763 → 3.785（-34.3%） | 4.721 → 3.363（-28.8%） |
| 正文混合 emoji | 5.175 → 2.961（-42.8%） | 5.229 → 3.061（-41.5%） | 8.294 → 5.337（-35.7%） |
| 密集 ZWJ emoji | 4.654 → 1.294（-72.2%） | 5.094 → 1.502（-70.5%） | 10.530 → 4.699（-55.4%） |

JIT 路径有明显波动。以首次扫描为例，三个进程的中位数范围如下（ms）：

| 场景 | 码点版范围 | 字素版范围 |
| --- | ---: | ---: |
| 纯 ASCII | 1.411–1.554 | 1.580–1.843 |
| 中英文正文 | 3.194–4.352 | 2.165–2.955 |
| 正文混合 emoji | 4.736–5.418 | 2.936–3.274 |
| 密集 ZWJ emoji | 4.186–4.719 | 1.288–1.306 |

局部 CPU 与保留内存分开看：下表前两列不运行 source/扫描器；创建列仅构造
40 个 Cursor，遍历列包含创建和对每个位置执行 get(1)/shift。旧版创建尚未分段，
因此不能只比较创建时间就判断整体性能。内存为 fresh-c state 及返回结果在完整 GC
后保留的 Lua 堆差值，不是 RSS。

| 场景 | 仅创建 40 个 Cursor，ms | 创建并遍历，ms | 保留 Lua 堆，KiB，码点 → 字素 |
| --- | ---: | ---: | ---: |
| 纯 ASCII | 0.006 → 0.160（+2604.6%） | 0.206 → 0.257（+24.5%） | 391.6 → 474.7 |
| 中英文正文 | 0.006 → 0.217（+3602.2%） | 0.853 → 0.295（-65.4%） | 262.1 → 305.1 |
| 正文混合 emoji | 0.006 → 0.315（+5270.6%） | 1.281 → 0.395（-69.2%） | 426.0 → 444.5 |
| 密集 ZWJ emoji | 0.006 → 0.168（+2757.3%） | 1.398 → 0.504（-64.0%） | 497.5 → 280.9 |

字素版提前分段并增加每簇最后码点的索引，因此纯文本保留内存增多。ZWJ fixture
扫描起点从 3,360 减至 800，缓存与候选推进相应减少，内存也下降。ASCII 起点数量
仍为 5,200，无扫描位置减少的收益；首次扫描及 shi 连续输入出现回退，coder 的
小幅中位数变化不足以说明普遍收益。这里只报告实测，未据此添加优化或特判。

复现脚本：[scripts/bench_grapheme.lua](../scripts/bench_grapheme.lua)。把改动前
版本展开到独立目录，使用当前同一脚本分别运行；每次启动新进程，串行重复三轮：

```sh
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_grapheme.lua /path/to/before
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_grapheme.lua "$PWD"
```

## 关闭多码点 source 的冷启动复核（2026-11-02）

完全移除 emoji source，包括它的码表构建与 Cursor 预遍历；只保留 ASCII literal
和默认全拼 initial（chinese scope），两者文本跨度均为 1。每个样本启动一个独立
`nvim --clean` 进程，不预热、不预扫描、不复用 state，每进程只调用一次 matcher.get。
保持 40 行相同 fixture、查询 c 和标签分配；固定 CPU 0，每场景每版本 30 个样本，
前后顺序交替。保留默认 JIT/GC 设置；不清操作系统文件缓存。

source 初始化包括 require、码表加载与 scope 构建；首次扫描包括新 Cursor、首次
查表、状态推进与结果/标签分配。进程总耗时由 Python 从启动命令至退出测量，含
Neovim 启动、source 初始化、buffer 准备、扫描、JSON 输出及退出；这是 headless
进程总时间，仍不是带 UI 的按键延迟。下表为中位数，单位 ms。

| 场景 | 阶段 | 码点版 | 字素版 | 耗时变化 |
| --- | --- | ---: | ---: | ---: |
| 纯 ASCII | 首次扫描 | 3.599 | 3.742 | +4.0% |
| 纯 ASCII | source 初始化 | 3.415 | 3.601 | +5.4% |
| 纯 ASCII | 进程总耗时 | 11.237 | 11.558 | +2.9% |
| 中英文正文 | 首次扫描 | 4.846 | 4.449 | -8.2% |
| 中英文正文 | source 初始化 | 3.406 | 3.601 | +5.7% |
| 中英文正文 | 进程总耗时 | 12.580 | 12.281 | -2.4% |

中英文首次扫描的样本范围：码点版 3.976–7.501 ms，字素版 3.794–5.497 ms；
ASCII 分别为 3.105–4.419 ms 和 3.066–4.603 ms，存在明显重叠。此配置下普通
中英文扫描耗时中位数减少约 8%，进程总耗时只减少约 2%；不能沿用之前的 38%。

原因复核：

- 原中英文 fixture 两版都是 4,160 个扫描起点。逐次计数得到 get 调用均为 28,080，
  set_offset 均为 8,440；不存在字素合并减少扫描位置的收益。
- 原基准中的 emoji source：旧版 max_chars=8，每次扫描执行 4,240 次 table.lookup；
  新版 max_chars=1，直接查表。即便正文没有 emoji，这条分支仍会运行；移除该 source
  后这项差异消失。
- Cursor 同时从惰性扩展改为预建边界，get 不再扩展边界；旧版本 fixture 调用
  _extend 4,201 次，新版不调用。另有 scope 首码点截取成本和 JIT 路径变化。
  这说明“没有多码点字素”不代表两套实现做相同的工作，但不能把剩余 8% 全归给某一项。

此外，单独运行中英文 fresh-c 的预热复测为 1.248 → 1.568 ms（各 3 个独立
进程中位数），与之前在其它工作负载之后执行时的方向相反。原脚本虽在每项前
调用 jit.flush，测量依然表现出执行历史敏感性；因此增加 fixture/workload 选择参数，
以后做局部 CPU 对照应每个进程只执行一项。该预热结果与上面的冷启动结果分开解释。

冷启动复现（每次命令一个样本，前后交替重复 30 次）：

```sh
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_grapheme_cold.lua /path/to/before chinese
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_grapheme_cold.lua "$PWD" chinese
```

将 chinese 改为 ascii 即为 ASCII 场景。预热单项隔离可用
`scripts/bench_grapheme.lua ROOT chinese fresh-c`，末尾再加 off 可关闭 JIT。

## 旧版预建码点边界的冷启动对照（2026-11-02）

在旧版临时副本中，只修改 Cursor.new：一次遍历填充原有 _offsets/_indices，
保留旧 get、set_offset、shift、扫描器、scope 和 source。复用旧 next_offset 迭代函数，
不添加字素规则，也不创建字符串缓存或新增最后码点索引。新增的构造逻辑为：

```lua
local offsets, indices = { 0 }, { [0] = 1 }
for after in next_offset, value, 0 do
  offsets[#offsets + 1] = after
  indices[after] = #offsets
end
-- 构造对象时 _offsets = offsets，_indices = indices，其余保持旧版。
```

沿用上节冷启动脚本和两种 fixture：40 行，literal + 单码点拼音，无 emoji source，
每进程只扫描一次，不预热。为降低波动，每场景每版本改为 100 个独立进程，
三种实现的运行顺序在六种排列之间轮换，固定 CPU 0，默认 JIT/GC。
这次三个版本在同一批次重新测量，不能与上节不同批次直接相减归因。

首次完整扫描中位数（含 Cursor 创建，未含 source 初始化和进程启动），单位 ms：

| 文本 | 旧版惰性码点 | 旧版预建码点 | 当前字素版 |
| --- | ---: | ---: | ---: |
| 纯 ASCII | 3.522 | 3.034 | 3.657 |
| 中英文正文 | 4.869 | 3.600 | 4.306 |

旧版仅预建边界后，ASCII 扫描耗时减少约 14%，中英文减少约 26%；
当前字素版相对预建码点版，两个场景的扫描耗时中位数分别增加约 21%、20%。
这组数据支持“预建边界本身已有收益”，不支持“没有复合字素的正文因字素规则而更快”。
当前字素版还包含 scope 首码点截取和其它读取路径改动，不能把差值全部当作分段器成本。

首次扫描的四分位区间（P25–P75），单位 ms：

| 文本 | 旧版惰性码点 | 旧版预建码点 | 当前字素版 |
| --- | ---: | ---: | ---: |
| 纯 ASCII | 3.269–3.784 | 2.797–3.203 | 3.411–3.814 |
| 中英文正文 | 4.544–5.397 | 3.365–4.561 | 4.111–4.675 |

尤其是中英文预建码点版仍有明显波动，区间与字素版重叠；以上比例仅描述这批
冷启动样本的中位数，不能外推到所有输入或 UI 延迟。

headless 进程总时间中位数（包含启动、初始化、准备 buffer、首次扫描、输出与退出），单位 ms：

| 文本 | 旧版惰性码点 | 旧版预建码点 | 当前字素版 |
| --- | ---: | ---: | ---: |
| 纯 ASCII | 11.110 | 10.577 | 11.442 |
| 中英文正文 | 12.404 | 11.214 | 12.115 |

本实验仅修改 /tmp 下的旧版副本，没有改动当前生产 Cursor。对照用上述补丁构建
旧版预建副本，再以同一个 scripts/bench_grapheme_cold.lua 分别传入三个实现目录。


## 仅缓存 get(1) 的对照（2026-11-06）

本次只改变字符串结果缓存；四组都保留当前 Unicode 17 字素分段、全部边界和
最后码点索引。之前“预建边界优于惰性边界”的结果，不能直接用于判断字符串缓存策略。
正式 Cursor 未修改，实验脚本在临时目录复制 lua 并替换 Cursor 的字符串读取路径。

| 方案 | 字符串策略 |
| --- | --- |
| all-lazy（现状） | 按需缓存所有读取长度，包括 get() 后缀；长度 → 起点两级表 |
| one-lazy | 只按需缓存 get(1)，用起点索引的一维表；其它读取直接 sub |
| one-eager | 在现有分段回调内预存每个 get(1) 结果，读取沿用 one-lazy 路径 |
| none | 所有读取直接 sub；保留空 _values 表，控制对象构造差异 |

环境：i5-14600K，Neovim 0.12.6，LuaJIT 2.1.1793383622，固定 CPU 0，串行运行，
默认 GC/JIT。每种文本 40 行，fixture、source 与已有脚本一致。
以下均为 ms，数字为中位数；这些是扫描器及局部操作的计时，不是实际 UI 按键延迟。

冷启动：复用 bench_grapheme_cold.lua，只启用 literal + 单字素拼音 initial；每组每场景
72 个独立进程，各进程只扫描一次，不预热，四组运行顺序遍历 24 种排列。
扫描包含 Cursor 创建、匹配和结果分配，不包含 source 初始化及进程启动。

| 首次扫描 | 现状 | 仅按需 get(1) | 预存 get(1) | 无字符串缓存 |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 3.116 | 2.750 | 2.505 | 2.338 |
| 中英文正文 | 4.511 | 3.641 | 3.380 | 3.352 |

仅按需 get(1) 分别比现状减少 11.8%、19.3%；无字符串缓存的首次扫描更快。
但中文冷启动波动明显：四组最小–最大范围分别为 3.175–5.806、2.574–5.314、
2.493–4.733、2.487–4.907 ms。对应 headless 进程总时间中位数：

| 进程总时间 | 现状 | 仅按需 get(1) | 预存 get(1) | 无字符串缓存 |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 10.484 | 10.127 | 9.898 | 9.680 |
| 中英文正文 | 11.823 | 11.025 | 10.753 | 10.720 |

预热：复用 bench_grapheme.lua，包含 literal、拼音和 emoji source。每个进程只测一个
fixture/workload；每组 3 个独立进程，各进程预热后取 7 次批量测量的中位数，再取三个
进程的中位数。连续输入每次从新 state 开始，包含逐键输入整个词的全部扫描。

| 文本 / 工作负载 | 现状 | 仅按需 get(1) | 预存 get(1) | 无字符串缓存 |
| --- | ---: | ---: | ---: | ---: |
| ASCII / 扫描 c | 1.186 | 1.142 | 1.118 | 1.143 |
| ASCII / 逐键 shi | 1.659 | 1.596 | 1.561 | 1.643 |
| ASCII / 逐键 coder | 1.276 | 1.220 | 1.207 | 1.243 |
| 中英文 / 扫描 c | 1.096 | 1.103 | 1.071 | 1.201 |
| 中英文 / 逐键 shi | 1.581 | 1.518 | 1.489 | 1.524 |
| 中英文 / 逐键 coder | 1.264 | 1.203 | 1.222 | 1.341 |
| 正文 + emoji / 扫描 c | 1.254 | 1.214 | 1.225 | 1.261 |
| 正文 + emoji / 逐键 shi | 1.213 | 1.129 | 1.200 | 1.182 |
| 正文 + emoji / 逐键 coder | 2.117 | 1.973 | 1.969 | 1.975 |
| 密集 ZWJ / 扫描 c | 0.537 | 0.522 | 0.541 | 0.515 |
| 密集 ZWJ / 逐键 shi | 0.640 | 0.594 | 0.594 | 0.587 |
| 密集 ZWJ / 逐键 coder | 2.076 | 1.847 | 1.861 | 1.889 |

只按需 get(1) 的连续输入耗时多数减少约 4%–11%，中文预热 fresh-c 基本持平。
预存 get(1) 没有稳定优于按需：例如正文 + emoji 的 shi 为 1.200 对 1.129 ms。
完全不缓存也并非总是更快，中文 coder 为 1.341 对现状 1.264 ms。

关闭 JIT 后复核 fresh-c，每组仍取 3 个独立进程的中位数：

| JIT off / fresh-c | 现状 | 仅按需 get(1) | 预存 get(1) | 无字符串缓存 |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 4.710 | 4.404 | 4.461 | 4.510 |
| 中英文 | 4.231 | 4.069 | 4.142 | 4.322 |

关闭 JIT 后，仅按需 get(1) 仍减少约 6.5%、3.8%，说明收益并非全部来自 JIT。
但这不能单独区分少建缓存桶、少查表和少做后缀共享判断各自的贡献。

保留内存只看隔离的 fresh-c 进程，完整 GC 后的 Lua 堆差值，包含 state 和结果，不是 RSS：

| Lua 堆，KiB | 现状 | 仅按需 get(1) | 预存 get(1) | 无字符串缓存 |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 474.6 | 466.6 | 466.4 | 386.1 |
| 中英文 | 305.0 | 297.1 | 296.9 | 256.6 |
| 正文 + emoji | 444.4 | 436.5 | 436.5 | 396.1 |
| 密集 ZWJ | 280.8 | 273.0 | 273.0 | 262.6 |

每 40 行仅减少约 8 KiB，并没有大幅减少存储。另开不计时进程，对冷启动扫描的 get
调用及读取前已有缓存进行计数（含不足长度时递归调用 get()）：

| 文本 | get(1) 调用 / 已有缓存 | get() 调用 / 已有缓存 |
| --- | ---: | ---: |
| ASCII | 21,320 / 15,919 | 200 / 159 |
| 中英文 | 16,920 / 11,120 | 2,680 / 2,638 |

这些场景没有 get(2+) 调用，原来就主要只有长度 1 和后缀两个桶；不能把收益归因于
“缓存了太多长度”。one-lazy 同时把两级缓存改为一维、移除了后缀共享逻辑；结果支持
简化读取路径有收益，尚不足以确定缓存数量的独立影响。LuaJIT 字符串会驻留，重复 sub
也不等于每次都分配新字符串；高缓存命中率本身不能证明一定比直接 sub 快。

因此本次保留正式实现：只缓存 get(1) 值得继续考虑，但会失去 get() 与 get(2+) 的跨次
读取缓存。当前 emoji fixture 的每个键也是一个完整字素，没有覆盖频繁读取多个字素的
第三方 source；不能据此保证那些 source 的性能。四种临时实现均通过 tests/cursor.lua
的 775 个 Unicode/边界用例，以及 match/literal、match/codetable、scope 测试；这验证
读取语义，不代表满足原来所有内部缓存复用断言。

复现（Linux，Python 标准库；默认运行完整实验，临时目录中保留变体、raw.jsonl 与 summary.json）：

```sh
python scripts/bench_cursor_cache.py --baseline /path/to/before
# 少量样本，仅用于检查脚本能否运行，不用于性能结论：
python scripts/bench_cursor_cache.py --baseline /path/to/before --cold-samples 1 --warm-samples 1
```

before 目录需包含本节实验前的完整 lua 目录及原始 Cursor 构造方法。

本轮原始记录：/tmp/flash-any-cursor-cache-kh6atfhd/{raw.jsonl,summary.json}。

English: Keeping segmentation unchanged, caching only get(1) reduced cold scan medians
by 12%/19% for ASCII/Chinese and usually improved warmed typing by 4%–11%. Retained
heap fell only about 8 KiB per 40 lines. This experiment also flattened the cache and
removed suffix-sharing work, so it does not isolate cache volume as the cause. Eager
get(1) caching was not consistently better; no caching could regress warmed scans.
Production code remains unchanged pending workloads with frequent multi-grapheme reads.


## 只考虑 text：预建边界与单向扫描（2026-11-06）

本次只替换扫描器创建的行 text，stream 保持原 Cursor，字符串缓存策略也保持不变。
单轮 text 扫描单向前进，但行对象跨 pattern 复用：追加输入从最早的待续位置恢复，
删除、替换输入从行首重扫。因此“单轮单向”不等于对象生命周期内不回头。

区分对照基线的三份索引：

- _offsets：字素边界顺序数组，供推进及重复读取使用。
- _indices：字节边界到字素下标的反向表；扫描时通常只是前进一格。
- _lasts：每个字素最后码点的起始字节，用于 Neovim 匹配终点；即便只读 get(1)，
  复合字素的最后码点也不一定从 after - 1 开始。

第一批比较 eager（现状）、eager-noindex（仅去掉反向表）、lazy-noindex（按需扩展并
保留边界）、streaming（按需扩展并丢弃已走过的边界）。第二批加入专门优化 get(1) 的
轻量 direct：常规读取只保存当前 after/last；不建完整边界数组，只在 get(2+) 时创建
向前看记录；回到较早位置时从行首重建 Unicode 分段上下文。迭代器沿用原分段状态机，
保留 RI/Indic/ZWJ 状态，不用 coroutine，也不在每次前进时从行首重扫。

eager-noindex 仍用原来的 each 一次建立 _offsets/_lasts；set_offset 对当前位置、下一
字素及行首走直接路径，其它位置二分查找边界。不增加调用方的索引或缓存生命周期。
以下表格均来自第二批，避免跨批次相减。测试环境同上：CPU 0，默认 JIT/GC，40 行；
冷启动每组每场景 72 个独立进程，三组运行顺序遍历 6 种排列；预热每项每组 3 个独立
进程，各进程取 7 次批量计时的中位数，再取三个进程的中位数。单位 ms。

冷启动 source 只有 literal 和单字素拼音 initial，text 全部读取都是 get(1)：

| 首次扫描 | 现状预建 | 预建但无反向表 | direct 单向游标 |
| --- | ---: | ---: | ---: |
| ASCII | 3.173 | 3.054 | 3.871 |
| 中英文 | 4.210 | 3.821 | 5.083 |

只去反向表的冷启动收益有波动：第一批 ASCII 为 3.171 → 3.107 ms，中英文为
4.180 → 4.194 ms；第二批分别减少约 4%、9%。不能把第二批比例看作稳定收益。

预热完整扫描含 literal、拼音和 emoji source；这些 fixture 的 emoji 键都是一个完整
字素，同样不依赖多字素查询。连续输入每次从新 state 输入完整词，包含全部逐键扫描。

| 文本 / 工作负载 | 现状预建 | 预建但无反向表 | direct 单向游标 |
| --- | ---: | ---: | ---: |
| ASCII / 扫描 c | 1.210 | 1.181 | 1.491 |
| ASCII / 逐键 shi | 1.721 | 1.684 | 3.234 |
| ASCII / 逐键 coder | 1.332 | 1.305 | 2.441 |
| 中英文 / 扫描 c | 1.181 | 1.101 | 1.428 |
| 中英文 / 逐键 shi | 1.544 | 1.437 | 2.674 |
| 中英文 / 逐键 coder | 1.316 | 1.228 | 1.926 |
| 正文 + emoji / 扫描 c | 1.280 | 1.079 | 1.713 |
| 正文 + emoji / 逐键 shi | 1.203 | 1.030 | 1.905 |
| 正文 + emoji / 逐键 coder | 2.107 | 1.929 | 4.246 |
| 密集 ZWJ / 扫描 c | 0.544 | 0.516 | 0.645 |
| 密集 ZWJ / 逐键 shi | 0.603 | 0.584 | 0.812 |
| 密集 ZWJ / 逐键 coder | 2.097 | 1.895 | 3.554 |

关闭 JIT 后的 fresh-c 复核（每组 3 个独立进程）：

| JIT off | 现状预建 | 预建但无反向表 | direct 单向游标 |
| --- | ---: | ---: | ---: |
| ASCII | 4.781 | 4.659 | 5.308 |
| 中英文 | 4.313 | 4.166 | 5.118 |

保留 Lua 堆（隔离 fresh-c，完整 GC 后包含 state 与结果，不是 RSS），KiB：

| 文本 | 现状预建 | 预建但无反向表 | direct 单向游标 |
| --- | ---: | ---: | ---: |
| ASCII | 474.4 | 391.5 | 249.6 |
| 中英文 | 305.0 | 221.9 | 160.1 |
| 正文 + emoji | 444.4 | 357.5 | 295.7 |
| 密集 ZWJ | 280.8 | 247.1 | 245.1 |

去反向表在普通文本每 40 行省约 83 KiB；仍保留两份顺序数组。direct 更省内存，
但两个批次中，按需/丢弃边界方案的完整扫描均没有稳定胜过预建。该结论只描述这些
原型，不能证明所有单向实现都必然更慢。

额外计数使用独立、不计时进程；literal + 单字素拼音，40 行，无 emoji source。
统计的是输出的字素簇数量，含重扫时再次输出的簇，不是解码码点数：

| 文本 / 输入 | 现状分段簇数 | direct 分段簇数 | text 回退次数 | text get(2+) |
| --- | ---: | ---: | ---: | ---: |
| ASCII / c | 5,200 | 5,200 | 0 | 0 |
| 中英文 / c | 4,160 | 4,160 | 0 | 0 |
| ASCII / shi | 5,200 | 14,320 | 80 | 0 |
| 中英文 / shi | 4,160 | 11,760 | 80 | 0 |

每条行对象只创建一次。输入 shi 时 direct 创建 120 个分段迭代器（40 行 × 3 轮），
预建版每行只分段一次。即便 source 只调用 get(1)，连续输入仍会重访旧 text；
单轮完整扫描也没有因按需分段减少经过的字素数量。

因此这里支持“保留可复用的顺序边界，精简反向表”。没有把低频 get(n) 当作维持完整
反向索引的理由。_lasts 的存储是否可进一步换成按需计算，需要单独比较，本次没有
改变它。上述实验阶段未修改正式 Cursor 与扫描器；把 text 独立成另一个类仅用于隔离实验，
不作为生产设计建议。

五种临时 text 均通过 775 个 Unicode/边界用例、match/init、match/char、match/word；
包括多字素 lookahead、输入追加/删除/替换及复合字素。临时测试只调整了预分段次数的
实现断言，以及 text/stream 必须具有相同 metatable 的断言，未改匹配结果断言。
保存的生成器已核对能逐字节重建本轮五种实现。

复现两批对照（Linux，Python 标准库；先运行测试，再串行计时）：

```sh
python scripts/bench_text_boundaries.py --baseline /path/to/before
python scripts/bench_text_boundaries.py --baseline /path/to/before --variants eager eager-noindex direct
```

before 目录需包含移除 _indices 之前的完整 lua 和 tests 目录；旧变体使用基线的 Cursor 测试，current 使用工作区的测试和分段器。

第一批日志：/tmp/flash-any-text-boundaries-s2lgzi31/{raw.jsonl,summary.json}。
第二批日志：/tmp/flash-any-text-boundaries-ieq4vx8y/{raw.jsonl,summary.json}。
扫描耗时不包含 source 初始化、进程启动、UI 或真实输入事件，不能视作按键延迟。

English: Text scans move forward within each pass but revisit cached lines across input
changes. With stream and string caches unchanged, removing only the reverse byte-to-index
map saved about 83 KiB per 40 ordinary-text lines and usually reduced warmed scan time.
A get(1)-optimized forward cursor saved more memory but regressed these scan workloads.
Typing shi segmented 14,320 versus 5,200 ASCII clusters despite no get(2+) calls, because
it rebuilt segmentation context on backward resumes. This supports retaining reusable
sequential boundaries while simplifying the reverse index; these experiments preceded the
production change described below.


## 移除反向表：恢复时顺扫已有边界（2026-11-06）

最终实现保留 _offsets/_lasts 和原字符串缓存，移除 _indices。set_offset 向前定位
从当前下标顺扫 _offsets；回退时从下标 1 顺扫，找到目标字节边界后更新游标。
不重新解码或分段，也不在查找途中调用 source。顺序前进通常只检查相邻边界；
任意定位的最坏耗时改为线性，换掉每个对象常驻的反向表，不增加二分查找或特殊分支。

这区别于前面的 direct：恢复定位并不需要重新生成 Unicode 字素，已有的“字素下标
→ byte”顺序表足够。前面用 direct 重复分段的簇数说明代价，并不能否定顺扫已有数组。

先比较带“当前位置/下一字素/行首”快速分支的线性查找与二分查找：两者互有快慢，
没有稳定的性能差距，日志保存在 /tmp/flash-any-text-boundaries-oev1kito/。
随后最终实现进一步简化为一段顺扫循环，下面是与原版重新运行的同批对照；
仍然只替换 text，stream 使用基线实现，控制变量。正式类由 text/stream 共用，
因此落地时两者均使用顺扫定位，全部相关测试已通过。

冷启动每组每场景 72 个独立进程，交替运行；预热每项每组 3 个独立进程，每进程
取 7 次批量计时中位数，再取三个进程的中位数，CPU 0，默认 GC/JIT，沿用上述脚本。
单位 ms；不包含 source 初始化、进程启动或真实 UI 输入延迟。

| 文本 / 工作负载 | 原版 | 顺扫已有边界 |
| --- | ---: | ---: |
| ASCII / 冷启动首次扫描 | 3.129 | 3.046 |
| ASCII / 预热扫描 c | 1.212 | 1.181 |
| ASCII / 逐键 shi | 1.916 | 1.720 |
| ASCII / 逐键 coder | 1.334 | 1.295 |
| ASCII / JIT off 扫描 c | 4.681 | 4.605 |
| 中英文 / 冷启动首次扫描 | 4.182 | 3.961 |
| 中英文 / 预热扫描 c | 1.102 | 1.045 |
| 中英文 / 逐键 shi | 1.590 | 1.605 |
| 中英文 / 逐键 coder | 1.297 | 1.257 |
| 中英文 / JIT off 扫描 c | 4.238 | 4.204 |

首次扫描中位数分别减少约 2.7%、5.3%；不声称所有输入都稳定获得此比例。中文 shi
为 1.590 → 1.605 ms，基本持平。主要可确定收益是减少构造时写入与常驻反向表：
隔离 fresh-c 的完整 GC 后 Lua 堆，ASCII 为 474.6 → 391.5 KiB，中英文为
305.0 → 221.9 KiB，每 40 行均省约 83 KiB；这包含 state 与结果，不是进程 RSS。

验证：17 个现有测试入口全部通过，包括 Cursor 的 775 个 Unicode/边界用例、全部
match 测试和 Flash/char/remote 集成；LuaLS 使用真实 Neovim/Flash library，开启全部
诊断级别，结果无诊断。开发文档同步说明中英文的定位规则。

复现隔离 text 的最终对照（before 是含原始 _indices 的修改前副本，current 读取工作区 Cursor）：

```sh
python scripts/bench_text_boundaries.py --baseline /path/to/before --variants eager current
```

本轮记录：/tmp/flash-any-text-boundaries-68bhgs_f/{raw.jsonl,summary.json}。

English: Production Cursor now removes the reverse index and locates byte offsets by
walking its existing boundary array, starting from the current ordinal for forward seeks
or from ordinal 1 for backward seeks. This does not resegment text or invoke sources.
Text-only isolated cold medians improved by about 2.7%/5.3% for ASCII/Chinese; retained
heap fell about 83 KiB per 40 lines. Arbitrary seeks are now linear. The shared class
applies the same behavior to stream; all 17 test entries and full LuaLS diagnostics passed.


## 两级字素/码点索引与 get_codepoint（2026-11-06）

在上一节已移除反向表、用顺扫定位的实现上，新增 get_codepoint(pos)：pos 是相对
当前字素起点的 Unicode 码点偏移，默认 0 为当前，1 为下一个，-1 为上一个；可访问
字素内部的组合音标、ZWJ。越界返回 nil，无效 UTF-8 每字节保存为 -1，合法 NUL 为 0。

最终存储为字素边界 → 码点下标 → 字节边界，另有并行的码点值数组。分段器通过可选
码点回调传出已经解码的数值和字节终点；不重新解码。原 _lasts 数组移除：某个字素
末尾码点的起始字节可由下一个字素的码点下标减一，再查字节数组得到。相对上节，
顺序数组从两张变为三张；复合字素的码点数可能远多于字素数，因此并非只按字素数
多存一个固定大小的表。普通 get(n)、shift 和 set_offset 查询 byte 时多一次数组索引。

本轮前后版本独立运行、固定 CPU 0、串行交替，默认 GC/JIT。before 是上一节顺扫
定位的副本，不是仍有反向表的 HEAD。完整扫描同时使用各版本的 text 与 stream。
冷启动每组每场景 72 个独立进程，只调用一次 scanner.get，不预热；预热每项每组
3 个独立进程，各进程取 7 次批量计时的中位数，再取三个进程的中位数。

| 40 行 / 工作负载，ms | 单级边界，无码点值缓存 | 两级索引，含码点缓存 |
| --- | ---: | ---: |
| ASCII / 冷启动首次扫描 | 3.130 | 3.553 |
| ASCII / 仅创建 Cursor | 0.125 | 0.180 |
| ASCII / 预热扫描 c | 1.151 | 1.220 |
| ASCII / 逐键 shi | 1.647 | 1.791 |
| 中英文 / 冷启动首次扫描 | 4.017 | 4.444 |
| 中英文 / 仅创建 Cursor | 0.118 | 0.162 |
| 中英文 / 预热扫描 c | 1.062 | 1.067 |
| 中英文 / 逐键 shi | 1.436 | 1.538 |

冷启动首次扫描约增加 0.42 ms（ASCII +13.5%，中英文 +10.6%）；这批测量没有任何
source 消费新码点接口，因此只体现索引布局及缓存成本。不能把该功能称为整体扫描
优化；构造期多写数据、码点回调和读取时的额外查表都可能影响耗时，本次未分别归因。
隔离 fresh-c 的 GC 后保留 Lua 堆：

| 40 行，KiB | 无码点值缓存 | 两级索引，含码点缓存 |
| --- | ---: | ---: |
| ASCII | 391.4 | 474.9 |
| 中英文 | 221.8 | 265.4 |

ASCII 增约 84 KiB，中英文增约 44 KiB；包含 state 与结果，不是 RSS。
仅创建 Cursor 的进程内存受到循环残留及 JIT trace 引用影响，这里只使用隔离 fresh-c
结果评价保留内存，不将其它工作负载末尾的堆差值当作精确 Cursor 大小。

局部读取收益另用 bench_codepoint.lua 测量：文本为 (á中👩‍💻🇨🇳) × 8，共 32 个字素；
先构造游标并预热所有 get(1) 字符串缓存，计时反复遍历并累加每个字素的首码点值。
构造与字符串预热不计时，遍历推进计时。每项取 3 个独立进程的中位数。

| 完整遍历 32 个字素 | 中位数，微秒 |
| --- | ---: |
| 旧布局 get(1) + char2nr | 2.943 |
| 新布局 get(1) + char2nr | 2.975 |
| 新布局 get_codepoint() | 0.113 |

新布局下数值读取约为原生 char2nr 路径的 1/26 耗时；这是局部、预热后的读取对照，
没有 source、完整 matcher、UI 或真实输入事件，不能外推为整体搜索加速 26 倍。
原生路径写成 vim.fn.char2nr((text:get(1)))，用括号截断 get(1) 的多个返回值。

验证：17 个现有测试入口全部通过；Cursor 的 775 个 Unicode/边界用例同时核对了
相对码点索引、负偏移和越界行为，另覆盖 NUL、最大 Unicode 标量、无效 UTF-8，
并验证重复读取不重新分段。自定义 scope 新增码点读取用例；原 scope 的完整字素
匹配语义不变。LuaLS 使用真实 Neovim/Flash library 和全部诊断级别，结果无诊断。
中英文 README、source 文档、开发文档及帮助已同步。

复现（两个目录分别保存本节修改前后版本；每次命令运行独立进程，串行交替重复）：

```sh
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-codepoint.log nvim --clean -l scripts/bench_grapheme_cold.lua /path/to/before ascii
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-codepoint.log nvim --clean -l scripts/bench_grapheme_cold.lua /path/to/after ascii
# 改为 chinese 测中英文；预热单项用 bench_grapheme.lua ROOT ascii fresh-c。
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-codepoint.log nvim --clean -l scripts/bench_codepoint.lua /path/to/after native
taskset -c 0 env NVIM_LOG_FILE=/tmp/flash-any-codepoint.log nvim --clean -l scripts/bench_codepoint.lua /path/to/after cached
```

本轮基线 /tmp/flash-any-codepoint-before-mke0b_1w/；原始记录
/tmp/flash-any-codepoint-results/{raw.jsonl,summary.json}。

English: Cursor now uses grapheme-to-codepoint and codepoint-to-byte indexes plus cached
scalar values, removing the separate final-codepoint array. get_codepoint(pos) uses a
relative codepoint offset: 0/current, 1/next, -1/previous. Out-of-range reads return nil;
malformed bytes are -1. Warm cached numeric reads took about 1/26 the native char2nr
path's time in the microbenchmark, but cold complete scans increased about 0.42 ms and
retained heap grew 44–84 KiB per 40 lines. This adds a read API with measurable setup
cost rather than a general scan optimization. All tests and full LuaLS diagnostics passed.


## 码点值改为紧密 Lua 字符串（2026-11-06）

只改变 _codepoints 的存储与读取，字素 → 码点 → byte 两级索引及字符串片段缓存
保持不变。四组临时实现均通过 Cursor 的 775 个 Unicode/边界用例，以及 scope、
match/init、match/word、match/char，包含相对负偏移、越界、NUL、最大标量及无效 UTF-8。
正式实现仍使用整数数组，本实验未改生产代码。

| 方案 | 构造与读取方式 |
| --- | --- |
| array | 当前 Lua 数组，直接按下标读取数值 |
| string3 | 每个码点加一后打包为小端 3 字节；string.char 生成小块，table.concat 合并；读取用 string.byte 取三字节再还原 |
| string4-ffi | 构造期 FFI uint32_t 缓冲区，完成后复制成 Lua 字符串；读取临时转为 uint32_t 指针，检查范围后读取，不保留指针 |
| utf8 | 不额外存码点值；通过已有 byte 索引找到原始 UTF-8 中的码点，再调用同一分段器的严格解码函数 |

两个打包方案用 codepoint + 1 编码：无效字节 -1 编为 0，合法 NUL 编为 1，
最大标量 0x10FFFF 编为 0x110000，三字节可容纳；负偏移和越界在读字符串前检查。
FFI 方案使用本机字节序，字符串只作为进程内缓存；没有序列化或跨平台交换格式。
utf8 是对照方案，不等同于缓存已解码的数值。

固定 CPU 0，串行运行，默认 GC/JIT。每场景每方案冷启动 72 个独立进程，运行顺序
遍历四组的 24 种排列；预热每项每方案 3 个独立进程，各进程取 7 次批量计时中位数，
再取三个进程的中位数。扫描仍含 Cursor 创建、匹配和结果分配，不含 source 初始化。
完整扫描的 source 不调用 get_codepoint，因此主要比较构造/GC 成本，不是数值读取收益。

| 40 行 / 工作负载，ms | array | string3 | string4-ffi | utf8 |
| --- | ---: | ---: | ---: | ---: |
| ASCII / 首次扫描 | 3.630 | 3.864 | 3.354 | 3.329 |
| ASCII / 仅构造 | 0.187 | 0.254 | 0.144 | 0.128 |
| ASCII / 预热扫描 c | 1.259 | 1.325 | 1.208 | 1.202 |
| 中英文 / 首次扫描 | 4.662 | 4.905 | 4.694 | 4.585 |
| 中英文 / 仅构造 | 0.160 | 0.222 | 0.165 | 0.126 |
| 中英文 / 预热扫描 c | 1.086 | 1.225 | 1.039 | 1.020 |

纯 Lua 3 字节字符串的构造比数组约慢 36%–39%，首次扫描约慢 5%–6%。FFI 打包
ASCII 首次扫描较快，中英文基本持平；没有稳定的跨场景速度优势。headless 进程总
耗时还包括模块加载、source 初始化、buffer 准备、输出及退出，另列如下，单位 ms：

| 进程总耗时 | array | string3 | string4-ffi | utf8 |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 11.373 | 11.600 | 11.001 | 10.959 |
| 中英文 | 12.285 | 12.561 | 12.298 | 12.344 |

局部读取用同一个 bench_codepoint.lua，预热后遍历 32 个字素，累加首码点数值；
包括推进，不包括构造、source、完整 matcher 或 UI。单位为每次完整遍历的微秒：

| array | string3 | string4-ffi | utf8 |
| ---: | ---: | ---: | ---: |
| 0.122 | 0.175 | 0.122 | 0.491 |

紧密字符串需要在读取时还原数字；纯 Lua 的 string.byte 和算术成本超过了数组直接
读取，约慢 50%。FFI uint32_t 读取接近数组，但需要原生类型构造、临时指针转换和
显式边界检查。直接解码原 UTF-8 最省存储，读取约为数组耗时的 4 倍。本结果不能
外推成 UI 按键延迟，也不代表打包所有索引数组会有同样结果。

内存另开进程测量，jit.off，构造 40 个 Cursor，完整 GC 后取堆差值，保留所有对象；
不做匹配或 get(1) 字符串预热，不含 require 阶段的固定模块开销。每条输入为
(local result = cursor:get(1) -- 工作记录 á👩‍💻🇨🇳; ) × 2；unique 在末尾追加不同的行号。

| 保留 Lua 堆，KiB | array | string3 | string4-ffi | utf8 |
| --- | ---: | ---: | ---: | ---: |
| 40 条相同内容 | 142.8 | 100.3 | 100.3 | 100.0 |
| 40 条不同内容 | 149.1 | 118.3 | 122.1 | 106.3 |

相同字符串会驻留共享，因此相同行的打包缓存只需一份；不能只用该场景估计真实行
数据的收益。不同内容时 string3 相比数组省约 21%，string4-ffi 省约 18%，直接使用
原 UTF-8 省约 29%。这些是 Cursor 整体堆差值，不是单独码点缓存大小，也不是 RSS。

脚本同时记录停止 GC 后重新构造同样 40 条输入的堆增量 allocated_kib；这包含临时
数组、FFI 缓冲区和字符串，但已有相同字符串可驻留复用，不能作为无共享的冷启动
峰值；不依据此数字判断 RSS。3 字节方案还需临时块表和 concat，紧密存储并不等于
构造期间没有临时分配。

结论：纯 Lua 紧密字符串适合进一步节省常驻内存，当前没有速度收益。FFI 方案读速
接近数组、部分构造更快，但增加实现及依赖成本，当前不据此替换正式数组缓存。

复现（生成四种副本、运行语义测试，再串行测量）：

```sh
python scripts/bench_packed_codepoints.py
# 仅用于检查脚本运行，不用于性能结论：
python scripts/bench_packed_codepoints.py --cold-samples 1 --warm-samples 1
```

本轮记录：/tmp/flash-any-packed-codepoints-3br0eurg/{raw.jsonl,summary.json}；
临时实现及独立内存脚本 heap.lua 保留在同一目录。

English: Packing only decoded codepoint values into three-byte Lua strings reduced
retained heap by about 21% for 40 distinct mixed-text lines, but reads were about 50%
slower and construction about 36%–39% slower. Four-byte strings read via LuaJIT FFI
matched array read speed, with mixed first-scan results and additional implementation
cost. Identical-line memory results benefit from string interning and are reported
separately. Production keeps the numeric array; benchmarks and temporary variants remain
available for reproduction.


## 完整 C Cursor 与 C 构造 + LuaJIT 读取（2026-11-06）

原型不是只把某个 getter 改成 C：UTF-8 严格解码、Unicode 17 字素分段、三张连续的
32-bit 索引/码点数组、游标状态与完整读取方法都写入了 C。使用原 Lua 属性表生成
C 页索引和范围表，保持 ASCII/Hangul 分支和所有 RI、ZWJ、Indic 分段规则；没有换
Unicode 版本或第三方分段器。C 构造不逐码点回调 Lua。

比较三种绑定，正式 lua/flash-any/cursor.lua 本轮未修改：

| 方案 | 数据及方法 |
| --- | --- |
| lua | 当前纯 Lua Cursor，两级索引和码点值均为 Lua 数组 |
| native | 完整 C userdata；方法及 value/offset 字段访问通过 Lua C API / __index；缓存字符串仍由 Lua 表和 GC 持有 |
| ffi | 同一 C 构造器和紧密索引；返回 Lua 包装表，短方法保留 Lua，LuaJIT 通过 FFI 指针读取 native 索引，不在每次读取时调用 C 函数 |

C 临时构造缓冲区与最终精确大小的对象均为 Lua 所有的 userdata，不用外部 malloc，
因此可被 GC 正常记账和回收。userdata 的 environment 固定持有原输入及字符串缓存；
ffi 包装表同时持有 userdata 所有者和借用指针，指针不独立延长底层内存生命周期。
最终对象保存一份连续的 int32 码点值、uint32 byte 边界与 uint32 字素边界；byte 定位
仍顺扫，不恢复反向表或添加二分。native 对象类型为 userdata，ffi 方案仍为 table。

文件：[C 原型](../scripts/bench_cursor.c)、[FFI 绑定](../scripts/bench_cursor_ffi.lua)、
[构建及测试/性能脚本](../scripts/bench_native_cursor.py)。构建只发生在 /tmp；没有接入
生产 require 路径或增加插件默认加载入口。实验环境 Linux x86-64，cc -O3，LuaJIT 2.1，
Neovim 0.12.6；不代表已完成 Windows/macOS 的构建、ABI 与发布适配。

固定 CPU 0，串行执行；冷启动每场景每组 72 个独立进程，三组顺序在 6 种排列间轮换。
每进程只扫描一次，无预热。source 为 literal + 单字素拼音 initial，40 行，输入 c。
下面是 scanner.get 耗时，含 Cursor 构造、扫描和结果分配，不含 source 初始化，单位 ms。

| 首次扫描 | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII | 3.492 | 4.860 | 2.789 |
| 中英文 | 4.972 | 4.594 | 3.718 |

ffi 方案分别减少约 20.1%、25.2%，但完整 C userdata 没有稳定胜出：ASCII 更慢，中英文
略快。冷启动也有波动，中英文 lua 的最小–最大为 3.151–9.067 ms，ffi 为 2.447–9.112 ms；
这里的百分比只描述本批中位数。包含加载动态库/FFI、初始化、准备 buffer、输出和退出
的 headless 进程总时间另列，仍不等于实际 UI 按键延迟：

| 进程总时间，ms | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII | 10.865 | 12.153 | 10.282 |
| 中英文 | 12.338 | 11.918 | 11.195 |

预热每个 fixture/workload 独立进程，每组 3 个进程；每进程取 7 次批量计时的中位数，
再取三个进程的中位数。保持默认 JIT/GC，沿用 bench_grapheme.lua 的 source 和输入。

| 仅创建 40 个 Cursor，ms | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII | 0.182 | 0.036 | 0.046 |
| 中英文 | 0.161 | 0.047 | 0.057 |
| 正文 + emoji | 0.184 | 0.053 | 0.063 |
| 密集 ZWJ | 0.193 | 0.048 | 0.059 |

完整 C 构造约为 Lua 耗时的 1/3–1/5，ffi 包装后仍约为 1/3–1/4；这说明解码、
分段和连续存储值得搬到 C。不过构造时间不是完整输入延迟，不能沿用该倍数评价搜索。

| 预热完整扫描 / 连续输入，ms | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII / 扫描 c | 1.231 | 5.968 | 1.060 |
| ASCII / 逐键 shi | 1.878 | 8.848 | 1.591 |
| ASCII / 逐键 coder | 1.338 | 6.778 | 1.231 |
| 中英文 / 扫描 c | 1.058 | 5.187 | 0.941 |
| 中英文 / 逐键 shi | 1.544 | 7.473 | 1.511 |
| 中英文 / 逐键 coder | 1.335 | 5.864 | 1.245 |

完整 userdata 在 ASCII/中英文预热扫描反而约为 Lua 耗时的 4–5 倍。其热路径包含多次
C __index、Lua C API 方法调用、参数验证、Lua 缓存表访问与返回值转换；不能因为内部
数组是 C 就认为短方法也应全部改成 C。两种 C 绑定共用分段与存储实现，但不同热路径
成本并未进一步逐项归因。

ffi 避免逐次进入 C API，通常保留了构造收益；也不是所有输入都更快：密集 ZWJ 的
coder 为 2.166 → 2.351 ms（+8.6%），而该场景 fresh-c 为 0.577 → 0.431 ms。

关闭 JIT 的 fresh-c 复核，单位 ms：

| JIT off | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII | 5.062 | 6.438 | 6.355 |
| 中英文 | 4.404 | 5.770 | 5.494 |

ffi 路线的优势依赖 LuaJIT 能优化指针读取及短方法；解释执行时更慢，不支持将本实验
结论推广到所有 Lua 运行时。

局部数值读取沿用 bench_codepoint.lua，预热后遍历 32 个字素并累加首码点，包含
字段访问、get_codepoint 和 shift，不含构造或 source。每次完整遍历耗时，单位微秒：

| lua | native | ffi |
| ---: | ---: | ---: |
| 0.113 | 6.323 | 0.070 |

native 的差距包含字段、方法分派和推进，不能把它全部当作一次码点数组读取的开销。

保留内存只看隔离 fresh-c、完整 GC 后的 Lua 堆，含 state 和结果，KiB：

| 40 行 | lua | native | ffi |
| --- | ---: | ---: | ---: |
| ASCII | 474.7 | 283.4 | 303.9 |
| 中英文 | 265.4 | 181.7 | 202.4 |
| 正文 + emoji | 401.0 | 313.5 | 334.3 |
| 密集 ZWJ | 320.6 | 247.4 | 268.2 |

这包含 userdata 的数组内存，也包含 ffi 包装表和指针对象，不含动态库映射、生成的
只读属性表和 require 阶段的固定开销，不是 RSS。ffi 方案 ASCII/中英文约省 36%/24%。
不能用仅构造工作负载最后的堆差值代替精确对象大小：JIT trace 与循环返回值可能保留
额外引用；本报告没有据此宣称峰值内存改善。

验证：三组均通过全部 17 个测试入口，包含 Cursor 的 775 个 Unicode/边界用例、
完整 match/source/scope/Flash/char/remote 测试。native 唯一测试调整是把“string.sub
调用一次”的实现计数改为检查同一后缀缓存，未改匹配结果断言；C 通过 lua_pushlstring
构造字符串，本来不会调用 Lua 的 string.sub。ffi 使用原测试，不需要该调整。
另外构造 500 个含组合音标、ZWJ、NUL、坏字节和唯一行号的对象，反复 GC 后验证所有
字段和码点读取。native/ffi 另以 UBSan 编译运行 Unicode、增量匹配、多字素和 GC
用例，无 undefined-behavior 报告。C 构建开启 -Wall -Wextra -Werror，LuaLS 保留真实
Neovim/Flash library 与全部诊断级别，FFI 字段补真实结构类型说明，检查无诊断。

当前结果支持“C 构造和持有索引，LuaJIT 负责短读取方法”，不支持直接把全部 Cursor
方法改成 C 就会整体快数倍。要接入生产还需决定编译、平台支持和发布方式；本轮只
保留原型和复现入口，不引入自动回退、可选后端配置或新的生产加载层。

复现要求本机 cc、pkg-config 和 LuaJIT 开发头文件/库，原型脚本使用 Linux shared-library
编译参数，Unicode 数据从仓库本地生成，不联网下载：

```sh
python scripts/bench_native_cursor.py
# 少量样本检查流程，不用于性能结论：
python scripts/bench_native_cursor.py --cold-samples 1 --warm-samples 1
```

本轮记录：/tmp/flash-any-native-cursor-6l1iw8s4/{raw.jsonl,summary.json}；生成的属性头文件、
共享库、三组独立快照、gc.lua 与 UBSan 变体均保留在同一目录。

English: A complete C userdata Cursor constructed about 3–5 times faster, but frequent
Lua/C method and field calls regressed warm ASCII/Chinese scans by about 4–5 times.
The same C indexing/storage with LuaJIT/FFI short methods reduced cold scan medians by
20%/25% and retained Lua heap by 36%/24% in those fixtures; one dense-ZWJ typing case
still regressed. All 17 test entries, additional GC ownership checks, UBSan checks and
full LuaLS diagnostics passed. At this experiment stage production remained Lua; the C prototype and benchmark
runner are retained without introducing a production backend or loader.

## 二进制码表与 Rime MARISA 对照

本轮改为一次调用 C 扫描完整文本范围，而非 Lua 逐字素调用 C Cursor。
构建完整码表、字符串/编码集合去重、词组前缀和静态哈希都提前完成；加载时直接
校验并查询二进制数据。生产构建只需 C/LuaJIT，MARISA 是可选对照项。

参考 librime 的 [ReverseDb](https://github.com/rime/librime/blob/master/src/rime/dict/reverse_lookup_dictionary.cc)
及 [StringTable](https://github.com/rime/librime/blob/master/src/rime/dict/string_table.cc)：
Rime 的反查方向也是文本→编码，使用两棵 MARISA trie 和 key-ID→value-ID 数组。
本实现借鉴静态数据、ID 引用及集合共享，但根据下面的短键查询结果保留哈希。

CPU 绑定同一核心，独立进程交替运行各方案，无并行性能任务。局部查询对同一
码表/条目取最多 256 个均匀分布键，循环到至少 30 ms，7 次取中位数，再取
3 个进程中位数。计时使用 clock()，没有 Lua 调用、文件 IO 或编译；查询及条目
flags 读取均在计时内。MARISA 0.3.1 使用默认构建参数，序列化后 map；同时测
Rime 风格每次新建 Agent 和复用 Agent。所有抽样查询先校验与生产哈希结果相同。
这是小查询集的热缓存 CPU 测量，不能等同于整表随机访问或编辑器响应延迟。

| 完整码表 | 哈希命中 ns | 有序表二分 ns | MARISA 新 Agent ns | MARISA 复用 Agent ns | 哈希文本索引 KiB | MARISA 文本索引 KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pinyin | 9.58 | 70.55 | 110.29 | 100.82 | 751 | 250 |
| tiger | 8.75 | 87.88 | 144.78 | 135.10 | 2158 | 550 |
| wubi86 | 9.13 | 65.74 | 138.97 | 129.82 | 1310 | 392 |
| unicode | 9.37 | 60.94 | 114.05 | 103.61 | 709 | 225 |
| nerdfont | 8.63 | 65.72 | 92.39 | 82.46 | 185 | 62 |
| 2000 个三字素词组 | 12.65 | 45.07 | 125.17 | 118.48 | 114 | 37 |

索引体积仅对比文本→条目映射：哈希含槽位、key offset/length 及键字节；MARISA
含 trie image 和到相同条目序号的 u32 映射，不含共享编码数据和 scope。直接按
MARISA key ID 排列 payload 可省去这层序号映射。哈希键字节按独立文本索引计，
不扣除与全局字符串池其他内容碰巧相同的部分。MARISA 并非整个包缩小到这个比例。
对照程序输出的 load_ms 仍是公共二进制包的 C 校验时间，**不是 MARISA 加载耗时**；
本轮没有比较两种完整文件格式的冷加载。

同一机器的首次加载使用9个全新 Neovim进程/方案，交替运行；包括模块 require、
文件读取及准备，hrtime 计时。Lua 为常用表加按需 TSV，二进制为完整冻结快照，
覆盖范围/常驻数据量不同；collectgarbage 后只统计 Lua 所有堆，不是 RSS。

| 码表 | 完整条目 | 二进制字节 | Lua 加载 ms | 二进制加载 ms | Lua 保留 KiB | 二进制保留 KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pinyin | 44469 | 1348694 | 3.49 | 1.19 | 1060 | 1322 |
| tiger | 99171 | 4595520 | 4.10 | 2.46 | 1252 | 4493 |
| wubi86 | 70394 | 3011822 | 4.08 | 1.85 | 1266 | 2946 |
| unicode | 40162 | 3090098 | 4.41 | 2.02 | 1174 | 3023 |
| nerdfont | 10604 | 678563 | 4.13 | 0.60 | 1095 | 668 |

二进制存索引而非压缩原文本：对应原 TSV 分别约 401/980/675/1363/283 KiB，
不能宣称文件更小或总体内存一定更少。C 直接 fread 到 Lua-owned userdata，避免
Lua io.read 的临时完整字符串和缓冲；加载后不重建每条数据对象。此轮初次编译
完整表约 130/553/382/369/57 ms，构建不属于启动或输入扫描计时。

完整范围扫描用40行相同混合文本，每行重复4次
`中国人民学习中文，ASCII flash_any 混合文本。`，sources 仅 pinyin；依次输入
`z → zh → zho → zhon → zhong → zhongg → zhonggu → zhongguo`。
每种后端/冷热情况7个独立进程交替取中位数。模块与码表加载单独计时，不含源码
编译和码表生成；扫描包括 Neovim 文本获取、分段、匹配、合并和 Lua 结果对象构造，
不含 Flash 绘制、按键分发或进程启动。两种后端总候选数均为2080。

| 阶段，ms | Lua | C 二进制 |
| --- | ---: | ---: |
| 模块及码表加载 | 3.68 | 1.25 |
| 首次输入扫描 | 5.54 | 0.46 |
| 同一进程预热后的新 `z` 扫描 | 1.06 | 0.26 |

首次扫描 CPU 为5.522/0.455 ms，与 elapsed 接近。冷进程后续7次输入中，Lua 每次
0.48–2.19 ms，C 每次0.25–0.38 ms；预热后两者多数在0.24–0.39 ms附近，C并非
每次更快。这只是固定重复文本的对照，不覆盖任意文档、码表组合及真实交互延迟。
C 当前在输入变化时重新扫描已有行索引，Lua 保留增量匹配缓存；C 相同输入复用
候选，Flash state 内复用行索引，独立跳转之间只共享码表。

复现入口：

```sh
make
python scripts/bench_binary.py
python scripts/bench_binary.py --marisa  # 另需 pkg-config marisa、C++17 编译器
# 上个命令会输出临时目录，以下 PACKAGE 为其中的 pinyin.bin
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_binary_load.lua pinyin binary PACKAGE
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_native.lua lua PACKAGE cold
NVIM_LOG_FILE=/tmp/flash-any-bench.log nvim --clean -l scripts/bench_native.lua binary PACKAGE cold
```

原始记录：`/tmp/flash-any-binary-bench-016al9te/{raw.jsonl,summary.json,build.jsonl,load-raw.json,load-summary.json}`，
MARISA 对照 `/tmp/flash-any-binary-bench-3akq_k9u/{raw.jsonl,summary.json}`，
扫描 `/tmp/flash-any-native-scan-raw.json`。新增后端通过528组 Lua/C差分、775组
C Cursor Unicode/边界测试、真实 Flash jump/char/remote 集成和 UBSan；全部原有
测试通过，LuaLS 使用真实 Neovim/Flash library 和全部诊断级别，无诊断。

English: Rime's reverse dictionary informed the immutable ID/shared-value layout.
MARISA produced a smaller text index, but even a reused Agent was much slower for
these hot short-key queries, so production retains a static hash without MARISA.
Complete binary packages load faster here while often retaining more dictionary
data than lazy Lua/TSV. The 40-line fixture's first scan fell from 5.54 to 0.46 ms;
warm continuations were much closer and did not improve uniformly. These timings
exclude Flash rendering and key handling. The optional C backend is now available
through build.binary and setup({binary = path}); Lua remains the default backend.

## 单码点分页索引

在上述 C 二进制后端上仅改变文本→条目索引。单个合法 Unicode 码点键（含词组的
单码点前缀）进入两级数组，复杂字素、词组和非法 UTF-8 键保留静态哈希。
`cp >> 8` 定位页，`cp & 255` 定位槽；目录 4352 个 u32，只有出现的页分配
256 个 u32。槽保存条目序号+1，0 表示没有条目。C 扫描已缓存每个码点及字素边界，
仅当当前完整字素恰好含一个合法码点时使用整数索引，不重新解码、不比较键字节，
不增加 Lua/C 调用或查询缓存。复杂字素不能仅凭首码点认领，例如 `a` 不匹配 `á`。

`scripts/bench_binary.py` 继续独立进程、同核心、交替顺序、相同键和条目，热查询
7次采样/进程、3进程中位数；哈希对照在计时外按旧规则重建完整文本哈希。
scalar 模式在计时外取得码点，符合扫描器已有解码结果的条件；pages 模式计时内
重新解码，分开记录。查询和读取条目 flags 在计时内，无 Lua 调用。未单独测 Lua
数字表，因此不能据此声称比 Lua 数字表快。命中结果如下：

| 码表 | 旧文本哈希 ns | 已有码点分页 ns | 含解码的分页 ns | 旧二进制字节 | 新二进制字节 |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinyin | 9.74 | 2.44 | 4.65 | 1348694 | 1500254 |
| tiger | 10.00 | 2.34 | 5.40 | 4595520 | 3968840 |
| wubi86 | 9.58 | 2.35 | 4.89 | 3011822 | 2823414 |
| unicode | 9.92 | 2.48 | 4.95 | 3090098 | 3049146 |
| nerdfont | 8.81 | 2.21 | 4.91 | 678563 | 681643 |

页大小按16/32/64/128/256/512测算目录及槽位体积；256在这些内置数据上接近
最小，但不是每张表都比哈希省空间。拼音条目分布稀疏，页内空槽使文件增加约
148 KiB；虎码减少约612 KiB，五笔减少184 KiB，Unicode减少40 KiB，Nerd Font
增加3 KiB。保留固定页大小和简单两级读取，未增加 bitmap/rank 或不同源自选格式。
本版仍保留 key 描述和字符串用于复杂键、校验与通用查询，并未移除所有文本数据。

完整扫描沿用40行混合文本、pinyin、8次逐键输入。优化前后的模块/共享库快照
独立加载，同一核心交替运行各9个全新进程，加载和扫描分开计时。首次扫描中位数
0.459→0.443 ms（CPU 0.455→0.441 ms），约3.4%；加载1.236→0.901 ms。
后续各次输入大多接近，部分样本更慢，不能由局部查询4倍推断完整扫描也快4倍。
不含 Flash 绘制和按键处理，结果总数同为2080。

二进制格式升级 `FANYBIN\4`，source 描述52 bytes，追加页数；u32索引 section
保存该 source 的复杂键哈希、页目录及页槽。运行时不重建任何码表索引，旧包须
重新调用 build.binary。行索引和相同输入的候选缓存仍保留，独立于码表查找。
554组 Lua/C 差分（新增首码点误匹配、NUL、最大码点、非法字节和词组前缀）、
真实 Flash jump/char/remote 集成及 UBSan通过；真实 Neovim/Flash library下的
LuaLS全部级别检查无诊断。

记录：`/tmp/flash-any-binary-bench-9gpxpgy8/{raw.jsonl,summary.json,build.jsonl}`；
完整扫描 `/tmp/flash-any-page-scan-raw.json`；旧模块快照 `/tmp/flash-any-before-codepoint`。
复现局部测试用 `python scripts/bench_binary.py`；完整扫描脚本可用第4个参数指定
后端 runtime 根目录，以便分别加载旧/新模块和各自格式的码表。

English: Single-scalar graphemes now index compiled sparse codepoint pages directly,
without a dictionary lookup cache. Compound graphemes/words retain the text hash.
Hot scalar hits fell from roughly 9–10 to 2.2–2.5 ns, while the 40-line first scan
improved only about 3.4%. File size depends on sparsity: pinyin grew about148 KiB,
whereas tiger shrank about612 KiB. Packages use format v4 and must be rebuilt.

## 多码点字素 hash 的结构分析（实验，未修改运行时）

对照脚本为 `scripts/bench_grapheme_hash.py` 和 `.c`。首先用当前 Unicode17
分段器过滤为完整单字素，再去重；不把词组混入字素样本。五张内置完整表逐一
materialize 后共264800条（跨表未去重），全部是单码点。因此本轮针对未来组合
字素/完整 emoji 数据，不会直接改善当前这些内置表的数组查询路径。

Unicode 的结构依据是 [UAX29](https://www.unicode.org/reports/tr29/) 和
[UTS51](https://www.unicode.org/reports/tr51/)。多码点字素包括基字符+Extend/
SpacingMark、Prepend、Hangul Jamo 连写、Indic 辅音/连接符连写、两个区域指示符、
肤色/变体选择符/键帽/ZWJ/tag emoji序列；Extend 等可以重复，长度没有固定上限。
ZWJ/VS/肤色/标记顺序都不能丢弃。本插件没有归一化，不合并原始不同序列。

样本来源：Unicode17官方 `emoji-test.txt` 中3825个多码点序列，涵盖fully/minimally/
unqualified形式（互斥分类为ZWJ2667、肤色665、旗帜259、VS207、键帽24、tag3）；
Python Unicode16 NFD产生并经Unicode17分段器过滤的1046个非Hangul字素、11172个
Hangul分解字素；2184个由a/b和3种重音标记的1至6位有序组合构造的压力样本；
项目Unicode17 GraphemeBreakTest中的242个多码点字素。合并去重18463个。
NFD只用于造测试输入，不改变匹配语义；此语料没有模拟真实文档的出现频率。

对32位结果及截断结果统计碰撞，再按生产规则取二次幂槽数、线性探测；combined
为32768槽、56.3%负载。碰撞数指超出不同hash值数量的额外键数，不是碰撞对数。
平均/最大探测数为按相同字典序插入所有键时的槽访问数，不是端到端查询时间。
CPU微测使用已解码码点和原UTF8，文件IO/分段/解码在计时外，每次独立进程，
同核心交替顺序、3进程中位数，每进程5次、校准到至少15ms；只计计算hash，
不包含表探测和原文比较。ns列均是combined语料平均，不是对应子集的延迟。

| 算法 | 完整32位额外碰撞键 | 平均插入探测 | 最大插入探测 | 仅hash约ns/字素 |
| --- | ---: | ---: | ---: | ---: |
| 码点相加 | 15757 | 3634.31 | 11779 | 1.34 |
| 码点多项式×31 | 27 | 33.32 | 2009 | 1.85 |
| 码点多项式×33 | 41 | 30.82 | 1862 | 1.84 |
| 码点多项式×65599 | 0 | 11.23 | 505 | 1.84 |
| 码点多项式×0x9E3779B1 | 0 | 8.17 | 166 | 1.84 |
| 循环左移5位再异或码点 | 73 | 102.40 | 3078 | 1.84 |
| 循环左移13位再异或码点 | 136 | 992.77 | 3224 | 1.79 |
| 现有逐UTF8字节FNV-1a | 0 | 1.70 | 46 | 3.74 |
| FNV式逐码点异或/乘法 | 0 | 1.66 | 28 | 1.85 |
| 多项式×33 + fmix32 | 41 | 1.69 | 36 | 1.79 |
| 多项式×0x9E3779B1 + fmix32 | 0 | 1.62 | 23 | 1.78 |
| 结构分类位打包+通用后备 | 0 | 2.55 | 185 | 1.92 |
| 结构分类位打包+通用后备+fmix32 | 0 | 1.63 | 27 | 1.85 |

fmix32来自公有领域 [MurmurHash3](https://github.com/aappleby/smhasher/blob/master/src/MurmurHash3.cpp)。
它在完整32位上是置换，只改善位分布，不能消除前一步已经产生的相同hash值。
例如乘31确实让 `D+0323` 与 `E+0304` 相撞：`31*0x44+0x323 == 31*0x45+0x304`。
乘33同理让 `A+0328` 与 `B+0307` 相撞。保留长度作初始状态仍然无法区分这些
相同长度的键。Hangul有规律的低位让乘31在其独立语料上平均插入81次。
因此必须同时看完整hash碰撞和实际槽位聚集，不能只统计完整32位是否不同。

结构分类实验对两码点旗帜用26进制、0300–036F组合标记用base<<7|mark、
FE00–FE0F用base<<4|selector、肤色用base<<3|modifier，并分配互不重叠类型前缀；
其余使用带类型前缀的29位FNV码点后备。前四类在各自范围可一一编码，后备仍
可能冲突。完整值不碰撞不代表低位分槽均匀；再加fmix32后才接近通用算法，
但增加规则/分支，不能由本轮数据证明值得接入生产。

建议候选为FNV式码点混合：初值2166136261，每个已解码码点执行
`h = (h ^ cp) * 16777619`，uint32自然回绕；它是码点变体，不是标准的字节FNV。
本轮全32位/低31位均无碰撞，低21位产生42个额外碰撞键，故不宜为了内部编码
空间贸然压缩到21位。若要分离真实码点与复杂字素hash，可用高位标志加31位
结果，但仍需处理冲突/原文校验。样本无碰撞不能保证其他字素或未来数据无碰撞。
该候选可以直接读已缓存码点，或在分段时对多码点字素累计；尚未测完整扫描收益，
本轮不替换运行时算法、不新增字素hash数组/缓存。

复现：下载官方数据到临时目录，然后运行：

```sh
curl -fL https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt -o /tmp/emoji-test.txt
python scripts/bench_grapheme_hash.py --emoji /tmp/emoji-test.txt
```

报告 `/tmp/flash-any-grapheme-hash-cw_fmp53/report.json` 含分组、完整/31/21位碰撞、
槽位/探测数及逐进程CPU数据。生成的C内核使用-O3和-Wall -Wextra -Werror，
与本轮完整样本一起运行通过；没有改动生产API，不涉及端到端性能结论。

English: An 18,463-key Unicode/grapheme corpus exposed collisions and severe bucket
clustering in simple sums, rotations and small polynomial multipliers. A codepoint-wise
FNV-style xor/multiply retained ordering with zero full-32-bit collisions in this corpus,
and roughly halved hash-only CPU time relative to byte FNV. Structured packing handled
some subsets injectively but still required mixing for bucket quality. Results do not
guarantee collision freedom or editor latency improvements; runtime remains unchanged.

## 统一字素索引与 matcher 标记

本轮将前述候选接入生产，并限定二进制键恰好一个完整字素。所有配置码表共用
码点分页数组和复杂字素hash，编译时过滤scope、处理fallback和空编码认识状态，
随后按matcher模式合并去重。运行时不保留source身份、scope、fallback或词组状态。
ASCII literal展开为128个普通索引项；它仍只接受单字节输入字素，`á`不作为`a`
字面匹配。多字素键构建时报错，Lua后端的词组功能保持；连续输入跨字素仍支持。

每个条目改为16bytes：key offset/length、编码列表offset/length。编码以0x80–83
分别标识literal/full_code/initial/prefix，其后的ASCII直到下个标记或列表末尾。
ID兼作分隔符，不存source ID、编码结束符、逐编码ID或编码字符串描述。相同的
整份带标记列表在pool中共享。单码点用现有码点直接查数组；复杂字素以码点做
FNV式xor/multiply，非法字节使用0x110000+原字节的独立token，命中校验原文。
每个扫描位置只查一次字典，复用列表给该位置的所有输入状态，不新增查询缓存。
固定两槽请求环替代按最长词长分配。格式升级FANYBIN v5，旧包需重建。

对照为修改前v4的完整lua/src/native.so快照 `/tmp/flash-any-before-merge`，使用
相同配置和脚本，分别在独立全新Neovim进程加载对应root和对应二进制。3种场景
各冷/暖两组，每个后端9个进程，固定同一核心、交替运行；warm先完成30轮8次
输入，再GC后测新一轮。编译发生在测量之外；构建数据另列单次观测，不作为稳定
编译耗时结论。load包含模块加载/文件读取/校验，first包含文本获取、行分段、C
匹配和Lua结果构造；typing为8次输入扫描之和。全部排除Flash绘制、按键分发和
进程启动。Lua-owned字典堆在GC后统计，非RSS；没有并行性能任务。

| 配置 | v4字节 | v5字节 | 变化 |
| --- | ---: | ---: | ---: |
| pinyin | 1500254 | 1316413 | −12.3% |
| 五张内置表 | 11338490 | 6027609 | −46.8% |
| 小型组合字素表 | 19153 | 22147 | +15.6% |

五表是pinyin/tiger/wubi86/nerdfont/unicode，按此顺序；Unicode为fallback。
v4有264800条source记录，v5有148555个合并后的可匹配字素（含ASCII）。该差异
包含跨表键合并、scope过滤和删除已被覆盖的fallback，不能仅归因于省分隔符。
单拼音v5有44525字素，小表有134字素；小表增加ASCII索引项而变大。
五表构建单次观测约1.58→1.05s，单拼音0.117→0.124s。

文本均40行，每行重复4次。拼音/五表用
`中国人民学习中文，ASCII flash_any 混合文本。󰊢😀`，输入为
`z→zh→zho→zhon→zhong→zhongg→zhonggu→zhongguo`。
组合字素表用 `á👩‍💻🇨🇳1️⃣👍🏽 x Ω `，混合initial/prefix/full_code/fallback，
输入为`a→ac→acc→acce→accen→accent→accentd→accentdev`。
两版候选数逐次相同，总数分别2080、2240、1440。

| 冷进程，中位数ms | 加载v4→v5 | 首次扫描v4→v5 | 8次扫描v4→v5 |
| --- | ---: | ---: | ---: |
| pinyin | 0.870→1.203 | 0.372→0.226 | 2.461→1.277 |
| 五表 | 4.935→4.499 | 0.822→0.344 | 5.587→1.630 |
| 组合字素小表 | 0.184→0.187 | 0.149→0.132 | 1.113→0.943 |

| 预热进程，中位数ms | 首次扫描v4→v5 | 8次扫描v4→v5 |
| --- | ---: | ---: |
| pinyin | 0.270→0.130 | 2.199→1.082 |
| 五表 | 0.696→0.215 | 5.185→1.249 |
| 组合字素小表 | 0.091→0.076 | 0.831→0.672 |

冷首次CPU分别0.368→0.226、0.821→0.344、0.149→0.132ms，与elapsed接近。
五表Lua-owned字典堆约11078→5891KiB，拼音1470→1290KiB，小表23.8→26.7KiB。
单拼音的加载校验会遍历带标记列表，虽然文件更小，load仍增加约0.33ms；不能
宣称所有配置的“加载+第一次扫描”都变快。主要收益是合表后每位置一次查询与
取消source分派；当前对照同时改变布局、标记编码、字素hash与查询复用，不能
把收益全部算作hash算法本身。数据是固定合成文本，不代表任意文档或交互延迟。

复现：保留v4的完整lua/src快照及已编译native.so，再运行：

```sh
make
python scripts/bench_merge.py /path/to/v4-root
```

记录 `/tmp/flash-any-merge-bench-3fojhj_y/{build.json,raw.json,summary.json}`。
模式ID由C统一导出给构建器，固定两槽工作区不再携带可变槽数。初版记录保留在
`/tmp/flash-any-merge-bench-73ww6d2d`，表格取最终实现的重测。当前局部索引对照
`scripts/bench_binary.py`已适配v5，复杂字素fixture取CJK+组合重音，不再使用词组；
其hash对照也改为码点规则，不能把未来结果直接当作旧UTF8字节hash的同变量复测。

686组Lua/C差分、强制64槽碰撞链、NUL编码、空编码屏蔽fallback、五表合并、
标签/输入/buffer变化、坏文件、确定性与原子构建、共享列表及GC持有均通过；
真实Flash jump/char/remote集成、UBSan和全部原有测试通过。LuaLS使用真实
Neovim/Flash library、全部诊断级别，无诊断。改动仅在工作区。

English: Format v5 merges sources into one complete-grapheme dictionary. Build time
resolves scope/fallback; runtime reads tagged, deduplicated code lists without source
dispatch. Five-table packages shrank from11.34 to6.03MB, with cold first-scan medians
of0.822→0.344ms and eight-input totals5.587→1.630ms on the fixed40-line fixture.
Single-pinyin load validation regressed and small dictionaries grew slightly. Timings
exclude Flash rendering and key handling. Multi-grapheme keys are rejected; continuous
matching across graphemes remains supported. Existing packages must be rebuilt.

## C-only 收敛与常用字缓存对照

最终运行时只加载二进制码表，由 C 完成字素分段、查询、扫描匹配和结果生成。
Lua 保留构建工具与 Neovim/Flash 桥接；删除运行时 Lua matcher、Cursor、自定义
matcher/scope 回调。旧 Lua 实现冻结在 tests/reference，仅供差分测试和历史对照。
当前不实现词组或前缀扩展标记，码表键必须为单个完整字素。

常用字对照使用原 Lua 版本 `d3f1fec`（含常用字缓存），与合表 C 后端分别运行。
固定同一 CPU 核，每组9个独立进程、轮换运行顺序；40行中英混排文本，连续输入
`z, zh, zho, zhon, zhong, zhongg, zhonggu, zhongguo`。构建、加载码表在计时外，
计时段 TSV 查询次数均为0。warm 先运行30轮，再取30轮的进程内中位数，最后取
9个进程中位数。数字是完整扫描耗时，并非单次索引查询或 Flash 端到端延迟。

| 40行场景 | 原 Lua / C（ms） | 加速 |
| --- | ---: | ---: |
| 拼音，冷首次输入 | 4.426 / 0.219 | 20.2倍 |
| 五表，冷首次输入 | 5.052 / 0.331 | 15.3倍 |
| 拼音，warm八次输入合计 | 3.808 / 1.081 | 3.5倍 |
| 五表，warm八次输入合计 | 5.333 / 1.222 | 4.4倍 |
| 拼音，已预热但新建搜索，首次输入 | 1.734 / 0.160 | 10.8倍 |
| 五表，已预热但新建搜索，首次输入 | 1.837 / 0.237 | 7.8倍 |

记录 `/tmp/flash-any-cached-bench-suhifrh2/{baseline.json,raw.json,summary.json}`；
复现 `python scripts/bench_cached.py --samples 9`。该记录在删除生产 Lua 路径前
测得；之后只做收敛及验证，没有重新把清理收益计入性能数字。历史 Cursor、边界
预建等实验针对当时架构，部分脚本需要对应旧版本，不代表当前公开 API。

收敛后通过772组 C Unicode/边界用例、686组 Lua/C 差分、真实 Flash jump/char/
remote 集成及 UBSan。LuaLS 保留全部 Hint 级别诊断与真实 Neovim/Flash library；
clangd 检查生产 C 和内部头文件均无错误。生成头保留于 build/，make 同时生成
真实编译数据库，修复临时头删除导致的 LSP 找不到 grapheme_data.h。

English: Runtime is now C-only; Lua remains for building and editor integration. The
old Lua scanner exists only as a test oracle. Against the original cached Lua version,
the fixed 40-line fixture improved cold first input by 15–20x and warm eight-input
totals by 3.5–4.4x. These measurements exclude loading and Flash rendering. The final
cleanup passed Unicode, differential, integration, UBSan and language-server checks.

## 当前 C 文本/结果缓存收益

`python3 scripts/bench_cache.py --samples 9` 对照当前实现。码表始终已加载，固定
CPU核，每模式9个独立进程、轮换顺序；先预热30轮，再测50轮，先取进程内中位数，
再取进程间中位数。沿用上一节每行重复4次的中英混排文本；只测C scan调用，包含
结果转换为Lua表的开销，不含buffer读取、Flash绘制或文件加载。elapsed和CPU接近。

| 40行场景 | 缓存（ms） | 重建/重扫（ms） | 耗时减少 |
| --- | ---: | ---: | ---: |
| 拼音，八次连续输入，复用/重建文本索引 | 1.101 | 1.453 | 24% |
| 五表，八次连续输入，复用/重建文本索引 | 1.223 | 1.766 | 31% |
| 拼音，同输入重复请求，复用结果/重扫 | 0.060 | 0.125 | 52% |
| 五表，同输入重复请求，复用结果/重扫 | 0.107 | 0.176 | 39% |

单行八次输入的文本缓存收益仅约0.006ms（拼音0.029→0.035、五表0.040→0.046）。
以上为预热后的后续请求，不代表首次输入收益。

文本对照只改变是否每次传入原始行，重建模式仍使用当前三数组布局；结果对照
在临时C副本中仅禁用缓存命中分支，保留结果存储开销。生产源码和库不修改。
因此这些数字衡量现有缓存的复用收益，不能推断“完全移除缓存存储”或“边解码
边匹配的单趟实现”的性能。两组结果数量分别一致；原始数据保存在
`/tmp/flash-any-cache-b9dprt5i/{raw.json,summary.json}`。

English: With dictionaries preloaded, reusing text indexes reduced warmed eight-input
totals by 24–31% on the 40-line fixture. Reusing an identical query result reduced one
request by 39–52%, about 0.065–0.068ms. Rebuilds use the current indexed algorithm;
the experiment does not compare a fused streaming decoder/matcher. Measurements exclude
buffer IO and Flash rendering. Temporary variants preserve production files.

## 单趟解码匹配替换文本索引

当前运行时改为边解码边匹配，删除文本三数组和建索引步骤；保留原始行缓存、
相同输入的结果缓存和只读码表。结果改为命中后追加、按需增长，避免为所有字素
预分配并清零候选。原版本快照 `/tmp/flash-any-indexed-h1ottyzl` 保留独立动态库。

复现 `python3 scripts/bench_scan.py /path/to/indexed-snapshot --samples 9`。
同一CPU核、同一码表和文本，9个独立进程/模式，轮换顺序；warm预热30轮再测30轮，
先取进程内中位数再取进程间中位数。包含Lua适配器、buffer读取/缓存检查及结果
转换，不含码表加载、Flash按键与绘制。两版结果数量一致、计时段TSV查询均为0。

| 40行场景（ms） | 原索引版 | 单趟版 |
| --- | ---: | ---: |
| 拼音，冷首次输入 | 0.2205 | 0.1657 |
| 五表，冷首次输入 | 0.3317 | 0.2734 |
| 拼音，冷八次输入合计 | 1.2872 | 1.1621 |
| 五表，冷八次输入合计 | 1.5726 | 1.5476 |
| 拼音，warm八次输入合计 | 1.0991 | 1.1517 |
| 五表，warm八次输入合计 | 1.2291 | 1.2467 |
| 拼音，已预热但新建搜索，首次输入 | 0.1617 | 0.1333 |
| 五表，已预热但新建搜索，首次输入 | 0.2404 | 0.2107 |

冷首次减少约25%/18%，warm八次总计退步约5%/1%；单行冷首次0.0141→0.0144ms、
0.0192→0.0200ms，没有首次加速。不能宣称所有输入规模都更快。当前优先首次输入，
且单趟实现无需维护文本索引，因此保留单趟版，不添加运行时切换选项。

同一40行fixture、首次输入z，GC后搜索状态保留的Lua分配增量约252.9→21.6KiB；
不含已加载码表和预建原始行，包含候选结果及状态。此fixture各行内容相同，Lua
原始字符串共享；真实文档内存会不同。该数字也不代表峰值或进程RSS。

原始记录 `/tmp/flash-any-scan-m7t2btxd/{raw.json,summary.json,memory.json}`，内存
测量脚本同目录memory.lua。旧文本缓存对照脚本现在需传入索引版快照：
`python3 scripts/bench_cache.py --root /path/to/indexed-snapshot --samples 9`。

单趟版通过774组Unicode/边界/长行用例，覆盖f/F/t/T邻接位置、万码点组合字素与
4096条结果增长；另通过686组Lua差分、Flash集成、UBSan及完整LuaLS/clangd检查。

English: Sequential decoding/matching replaces per-line indexes. On the fixed 40-line
fixture, cold first input improved by 18–25%; warmed eight-input totals regressed by
1–5%. Single-line cold first input did not improve. Raw-line and result caches remain.
The matched-result buffer now grows on demand. Retained search-state Lua allocations
fell from about253 to22KiB on this fixture, excluding dictionaries and original strings;
this is not peak memory or RSS. The sequential version is retained to favor first input.

## 单字素 Lua matcher 由 C 调用的实验

复现：`python3 scripts/bench_lua_matcher.py --samples 9`。生成的C模块仅存在于
临时目录；生产C代码和API不变。实验接口为：

```lua
matcher(grapheme, input, pos) --> consumed_bytes?, next_ascii_byte?
```

grapheme是完整字素字符串，input是完整输入，pos为Lua的1-based byte位置。
函数每个待匹配输入状态调用一次，返回一个消费长度及/或一个下一键byte值。
本次只实现每字素一个ASCII全码，不复原Cursor、source或emit协议，也不声称
覆盖多消费分支的任意Lua matcher。ASCII literal仍由C负责。

固定单核，各模式9个独立Neovim进程，轮换顺序。common沿用40行中英混排文本、
八次输入z→zhongguo；complex使用组合音标、ZWJ emoji、旗帜和肤色修饰字素，
八次输入a/ac/acc/accent/accentd/accentde/accentdev/dev。warm预热30轮，再测30轮；
先取进程内中位数，再取9进程中位数。C和Lua使用同一小型码表，非整套拼音表。
不含字典构建/加载、buffer读取和Flash绘制，含C扫描、参数传递及结果Lua表转换。

| 40行场景（ms） | 生产纯C | 实验模块关闭回调 | 每字素空回调 | 每输入状态空回调 | Lua全码matcher |
| --- | ---: | ---: | ---: | ---: | ---: |
| common，冷首次 | 0.1550 | 0.1519 | 0.3090 | 0.3060 | 0.3428 |
| common，冷八次合计 | 1.2709 | 1.2502 | 2.4780 | 2.5041 | 2.6511 |
| common，warm八次合计 | 1.0702 | 1.0820 | 2.2780 | 2.3211 | 2.3722 |
| complex，冷首次 | 0.1340 | 0.1336 | 0.1961 | 0.2008 | 0.2266 |
| complex，warm八次合计 | 1.1268 | 1.1286 | 1.6287 | 1.6814 | 1.6242 |

common每轮八次输入共39840次Lua matcher调用；每字素空回调为38400次。
complex分别16000和14080次。空回调对照显示此fixture的主要增量来自调用、参数
和字素字符串传递；Lua字典查询和短码比较增加较少。单行warm八次输入则为
common0.0324→0.0657ms、complex0.0322→0.0432ms，绝对增量很小。

字素字符串在每次扫描中每字素只推入一次，供该字素所有待匹配状态复用；没有
输入子串切片或Lua Cursor对象。计时期间不运行Lua计数包装器；调用次数单独统计。
所有模式的完整位置、末尾位置、下一键和标签签名一致。回调错误可传播到外层
pcall，随后扫描仍正常。实验模块关闭回调的对照用于区分插桩和实际Lua调用成本。

另做500000次/轮、预热5轮及测量11轮的分派微测，9进程取中位数：C循环经Lua C API
调用三参数、双数值返回的简单函数约19.90ns/次；LuaJIT直接循环约2.30ns/次。
前者包含C循环、参数压栈、Lua表取值和返回处理，并非纯VM边界成本；后者允许
LuaJIT内联，不能把倍数直接用于完整扫描。实际空回调扫描增量约31ns/调用。

当前结论：C调用简单Lua matcher可用，但对每字素/输入状态无条件调用会积累成本。
此场景warm完整扫描约慢2.22倍（common）或1.44倍（complex），不能把所有回调
模式概括为同一个比例。只在少量候选上调用预计影响较小，这是按调用次数作出的
推断，尚未测试混合分派策略。更复杂Lua matcher的函数体成本也需另测。

原始记录 `/tmp/flash-any-lua-matcher-h5_st6ko/{raw.json,summary.json,micro.json}`，
同目录native.c为完整实验实现。两个脚本及LuaLS Hint检查通过，未更改生产接口。

English: A temporary C module calls a single-grapheme Lua matcher with the grapheme,
complete input and 1-based byte position. On a small one-code-per-glyph fixture,
warmed eight-input totals increased from1.07 to2.37ms on40 common-text lines and
from1.13 to1.62ms on40 complex-grapheme lines. Empty callbacks explain most of the
increase. C-to-Lua dispatch including arguments/results measured about20ns per call,
versus2.3ns for an inlineable LuaJIT loop; this microbenchmark ratio is not a scan ratio.
Result signatures and callback-error recovery agree. Production APIs remain unchanged.

## 多个 Lua matcher：分别跨界与一次 Lua 分派

复现：`python3 scripts/bench_lua_matcher.py --multiple --samples 9`。沿用临时C模块、
三参数单字素matcher。比较：

- direct：C持有函数数组，每个输入状态逐个调用N个Lua函数并合并结果。
- batch：C仅调用一个Lua函数，Lua遍历同一组N个函数，再把结果交回C。

每个状态两种方式均完整执行N个matcher，不因命中而短路。使用同类函数（同一
函数原型、各自拥有码表），分别测试空函数、拆分码表（一个字素最多属于一个
matcher）、重叠码表（每个matcher持有独立副本并完成相同匹配）。这些fixture
各状态最多产生一个不同的消费长度/下一键，batch可无分配地合并为两个标量。
一般的多分支matcher可能需要更复杂的结果合并，不属于此次测量。

40行common文本，warm八次输入合计，预热30轮、测量30轮，9个独立进程取中位数。
同一CPU核，每个N内轮换direct/batch顺序；保持构建和加载在计时外。单位ms：

| matcher数 | 重叠码表：分别C→Lua | 重叠码表：一次C→Lua后批量 | 拆分码表：分别C→Lua | 拆分码表：批量 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2.924 | 2.603 | 2.875 | 2.635 |
| 2 | 3.858 | 2.688 | 3.918 | 2.788 |
| 4 | 5.700 | 2.995 | 5.845 | 2.942 |
| 8 | 9.577 | 3.335 | 9.669 | 3.081 |
| 16 | 16.665 | 4.117 | 15.875 | 3.405 |

本次纯C对照1.178ms，实验模块关闭回调1.133ms；不要用此前不同运行的1.070ms
计算本次倍率。重叠码表batch从1到16个仅增至约1.58倍，direct约5.70倍；这不是
固定无增长，Lua内部循环、各函数工作和结果合并仍随N增加。

空函数batch为2.599、2.595、2.674、2.717、2.827ms；direct为2.888、3.728、5.478、
8.881、15.405ms。16个空函数的direct与真实重叠matcher分别为15.405和16.665ms，
而batch分别为2.827和4.117ms。此简单函数下，大部分可避免增量来自重复跨C/Lua
边界及相应参数/返回处理，而不是函数体本身。空函数可被LuaJIT优化，代表下界；
Lua/C字典路径也不同，差值不能解释为严格分离出的函数体CPU时间。

每轮八次扫描，direct跨界39840×N次，batch始终39840次；Lua内部仍调用N个函数。
计数在计时外做。位置、范围、下一键及标签的完整签名与纯C对照一致，错误传播
和恢复测试通过。没有构建Lua Cursor、输入子串或每matcher临时结果表。

另用不同闭包参数的简单数值函数做微测（100000组/轮，预热3轮、测7轮，9进程）：

| 函数数 | C逐个调用（ns/组） | Lua内部批量（ns/组） |
| --- | ---: | ---: |
| 1 | 20.96 | 22.20 |
| 2 | 42.48 | 21.85 |
| 4 | 82.44 | 24.60 |
| 8 | 166.93 | 25.84 |
| 16 | 326.06 | 31.93 |

检查两种方式的返回值累加和相同；LuaJIT可内联/优化Lua内部调用及算术，该微测
不是任意Lua matcher的固定成本。实际趋势可表达为：分别调用约为C扫描成本+
N次跨界与函数工作；批量约为C扫描成本+一次跨界+N份Lua工作与合并。复杂或不同
原型的matcher、不同结果协议仍需另测，不能承诺16个任意函数都只慢1.58倍。

原始记录 `/tmp/flash-any-lua-matcher-c45duhfq/{baseline.json,raw.json,summary.json,micro.json}`；
生产代码未改，默认单matcher实验回归和LuaLS Hint检查均通过。

English: With40 warmed text lines and eight inputs,16 overlapping matchers cost
16.67ms when C called them separately and4.12ms when C called one Lua dispatcher.
The single-matcher batched baseline was2.60ms. Sixteen empty functions cost15.41ms
versus2.83ms. Batching largely avoids repeated VM/API entry costs, but Lua loop,
function and merge work still grows with matcher count. All functions execute;
these homogeneous fixtures merge into two scalars without temporary result tables.
Results match the pure-C baseline. Complex heterogeneous matchers require separate tests.


## 高频记录的短编号体积原型 / Compact record dictionary prototype

本轮仅验证文件体积，不修改生产 C 格式或匹配器。原型将完整 matcher、参数和编码
作为共享项，0xC0–0xDF 表示 32 个单字节编号，0xE0–0xFF 加一字节表示
8,192 个双字节编号。唯一码内联。先对已有去重后的编码列表统计重复次数，
再按预计收益选择共享项；构建结果继续对整份列表去重。
共享项的 offset/length 目录每项 8 字节，字典本体和目录全部计入下表。

环境：Linux，Neovim 0.11.0，当前 FANYBIN v7 输入。字节大小确定，不涉及计时。
“唯一码”在相同 44,397 个非 ASCII 字符上增加 uxxxx，保持字符覆盖和索引不变。
默认组合为 pinyin/nerdfont/unicode；全部组合为 pinyin/tiger/wubi86/nerdfont/unicode。

| 配置 | 原始 KiB | 原型 KiB | 节省 KiB | 节省比例 | 单字节/双字节共享项 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 全拼 | 1285.6 | 1267.9 | 17.7 | 1.38% | 32/331 |
| 全拼＋内置模糊音 | 1300.1 | 1274.3 | 25.8 | 1.98% | 32/352 |
| 全拼＋唯一码 | 1733.2 | 1618.2 | 115.0 | 6.63% | 32/359 |
| 全拼＋模糊音＋唯一码 | 1841.9 | 1663.2 | 178.7 | 9.70% | 32/377 |
| 默认内置组合 | 3835.3 | 3652.3 | 183.0 | 4.77% | 32/3933 |
| 全部内置 source | 6090.9 | 5807.1 | 283.8 | 4.66% | 32/5169 |
| 全部内置 source＋模糊音 | 6199.6 | 5852.7 | 346.9 | 5.60% | 32/5187 |

原型输出 .tokens 文件，不能交给当前 C 加载器使用。重新读取输出文件，验证全部
字符键、共享字典和编码列表能还原到输入的原始字节；七组共校验 1,391,876 条记录。
最大组合使用 32＋5,187 项，尚未耗尽预留编号。尚未测试运行时解引用成本。

复现：先用 build.binary 导出要比较的包，再运行：

```sh
python scripts/bench_code_pool.py /tmp/package.bin
```

This is a size-only prototype, not a production-format change. Repeated complete
matcher/code records use 32 one-byte or up to 8,192 two-byte tokens; unique records
remain inline. Existing whole-list sharing is preserved. Reported sizes include
eight-byte offset/length entries and all dictionary payloads. The serialized files
are read back and every key and code record is verified against the source.
The seven cases above verify 1,391,876 records. Runtime lookup speed is unmeasured.


### 双拼对照 / Double-pinyin comparison

沿用上面的相同原型和统计口径，只把拼音转换为 flypy。两字母编码连 matcher
通常占 3 字节，单/双字节 token 分别省 2/1 字节，再扣除共享字典开销。

| 配置 | 原始 KiB | 原型 KiB | 节省 KiB | 节省比例 |
| --- | ---: | ---: | ---: | ---: |
| 小鹤双拼 | 1275.0 | 1266.8 | 8.1 | 0.64% |
| 小鹤双拼＋唯一码 | 1678.1 | 1616.7 | 61.4 | 3.66% |
| 小鹤双拼＋内置模糊音 | 1284.7 | 1273.2 | 11.5 | 0.89% |
| 小鹤双拼＋模糊音＋唯一码 | 1750.4 | 1660.6 | 89.7 | 5.13% |

每一行均对同一包做压缩前后比较并完整还原校验。纯双拼包为 44,521 个条目；
加入原先的唯一码文件后为 44,525 个条目，因唯一码覆盖了四个无双拼输出的条目。
只评价体积，不代表扫描速度提升。

The same prototype also saves space for two-letter flypy codes, but less than
full pinyin. Each row compares the same package before/after encoding and passes
complete round-trip checks. Unicode-code coverage adds four otherwise absent
entries (44,521 to 44,525). Scan performance remains unmeasured.


## 全拼音节与可选字节原型 / Full-pinyin syllable and optional-byte prototypes

本轮只测全拼，不测双拼，也没有改生产代码。基线是现有 native.so；两个实验版本
由 scripts/bench_pinyin.py 在 /tmp 中复制并补充 C 扫描器后编译。实验模块使用独立
userdata 类型与文件 magic，不能替代生产模块。音节版的共享数据单独输出，体积已计入。

- expanded：现有逐字展开模糊音。
- syllables：字引用 426 个标准音节 ID；C Trie 对每个输入位置识别完整音节、简拼、
  未完成输入和 next，生成一次匹配表，供所有行复用。
- skip：仅把内置 zh/z、ch/c、sh/s 和 ang/an、eng/en、ing/in 表示为可选 h/g；
  C 用小型位集 NFA 匹配。没有可选标记的编码仍走原有路径。

### 文件体积 / File size

44,525 个相同条目；唯一码为同一批字符加 uxxxx。没有叠加之前的短编号压缩。

| 实现 | 无模糊音 KiB | 有模糊音 KiB | 模糊音额外 KiB | 加唯一码后无模糊音 KiB | 加唯一码后有模糊音 KiB | 模糊音额外 KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| expanded | 1285.56 | 1300.15 | 14.59 | 1733.17 | 1841.90 | 108.73 |
| syllables | 1278.52 | 1279.57 | 1.05 | 1681.58 | 1682.63 | 1.05 |
| skip | 1285.56 | 1287.77 | 2.21 | 1733.17 | 1764.48 | 31.31 |

音节版的逐字主体文件在开关模糊音时逐字节相同，变化仅在共享拼写数据：
3,497 → 4,573 bytes，增加 1,076 bytes。唯一码不会破坏这一性质。

### 扫描 / Scanning

Linux、Neovim 0.11.0、GCC -O3、固定单个 CPU，每个配置独立进程 7 次；
每进程 25 轮取中位数，再取进程中位数。每轮更改 tick 强制重扫文本。
每行重复四次“中国人民学习中文，ASCII flash_any 混合文本。”。
首次输入 z；后续七次为 zh/zho/zhon/zhong/zhongg/zhonggu/zhongguo。
CPU 包含 C 查询图构建、扫描和 Lua 结果返回，不含 Flash UI；Wall 包含相同扫描调用。

| 模糊音 | 行数 | 实现 | 首次 CPU ms | 后续七次 CPU ms | 首次 Wall ms | 后续七次 Wall ms |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| plain | 1 | expanded | 0.006 | 0.029 | 0.006 | 0.029 |
| plain | 1 | syllables | 0.007 | 0.033 | 0.007 | 0.033 |
| plain | 1 | skip | 0.006 | 0.029 | 0.006 | 0.029 |
| plain | 40 | expanded | 0.143 | 0.836 | 0.144 | 0.838 |
| plain | 40 | syllables | 0.141 | 0.804 | 0.141 | 0.808 |
| plain | 40 | skip | 0.140 | 0.818 | 0.140 | 0.820 |
| fuzzy | 1 | expanded | 0.007 | 0.030 | 0.007 | 0.030 |
| fuzzy | 1 | syllables | 0.007 | 0.033 | 0.007 | 0.034 |
| fuzzy | 1 | skip | 0.007 | 0.033 | 0.007 | 0.033 |
| fuzzy | 40 | expanded | 0.166 | 0.878 | 0.166 | 0.881 |
| fuzzy | 40 | syllables | 0.157 | 0.800 | 0.157 | 0.802 |
| fuzzy | 40 | skip | 0.169 | 0.961 | 0.170 | 0.965 |

共享音节在一行时有小额解析固定成本；40 行模糊音测试后续七次约 0.800 ms，
基线约 0.878 ms。skip 原型约 0.961 ms，当前更慢，不能因代码更少就认为更快。
测试只代表此输入/文本样本，不代表所有真实缓冲区；没有完整输入法的词频和组词模型。

### 复杂度与验证 / Complexity and validation

C 核心在 prototype_pinyin.h 共 256 行：共享音节/序列化/Trie/输入匹配约 210 行，
可选字节 NFA 约 40 行；隔离扫描器接入净增约 37 行。其余脚本是构建、计时和对照。
音节版每次新输入分配 (输入字节数+1)×426×8 bytes 的临时匹配表，跨行复用；
尚未实现按输入追加复用解析图。Trie 加载后由引擎共享。
可选字节版只覆盖这六组插删关系，不支持 l/n、f/h 等替换关系。

与生产基线做 33,296 项结果对照，覆盖所有 426 个音节的代表字、变体前缀、
简拼、连续音节、错误后缀、标点、非法 UTF-8 和 f/F/t/T；结果位置、next、标签一致。
UBSan 通过，LuaLS 与生成 C 源码的 clangd 检查无诊断。生产代码未切换。

```sh
python scripts/bench_pinyin.py --baseline-native /path/to/v7/native.c --samples 7 --nvim .dev/nvim-0.11.0/bin/nvim
```

These are isolated full-pinyin prototypes, not production changes. A shared-syllable
Trie builds matching information once per input position, retaining ambiguity,
abbreviations, partial matches and next bytes. Its per-character dictionary is
byte-identical with fuzzy matching enabled/disabled; only the shared spelling
profile grows by 1,076 bytes. The optional-byte prototype supports only the six
built-in insertion/deletion groups. It saves space but is slower on this workload.
CPU and wall measurements above cover scanning and returned matches, not Flash UI.
All 33,296 comparisons agree with production and pass UBSan. Neither prototype
supports double pinyin in this experiment or replaces the production matcher.


## 按需音节 matcher 与预建输入图 / Direct syllable matcher versus prebuilt graph

在上面的音节原型中增加 ondemand：每个字引用一个或多个标准音节 ID，访问到该字时
才对其音节的每种拼写求最长公共前缀，再按 full/initial/prefix 生成消费长度和 next。
不同拼写的合法结果全部保留，相同消费长度去重。没有建所有位置的结果表，也没有
按需结果缓存。两版共用相同的标准读音、模糊拼写和二进制文件。

为使三种模式共用同一拼写数据，简拼不再作为独立拼写写入 profile，而由 C 的
initial 模式生成；这使 profile 从上一轮的 3,497/4,573 bytes 降为 2,655/3,731 bytes。
模糊音仍只增加 1,076 bytes；逐字码表主体开关模糊音仍逐字节相同。

沿用固定 CPU、独立进程 7 次、每进程 25 轮取中位数的扫描条件。默认 initial 模式
计时，全拼 full/initial/prefix 均做正确性校验。

| 模糊音 | 行数 | 实现 | 首次 CPU ms | 后续七次 CPU ms | 首次 Wall ms | 后续七次 Wall ms | 音节常驻结构 KiB |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| plain | 1 | syllables | 0.007 | 0.033 | 0.0067 | 0.0334 | 164.46 |
| plain | 1 | ondemand | 0.006 | 0.029 | 0.0058 | 0.0290 | 12.66 |
| plain | 40 | syllables | 0.142 | 0.807 | 0.1417 | 0.8099 | 164.46 |
| plain | 40 | ondemand | 0.142 | 0.814 | 0.1417 | 0.8209 | 12.66 |
| fuzzy | 1 | syllables | 0.008 | 0.033 | 0.0074 | 0.0338 | 261.62 |
| fuzzy | 1 | ondemand | 0.006 | 0.029 | 0.0063 | 0.0289 | 17.37 |
| fuzzy | 40 | syllables | 0.159 | 0.811 | 0.1593 | 0.8141 | 261.62 |
| fuzzy | 40 | ondemand | 0.158 | 0.816 | 0.1575 | 0.8202 | 17.37 |

40 行模糊音测试中约为 0.811/0.816 ms，差异很小；单行按需版少了固定的图构建成本。
按需常驻结构包括音节拼写和 offsets，约 17.37 KiB；预建版还包含当前原型的
稠密 Trie 与终止项，约 261.62 KiB，尚未压缩 Trie 或收紧预留容量。两者均不含字典主体。
预建版另外为每次新输入分配 (字节数+1)×426×8 的临时表；按需版只用栈上 8-byte 结果。
这组数据支持优先采用按需版：性能近似，状态更少；不证明所有文本上都更快。

全拼 full/initial/prefix、全部 426 音节代表字和变体前缀、连续输入、多音字、
标点以及 f/F/t/T 共 93,912 项结果对照通过；含混合唯一码。UBSan、LuaLS 和
包含实验头文件的生成 C 源码 clangd 检查均通过。生产模块仍未修改。

The direct variant computes common prefixes only for the syllables referenced by
each text grapheme. Matching mode then determines all valid consumed lengths and
next bytes; alternatives are unioned, not reduced to one global longest match.
It shares exactly the same serialized syllable data with the prebuilt variant.
On this workload, 40-line CPU times are nearly equal, while direct matching avoids
the graph startup cost for one line and reduces retained prototype profile memory.
The prebuilt trie has not been memory-optimized. All 93,912 comparisons across
full/initial/prefix match production, including punctuation and mixed Unicode codes.


## 正式按需音节实现 / Production on-demand syllables (2026-11-08)

全拼已接入正式扫描器，格式为 v8。0x08 引用标志与三种模式正交组合，
普通编码与音节拼写复用 match_spelling；未接入预建 Trie 或可选字节 NFA。
脚本的 shared 是正式实现，expanded 使用同一正式 C 模块读取逐字展开的编码，
其余三项仍是 v7 快照生成的隔离原型。实验源使用独立 metatable，不覆盖正式模块。

同机固定单核、每组七个独立进程，每进程 25 轮；下表为进程均值的中位数，
单位 ms CPU，开启全部内置模糊音，未混入 UX。输入为 z，随后连续七次追加。

| 行数 | 编码方式 | 首次扫描 | 后续七次合计 |
| --- | --- | ---: | ---: |
| 1 | 展开编码 | 0.006 | 0.030 |
| 1 | 正式共享音节 | 0.006 | 0.027 |
| 40 | 展开编码 | 0.158 | 0.835 |
| 40 | 正式共享音节 | 0.148 | 0.764 |

这是扫描及 Lua 结果转换的局部测试，不包含 Flash UI，不代表所有文本的固定收益。
正式版 profile_memory 字段没有单独插桩，脚本中的 0 不表示没有音节视图分配。

正式 v8 文件（bytes）：无模糊音 1,308,365，全部内置模糊音 1,309,441；
混入每字 UX 唯一码后为 1,721,092 / 1,722,168。两种情形模糊音均只增 1,076 bytes。
音节区本身为 2,655 / 3,731 bytes；高频码 token 原型未参与正式实现。

本轮原型、正式实现和展开编码共 134,160 次差分对照通过。
常规测试另有 100,920 次音节对照及 1,406 次 Lua 参考扫描对照；包括三种模式、
补空格、多音字、next、f/F/t/T、非法 UTF-8、损坏文件、GC 保活和大音节区。
Make 3.81、Nvim 0.11、真实 Flash jump/char/remote、UBSan、LuaLS、clangd 检查通过。
双拼尚未切换为共享音节，用户配置保持不变。

Full pinyin now uses flag-based references in the production v8 codec. All three
modes share the inline spelling implementation. Isolated-process measurements above
compare expanded records and shared references using the same production scanner;
only data representation varies. Fuzzy spellings add 1,076 bytes even alongside
unique per-character UX codes. These are local CPU timings, not end-to-end UI latency.
Double pinyin retains its existing build-time expansion. The prototype runner needs
a v7 native.c snapshot via --baseline-native; historical results above remain historical.


## 通用组去重 / Generic group interning (2026-11-08)

外置 source 后，核心按规范化拼写列表而非拼音名称共享编码组。source 内的组名只负责
引用，不进入二进制。相同内容（包括顺序不同或重复项）会合并；不同 source 的同名组
可有不同内容。选键分配也已成为通用的 build.selectors，默认键由 source 提供。

使用同一套 44,525 字素及相同 C v8 格式重新构建：

| 全拼配置 | 文件 bytes | 编码组数 | 组区 bytes |
| --- | ---: | ---: | ---: |
| 无模糊音 | 1,308,365 | 426 | 2,655 |
| 全部内置模糊音 | 1,306,155 | 334 | 2,539 |
| 无模糊音 + UX | 1,721,092 | 426 | 2,655 |
| 全部内置模糊音 + UX | 1,720,706 | 334 | 2,539 |

模糊音使部分标准读音拥有完全相同的拼写组，当前实现将其合并，因此本例开启模糊音
反而略小。这里只测体积，不声称新的 CPU 收益；扫描算法与上轮一致，仅去除了专用命名。
独立 source 包及核心分别通过 LuaLS，核心 C 通过 clangd；核心不安装任何 source 时
测试通过，五个包各自单独安装及一起安装的集成测试均通过。

Generic interning keys groups by normalized spelling contents rather than local
names. Built-in fuzzy pinyin collapses 426 groups to 334, so these particular binaries
become slightly smaller. The same v8 codec and scanning algorithm are retained;
these figures measure file size only. Source packages are independently installed
and are no longer shipped as part of the core repository.

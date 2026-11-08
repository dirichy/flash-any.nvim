# 真实码表验证 / Real dictionary checks

本轮在 Linux 上使用 Neovim 0.11.0 / GNU make 3.81，以及 Neovim 0.12.6 验证。
11 份原始上游文件固定提交和 SHA256，逐项核对 338,500 组文本/编码关系；
另有真实 CSV 内容转码得到的 GB18030、UTF-16LE 两个派生用例。全部通过。

Each original file is checked in auto and explicit format modes; TSV also checks the tab alias.
An independent Python reader compares every key and encoding array, not just counts.
C matching uses single-scalar samples spread across the source, plus comma/hash-code samples.
The reports include 1,105 native checks across all 13 cases; these are samples, not exhaustive C queries.

| 用例 / Case | 固定版本源文件 / Pinned source | 文本键 / Keys | 编码关系 / Pairs | C 抽样 / Samples |
| --- | --- | ---: | ---: | ---: |
| csv-xhup | [mruru/xhup](https://github.com/mruru/xhup/blob/932c9e8528a915eb1b2f75aed218d5b4d2ec0c8b/%E5%B0%8F%E9%B9%A4%E9%9F%B3%E5%BD%A2%E5%8D%95%E5%AD%97.csv) | 8,446 | 12,654 | 100 |
| fcitx-array30 | [fcitx/fcitx5-table-extra](https://github.com/fcitx/fcitx5-table-extra/blob/dbc7154a7f0b9fc04313160ae8066ed4d8cbc446/tables/array30.txt) | 27,489 | 31,585 | 105 |
| fcitx-compose | [fcitx/fcitx5-table-other](https://github.com/fcitx/fcitx5-table-other/blob/0716685056e6c5f0710142164011ca0f2f8bc633/tables/other/compose.txt) | 183 | 462 | 105 |
| fcitx-translit | [fcitx/fcitx5-table-other](https://github.com/fcitx/fcitx5-table-other/blob/0716685056e6c5f0710142164011ca0f2f8bc633/tables/ru/translit.txt) | 66 | 75 | 77 |
| ibus-latex | [moebiuscurve/ibus-table-others](https://github.com/moebiuscurve/ibus-table-others/blob/35863cede0de0c1fbb652d2a5757ce2c24c535c8/tables/latex.txt) | 777 | 784 | 100 |
| ibus-translit | [moebiuscurve/ibus-table-others](https://github.com/moebiuscurve/ibus-table-others/blob/35863cede0de0c1fbb652d2a5757ce2c24c535c8/tables/translit.txt) | 66 | 127 | 102 |
| rime-luna | [rime/rime-luna-pinyin](https://github.com/rime/rime-luna-pinyin/blob/56b934b099dfbeab842320f13aa8b461a6ab3e42/luna_pinyin.dict.yaml) | 62,073 | 70,732 | 100 |
| rime-terra | [rime/rime-terra-pinyin](https://github.com/rime/rime-terra-pinyin/blob/723e51bc266cf9464530c1ddedb856aa18e3da34/terra_pinyin.dict.yaml) | 91,061 | 99,329 | 100 |
| space-bpmf | [openvanilla/McBopomofo](https://github.com/openvanilla/McBopomofo/blob/745e8641a95d958532f0820c3ee679c2a585d8e3/Source/Data/BPMFBase.txt) | 21,786 | 26,535 | 100 |
| tsv-mozc | [google/mozc](https://github.com/google/mozc/blob/c4ed4683fb400b240e81d0a3895d024e3e21325e/src/data/dictionary_oss/dictionary00.txt) | 94,366 | 95,140 | 0 |
| tsv-mozc-suffix | [google/mozc](https://github.com/google/mozc/blob/c4ed4683fb400b240e81d0a3895d024e3e21325e/src/data/dictionary_oss/suffix.txt) | 1,077 | 1,077 | 16 |

## 范围与限制 / Scope and limits

- 表中数量是完整文件去重后的文本键和编码关系，包含词组，不等于单字素数量。
- Mozc dictionary00 的 94,366 个键全部是多字素条目，验证全部过滤，生成的表仅保留 ASCII 字面匹配；另用官方 suffix 表验证正向匹配。
- Mozc、转写表中的非 ASCII 编码由测试用 converter 转成 ASCII 后验证 C 匹配；这不表示运行时直接接受任意 Unicode 编码。
- Rime 验证显式条目，不调用 Rime 的预设词库或造码规则；递归导入另由 tests/formats.lua 测试覆盖。
- 转码用例由系统 iconv 从原始 CSV 内容生成，不冒充新的上游文件。GB18030 的版本映射以宿主 iconv 为准。

The tested files cover Rime, Fcitx, IBus, CSV, ordinary TSV and whitespace tables.
Native samples exclude identity mappings that could pass through ASCII literal matching alone.
Non-ASCII codes use a build-time test converter. Word filtering and explicitly encoded entries
are tested; this does not claim full input-method-engine or arbitrary YAML compatibility.

## 本轮修复 / Fixes found by real data

- Fcitx 的英文 [Data] 标记，以及 Prompt / ConstructPhrase 非候选条目。
- Fcitx 数据段的 #、##、; 编码；IBus 只有 ### 是注释。
- CSV 标题行通过 header=true 跳过。
- 文件先整体解码再分行，避免 UTF-16 的 NUL 和双字节换行损坏输入。
这些行为已加入普通 tests/formats.lua，日常测试不需要网络或下载第三方数据。

Regressions for English Fcitx markers, special input keys, non-candidate rows,
CSV headings and UTF-16 decoding are covered by the normal offline format tests.

## 复现 / Reproduce

```sh
python scripts/check_dictionaries.py --download --nvim .dev/nvim-0.11.0/bin/nvim
# 已下载后可离线运行 / Offline after the first download:
python scripts/check_dictionaries.py
```

版本清单在 tests/data/dictionaries.json；下载、独立期望值和 results.json 报告均在
忽略的 .dev/real-tables。原始第三方数据不随插件分发。开发验证需要 Python、iconv、
Neovim 和 C 构建工具；插件安装依赖不变。首次使用 --download 需要网络。

The manifest pins upstream commits and file checksums. Downloads, generated reference models
and reports stay under .dev/real-tables. Upstream payloads are not redistributed with this plugin.
Python and iconv are optional developer-test tools, not plugin installation dependencies.

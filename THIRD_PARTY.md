# Third-party data / 码表来源

The root MIT license covers this project's original code. Bundled data retains
its upstream notices and terms. This repository distributes derived character
and encoding tables, not font files or input-method binaries.

项目自身代码采用根目录的 MIT 许可；第三方码表保留上游说明及条款。仓库只包含
转换后的字符编码数据，不包含字体文件或输入法程序。

| Files / 文件 | Upstream / 来源 | Notices / 许可原文 |
|---|---|---|
| `table/pinyin.lua`, `pinyin.tsv`, `pinyin_parts.lua` | [mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data) | [MIT, copyright 2016 mozillazg](licenses/pinyin-data-MIT.txt) |
| `table/wubi86.lua`, `wubi86.tsv` | [rime/rime-wubi](https://github.com/rime/rime-wubi), `wubi86.dict.yaml` | [LGPL-3.0](licenses/rime-wubi-LGPL-3.0.txt), [GPL-3.0 text incorporated by LGPL](licenses/GPL-3.0.txt) |
| `table/unicode.lua`, `unicode.tsv` | [UnicodeData.txt](https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt) | [Unicode License V3](licenses/Unicode-3.0.txt) |
| `table/nerdfont.lua`, `nerdfont.tsv` | [Nerd Fonts glyphnames.json](https://github.com/ryanoasis/nerd-fonts/blob/master/glyphnames.json) | [Nerd Fonts upstream licensing notice](licenses/nerd-fonts.txt) |

虎码码表来源：[虎码官网](https://www.tiger-code.com/)。

Double-pinyin key mappings in `table/schemes.lua` reference the
[Chinese Wikipedia double-pinyin layouts](https://zh.wikipedia.org/wiki/双拼).

The transformation scripts are in `scripts/`. Pinyin tone marks are normalized
to ASCII (including `ü` → `v`); common tables use a subset of characters, full
TSVs are sorted by UTF-8 bytes, and Unicode/icon names are shortened to aliases.
Wubi conversion keeps single-character codes and merges alternatives; the Lua
common subset and full TSV remain readable data. The Rime source credits Gong
Chen, Yu Yuwei, Chen Xing, and original table author Wozy.

生成脚本位于 `scripts/`：拼音去声调并转为 ASCII；Lua 保存常用子集，TSV 保存按
UTF-8 字节序排序的完整数据；Unicode 与图标名称转换为短别名。五笔保留单字编码并
合并多个编码，原始 Rime 词典及作者说明见上游链接。

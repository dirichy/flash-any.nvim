# Latin source / 拉丁字母

## 使用 / Usage

`latin` 随主插件提供，无需另装 source 插件：

```lua
require("flash-any").setup({ sources = { "latin" } })
```

| 文本 / Text | 编码 / Code |
| --- | --- |
| é、é | e |
| ä、ä、ấ | a |
| ø | o |
| æ | ae |
| ß | ss |
| É、É | E |
| Æ | AE |

大小写遵循 Neovim 的 `ignorecase` / `smartcase`。关闭 `ignorecase` 时，
大写字母使用大写编码；开启后，`e` 也能匹配 `É`。同时开启 `smartcase` 时，
查询包含大写字母就区分大小写。连字必须输入完整编码才能继续匹配后面的文字，
例如 `æx` 使用 `aex`，不是 `ax`。

The source is bundled; no separate source plugin is needed. Letter case follows
Neovim's `ignorecase` / `smartcase`. With `ignorecase` off, capital letters use
capital codes. With it on, `e` also matches `É`; `smartcase` makes queries containing
uppercase letters case-sensitive. Ligatures need their complete code before
continuing: `aex` matches `æx`, while `ax` does not.

`letter` matcher 根据首个码点查表，消费整个字素。同一字素内的组合后缀可以重复，
不必逐个枚举，也不使用后缀白名单。完整字素的其他显式编码仍能同时参与匹配。
不执行 Unicode 规范化，也不把任意字母自动转写成 ASCII。

The `letter` matcher looks up the first codepoint and consumes the entire grapheme.
Combining suffixes may repeat without extra entries or a suffix whitelist. Other
explicit whole-grapheme encodings can still match. This is table lookup, without
Unicode normalization or automatic transliteration of unknown letters.

## 收录与维护 / Coverage and maintenance

唯一的码表文件是 [latin.tsv](../lua/flash-any/tables/latin.tsv)：362 个非 ASCII
字母，加上 52 个 ASCII 大小写字母，共 414 个条目，约 2 KiB。ASCII 条目让
`letter` 能处理 `é` 等组合形式；默认 literal 仍负责普通 ASCII 文本。
不配置 `latin` 时，不加载或编译这份表。配置后仅在构建二进制时读取，运行时由 C 匹配。

The single table contains 362 non-ASCII letters and 52 ASCII letters: 414 entries,
about 2 KiB. ASCII entries enable compound forms such as `é`; literal still handles
ordinary ASCII text. The table is read only when compiling a configured Latin source;
C performs runtime matching. It is unused when `latin` is not configured.

非 ASCII 映射迁自原 latin source：收录 CLDR 48 拉丁文字语言的主字母集及对应
大小写形式，不包含辅助字母集、数学字体、带框字符或仅用于历史/音标的字母。
`ŋ`、`ɛ` 等用于日常拼写的字母仍保留。原表未映射的 18 个字母现按外形补充别名，
见下表；这些别名是本项目的输入约定，不是标准转写。

Non-ASCII mappings were migrated from the original Latin source, covering CLDR 48
main Latin-script exemplars and case partners. Auxiliary exemplars, mathematical
styles, enclosed characters and letters used only historically or phonetically are
excluded. Everyday spelling letters such as `ŋ` and `ɛ` remain. The 18 previously
unmapped letters now have visual aliases below. These are project input conventions,
not standard transliterations.

| 字母 / Letters | 外形别名 / Visual aliases |
| --- | --- |
| Ɔ、ɔ | `C`、`c` |
| Ǝ、ǝ | `E`、`e` |
| Ə、ə | `E`、`e` |
| Ɣ、ɣ | `Y`、`y` |
| Ʊ、ʊ | `U`、`u` |
| ɩ | `i` |
| ʔ | `?` |
| ǀ、ǁ | `\|`、`\|\|` |
| ǂ | `\|` |
| ǃ | `!` |
| Ꞌ、ꞌ | `'` |

数据依据 Unicode 17 的字符分解及 CLDR 48 的 Latin-ASCII 转写规则，保留原表已确认
的基础字母映射，补充编码大小写及上述外形别名。更新时直接修改 TSV，并运行：

```sh
nvim --clean -l tests/latin.lua
```

The reviewed base-letter mappings derive from Unicode 17 decompositions and CLDR 48
Latin-ASCII rules, with code case and visual aliases added here. Edit the TSV directly to maintain
it; the test covers every shipped entry and combining suffixes.

- [Unicode 17 character data](https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt)
- [CLDR 48 Latin-ASCII rules](https://github.com/unicode-org/cldr/blob/release-48/common/transforms/Latin-ASCII.xml)
- [Unicode data license](../licenses/Unicode-3.0.txt)

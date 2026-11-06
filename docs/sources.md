# 构建码表 / Building dictionaries

扩展只提供构建时数据，不再提供运行时 Lua matcher、Cursor、scope 函数或按需
loader。运行时统一使用 C；setup 接收 `sources`，缺失二进制时自动调用构建器。

Extensions provide build-time data, not runtime Lua matchers, cursors, scope callbacks
or lazy loaders. Setup accepts `sources` and builds missing packages; matching is C-only.

## 工厂 / Factory

在 runtimepath 中提供 `lua/flash-any/sources/japan.lua`：

```lua
return function(opts)
  return {
    data = { ["あ"] = { "a" }, ["い"] = { "i" } },
    matcher = "full_code",
    scope = { { "ぁ", "ヿ" } },
    fallback = false,
  }
end
```

也可用 `codetable = "japan"` 代替 data，加载 `lua/flash-any/tables/japan.lua` 和
可选完整 `japan.tsv`。表名与工厂名不必相同。需要转换时可在工厂调用
`require("flash-any.table").load(name, {convert = fn, extra = map})`；这些 Lua
函数仅在构建时执行。工厂接收名称配置对象，名称简写传空表。

A factory may return `codetable = "japan"` instead of data to load the corresponding
Lua/TSV files under `flash-any/tables`. It can call `table.load(name, {convert = fn,
extra = map})` for build-time transformations. Custom factory options pass through;
a name-only specification supplies an empty options table. No callbacks run during
searches.

```lua
require("flash-any").setup({
  sources = { "pinyin", { name = "japan", matcher = "prefix" }, "unicode" },
})
```

## 数据与规则 / Data and rules

- 每个 key 须为一个完整 Unicode17 字素；`á`、`👩‍💻` 合法，`中国` 是两个字素，
  当前会报错。非法 UTF8 字节分别作为独立单元处理。不做 Unicode 归一化。
- 编码为非空 ASCII 字符串或数组。空数组表示已认识但没有匹配，可屏蔽 fallback。
- `matcher` 只能是 `full_code`、`initial`、`prefix`。前者接受完整编码，initial
  同时接受首字母和完整编码，prefix 接受任意非空前缀。
- `scope` 为预定义名称或混合字符/区间表。字符键优先，false 可排除区间内字素。
  端点为码点整数或单字素字符串，区间按完整 UTF8 字节序比较。
- 普通源都贡献编码；fallback 仅在此前源未认识时贡献。scope 过滤不算认识。
- 相同 matcher 模式和编码自动去重，不保留 source 归属。

Each key is exactly one complete Unicode17 grapheme. Codes are nonempty ASCII strings
or arrays; an empty array recognizes without matching. The three built-in modes are
full code, initial/full code, and arbitrary nonempty code prefix. Scope declarations
filter before fallback resolution; exact character overrides take priority over byte-
ordered ranges. Ordinary sources contribute independently; fallbacks contribute only
for previously unknown graphemes. Duplicate mode/code pairs merge without source IDs.

```lua
scope = { { "a", "z" }, a = false, ["👩‍💻"] = true }
```

## 覆盖与文件 / Overrides and files

`name` 调用工厂取得默认值；显式 `data` 或 `lua`/`tsv` 覆盖数据，显式 matcher、
scope、fallback 覆盖默认规则，包括 `fallback = false`。`append_space_below` 在
主构建器应用，工厂不要重复补空格。完整 TSV 应包含 Lua 常用表所有条目；Lua
覆盖项和 extra 保持优先。每次构建读取完整数据，不依赖先前搜索命中过什么字。

Named factories supply defaults. Explicit data/files and matcher/scope/fallback
options override them. Padding is applied by the host, not repeated by factories.
Full TSV files include all common Lua entries; Lua overrides/extras win. Compilation
reads the complete table, independently of previous searches.

```text
中<TAB>zhong,chong
国<TAB>guo
```

`:FlashAnyBuildTable` 可从 Rime/CSV/TSV/空白分隔词典生成 Lua/TSV。转换器保留
多字素条目并报告数量，但当前 C 二进制构建只接受单字素键。格式详见
[开发说明](development.md)；测试参考实现不属于插件 API。

The conversion command preserves and reports multi-grapheme entries; filter these
before compiling the current C dictionary. See [development notes](development.md)
for binary layout. The frozen Lua oracle under tests is not a plugin API.

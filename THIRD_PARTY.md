# Third-party data / 码表来源

The root MIT license covers this project's original code. Unicode grapheme data retains
its upstream notices and terms. Optional code tables are distributed separately.

项目自身代码采用根目录的 MIT 许可；Unicode 字素数据保留上游说明及条款。
码表由独立 source 插件分发，核心不包含输入法码表。

| Files / 文件 | Upstream / 来源 | Notices / 许可原文 |
|---|---|---|
| `vendor/luajit/*.h` | [LuaJIT 2.1.1793383622 public Lua/C headers](https://github.com/LuaJIT/LuaJIT/tree/v2.1/src) | [LuaJIT MIT](vendor/luajit/COPYRIGHT), [Lua.org MIT in lua.h](vendor/luajit/lua.h) |
| `scripts/data/grapheme_data.lua`, `tests/data/GraphemeBreakTest-17.0.0.txt` | Unicode 17.0.0 grapheme, Indic conjunct and emoji properties / 字素、连字与 emoji 属性 | [Unicode License V3](licenses/Unicode-3.0.txt) |

Input-method tables and their transformation scripts are distributed by independent
source plugins, each with its own THIRD_PARTY.md and upstream license files.
码表和专用转换脚本已归各独立 source 插件，各自携带上游来源和许可文件。

## Demo artwork / 演示素材

`demos/common/backdrop.png` is copied from
[dpezto/chezmoi-template.nvim](https://github.com/dpezto/chezmoi-template.nvim/tree/670ba83095ba6571f3125a5e5fd4118505a2c3c6/assets/tapes),
via vimoi.nvim. Copyright © 2026 Dai López, distributed under the
[MIT license](demos/common/backdrop.LICENSE).

演示渐变背景保留上游版权与 MIT 许可，见上面的来源与许可文件。

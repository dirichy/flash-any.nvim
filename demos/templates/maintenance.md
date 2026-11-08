# Maintaining a code-table package / 维护码表包

This document is for contributors; installing and using the package does not require
editing its dictionary or recording a demo.
本文面向维护者；普通用户无需修改码表或安装录制工具。

For your first package, follow the [source tutorial](https://github.com/dirichy/flash-any.nvim/blob/main/docs/writing-sources.md).
首次编写 source 可按[分步教程](https://github.com/dirichy/flash-any.nvim/blob/main/docs/writing-sources.zh-CN.md)操作。

## Package layout / 包结构

Copy the templates to these locations, then replace OWNER/TABLE and SOURCE:
复制模板到以下位置，再替换 OWNER/TABLE 和 SOURCE：

| Template / 模板 | Package path / 包内路径 |
| --- | --- |
| source.lua | lua/flash-any/sources/SOURCE.lua |
| table.tsv (or your complete table / 或完整码表) | lua/flash-any/tables/SOURCE.tsv |
| table-demo.lua | demo.lua |
| table-demo.yml | .github/workflows/demo.yml |
| README.zh-CN.md (Chinese-source homepage / 中文 source 主页) | README.md |
| README.md (English translation / 英文版) | README.en.md |
| maintenance.md | docs/maintenance.md |

For a language-specific source, put that language's documentation in README.md and
link the English translation as README.en.md. For Chinese sources, the table above
and the templates' language links already follow this layout. For language-neutral
packages such as Unicode or Nerd Font, keep English as README.md and Chinese as
README.zh-CN.md, updating both navigation links accordingly.
语言类 source 用对应语言的 README.md 作主页，英文版存为 README.en.md 并互相链接。
上表和模板默认链接适用于中文 source；Unicode、Nerd Font 等非单一语言包保持英文主页，
中文存为 README.zh-CN.md，并调整两份文档的导航链接。

Use the same SOURCE name in the factory filename, its codetable field, the README's
sources list, and demo.lua's file path. The workflow reads demo.lua without overriding
its dictionary or matcher. Set the mode in both the factory and demo.lua if changing
from full_code. Source-specific options belong in the factory; plain tables need no
additional loading code. Verify data provenance and licenses before publication.
工厂文件名、codetable、README 的 sources、demo.lua 的码表路径使用同一 SOURCE 名称。
工作流只读取 demo.lua，不再重复覆盖码表和匹配模式；修改模式时同步工厂与 demo.lua。
专有配置留在各 source 工厂；纯码表无需额外加载逻辑。发布前核实数据来源与许可。

## Configuration documentation / 配置文档

Document every user-facing option: type, default, enum values, practical examples and
constraints. Keep source-factory build metadata in maintainer documentation rather
than presenting it as installation settings. Verify the supported user settings
against the factory instead of copying every field it accepts.
列全面向使用者的选项、类型、默认值、枚举值、实际示例与限制。工厂交给构建器的内部
数据放在维护文档，不列成安装配置；不要把工厂接受的所有字段原样复制为用户选项。

## Dictionary / 码表

The default TSV format is one grapheme, a Tab, and one code per row. Repeat rows for
multiple codes; commas in codes are literal. Other formats, column order, converters,
and optional weights are documented in [source configuration](https://github.com/dirichy/flash-any.nvim/blob/main/docs/sources.md).
默认 TSV 每行是字素、Tab、编码；多编码重复写行，逗号原样保留。
其他文件格式、列顺序、编码转换及可选权重见上述 source 文档。

Record the upstream source and license in THIRD_PARTY.md when updating the dictionary.
更新时在 THIRD_PARTY.md 中记录上游来源与许可。

## Demo / 演示

Copy flash-any's [workflow template](https://github.com/dirichy/flash-any.nvim/blob/main/demos/templates/table-demo.yml)
to .github/workflows/demo.yml and its commented [Lua config](https://github.com/dirichy/flash-any.nvim/blob/main/demos/templates/table-demo.lua)
to demo.lua. Set the dictionary path and familiar target text, edit both narration
comments, and use `config: demo.lua` in the workflow. Optional `sample` loads your own
short sample file. Codes come from the table automatically.
复制上述工作流模板和带注释的 Lua 配置，填写码表路径、熟悉的目标文字、两段旁白；
工作流用 `config: demo.lua` 指向配置。可用 `sample` 指定简短样本文件，编码自动从码表推导。

Pin the workflow reference and flash-any-ref to the same tested core commit.
Push to main to record automatically, or run the workflow manually. After verification,
the caller workflow replaces the GIF, MP4, cover and reports in the dedicated `demos`
prerelease. README links use stable release asset URLs; generated media is never
committed. Only the publishing job needs contents:write. Outdated runs skip publication
when main has changed. Authenticated downloads verify the published assets, including
for private repositories. Artifacts remain available for diagnosis.
推送 main 自动录制，也可手动运行。验证成功后，调用工作流替换独立 `demos` prerelease
中的 GIF、MP4、封面与报告。README 引用固定附件地址，生成媒体不提交到 Git。
仅发布任务需要 contents:write；main 已变化时跳过旧录制。发布后使用认证下载核对附件，
也适用于私有仓库。artifact 同时保留用于排查问题。

For local commands, dependencies, font coverage and playback checks, see the
[recording guide](https://github.com/dirichy/flash-any.nvim/blob/main/demos/README.md).
本地命令、录制依赖、字体覆盖与回放验证见上述录制说明。

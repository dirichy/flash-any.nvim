-- Copy this file into your code-table repository and edit the fields below.
-- 在码表仓库内复制并修改此文件；用 sh demos/record.sh table /path/demo.lua 录制。
-- All relative paths start at this file's directory, not the shell's working directory.
-- 所有相对路径均以本文件所在目录为基准。
return {
	-- Replace SOURCE with your source name / 将 SOURCE 换成 source 名称。
	-- Dictionary file / 码表路径。One grapheme per key; codes are inferred automatically.
	file = "lua/flash-any/tables/SOURCE.tsv",

	-- Built-in matching mode / 匹配模式：full_code (default), initial, or prefix.
	matcher = "full_code",
	-- Usually auto-detected / 通常不必填写；特殊格式可指定以下字段。
	-- format = "tsv", -- auto, rime, tsv, csv, space, fcitx, ibus
	-- columns = { "text", "code", "weight" }, -- Column order / 列顺序。
	-- encoding = "UTF-8", -- Input encoding / 原码表编码。
	-- header = true, -- Skip a CSV header / 是否有标题行。
	-- converter = "converter.lua", -- Build-time code converter / 构建时编码转换。

	-- Name shown in the title and default narration / 标题、默认旁白中的文本名称。
	-- Omit for "any text" / 省略时使用 "any text"。
	text_name = "Chinese",
	-- First search: one grapheme / 第一次匹配的单字素，不必填写它的编码。
	-- Omit for a font-checked random entry / 省略时随机抽取字体覆盖的条目。
	text = "中",
	-- Second search: mix table text and literal ASCII / 第二次演示码表文字与 ASCII 混输。
	-- Prefer a distinct phrase; several labels are also allowed / 尽量用独特的短语，也允许多个标签。
	-- Default / 默认：text .. " with flash"。
	mixed_text = "中文 with flash",

	-- Editable narration, rendered as comments above the examples / 可修改的演示旁白。
	-- Newlines are supported; omit to use text_name-based defaults / 支持换行，省略则按文本名称生成。
	comment = "Flash can match Chinese: type a code, then choose a label.",
	mixed_comment = "Mix Chinese codes with ASCII in the same search.",

	-- Optional existing sample file / 可选：直接使用自己的样本文件，保持一屏可见。
	-- It must contain mixed_text / 文件里须包含混输目标。
	-- Omit to generate the main examples / 省略则自动生成主样本。
	-- The recorder adds two extra copies of text for multiple labels / 脚本另补两个单字作为候选。
	-- sample = "table-sample.lua",

	-- Optional window title and random seed / 可选：窗口标题、随机抽样种子。
	-- title = "My table + ASCII",
	-- seed = 20261108, -- Same table and fonts reproduce the sample / 同一码表和字体下可复现。
}

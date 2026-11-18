-- Each example runs with the same installed sources and native dictionary.
-- Edit the text, query and pauses here; labels and targets are verified automatically.
return {
	title = "f / s / r / search: all sources",
	sources = { "latin", "pinyin", "japanese", "nerdfont" },
	examples = {
		{
			title = "f: shared first code across sources",
			mode = "char",
			text = "źebra",
			alternatives = "中途停留    字里行间    ずっと     shell    z",
			pattern = "z",
		},
		{
			title = "Chinese pinyin",
			text = "中文",
			pattern = "zhongwen",
			checkpoints = { "zhong", "zhongwen" },
		},
		{
			title = "r: yank a Japanese word, then return",
			mode = "remote",
			text = "食べる",
			pattern = "taberu",
			checkpoints = { "ta", "taberu" },
		},
		{
			title = "Nerd Font icon names",
			text = "",
			pattern = "vim",
			checkpoints = { "v", "vim" },
		},
		{
			title = "search: mixed input offscreen",
			comment = "Keep typing to skip near matches beyond the screen.",
			mode = "search",
			decoys = { "café noir", "café 中文 notes", "café 中文 食べる notes" },
			text = "café 中文 食べる ",
			pattern = "cafe zw taberu vim",
			checkpoints = { "cafe", "cafe zw", "cafe zw taberu", "cafe zw taberu vim" },
		},
	},
}

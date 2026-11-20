-- Each example runs with the same installed sources and native dictionary.
-- Edit the text, query and pauses here; labels and targets are verified automatically.
return {
	title = "s / f / dr / search: all sources",
	sources = { "latin", "pinyin", "japanese", "korean", "nerdfont" },
	examples = {
		{
			title = "Chinese pinyin",
			text = "中文",
			pattern = "zhongwen",
			checkpoints = { "zhong", "zhongwen" },
		},
		{
			title = "Korean Dubeolsik",
			text = "한글",
			pattern = "gksrmf",
			checkpoints = { "gks", "gksrmf" },
		},
		{
			title = "Nerd Font icon names",
			text = "",
			pattern = "vim",
			checkpoints = { "v", "vim" },
		},
		{
			title = "f: shared code across sources",
			mode = "char",
			text = "źebra",
			alternatives = "中途  字里  ずっと  코드   file  z",
			pattern = "z",
		},
		{
			title = "dr: delete and return",
			mode = "remote",
			text = "食べる",
			pattern = "taberu",
			checkpoints = { "ta", "taberu" },
		},
		{
			title = "search: mixed input offscreen",
			comment = "Keep typing to skip near matches beyond the screen.",
			mode = "search",
			decoys = {
				"café noir",
				"café 中文 notes",
				"café 中文 한글 notes",
				"café 中文 한글 食べる notes",
			},
			text = "café 中文 한글 食べる ",
			pattern = "cafe zw gksrmf taberu vim",
			checkpoints = { "cafe", "cafe zw", "cafe zw gksrmf", "cafe zw gksrmf taberu", "cafe zw gksrmf taberu vim" },
		},
	},
}

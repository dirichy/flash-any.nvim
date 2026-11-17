-- Each example runs with the same installed sources and native dictionary.
-- Edit the text, query and pauses here; labels and targets are verified automatically.
return {
	title = "Latin + Chinese + Japanese + Nerd Font",
	sources = { "latin", "pinyin", "japanese", "nerdfont" },
	examples = {
		{
			title = "Latin accents",
			text = "café",
			pattern = "cafe",
			checkpoints = { "caf", "cafe" },
		},
		{
			title = "Chinese pinyin",
			text = "中文",
			pattern = "zhongwen",
			checkpoints = { "zhong", "zhongwen" },
		},
		{
			title = "Japanese romaji",
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
			title = "One search, all sources",
			text = "café 中文 食べる ",
			pattern = "cafe zw taberu vim",
			checkpoints = { "cafe", "cafe zw", "cafe zw taberu", "cafe zw taberu vim" },
		},
	},
}

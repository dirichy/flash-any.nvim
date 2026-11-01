-- flash-any.nvim
-- Jump with the encodings you already know.

-- Double pinyin: narrow the matches as you type.
local words = {
  "中国",
  "中华",
  "中文",
  "重庆",
}

-- Unicode names: letters, symbols, and emoji.
local symbols = {
  "α", "β", "γ",
  "→", "∞", "≠",
  "😀", "🎉", "🚀",
}

-- ASCII and encoded characters can share a search.
return { words = words, symbols = symbols }

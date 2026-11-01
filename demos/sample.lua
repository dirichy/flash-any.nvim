-- flash-any.nvim
-- Jump with the encodings you already know.

-- Full pinyin: quan + pin
local full = {
	"全拼",
}
-- Initials: j + p
local initials = {
	"简拼",
}
-- hun + s + ascii + grin
local mixed = {
	"混输ascii😀",
}
-- Full pinyin + initial + literal + Unicode name
return { full = full, initials = initials, mixed = mixed }

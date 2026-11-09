vim.opt.runtimepath:prepend(vim.uv.cwd())
local factory = require("flash-any.sources.latin")
assert(factory().codetable == "latin" and factory().matcher == "letter")
local registry, native = require("flash-any.source"), require("flash-any.native")
assert(vim.tbl_contains(registry.available(), "latin"))
local path = vim.fn.tempname() .. ".bin"
local _, entries = require("flash-any.build").binary({ sources = { "latin" }, output = path })
assert(entries == 490, "362 non-ASCII letters plus 128 literals")
local book = native.load(path)
local query = ""
local state = {
	pattern = function()
		return query
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
local function find(text, input)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
	query = input
	return native.get(0, state, range, book)
end

vim.go.ignorecase, vim.go.smartcase = false, false
for _, case in ipairs({
	{ "é", "e" },
	{ "É", "E" },
	{ "ø", "o" },
	{ "ấ", "a" },
	{ "ŋ", "n" },
	{ "æ", "ae" },
	{ "Æ", "AE" },
	{ "ß", "ss" },
	{ "ẞ", "SS" },
	{ "é", "e" },
	{ "É", "E" },
	{ "ấ", "a" },
	{ "á̂", "a" },
	{ "é" .. ("́"):rep(100), "e" },
	{ "e͏", "e" },
	{ "e️", "e" },
	{ "café Straße déjà vu", "cafe Strasse deja vu" },
}) do
	assert(#find(case[1], case[2]) == 1, vim.inspect(case))
end
-- Previously unmapped letters use visual aliases, including literal punctuation.
for _, case in ipairs({
	{ "Ɔ", "C" },
	{ "ɔ", "c" },
	{ "Ǝ", "E" },
	{ "ǝ", "e" },
	{ "Ə", "E" },
	{ "ə", "e" },
	{ "Ɣ", "Y" },
	{ "ɣ", "y" },
	{ "Ʊ", "U" },
	{ "ʊ", "u" },
	{ "ɩ", "i" },
	{ "ʔ", "?" },
	{ "ǀ", "|" },
	{ "ǁ", "||" },
	{ "ǂ", "|" },
	{ "ǃ", "!" },
	{ "Ꞌ", "'" },
	{ "ꞌ", "'" },
}) do
	assert(#find(case[1], case[2]) == 1, vim.inspect(case))
end
assert(#find("ǀǁǂǃʔꞋꞌ", "||||!?''") == 1)
assert(#find("ǁx", "|x") == 0, "double-bar alias must finish before continuing")
assert(find("ǁ", "|")[1].next["|"])
assert(#find("é", "E") == 0 and #find("É", "e") == 0)
assert(#find("É", "e") == 0 and #find("A", "a") == 0)
assert(#find("æx", "ax") == 0, "ligatures require the complete code before continuing")
assert(find("æ", "a")[1].next.e)
assert(find("é", "e")[1].end_pos[2] == 1, "consume the combining mark")
for _, unknown in ipairs({ "́", "🙂", "中", "𝕒", "ⓐ" }) do
	assert(#find(unknown, "a") == 0, unknown)
end
vim.go.ignorecase = true
assert(#find("É É é é", "e") == 4)
assert(#find("É É é é", "E") == 4)
assert(#find("Straße CAFÉ", "strasse cafe") == 1)
assert(find("Æ", "a")[1].next.e and find("Æ", "a")[1].next.E)
vim.go.smartcase = true
assert(#find("É É é é", "e") == 4)
assert(#find("É É é é", "E") == 2)

-- Exercise every shipped entry in both precomposed and extended grapheme form.
local data = assert(registry.load("latin").data)
local count = 0
for key, codes in pairs(data) do
	count = count + 1
	vim.go.ignorecase, vim.go.smartcase = false, false
	assert(#find(key, codes[1]) == 1, key)
	assert(#find(key .. "́x", codes[1] .. "x") == 1, key .. " + combining mark")
	vim.go.ignorecase = true
	assert(#find(key .. "́", codes[1]:lower()) == 1, key .. " insensitive")
end
assert(count == 414)
vim.uv.fs_unlink(path)
print("built-in Latin source tests passed (414 entries)")

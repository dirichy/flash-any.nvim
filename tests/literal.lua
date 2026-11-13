vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local path = vim.fn.tempname() .. ".bin"
build.binary({ sources = {}, output = path })
local book = native.load(path)
local query, labels = "", { "中", "👩‍💻", "á", "z" }
local state = {
	pattern = function()
		return query
	end,
	labels = function()
		return labels
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
local function find(text, input, motion)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
	query = input
	return motion and native.char(0, state, range, book, motion) or native.get(0, state, range, book)
end
vim.go.ignorecase, vim.go.smartcase = false, false
for _, glyph in ipairs({
	"中",
	"𠀀",
	"é",
	"é",
	"á̈",
	"👩‍💻",
	"👍🏽",
	"🇨🇳",
	"1️⃣",
	"क्‍ष",
	"́",
	"\255",
}) do
	local text = "\1" .. glyph .. "\2"
	local found = find(text, glyph)
	assert(#found == 1 and found[1].pos[2] == 1, glyph)
	local full_end = found[1].end_pos[2]
	assert(#find(text, glyph .. "\2") == 1)
	for _, motion in ipairs({ "f", "F", "t", "T" }) do
		found = find(text, glyph, motion)
		local col = motion == "t" and 0 or (motion == "T" and #glyph + 1 or 1)
		assert(#found == 1 and found[1].pos[2] == col, glyph .. " " .. motion)
	end
	for n = 1, #glyph - 1 do
		local partial = find(text, glyph:sub(1, n))
		assert(#partial == 1, "literal prefix: " .. glyph .. " " .. n)
		assert(partial[1].end_pos[2] == full_end)
		assert(next(partial[1].next) == nil, "preview must not consume the rest of the glyph")
	end
end
-- Buffer lines cannot contain LF; exercise CRLF directly through the C scanner.
local raw = book:new_state()
assert(#raw:scan(0, 0, 1, 1, 1, { "|\r\n|" }, "\r\n", nil) == 1)
assert(#raw:scan(0, 0, 1, 1, 1, nil, "\r", nil) == 1)
for _, case in ipairs({
	{ "e", "é" },
	{ "é", "é́" },
	{ "👩", "👩‍💻" },
	{ "🇨", "🇨🇳" },
	{ "\r", "\r\n" },
}) do
	assert(#find("|" .. case[1] .. "|", case[2]) == 0)
end
assert(#find("中国 中国", "中国") == 2)
assert(#find("中á👩‍💻", "中á👩‍💻") == 1)
assert(#find("é", "é") == 0, "literal performs no normalization")
assert(#find("中", "zhong") == 0, "no inferred transliteration")

-- A preview keeps the entire text range, without advancing to the following glyph.
assert(#find("éx", "ex") == 0)
assert(#find("👩‍💻x", "👩x") == 0)
assert(next(find("éx", "e")[1].next) == nil)
assert(next(find("👩‍💻x", "👩")[1].next) == nil)
assert(#find("éx", "éx") == 1)

-- Unicode next keys must reserve labels, including on cache hits and changed labels.
local matches = find("a中 a👩‍💻 aá", "a")
assert(#matches == 4 and matches[1].next["中"] and matches[2].next["👩‍💻"] and matches[3].next["á"])
assert(matches[2].next["👩"] and matches[3].next.a, "lookahead must reserve literal prefixes too")
assert(next(matches[4].next) == nil)
assert(matches[1].label == "z" and not matches[2].label)
assert(vim.deep_equal(matches, native.get(0, state, range, book)))
labels = { "👩‍💻", "中", "x" }
assert(native.get(0, state, range, book)[1].label == "x")
vim.go.ignorecase = true
assert(#find("a中A中", "A中") == 2)
assert(#find("É é", "é") == 1, "Unicode literal case stays exact")
vim.go.smartcase = true
assert(#find("a中A中", "A中") == 1)

-- Literal and table encodings can alternate in either direction.
build.binary({ sources = { { data = { ["中"] = "zhong", ["国"] = "guo" } } }, output = path })
book = native.load(path)
for _, input in ipairs({ "中国", "中guo", "zhong国", "zhongguo", "中g" }) do
	assert(#find("中国", input) == 1, input)
end
assert(#find("中国x", "中guox") == 1)
assert(#find("中国", "Zhong国") == 0, "ordinary codes remain exact")
build.binary({ sources = { "latin" }, output = path })
book = native.load(path)
local alternatives = find("é中", "e")
assert(#alternatives == 1 and alternatives[1].next["中"])
assert(#find("é中", "e中") == 1, "letter consumption can omit marks independently of literal preview")
vim.uv.fs_unlink(path)
print("Unicode literal prefixes, whole-glyph ranges and mixed encoding tests passed")

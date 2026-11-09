-- make && nvim --clean -l tests/native.lua
vim.opt.runtimepath:prepend(vim.uv.cwd())
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local build = require("flash-any.build")
local native = require("flash-any.native")
local match = require("reference.match")
local registry = require("reference.source")
local grapheme = require("reference.grapheme")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial, comparisons = 0, 0
local function engine(sources)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = sources, output = path })
	return native.load(path), path
end
local function words(codes)
	local prefixes, maximum = {}, 1
	for key in pairs(codes) do
		maximum = math.max(maximum, grapheme.len(key))
		grapheme.each(key, function(_, after)
			if after < #key then
				prefixes[key:sub(1, after)] = true
			end
		end)
	end
	return { codes = codes, prefixes = prefixes, max_chars = maximum }
end
local function equal(found, expected, context)
	for _, item in ipairs(found) do
		for key in pairs(item.next) do
			if #key ~= 1 or key:byte() >= 128 then
				item.next[key] = nil
			end
		end
	end
	comparisons = comparisons + 1
	assert(vim.deep_equal(found, expected), context .. "\n" .. vim.inspect(found) .. "\n" .. vim.inspect(expected))
end
-- Adapt the literal rule only; the frozen scanner still checks code-table branching.
---@type ReferenceMatcher
local function literal(text, stream, _, emit)
	local glyph, input = text:get(1), stream:get()
	local common = math.min(#glyph, #input)
	if glyph:sub(1, common) == input:sub(1, common) then
		if #input < #glyph then
			-- The frozen emitter only represents ASCII next keys.
			emit(input == "" and glyph:byte() < 128 and glyph:sub(1, 1) or "")
		else
			emit(#glyph)
		end
	end
	return #glyph == 1 and glyph:byte() < 128
end
local function compare(lines, queries, specs)
	local compiled = engine(specs)
	local sources = registry.resolve(specs)
	sources[1].matcher = literal
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	local query, labels = "", vim.split("asdfghjklqwertyuiopzxcvbnm", "")
	local state = {
		pattern = function()
			return query
		end,
		labels = function()
			return labels
		end,
	}
	local range = { from = { 1, 0 }, to = { #lines, 0 } }
	for _, value in ipairs(queries) do
		-- The frozen cursor cannot resume inside an input grapheme; Unicode has its own suite.
		if not value:find("[\128-\255]") then
			query = value
			equal(
				native.get(0, state, range, compiled),
				match.get(0, state, range, sources),
				"scan " .. value .. " " .. vim.inspect(specs)
			)
			equal(native.get(0, state, range, compiled), match.get(0, state, range, sources), "cached " .. value)
			for _, motion in ipairs({ "f", "F", "t", "T" }) do
				equal(
					native.char(0, state, range, compiled, motion),
					match.char(0, state, range, sources, motion),
					motion .. " " .. value
				)
			end
		end
	end
	labels = { "z", "a", "🙂", "b" }
	equal(native.get(0, state, range, compiled), match.get(0, state, range, sources), "changed labels")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲a👩‍💻" })
	range.to = { 1, 0 }
	equal(native.get(0, state, range, compiled), match.get(0, state, range, sources), "changed buffer")
end
compare(
	{ "abc abca", "", "中a国", "á👩‍💻🇨🇳\0\255" },
	{ "", "a", "ab", "abc", "a", "x", "中", "á", "a‍", "\r\n", "\255", "\0" },
	{}
)
-- Scalar entries must not recognize just the first scalar of a compound grapheme.
local last_scalar = vim.fn.nr2char(0x10FFFF)
compare({ "a á 👩 👩‍💻 \0" .. last_scalar .. "\255", "中国中" }, { "x", "xx", "y", "w" }, {
	{ data = words({ a = "x", ["👩"] = "x", ["\0"] = "x", [last_scalar] = "x", ["\255"] = "y", ["国"] = "w" }) },
})
local codes = {
	["甲"] = { "a", "ab", "abc", "abcd" },
	["乙"] = { "a", "bb" },
	["中"] = "zhong",
	["国"] = "guo",
	["空"] = {},
}
for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
	compare(
		{ "甲乙甲乙空", "中国a中国", "á👩‍💻🇨🇳" },
		{ "a", "ab", "abc", "abcd", "abca", "a", "b", "bb", "zg", "zhongguo", "zhongg", "x" },
		{ { data = codes, matcher = mode }, { data = { ["空"] = "x", ["🙂"] = "x" }, fallback = true } }
	)
end
compare({ "👩‍💻á👩‍💻💻1️⃣", "中国中国", "きゃきゃ" }, {
	"d",
	"de",
	"dev",
	"deva",
	"devaccent",
	"word",
	"wordd",
	"worddev",
	"pc",
	"one",
	"1",
	"d",
	"kya",
	"country",
	"wordcountry",
}, {
	{
		data = words({
			["👩‍💻"] = "dev",
			["🇨🇳"] = "word",
			["á"] = "accent",
			["💻"] = "pc",
			["1️⃣"] = "one",
			["国"] = "country",
			["ゃ"] = "kya",
		}),
	},
})
compare({ "a á z ź 中 𠀀 👩‍💻 👩🏽‍💻", "\255x\0" }, { "x", "xx", "a", "z" }, {
	{ data = { a = "x", ["á"] = "x", z = "x", ["ź"] = "x" } },
	{ data = { ["中"] = "x", ["𠀀"] = "x" } },
	{
		data = { ["👩‍💻"] = "x", ["👩🏽‍💻"] = "x" },
	},
	{ data = { ["\255"] = "x", ["\0"] = "x" }, fallback = true },
})
compare({ ("甲"):rep(50) }, { "a", ("a"):rep(5), ("a"):rep(20), ("a"):rep(30), "b" }, {
	{
		data = {
			["甲"] = { "a", "aa", "aaa", "aaaa", "aaaaa", "aaaaaa", "aaaaaaa", "aaaaaaaa", "aaaaaaaaa", "aaaaaaaaaa" },
		},
	},
})
-- Full-data source comparisons run only when optional packages are installed.
if #vim.api.nvim_get_runtime_file("lua/flash-any/sources/pinyin.lua", false) > 0 then
	-- Full TSV entries, conversion, punctuation, fuzzy variants and padding are built once.
	compare(
		{ "中国，a。生僻字𠮷", "重行长" },
		{ "z", "zg", "zg,a.", "zhong", "chong", "x", "zhongg" },
		{ "pinyin" }
	)
	compare(
		{ "中国，a。声生" },
		{ "v", "vs", "vsgo", "vsgo,a.", "ug", "s" },
		{ { name = "pinyin", scheme = "flypy", fuzzy = true, append_space_below = 3 } }
	)

	for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
		for _, padding in ipairs({ 0, 4, 6 }) do
			compare(
				{ "中国，a。声生张安", "重行长㐀" },
				{ "z", "zh", "zg", "zong", "zhongguo", "zhongg", "zang", "zan", "an", "an ", "zang ", "zg,a.", "qiu" },
				{
					{
						name = "pinyin",
						matcher = mode,
						fuzzy = true,
						append_space_below = padding > 0 and padding or nil,
					},
				}
			)
		end
	end

	-- Recognition and fallback disappear at build time, including empty lists.
	compare(
		{ "中国，a。𠮷😀󰊢", "重行长" },
		{ "z", "zhong", "zg", "x", "g", "grin", "fa", "a" },
		{ "pinyin", { name = "tiger", selection = false }, "wubi86", "nerdfont", "unicode" }
	)
end
compare({ "甲乙丙a á👩‍💻\255" }, { "a", "b", "ab", "x", "xy", "\0", "\0a", "a\0" }, {
	{ data = { ["甲"] = {}, a = "ab", ["á"] = "xy" } },
	{ data = { ["甲"] = "a", ["乙"] = "b", a = "x" }, fallback = true },
	{ data = { ["甲"] = { "\0", "\0a", "a\0" }, ["乙"] = "ab", ["丙"] = "x" }, matcher = "initial" },
	{ data = { ["甲"] = "xy", ["👩‍💻"] = "ab" }, matcher = "prefix" },
})
local collision_codes, collision_text = {}, {}
for i = 1, 26 do
	-- Same low six scalar bits force a collision chain in the 64-slot hash.
	local key = vim.fn.nr2char(0x4E00 + i * 64) .. "́"
	collision_codes[key], collision_text[#collision_text + 1] = "x" .. i, key
end
compare({ table.concat(collision_text, " ") }, { "x", "x1", "x2", "x26", "x27" }, { { data = collision_codes } })
-- Build is deterministic and failed builds leave the previous package intact.
local _, path = engine({ { data = { ["中"] = "ab" } } })
local function read(file)
	local handle = assert(io.open(file, "rb"))
	local bytes = handle:read("*a")
	handle:close()
	return bytes
end
local first = read(path)
local function u32(bytes, offset)
	local a, b, c, d = bytes:byte(offset + 1, offset + 4)
	return a + b * 256 + c * 65536 + d * 16777216
end
local function replace(bytes, offset, value)
	local packed = string.char(
		value % 256,
		math.floor(value / 256) % 256,
		math.floor(value / 65536) % 256,
		math.floor(value / 16777216)
	)
	return bytes:sub(1, offset) .. packed .. bytes:sub(offset + 5)
end
build.binary({ sources = { { data = { ["中"] = "ab" } } }, output = path })
assert(read(path) == first)
-- C serialization handles buffer-sized encodings and owns failed-write cleanup.
local long_code = string.rep("a", 20000)
local _, long_path = engine({ { data = { ["中"] = long_code } } })
local long_bytes = read(long_path)
assert(long_bytes:find(long_code, 1, true))
build.binary({ sources = { { data = { ["中"] = long_code } } }, output = long_path })
assert(read(long_path) == long_bytes)
local directory = vim.fn.tempname()
assert(vim.uv.fs_mkdir(directory, 448))
assert(not pcall(build.binary, { sources = {}, output = directory }))
assert(vim.fn.glob(directory .. ".*") == "")
assert(vim.uv.fs_rmdir(directory))
assert(not pcall(build.binary, { sources = {}, output = directory .. "/missing.bin" }))
assert(not pcall(require("flash-any.native").write, path, { "中" }, { { { 99, "a" } } }))
assert(read(path) == first)
for _, specs in ipairs({
	{ { data = { ["中国"] = "word" } } },
	{ {
		matcher = function()
			return false
		end,
	} },

	{ {
		loader = function()
			return { "a" }
		end,
	} },
}) do
	assert(not pcall(build.binary, { sources = specs, output = path }))
	assert(read(path) == first)
end
local entries_start = 40
local hashes_start = entries_start + u32(first, 16) * 16
local pages_start = hashes_start + u32(first, 20) * 4
local pool_start = pages_start + (u32(first, 24) > 0 and (0x1100 + u32(first, 24) * 256) * 4 or 0)
local first_codes = pool_start + u32(first, entries_start + 8)
for _, bytes in ipairs({
	"",
	first:sub(1, 7),
	first:sub(1, -2),
	first .. "x",
	"B" .. first:sub(2),
	first:sub(1, 7) .. "\4" .. first:sub(9),
	replace(first, 8, 18),
	replace(first, 16, 0xFFFFFFFF),
	replace(first, 20, 3),
	replace(first, 24, 0xFFFFFFFF),
	replace(first, 32, 1),
	replace(first, entries_start, 0xFFFFFFFF),
	replace(first, entries_start + 12, 0xFFFFFFFF),
	replace(first, pages_start, 0xFFFFFFFF),
	replace(first, pages_start + 0x1100 * 4, 0xFFFFFFFF),
	first:sub(1, first_codes) .. "\132" .. first:sub(first_codes + 2),
}) do
	local file = root .. "/bad.bin"
	local handle = assert(io.open(file, "wb"))
	handle:write(bytes)
	handle:close()
	assert(not pcall(native.load, file), "corrupt package must fail")
end
-- Equal tagged lists share one blob even when source order/code order differs.
local _, shared_path = engine({
	{ data = { ["中"] = { "ab", "a" }, ["国"] = { "a", "ab", "a" } } },
	{ data = { ["中"] = "ab", ["国"] = "a" } },
})
local shared = read(shared_path)
local offsets = {}
local shared_pool = 40
	+ u32(shared, 16) * 16
	+ u32(shared, 20) * 4
	+ (u32(shared, 24) > 0 and (0x1100 + u32(shared, 24) * 256) * 4 or 0)
for i = 0, u32(shared, 16) - 1 do
	local record = 40 + i * 16
	local at, size = shared_pool + u32(shared, record), u32(shared, record + 4)
	local key = shared:sub(at + 1, at + size)
	if key == "中" or key == "国" then
		offsets[key] = u32(shared, record + 8)
	end
end
assert(offsets["中"] == offsets["国"], "identical tagged lists should share their payload")
-- A state pins the immutable snapshot even after its book/file disappears.
local session
do
	local book, snapshot_path = engine({ { data = { ["中"] = "ab" } } })
	session = book:new_state()
	assert(vim.uv.fs_unlink(snapshot_path))
end
collectgarbage("collect")
local found = session:scan(0, 1, 0, 1, 1, { "中" }, "ab", nil)
assert(#found == 1 and found[1].pos[2] == 0)
-- Native has no dependency on the runtime Lua scanner or Lua source callbacks.
local old_get, old_char = match.get, match.char
rawset(match, "get", function()
	error("native path called Lua scanner")
end)
rawset(match, "char", function()
	error("native path called Lua char scanner")
end)
local captured
package.loaded.flash = {
	jump = function(opts)
		captured = opts
	end,
	remote = function(opts)
		captured = opts
	end,
}
local plugin = require("flash-any")
plugin.setup({ binary = path })
plugin.jump()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" })
local state = {
	pattern = function()
		return "ab"
	end,
}
assert(#captured.matcher(0, state, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
plugin.remote()
assert(#captured.matcher(0, state, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
assert(not pcall(plugin.setup, { binary = path, sources = "pinyin" }))
rawset(match, "get", old_get)
rawset(match, "char", old_char)
collectgarbage("collect")
print("native binary/scanner tests passed (" .. comparisons .. " differential comparisons)")

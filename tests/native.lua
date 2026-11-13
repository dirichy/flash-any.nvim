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
	-- Frozen factories predate declarative file definitions; adapt only their data input.
	local reference_specs = vim.deepcopy(specs)
	for i, spec in ipairs(reference_specs) do
		local name = type(spec) == "string" and spec or spec.name
		if name and require("flash-any.source").load(name).file then
			local resolved = require("flash-any.source").resolve({ spec })[2]
			local data = {}
			for glyph, codes in pairs(require("flash-any.table").materialize(resolved.data)) do
				local spellings = {}
				for _, code in ipairs(codes) do
					vim.list_extend(spellings, resolved.groups and resolved.groups[code] or { code })
				end
				data[glyph] = spellings
			end
			reference_specs[i] = { data = data, matcher = resolved.mode, fallback = resolved.fallback }
		end
	end
	local sources = registry.resolve(reference_specs)
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
	{ "abc abca", "", "中a国", "á👩‍💻🇨🇳\255" },
	{ "", "a", "ab", "abc", "a", "x", "中", "á", "a‍", "\r\n", "\255" },
	{}
)
-- Scalar entries must not recognize just the first scalar of a compound grapheme.
local last_scalar = vim.fn.nr2char(0x10FFFF)
compare({ "a á 👩 👩‍💻 " .. last_scalar .. "\255", "中国中" }, { "x", "xx", "y", "w" }, {
	{ data = words({ a = "x", ["👩"] = "x", [last_scalar] = "x", ["\255"] = "y", ["国"] = "w" }) },
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
compare({ "a á z ź 中 𠀀 👩‍💻 👩🏽‍💻", "\255x" }, { "x", "xx", "a", "z" }, {
	{ data = { a = "x", ["á"] = "x", z = "x", ["ź"] = "x" } },
	{ data = { ["中"] = "x", ["𠀀"] = "x" } },
	{
		data = { ["👩‍💻"] = "x", ["👩🏽‍💻"] = "x" },
	},
	{ data = { ["\255"] = "x" }, fallback = true },
})
compare({ ("甲"):rep(50) }, { "a", ("a"):rep(5), ("a"):rep(20), ("a"):rep(30), "b" }, {
	{
		data = {
			["甲"] = { "a", "aa", "aaa", "aaaa", "aaaaa", "aaaaaa", "aaaaaaa", "aaaaaaaa", "aaaaaaaaa", "aaaaaaaaaa" },
		},
	},
})
-- All overlapping word prefixes share one forward traversal. Input consumption
-- can continue after a word, and completed matches reserve following word codes.
for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
	compare({
		"中国人中国人民甲乙丙中国",
		"きゃきゃ中á👩‍💻中国",
		("甲"):rep(40),
		"\255中国\255",
	}, { "a", "ab", "abc", "abcd", "abx", "x", "xy", "xyz", "abxyz", "zg", "zgr", "k", "kk", "q", "qq", "qqq", "b" }, {
		{
			matcher = mode,
			data = words({
				["中"] = "a",
				["中国"] = { "ab", "x" },
				["中国人"] = "abc",
				["中国人民"] = "abcd",
				["甲"] = "q",
				["甲甲"] = "qq",
				["甲甲甲"] = "qqq",
				["乙"] = "y",
				["乙丙"] = "yz",
				["甲乙"] = "xy",
				["甲乙丙"] = "xyz",
				["きゃ"] = "k",
				["きゃきゃ"] = "kk",
				["á👩‍💻"] = "b",
				["\255中国"] = "zg",
				["中国\255"] = "zgr",
			}),
		},
	})
end
-- Byte order is not token order when valid UTF-8 and malformed prefixes overlap.
compare({ "\194A|\194\160X|\194\255" }, { "bad", "valid", "tail", "b", "v", "t" }, {
	{ data = words({ ["\194A"] = "bad", ["\194\160X"] = "valid", ["\194\255"] = "tail" }) },
})
-- Deterministic small dictionaries exercise competing segmentations independently
-- of the prefix-index implementation, using the frozen matcher as the oracle.
math.randomseed(20261112)
for round = 1, 6 do
	local map = {}
	local glyphs = { "甲", "乙", "丙", "丁" }
	for _ = 1, 24 do
		local key = {}
		for _ = 1, math.random(1, 5) do
			key[#key + 1] = glyphs[math.random(#glyphs)]
		end
		map[table.concat(key)] = ({ "x", "xy", "y", "yx" })[math.random(4)]
	end
	local text = {}
	for _ = 1, 90 do
		text[#text + 1] = glyphs[math.random(#glyphs)]
	end
	compare({ table.concat(text), "甲乙丙丁甲甲甲乙" }, { "x", "y", "xy", "yx", "xx", "xyx", "yxy", "xyxy" }, {
		{ data = words(map), matcher = ({ "full_code", "initial", "prefix" })[(round - 1) % 3 + 1] },
	})
end
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
compare({ "甲乙丙a á👩‍💻\255" }, { "a", "b", "ab", "x", "xy" }, {
	{ data = { ["甲"] = {}, a = "ab", ["á"] = "xy" } },
	{ data = { ["甲"] = "a", ["乙"] = "b", a = "x" }, fallback = true },
	{ data = { ["甲"] = { "c", "ca", "ac" }, ["乙"] = "ab", ["丙"] = "x" }, matcher = "initial" },
	{ data = { ["甲"] = "xy", ["👩‍💻"] = "ab" }, matcher = "prefix" },
})
local collision_codes, collision_text = {}, {}
for i = 1, 26 do
	-- Nearby scalar labels exercise densely packed sibling transitions.
	local key = vim.fn.nr2char(0x4E00 + i * 64) .. "́"
	collision_codes[key], collision_text[#collision_text + 1] = "x" .. i, key
end
compare({ table.concat(collision_text, " ") }, { "x", "x1", "x2", "x26", "x27" }, { { data = collision_codes } })
-- Build is deterministic and failed builds leave the previous package intact.
local first_specs = { { data = { ["中"] = "ab", ["á"] = "accent", ["b́"] = "bee" } } }
local _, path = engine(first_specs)
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
build.binary({ sources = first_specs, output = path })
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
local function scalar_slot(bytes, cp)
	local page = u32(bytes, 40 + math.floor(cp / 256) * 4)
	assert(page > 0)
	return 40 + 0x1100 * 4 + (page - 1) * 256 * 4 + cp % 256 * 4
end
local pages_start = 40
local trie_start = 40 + (u32(first, 24) > 0 and (0x1100 + u32(first, 24) * 256) * 4 or 0)
local pool_start = trie_start + u32(first, 20) * 8
local function node(bytes, start, state)
	local low, high = u32(bytes, start + state * 8), u32(bytes, start + state * 8 + 4)
	local base = low % 0x1000000
	if base >= 0x800000 then
		base = base - 0x1000000
	end
	return base,
		math.floor(high / 32) % 0x800000,
		math.floor(low / 0x1000000) + high % 32 * 256,
		math.floor(high / 0x10000000)
end
local function put_node(bytes, start, state, base, parent, quotient, kind)
	local low = base % 0x1000000 + quotient % 256 * 0x1000000
	local high = math.floor(quotient / 256) + parent * 32 + kind * 0x10000000
	return replace(replace(bytes, start + state * 8, low), start + state * 8 + 4, high)
end
local function parent_of(bytes, start, state, parent)
	local base, _, quotient, kind = node(bytes, start, state)
	return put_node(bytes, start, state, base, parent, quotient, kind)
end
local function step(bytes, start, state, cp)
	local base, _, _, kind = node(bytes, start, state)
	local modulus = 2 ^ (kind + 8)
	local next_state = base + cp % modulus
	assert(next_state >= 0 and next_state < u32(bytes, 20))
	local _, parent, quotient, child_kind = node(bytes, start, next_state)
	assert(parent == state + 1)
	assert(cp == 0 and child_kind == 15 or cp > 0 and child_kind ~= 15 and quotient == math.floor(cp / modulus))
	return next_state
end
-- Local moduli differ between siblings' subtrees; unknown congruent labels fail.
local modular_map = {
	["aက"] = "left",
	["aᄀ"] = "right",
	["bက"] = "down",
	["bခ"] = "up",
	ab = "stem",
	["abက"] = "deep",
}
compare(
	{ "aက aᄀ bက bခ aሀ bᄀ abက" },
	{ "left", "right", "down", "up", "l", "r", "d", "u", "stem", "deep" },
	{
		{ data = words(modular_map) },
	}
)
local modular, modular_path = engine({ { data = modular_map } })
local modular_bytes = read(modular_path)
local modular_start = 40 + (0x1100 + u32(modular_bytes, 24) * 256) * 4
local a = step(modular_bytes, modular_start, 0, 97)
local b = step(modular_bytes, modular_start, 0, 98)
assert(select(4, node(modular_bytes, modular_start, a)) == 1, "a needs modulus 512")
assert(select(4, node(modular_bytes, modular_start, b)) == 0, "b keeps modulus 256")
local stem = step(modular_bytes, modular_start, a, 98)
assert(select(4, node(modular_bytes, modular_start, stem)) == 5, "terminal zero participates in modulus selection")
step(modular_bytes, modular_start, stem, 0)
step(modular_bytes, modular_start, stem, 0x1000)
for i, case in ipairs({ { "aሀ", "left" }, { "bᄀ", "down" } }) do
	assert(#modular:new_state():scan(0, 1, i, 1, 1, { case[1] }, case[2], {}) == 0)
end
local parents = engine({ { data = { aa = "left", ba = "down", bc = "right" } } })
assert(
	#parents:new_state():scan(0, 1, 1, 1, 1, { "c" }, "down", {}) == 0,
	"a matching quotient at another parent's slot must fail"
)
-- The largest exponent fits four bits and is selected without failed builds.
local far = "a" .. vim.fn.nr2char(0x100001)
local _, far_path = engine({ { data = { ["a\1"] = "low", [far] = "high" } } })
local far_bytes = read(far_path)
local far_start = 40 + (0x1100 + u32(far_bytes, 24) * 256) * 4
local far_node = step(far_bytes, far_start, 0, 97)
assert(select(4, node(far_bytes, far_start, far_node)) == 13, "modulus 2^21 is representable")
step(far_bytes, far_start, far_node, 0x100001)
-- Terminal payloads retain a full u32 offset, beyond the normal 24-bit base.
do
	local wide_path = root .. "/wide-offset.bin"
	native.write(wide_path, { "中", "甲乙" }, { { { 1, string.rep("a", 0x1000000) } }, { { 1, "tail" } } })
	local wide = native.load(wide_path)
	assert(#wide:new_state():scan(0, 1, 1, 1, 1, { "甲乙" }, "tail", {}) == 1)
end
local accent = step(first, trie_start, step(first, trie_start, 0, 97), 0x301)
local terminal = step(first, trie_start, accent, 0)
local code_slot = scalar_slot(first, vim.fn.char2nr("中"))
local first_codes = pool_start + u32(first, code_slot) - 1
local terminator = pool_start + u32(first, 28) - 1
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
	put_node(first, trie_start, 0, 0, 1, 0, 0), -- Root cannot have a parent.
	put_node(first, trie_start, 0, -0x800000, 0, 0, 0), -- Out-of-range root remainder.
	replace(first, trie_start + terminal * 8, 0), -- Missing terminal code list.
	replace(first, trie_start + terminal * 8, u32(first, 28)), -- Empty final pool byte.
	parent_of(first, trie_start, terminal, terminal + 1), -- Self parent.
	parent_of(first, trie_start, terminal, 0x7FFFFF), -- Invalid parent.
	put_node(first, trie_start, accent, 0, 1, 0, 14), -- Reserved exponent code.
	replace(first, code_slot, 0xFFFFFFFF),
	replace(first, 36, 0xFFFFFFFF),
	first:sub(1, terminator) .. "a" .. first:sub(terminator + 2), -- Missing final list terminator.
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
-- A disconnected parent cycle must fail even when labels and terminal counts fit.
local cycle = string.rep("\0", 6 * 8)
cycle = put_node(cycle, 0, 3, u32(first, code_slot), 6, 0, 15)
cycle = put_node(cycle, 0, 4, 4, 6, 0, 0)
cycle = put_node(cycle, 0, 5, 3, 5, 0, 0)
local cyclic = first:sub(1, trie_start) .. cycle .. first:sub(pool_start + 1)
cyclic = replace(replace(replace(cyclic, 12, #cyclic), 16, 1), 20, 6)
local cyclic_file = root .. "/cycle.bin"
local handle = assert(io.open(cyclic_file, "wb"))
handle:write(cyclic)
handle:close()
local valid, reason = pcall(native.load, cyclic_file)
assert(not valid and tostring(reason):find("cyclic binary Trie", 1, true), tostring(reason))
-- The two indexes can share one terminated list; scalar keys need no records.
local _, shared_path = engine({
	{ data = { ["中"] = { "ab", "a" }, ["国"] = { "a", "ab", "a" }, ["á"] = { "a", "ab" } } },
	{ data = { ["中"] = "ab", ["国"] = "a" } },
})
local shared = read(shared_path)
local chinese = u32(shared, scalar_slot(shared, vim.fn.char2nr("中"))) - 1
local country = u32(shared, scalar_slot(shared, vim.fn.char2nr("国"))) - 1
local text_start = 40 + (0x1100 + u32(shared, 24) * 256) * 4
local text_end = step(shared, text_start, step(shared, text_start, step(shared, text_start, 0, 97), 0x301), 0)
assert(
	chinese == country and chinese == u32(shared, text_start + text_end * 8) - 1,
	"both tables must share equal tagged lists"
)
assert(u32(shared, 16) == 1 and u32(shared, 36) == 129)
for _, case in ipairs({
	{ {}, {} }, -- No page directory and no text index.
	{ { "国", "中" }, { { { 1, "ab" } }, { { 1, "ab" } } } }, -- Scalar input order is irrelevant.
	{ { "á", "b́", "\255" }, { { { 1, "ab" } }, { { 1, "ab" } }, { { 1, "bad" } } } },
}) do
	native.write(root .. "/separate.bin", case[1], case[2])
	local bytes = read(root .. "/separate.bin")
	assert(u32(bytes, 36) == (#case[1] == 2 and 2 or 0))
	assert(u32(bytes, 16) == (#case[1] == 3 and 3 or 0))
	assert(not bytes:find("中", 1, true) and not bytes:find("国", 1, true), "scalar keys must not be serialized")
	assert(native.load(root .. "/separate.bin"))
end
-- NUL encodings and optional suffixes are rejected before replacing an existing package.
for _, code in ipairs({ "\0", "\0a", "a\0", "a\0b" }) do
	assert(not pcall(build.binary, { sources = { { data = { ["中"] = code } } }, output = path }))
	assert(not pcall(native.write, path, { "中" }, { { { native.modes.full_code, code } } }))
	assert(not pcall(native.write, path, { "中" }, { { { native.modes.suffix, "a", code } } }))
	assert(not pcall(build.selectors, {}, {}, { code }))
	assert(read(path) == first)
end
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

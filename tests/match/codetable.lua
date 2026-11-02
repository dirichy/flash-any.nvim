#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local Cursor = require("flash-any.cursor")
local codetable = require("flash-any.match.codetable")

local function collect(mode, char, stream, source)
	local counts, keys, branches = {}, {}, 0
	local known = codetable[mode](Cursor.new(char), Cursor.new(stream), source, function(value, chars)
		assert(chars == nil or chars == 1)
		branches = branches + 1
		if type(value) == "number" then
			assert(value > 0 and value <= #stream and value % 1 == 0)
			counts[#counts + 1] = value
		else
			for i = 1, #value do
				keys[value:sub(i, i)] = true
			end
		end
	end)
	table.sort(counts)
	return known, counts, keys, branches
end

local function check(name, mode, stream, codes, expected)
	local known, counts, keys, branches =
		collect(mode, "甲", stream, { data = { ["甲"] = codes }, matcher = codetable[mode] })
	assert(known, name .. " recognizes character")
	assert(vim.deep_equal(counts, expected.consumed or {}), name .. " consumed")
	assert(vim.deep_equal(keys, expected.next or {}), name .. " next")
	assert((branches > 0) == (expected.success ~= false), name .. " success")
	print("ok - " .. name)
end

check("full code passes remaining input by byte count", "full_code", "zhongg", { "zhong" }, { consumed = { 5 } })
check("full code prefix finishes input", "full_code", "zh", { "zhong" }, { next = { o = true } })
check("exact full code crosses character boundary", "full_code", "zhong", { "zhong" }, { consumed = { 5 } })
check("failed full code", "full_code", "wrong", { "zhong" }, { success = false })
check("empty input queries initial keys", "full_code", "", { "zhong", "guo" }, { next = { z = true, g = true } })
check(
	"overlapping codes retain both branches",
	"full_code",
	"a",
	{ "a", "ab" },
	{ consumed = { 1 }, next = { b = true } }
)
check("initial keeps full and initial paths", "initial", "zhongg", { "zhong" }, { consumed = { 1, 5 } })
check("prefix keeps all consumption boundaries", "prefix", "zhongg", { "zhong" }, { consumed = { 1, 2, 3, 4, 5 } })
check("non-ASCII input cannot match ASCII code", "full_code", "中", { "zhong" }, { success = false })
check("overlapping prefix boundaries are deduplicated", "prefix", "ab", { "a", "ab", "abc" }, {
	consumed = { 1, 2 },
	next = { c = true },
})
check("known empty code list returns no matches", "full_code", "a", {}, { success = false })
check("empty encodings cannot consume zero bytes", "prefix", "a", { "" }, { success = false })

for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
	assert(not collect(mode, "甲", "甲", { matcher = codetable[mode] }))
	assert(not collect(mode, "甲", "甲", { data = {}, matcher = codetable[mode] }))
end
print("ok - code-table modes never fall back to the character")

local known, counts = collect("full_code", "a", "x", {
	name = "pinyin",
	data = { a = { "x" } },
	matcher = codetable.full_code,
})
assert(known and vim.deep_equal(counts, { 1 }))
print("ok - code-table matcher does not infer a scope from its source name")
print("all code-table matcher tests passed")

local tables = require("flash-any.table")
local words = tables.normalize({
	codes = { ["中"] = "a", ["中国"] = "ab", ["中国人"] = "abc" },
	prefixes = { ["中"] = true, ["中国"] = true },
	max_chars = 3,
})
for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
	local spans = {}
	assert(codetable[mode](Cursor.new("中国人后"), Cursor.new("abc"), {
		data = words,
		matcher = codetable[mode],
	}, function(bytes, chars)
		if type(bytes) == "number" then
			spans[chars] = true
		end
	end))
	assert(spans[1] and spans[2] and spans[3], mode .. " keeps all word lengths")
end
assert(not codetable.full_code(Cursor.new("中国"), Cursor.new("a"), {
	data = { ["中国"] = { "a" } },
	matcher = codetable.full_code,
}, function()
	error("multi-codepoint matching must be explicitly enabled")
end))
local calls = {}
local lazy = tables.lazy(
	tables.normalize({ codes = { ["中"] = "common" }, prefixes = {}, max_chars = 3 }),
	function(key, offset)
		calls[#calls + 1] = { key, offset }
		if key == "中" then
			return nil, 10
		end
		if key == "中国" then
			assert(offset == 10)
			return { "ab" }, 20
		end
		if key == "中国人" then
			assert(offset == 20)
			return { "abc" }, false
		end
		error(key)
	end
)
for _ = 1, 2 do
	assert(codetable.full_code(Cursor.new("中国人后"), Cursor.new("abc"), {
		data = lazy,
		matcher = codetable.full_code,
	}, function() end))
end
assert(#calls == 3 and lazy["中"][1] == "common")
-- Padding retains the same prefix/offset behavior without changing its source.
local padded = tables.append_space(lazy, 4)
local spans = {}
assert(codetable.full_code(Cursor.new("中国人"), Cursor.new("ab "), {
	data = padded,
	matcher = codetable.full_code,
}, function(bytes, chars)
	if bytes == 3 then
		spans[chars] = true
	end
end))
assert(spans[2] and lazy["中国"][1] == "ab" and #calls == 3)
local combining = tables.normalize({
	codes = { ["é"] = "e", ["👩‍💻"] = "dev" },
	prefixes = {},
	max_chars = 1,
})
for _, pair in ipairs({ { "é", "e", 1 }, { "👩‍💻", "dev", 1 } }) do
	local matched
	assert(codetable.full_code(Cursor.new(pair[1]), Cursor.new(pair[2]), {
		data = combining,
		matcher = codetable.full_code,
	}, function(_, chars)
		matched = chars
	end))
	assert(matched == pair[3])
end
print("ok - metadata-driven multi-codepoint modes retain spans, prefix offsets, padding and warm caches")

local misses = 0
local absent = tables.lazy({}, function()
	misses = misses + 1
	return nil, false
end)
for _ = 1, 2 do
	local codes, offset = tables.lookup(absent, "不存在")
	assert(codes == nil and offset == false)
end
assert(misses == 1, "terminal misses cache pruning even without codes")
print("ok - offset=false caches terminal misses independently of binary-search nodes")

local marked = tables.normalize({ codes = { ["中国"] = "country" }, prefixes = { ["中"] = true }, max_chars = 2 })
assert(marked["中"] == nil)
local codes, continuation = tables.lookup(marked, "中")
assert(codes == nil and continuation == true)
codes, continuation = tables.lookup(marked, "中日")
assert(codes == nil and continuation == false)
assert(not codetable.full_code(Cursor.new("中"), Cursor.new("country"), {
	data = marked,
	matcher = codetable.full_code,
}, function()
	error("prefix-only keys have no encodings")
end))
local _, padded_prefix = tables.lookup(tables.append_space(marked, 9), "中")
assert(padded_prefix == true)
print("ok - independent prefix sets survive normalization and padding; leaves and absent keys prune")

local limited = tables.lazy(tables.normalize({ codes = {}, prefixes = {}, max_chars = 2 }), function(key)
	if key == "中" then
		return { "a" }, 10
	end
	assert(key == "中国", "max_chars must stop before querying a third codepoint")
	return { "ab" }, 20
end)
local lengths = {}
assert(codetable.full_code(Cursor.new("中国人"), Cursor.new("abc"), {
	data = limited,
	matcher = codetable.full_code,
}, function(_, chars)
	lengths[chars] = true
end))
assert(lengths[1] and lengths[2] and not lengths[3])
print("ok - max_chars limits text codepoints independently of ASCII code length")

#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables = require("flash-any.table")
local input = { ["甲"] = { "a" }, ["乙"] = "b", ["中国"] = { "country" }, ["きゃ"] = "kya" }
local normalized = tables.normalize(input)
normalized["甲"][1] = "changed"
assert(input["甲"][1] == "a" and input["乙"] == "b")
normalized["中国"][1] = "changed"
assert(input["中国"][1] == "country" and normalized["きゃ"][1] == "kya")
print("ok - normalize isolates caller-owned arrays")

local lazy = tables.lazy({ ["甲"] = { "a" } }, function(char)
	if char == "乙" then
		return { "b" }
	end
end)
local transformed = tables.append_space(lazy, 4)
assert(transformed ~= lazy and transformed["甲"] ~= lazy["甲"])
assert(transformed["甲"][1] == "a " and lazy["甲"][1] == "a")
assert(transformed["乙"][1] == "b " and lazy["乙"][1] == "b")
print("ok - append_space does not mutate its input")

local lengths = { ["甲"] = { "a", "abc", "abcd", "abcde" } }
assert(tables.append_space(lengths) == lengths)
assert(vim.deep_equal(tables.append_space(lengths, 4)["甲"], { "a ", "abc ", "abcd", "abcde" }))
assert(vim.deep_equal(lengths["甲"], { "a", "abc", "abcd", "abcde" }))
assert(transformed["丙"] == nil)
print("ok - only codes strictly below the threshold gain one trailing space")

local definition = {
	codes = { ["中"] = "zhong", ["中国"] = "country" },
	prefixes = { ["中"] = true },
	max_chars = 2,
}
local word_table = tables.normalize(definition)
definition.prefixes["中"] = nil
definition.codes["中国"] = "changed"
local word_codes, longer = tables.lookup(word_table, "中")
assert(word_codes and word_codes[1] == "zhong" and longer == true)
word_codes, longer = tables.lookup(word_table, "中国")
assert(word_codes and word_codes[1] == "country" and longer == false, "a leaf with codes must stop immediately")
assert(
	tables.metadata(word_table).max_chars == 2 and tables.metadata(tables.normalize({ ["中"] = "z" })).max_chars == 1
)
local copied = tables.normalize(word_table)
assert(select(2, tables.lookup(copied, "中")) == true and tables.metadata(copied).max_chars == 2)
local padded_words = tables.append_space(word_table, 9)
assert(select(2, tables.lookup(padded_words, "中")) == true)
assert(select(2, tables.lookup(padded_words, "中国")) == false)
assert(tables.metadata(padded_words).max_chars == 2 and padded_words["中国"][1] == "country ")
-- Once a full TSV-style loader is attached, its terminal status is authoritative.
local full = tables.lazy(
	tables.normalize({
		codes = { ["中"] = "z" },
		prefixes = { ["中"] = true },
		max_chars = 2,
	}),
	function()
		return nil, false
	end
)
assert(select(2, tables.lookup(full, "中")) == false)
assert(full["中"][1] == "z")
assert(tables.metadata(tables.normalize({ codes = { ["中国人"] = "p" }, prefixes = {} })).max_chars == 3)
for _, prefixes in ipairs({ { ["中"] = false }, { ["中"] = 0 }, { [""] = true }, { [1] = true } }) do
	assert(not pcall(tables.normalize, { codes = {}, prefixes = prefixes }))
end
---@type any
local invalid_codes = { ["中"] = true }
assert(not pcall(tables.normalize, invalid_codes))
print("ok - code maps and prefix sets remain independent, copied, precise and loader-authoritative")

local scoped_input = { codes = { ["α"] = "alpha" }, scope = { { "α", "ω" } } }
local scoped = tables.normalize(scoped_input)
scoped_input.scope[1][1] = "a"
assert(tables.metadata(scoped).max_chars == 1)
assert(tables.metadata(scoped).scope[1][1] == "α")
assert(scoped["codes"] == nil and scoped["scope"] == nil, "metadata must not leak into the encoding map")
local scoped_copy = tables.normalize(scoped)
local scoped_padded = tables.append_space(scoped, 9)
assert(tables.metadata(scoped_copy).scope[1][1] == "α")
assert(tables.metadata(scoped_padded).scope[1][1] == "α")
assert(tables.metadata(scoped).scope ~= tables.metadata(scoped_copy).scope)
assert(tables.metadata(scoped).scope ~= tables.metadata(scoped_padded).scope)
assert(not pcall(tables.normalize, { codes = {}, scope = "all" }))
print("ok - codes-only descriptors and scope metadata survive isolated normalization and padding")

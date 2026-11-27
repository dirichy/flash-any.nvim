vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables = require("flash-any.table")
local input = { ["甲"] = { "a" }, ["乙"] = "b", ["中国"] = { "country" }, ["きゃ"] = "kya", ["空"] = {} }
local normalized = tables.normalize(input)
assert(getmetatable(normalized) == nil)
assert(normalized["乙"][1] == "b" and #normalized["空"] == 0)
normalized["甲"][1] = "changed"
assert(input["甲"][1] == "a")
local descriptor = tables.normalize({ codes = { ["α"] = "alpha" } })
assert(vim.deep_equal(descriptor, { ["α"] = { "alpha" } }))

local lengths = { ["甲"] = { "a", "abc", "abcd", "abcde" }, ["中国"] = { "word" }, ["空"] = {} }
assert(tables.append_space(lengths) == lengths)
local padded = tables.append_space(lengths, 4)
assert(vim.deep_equal(padded["甲"], { "a ", "abc ", "abcd", "abcde" }))
assert(vim.deep_equal(lengths["甲"], { "a", "abc", "abcd", "abcde" }))
assert(getmetatable(padded) == nil and #padded["空"] == 0 and padded["missing"] == nil)
local groups = { ["声母"] = { "a", "long" }, ["韵母"] = { "b" } }
local data, spellings = tables.append_space({ ["中"] = { "声母 韵母", "x" } }, 3, groups)
assert(vim.deep_equal(data["中"], { "声母 韵母", "x " }))
assert(vim.deep_equal(spellings, { ["声母"] = { "a ", "long" }, ["韵母"] = { "b " } }))
assert(groups["声母"][1] == "a")
for _, threshold in ipairs({ 0, -1, 1.5, "4" }) do
	assert(not pcall(tables.append_space, lengths, threshold))
end
for _, invalid in ipairs({ { ["中"] = true }, { [""] = "a" }, { ["中"] = "\0" }, { ["中"] = "未知组" } }) do
	assert(not pcall(tables.normalize, invalid))
end
print("plain-map normalization, empty recognition, padding, groups and ownership tests passed")

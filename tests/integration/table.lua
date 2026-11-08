-- Source packages contain one complete TSV each; no common Lua or punctuation modules.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables, registry = require("flash-any.table"), require("flash-any.source")
local names = { "pinyin", "tiger", "wubi86", "nerdfont", "unicode" }
for _, name in ipairs(names) do
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".tsv", false) == 1)
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".lua", false) == 0)
	local source = registry.load(name)
	assert(source == registry.load(name))
	assert(next(tables.materialize(source.data)))
end
-- A table entry must not be silently discarded because of its Unicode block.
for name, text in pairs({ pinyin = "", tiger = "⺀", nerdfont = "⚡" }) do
	local data = assert(registry.load(name).data)
	local code = assert(data[text], name .. " regression entry disappeared")[1]
	local file = vim.fn.tempname() .. ".bin"
	require("flash-any.build").binary({ sources = { name }, output = file })
	local engine = require("flash-any.native").load(file)
	assert(#engine:scan(0, 0, 1, 1, 1, { text }, code, nil) == 1, name .. " discarded a table entry")
	vim.uv.fs_unlink(file)
end
print("all table entries remain eligible regardless of character range")
local pinyin = assert(registry.load("pinyin").data)
local flypy = assert(registry.load("pinyin", { scheme = "flypy" }).data)
local rules = require("flash-any.pinyin.schemes")
local rules_before = vim.deepcopy(rules)
assert(vim.deep_equal(pinyin["中"], { "zhong" }) and vim.deep_equal(pinyin["㐀"], { "qiu" }))
assert(vim.deep_equal(flypy["中"], { "vs" }) and vim.deep_equal(flypy["㐀"], { "qq" }))
local fuzzy = assert(registry.load("pinyin", { scheme = "flypy", fuzzy = { initials = { { "zh", "z" } } } }).data)
assert(vim.deep_equal(fuzzy["中"], { "vs", "zs" }))
local full_fuzzy = registry.load("pinyin", { fuzzy = true })
assert(vim.deep_equal(full_fuzzy.data["中"], { "zhong" }))
assert(vim.deep_equal(full_fuzzy.groups.zhong, { "zhong", "zong" }))
local custom = registry.load("pinyin", { fuzzy = { initials = { { "zh", "z" } }, finals = { { "ang", "an" } } } })
local actual, expected = vim.deepcopy(custom.groups.zhang), { "zhang", "zhan", "zang", "zan" }
table.sort(actual)
table.sort(expected)
assert(vim.deep_equal(actual, expected))
local rare = registry.load("pinyin", { fuzzy = { finals = { { "iu", "ou" } } } })
assert(vim.deep_equal(rare.data["㐀"], { "qiu" }) and vim.deep_equal(rare.groups.qiu, { "qiu", "qou" }))
local punctuation = { ["，"] = { "," }, ["。"] = { "." }, ["；"] = { ";" }, ["、"] = { "/", "\\" } }
for _, data in ipairs({
	pinyin,
	flypy,
	fuzzy,
	full_fuzzy.data,
	registry.load("tiger").data,
	registry.load("wubi86").data,
}) do
	for char, codes in pairs(punctuation) do
		assert(vim.deep_equal(data[char], codes), char)
	end
end
flypy["，"][1] = "changed"
assert(pinyin["，"][1] == "," and registry.load("pinyin", { scheme = "flypy" }).data["，"][1] == ",")
assert(vim.deep_equal(rules, rules_before), "scheme conversion must not mutate shared rules")
local padded = assert(registry.load("pinyin", { scheme = "flypy", append_space_below = 4 }).data)
assert(vim.deep_equal(padded["中"], { "vs " }) and vim.deep_equal(padded["㐀"], { "qq " }))
assert(vim.deep_equal(pinyin["㐀"], { "qiu" }))
for _, invalid in ipairs({ "yes", { initials = "zh" }, { finals = { { "ang", 1 } } } }) do
	assert(not pcall(registry.load, "pinyin", { fuzzy = invalid }))
end
for _, name in ipairs({ "pinyin", "tiger", "wubi86" }) do
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/" .. name .. "/punctuation.lua", false) == 0)
end
local tiger = registry.load("tiger")
assert(
	tiger.selectors["，"] == nil and tiger.selectors["；"] == nil,
	"punctuation must not receive selection suffixes"
)
local path = vim.fn.tempname() .. ".bin"
require("flash-any.build").binary({ sources = { "tiger" }, output = path })
local book = require("flash-any.native").load(path)
assert(#book:scan(0, 0, 1, 1, 1, { "，" }, ", ", nil) == 0)
assert(#book:scan(0, 0, 1, 1, 1, nil, ",", nil) == 1)
vim.uv.fs_unlink(path)
print("single-TSV source data, scheme conversion, punctuation and ownership tests passed")

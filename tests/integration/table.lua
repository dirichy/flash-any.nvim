-- Source packages contain one complete TSV each; no common Lua or punctuation modules.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables, registry = require("flash-any.table"), require("flash-any.source")
local names = { "pinyin", "tiger", "wubi86", "nerdfont", "unicode" }
for _, name in ipairs(names) do
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".tsv", false) == 1)
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".lua", false) == 0)
	local source = registry.load(name)
	assert(source == registry.load(name))
	assert(next(tables.materialize(registry.resolve({ name })[2].data)))
end
-- A table entry must not be silently discarded because of its Unicode block.
for name, text in pairs({ pinyin = "𰻝", tiger = "⺀", nerdfont = "⚡" }) do
	local data = assert(registry.resolve({ name })[2].data)
	local code = assert(data[text], name .. " regression entry disappeared")[1]
	local file = vim.fn.tempname() .. ".bin"
	require("flash-any.build").binary({ sources = { name }, output = file })
	local engine = require("flash-any.native").load(file)
	assert(#engine:scan(0, 0, 1, 1, 1, { text }, code, nil) == 1, name .. " discarded a table entry")
	vim.uv.fs_unlink(file)
end
print("all table entries remain eligible regardless of character range")
local function resolved(opts)
	return registry.resolve({ vim.tbl_extend("force", { name = "pinyin" }, opts or {}) })[2]
end
local pinyin = assert(resolved().data)
assert(vim.deep_equal(pinyin["嗯"], { "en", "eng" }), "Rime Ice input spellings must be preserved")
assert(not pinyin["瓲"], "do not reintroduce readings outside Rime Ice")
local flypy = resolved({ scheme = "flypy" })
local fuzzy = resolved({ scheme = "flypy", fuzzy = { initials = { { "zh", "z" } } } })
assert(vim.deep_equal(pinyin["中"], { "zhong" }) and vim.deep_equal(pinyin["㐀"], { "qiu" }))
assert(vim.deep_equal(flypy.data["中"], { "zhong" }) and vim.deep_equal(flypy.groups.zhong, { "vs" }))
assert(vim.deep_equal(flypy.groups.qiu, { "qq" }))
assert(vim.deep_equal(fuzzy.groups.zhong, { "vs", "zs" }))
local rules = require("flash-any.pinyin.schemes")
local rules_before = vim.deepcopy(rules)
local full_fuzzy = resolved({ fuzzy = true })
assert(vim.deep_equal(full_fuzzy.groups.zhong, { "zhong", "zong" }))
local custom = resolved({ fuzzy = { initials = { { "zh", "z" } }, finals = { { "ang", "an" } } } })
local actual, expected = vim.deepcopy(custom.groups.zhang), { "zhang", "zhan", "zang", "zan" }
table.sort(actual)
table.sort(expected)
assert(vim.deep_equal(actual, expected))
local rare = resolved({ fuzzy = { finals = { { "iu", "ou" } } } })
assert(vim.deep_equal(rare.data["㐀"], { "qiu" }) and vim.deep_equal(rare.groups.qiu, { "qiu", "qou" }))
local punctuation = { ["，"] = { "," }, ["。"] = { "." }, ["；"] = { ";" }, ["、"] = { "/", "\\" } }
for _, data in ipairs({
	pinyin,
	flypy.data,
	fuzzy.data,
	full_fuzzy.data,
	registry.resolve({ "tiger" })[2].data,
	registry.load("wubi86").data,
}) do
	for char, codes in pairs(punctuation) do
		assert(vim.deep_equal(data[char], codes), char)
	end
end
flypy.data["，"][1] = "changed"
assert(pinyin["，"][1] == "," and resolved({ scheme = "flypy" }).data["，"][1] == ",")
assert(vim.deep_equal(rules, rules_before), "scheme conversion must not mutate shared rules")
local padded = resolved({ scheme = "flypy", append_space_below = 4 })
assert(vim.deep_equal(padded.data["中"], { "zhong" }))
assert(vim.deep_equal(padded.groups.zhong, { "vs " }) and vim.deep_equal(padded.groups.qiu, { "qq " }))
assert(vim.deep_equal(pinyin["㐀"], { "qiu" }))
for _, invalid in ipairs({ "yes", { initials = "zh" }, { finals = { { "ang", 1 } } } }) do
	assert(not pcall(registry.load, "pinyin", { fuzzy = invalid }))
end
for _, name in ipairs({ "pinyin", "tiger", "wubi86" }) do
	assert(#vim.api.nvim_get_runtime_file("lua/flash-any/" .. name .. "/punctuation.lua", false) == 0)
end
local tiger = registry.resolve({ "tiger" })[2]
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

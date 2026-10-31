#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables = require("flash-any.table")

local input = { ["甲"] = { "a" }, ["乙"] = "b" }
local normalized = tables.normalize(input)
normalized["甲"][1] = "changed"
assert(input["甲"][1] == "a" and input["乙"] == "b")
print("ok - normalize isolates caller-owned arrays")

local raw_pinyin = require("flash-any.table.pinyin")
local raw_rules = require("flash-any.table.schemes")
local pinyin_before = vim.deepcopy(raw_pinyin)
local rules_before = vim.deepcopy(raw_rules)
local pinyin = tables.load("pinyin")
local flypy = tables.load("pinyin", { scheme = "flypy" })
local fuzzy = tables.load("pinyin", { scheme = "flypy", fuzzy = { initials = { { "zh", "z" } } } })
assert(vim.deep_equal(flypy["中"], { "vs" }))
assert(vim.deep_equal(tables.load("pinyin", { scheme = "flypy", fuzzy = false })["中"], { "vs" }))
assert(vim.deep_equal(fuzzy["中"], { "vs", "zs" }))
assert(vim.deep_equal(pinyin["中"], { "zhong" }))
assert(vim.deep_equal(raw_pinyin, pinyin_before) and vim.deep_equal(raw_rules, rules_before))
print("ok - scheme conversion preserves shared pinyin and rules")

assert(rawget(flypy, "㐀") == nil and rawget(fuzzy, "㐀") == nil)
assert(vim.deep_equal(flypy["㐀"], { "qq" }))
assert(vim.deep_equal(fuzzy["㐀"], { "qq" }))
assert(vim.deep_equal(pinyin["㐀"], { "qiu" }))
assert(rawget(flypy, "㐀") == flypy["㐀"])
assert(vim.deep_equal(flypy["中"], { "vs" }))
print("ok - lazy entries are converted and cached by their own scheme")

local full_fuzzy = tables.load("pinyin", { fuzzy = true })
assert(vim.deep_equal(full_fuzzy["中"], { "zhong", "zong" }))
local custom_fuzzy = tables.load("pinyin", {
  fuzzy = { initials = { { "zh", "z" } }, finals = { { "ang", "an" } } },
})
local actual = vim.deepcopy(custom_fuzzy["张"])
table.sort(actual)
local expected = { "zhang", "zhan", "zang", "zan" }
table.sort(expected)
assert(vim.deep_equal(actual, expected))
local rare_fuzzy = tables.load("pinyin", { fuzzy = { finals = { { "iu", "ou" } } } })
assert(rawget(rare_fuzzy, "㐀") == nil)
assert(vim.deep_equal(rare_fuzzy["㐀"], { "qiu", "qou" }))
assert(vim.deep_equal(pinyin["中"], { "zhong" }) and vim.deep_equal(pinyin["㐀"], { "qiu" }))
assert(vim.deep_equal(raw_pinyin, pinyin_before) and vim.deep_equal(raw_rules, rules_before))
print("ok - full pinyin expands fuzzy initials and finals without changing shared tables")

local padded = tables.load("pinyin", { scheme = "flypy", strategy = "top_force", max_length = 4 })
assert(vim.deep_equal(padded["中"], { "vs " }))
assert(vim.deep_equal(padded["㐀"], { "qq " }))
assert(vim.deep_equal(flypy["中"], { "vs" }) and vim.deep_equal(flypy["㐀"], { "qq" }))
assert(vim.deep_equal(pinyin["㐀"], { "qiu" }))
print("ok - top_force preserves ordinary and lazy default entries")

local lazy = tables.lazy({ ["甲"] = { "a" } }, function(char)
  if char == "乙" then return { "b" } end
end)
local transformed = tables.apply_strategy(lazy, { strategy = "top_force", max_length = 4 })
assert(transformed ~= lazy and transformed["甲"] ~= lazy["甲"])
assert(transformed["甲"][1] == "a " and lazy["甲"][1] == "a")
assert(transformed["乙"][1] == "b " and lazy["乙"][1] == "b")
print("ok - apply_strategy does not mutate its input")

local names = tables.available()
table.sort(names)
assert(vim.deep_equal(names, { "nerdfont", "pinyin", "tiger", "unicode", "wubi86" }))
assert(tables.load("pinyin") == pinyin)
assert(not pcall(tables.load, "flypy"))
assert(not pcall(tables.load, "pinyin", { scheme = "missing" }))
assert(not pcall(tables.load, "tiger", { scheme = "flypy" }))
print("ok - source registry exposes one pinyin source and rejects unknown schemes")

assert(not pcall(tables.load, "tiger", { strategy = "typo" }))
for _, value in ipairs({ 0, -1, 0.5, "4" }) do
  assert(not pcall(tables.load, "tiger", { strategy = "top_force", max_length = value }))
end
print("ok - strategy and max_length are validated during configuration")

for _, map in ipairs({ { ["ab"] = "x" }, { ["中"] = 1 }, { ["中"] = { "中" } }, { ["中"] = { "" } } }) do
  assert(not pcall(tables.normalize, map))
end
for _, invalid_fuzzy in ipairs({ "yes", { initials = "zh" }, { finals = { { "ang", 1 } } } }) do
  assert(not pcall(tables.load, "pinyin", { fuzzy = invalid_fuzzy }))
end
print("ok - code tables and fuzzy groups are validated before matching")

print("all table ownership tests passed")

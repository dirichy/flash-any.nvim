#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local build = require("flash-any.build")
local tables = require("flash-any.table")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function write(name, text)
	local path = root .. "/" .. name
	local file = assert(io.open(path, "wb"))
	file:write(text)
	file:close()
	return path
end
local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end
local function lua_codes(path)
	local value = dofile(path)
	assert(type(value.codes) == "table", "builder always emits a codes field")
	return value.codes
end
local source = write("source.csv", '"中","ab"\n"国","cd"\n"中","ab"\n"中国","word"\n')
local common = write("common.lua", 'return {["中"] = {"old"}}\n')
local opts = { source = source, lua = root .. "/out.lua", tsv = root .. "/out.tsv", common = common, format = "csv" }
local n, all, multi = build.table(opts)
assert(n == 1 and all == 3 and multi == 1)
assert(vim.deep_equal(lua_codes(opts.lua), { ["中"] = { "ab" } }))
assert(read(opts.tsv) == "中\tab\n中国\tword\n国\tcd\n")
assert(vim.deep_equal(dofile(opts.lua).scope, { { "中", "国" } }))
opts.common = write("empty.lua", "return {}\n")
n, all, multi = build.table(opts)
assert(n == 0 and all == 3 and multi == 1 and next(lua_codes(opts.lua)) == nil)
opts.common = write("single-quoted.lua", "return {['中'] = {'old'}}\n")
n, all, multi = build.table(opts)
assert(n == 1 and all == 3 and multi == 1)
opts.common = nil
n, all, multi = build.table(opts)
assert(n == 3 and all == 3 and multi == 1)
assert(vim.deep_equal(tables.from_files(opts.lua)["中国"], { "word" }))
opts.common = root .. "/missing.lua"
assert(not pcall(build.table, opts))
opts.common = nil
opts.format = "typo"
assert(not pcall(build.table, opts))

opts.source = write(
	"rime.yaml",
	"---\nname: demo\nversion: '1.0'\ncolumns:\n  - code\n  - text\n...\nab\t中\ncd\t国\nef\t中国\n"
)
for _, format in ipairs({ "rime", "auto" }) do
	opts.format = format
	n, all, multi = build.table(opts)
	assert(n == 3 and all == 3 and multi == 1)
	assert(read(opts.tsv) == "中\tab\n中国\tef\n国\tcd\n")
end

opts.source, opts.format = write("words.txt", "中国 country\nきゃ kya\n"), "space"
n, all, multi = build.table(opts)
assert(n == 2 and all == 2 and multi == 2)

local input =
	write("multi.tsv", "😀\tsmile,grin\r\n国\tgo\r\n中\t cd,ab,ab,, \r\n中\tef\r\n中国\tword\r\n空\t,, \r\n")
local expected_map =
	{ ["中"] = { "ab", "cd", "ef" }, ["中国"] = { "word" }, ["国"] = { "go" }, ["😀"] = { "grin", "smile" } }
local expected_tsv = "中\tab,cd,ef\n中国\tword\n国\tgo\n😀\tgrin,smile\n"
for _, format in ipairs({ "tsv", "tab", "auto" }) do
	opts.source, opts.format = input, format
	n, all, multi = build.table(opts)
	assert(n == 4 and all == 4 and multi == 1)
	assert(vim.deep_equal(lua_codes(opts.lua), expected_map))
	assert(read(opts.tsv) == expected_tsv)
end
local expected_lua = read(opts.lua)
opts.source = write("roundtrip.tsv", expected_tsv)
for _, format in ipairs({ "tsv", "auto" }) do
	opts.format = format
	n, all, multi = build.table(opts)
	assert(n == 4 and all == 4 and multi == 1)
	assert(read(opts.lua) == expected_lua and read(opts.tsv) == expected_tsv)
end
opts.common = common
n, all, multi = build.table(opts)
assert(n == 1 and all == 4 and multi == 1 and vim.deep_equal(lua_codes(opts.lua), { ["中"] = expected_map["中"] }))
assert(read(opts.tsv) == expected_tsv)
print("ok - multi-code TSV merges duplicate rows/codes and preserves words on round-trip")

local words = write(
	"words.tsv",
	"きゃ\tkya,kya\n中国\tcountry,word\n中国\tword\né\teacute\n👩‍💻\tdeveloper\n中\tzhong\n😀\tgrin\n"
)
opts.source, opts.format = words, "tsv"
opts.common = write("no-common.lua", "return {}\n")
n, all, multi = build.table(opts)
assert(n == 0 and all == 6 and multi == 2)
local empty_common = dofile(opts.lua)
assert(empty_common.max_chars == 2 and next(empty_common.codes) == nil and next(empty_common.prefixes) == nil)
local loaded = tables.from_files(opts.lua, opts.tsv)
assert(tables.metadata(loaded).max_chars == 2)
assert(vim.deep_equal(loaded["中国"], { "country", "word" }))
assert(vim.deep_equal(loaded["きゃ"], { "kya" }))
assert(vim.deep_equal(loaded["é"], { "eacute" }))
assert(vim.deep_equal(loaded["👩‍💻"], { "developer" }))
local word_common =
	write("word-common.lua", 'return {codes = {["中国"] = {"old"}}, prefixes = {["中"] = true}, max_chars = 2}\n')
opts.common = word_common
n, all, multi = build.table(opts)
assert(n == 1 and all == 6 and multi == 2)
assert(vim.deep_equal(tables.from_files(opts.lua)["中国"], { "country", "word" }))
assert(tables.from_files(opts.lua)["中"] == nil)
local _, longer = tables.lookup(tables.from_files(opts.lua), "中")
assert(longer == true)
print("ok - multi-codepoint keys load from Lua and lazy TSV, including combining and ZWJ sequences")

local lua_only_root = root .. "/lua-only"
vim.fn.mkdir(lua_only_root, "p")
local lua_only = { source = words, lua = lua_only_root .. "/out.lua", format = "tsv" }
n, all, multi = build.table(lua_only)
assert(n == 6 and all == 6 and multi == 2)
assert(#vim.fn.glob(lua_only_root .. "/*", false, true) == 1)
local pure = tables.from_files(lua_only.lua)
assert(tables.metadata(pure).max_chars == 2 and pure["中国"][1] == "country")
assert(select(2, tables.lookup(pure, "中")) == true)
assert(select(2, tables.lookup(pure, "中国")) == false)
lua_only.common = word_common
n, all, multi = build.table(lua_only)
assert(n == 1 and all == 6 and multi == 2)
assert(vim.deep_equal(lua_codes(lua_only.lua), { ["中国"] = { "country", "word" } }))
assert(dofile(lua_only.lua).max_chars == 2)
print("ok - Lua-only builds retain prefix metadata, full-input counts and common filtering")

local scope_input = write("scope.tsv", "🧑‍💻\tdev\n😀\tgrin\n")
local scope_lua = root .. "/scope.lua"
local scope_common = write("scope-common.lua", 'return { ["🧑‍💻"] = {"old"} }')
local scope_n = build.table({ source = scope_input, lua = scope_lua, common = scope_common })
assert(scope_n == 1)
local generated_scope = dofile(scope_lua).scope
assert(
	vim.deep_equal(generated_scope, { { "😀", "🧑‍💻" } }),
	"scope covers all entry starts before common filtering"
)
local scopes = require("flash-any.scope")
local accepts = scopes.describe(generated_scope)
assert(scopes.contains(accepts, "😀") and scopes.contains(accepts, "🧑‍💻"))
assert(not scopes.contains(accepts, "💻") and not scopes.contains(accepts, "‍"))
print("ok - generated scope covers complete-input first graphemes, including supplementary Unicode")

opts.common, opts.format = nil, "csv"
opts.source = write("empty-keys.csv", '"","ab"\n" ","ab"\n')
n, all, multi = build.table(opts)
assert(n == 0 and all == 0 and multi == 0)
assert(vim.deep_equal(dofile(opts.lua), { codes = {}, prefixes = {}, max_chars = 1, scope = {} }))
for _, code in ipairs({ "中", "ab,中" }) do
	opts.source = write("invalid.tsv", "中国\t" .. code .. "\n")
	opts.format = "tsv"
	assert(not pcall(build.table, opts))
end
opts.format = "csv"
opts.source = write("invalid.csv", '"中","a,b"\n')
assert(not pcall(build.table, opts))
opts.source = write("invalid-key.csv", '"a\tb","code"\n')
assert(not pcall(build.table, opts))
opts.format = "rime"
opts.source = write("invalid.dict.yaml", "---\ncolumns:\n  - code\n  - text\n...\na,b\t中\n")
assert(not pcall(build.table, opts))

local notices = {}
local notify = vim.notify
rawset(vim, "notify", function(message, level)
	notices[#notices + 1] = { message = message, level = level }
end)
package.loaded.flash = {}
require("flash-any")
local command_source = write("command.csv", '"中","ab"\n')
local command_lua, command_tsv = root .. "/command.lua", root .. "/command.tsv"
vim.cmd("FlashAnyBuildTable " .. table.concat({ command_source, command_lua, command_tsv, "-", "csv", "utf-8" }, " "))
assert(vim.deep_equal(lua_codes(command_lua), { ["中"] = { "ab" } }))
assert(read(command_tsv) == "中\tab\n" and #notices == 1 and notices[1].level == vim.log.levels.INFO)
local command_multi = write("command.tsv", "中\tcd,ab,ab\r\n")
vim.cmd("FlashAnyBuildTable " .. table.concat({ command_multi, command_lua, command_tsv, "-", "tsv", "utf-8" }, " "))
assert(vim.deep_equal(lua_codes(command_lua), { ["中"] = { "ab", "cd" } }))
assert(read(command_tsv) == "中\tab,cd\n" and #notices == 2 and notices[2].level == vim.log.levels.INFO)
vim.cmd("FlashAnyBuildTable " .. table.concat({ words, command_lua, command_tsv, word_common, "tsv", "utf-8" }, " "))
assert(#notices == 3 and notices[3].level == vim.log.levels.WARN)
assert(notices[3].message:find("2 multi-grapheme entries", 1, true))
assert(vim.deep_equal(lua_codes(command_lua), { ["中国"] = { "country", "word" } }))
assert(read(command_tsv):find("きゃ\tkya\n", 1, true))
build.command(opts)
assert(#notices == 4 and notices[4].level == vim.log.levels.ERROR)
local previous_cwd = vim.fn.getcwd()
vim.cmd.lcd(root)
vim.cmd("FlashAnyBuildTable " .. command_source .. " " .. lua_only.lua)
assert(#notices == 5 and notices[5].level == vim.log.levels.INFO)
assert(notices[5].message == "flash-any: wrote 1 Lua entries")
assert(vim.deep_equal(lua_codes(lua_only.lua), { ["中"] = { "ab" } }))
vim.cmd("FlashAnyBuildTable " .. table.concat({ words, lua_only.lua, "-", "-", "tsv", "utf-8" }, " "))
assert(#notices == 6 and notices[6].level == vim.log.levels.WARN)
assert(notices[6].message:find("wrote 6 Lua entries", 1, true))
assert(not notices[6].message:find("TSV", 1, true))
assert(notices[6].message:find("2 multi-grapheme entries", 1, true))
vim.cmd("FlashAnyBuildTable " .. table.concat({ words, lua_only.lua, "-", word_common, "tsv", "utf-8" }, " "))
assert(#notices == 7 and vim.deep_equal(lua_codes(lua_only.lua), { ["中国"] = { "country", "word" } }))
assert(vim.fn.filereadable(root .. "/-") == 0, "the TSV placeholder must never become an output file")
vim.cmd.lcd(previous_cwd)
rawset(vim, "notify", notify)
print("ok - commands support omitted/placeholder TSV paths and report full-input warnings")

assert(
	not pcall(build.binary, { sources = { { lua = command_lua, tsv = command_tsv } }, output = root .. "/words.bin" })
)
local clusters = write("clusters.tsv", "é\teacute\n👩‍💻\tdeveloper\n")
local clusters_lua = root .. "/clusters.lua"
local _, _, cluster_words = build.table({ source = clusters, lua = clusters_lua })
local definition = dofile(clusters_lua)
assert(cluster_words == 0 and definition.max_chars == 1 and next(definition.prefixes) == nil)
local cluster_data = tables.from_files(clusters_lua)
assert(tables.metadata(cluster_data).max_chars == 1)
local words_with_clusters = write("cluster-words.tsv", "👩‍💻é\tword\n")
build.table({ source = words_with_clusters, lua = clusters_lua })
definition = dofile(clusters_lua)
assert(definition.max_chars == 2 and vim.deep_equal(definition.prefixes, { ["👩‍💻"] = true }))
assert(tables.metadata(tables.normalize({ codes = { ["👩‍💻"] = "dev" } })).max_chars == 1)
print("ok - builder counts graphemes and emits only cluster-boundary prefixes")
-- Sorting full keys cannot determine first-grapheme extremes: a💻 sorts after á.
local prefix_order = write("prefix-order.tsv", "a💻\tword\ná\taccent\n")
build.table({ source = prefix_order, lua = clusters_lua })
local scope_definition = dofile(clusters_lua)
assert(vim.deep_equal(scope_definition.scope, { { "a", "á" } }))
local full_scope = assert(require("flash-any.scope").describe(scope_definition.scope))
assert(require("flash-any.scope").contains(full_scope, "a") and require("flash-any.scope").contains(full_scope, "á"))
local one_cluster = write("one-cluster.tsv", "👩‍💻\tdev\n")
build.table({ source = one_cluster, lua = clusters_lua })
scope_definition = dofile(clusters_lua)
assert(vim.deep_equal(scope_definition.scope, { { "👩‍💻", "👩‍💻" } }))
assert(require("flash-any.scope").contains(require("flash-any.scope").describe(scope_definition.scope), "👩‍💻"))
print("ok - scope extrema use complete first graphemes independently of whole-key order")
print("all build API tests passed")

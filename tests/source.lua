#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local registry = require("flash-any.source")
local tables = require("flash-any.table")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
local function write(name, lines)
	vim.fn.writefile(lines, root .. "/lua/flash-any/sources/" .. name .. ".lua")
end
write("algorithm", {
	'error("discovery must not execute a source module")',
})
vim.opt.runtimepath:append(root)
assert(vim.tbl_contains(registry.available(), "algorithm"))
assert(package.loaded["flash-any.sources.algorithm"] == nil)
print("ok - runtime discovery does not execute source modules")

-- Build a private external plugin fixture instead of shipping example sources.
vim.fn.mkdir(root .. "/lua/flash-any/tables", "p")
vim.fn.writefile(
	{ 'return { codes = { ["あ"] = { "a" } }, prefixes = {}, max_chars = 2, scope = { { "あ", "い" } } }' },
	root .. "/lua/flash-any/tables/japan.lua"
)
vim.fn.writefile({ "あ\ta", "い\ti" }, root .. "/lua/flash-any/tables/japan.tsv")
write("japan", {
	'return function() return { codetable = "japan", matcher = "full_code", scope = { { "ぁ", "ヿ" } } } end',
})
assert(vim.tbl_contains(registry.available(), "japan"))
assert(package.loaded["flash-any.tables.japan"] == nil)
local definition = require("flash-any.sources.japan")()
assert(definition.codetable == "japan" and definition.data == nil)
assert(package.loaded["flash-any.tables.japan"] == nil)
local source = registry.load("japan")
assert(source.codetable == nil and tables.metadata(source.data).max_chars == 2)
assert(source == registry.load("japan"))
assert(source.data["あ"][1] == "a" and rawget(source.data, "い") == nil)
assert(source.data["い"][1] == "i")
assert(source.data["う"] == nil and rawget(source.data, "う") == false)
local padded = registry.load("japan", { append_space_below = 2 })
assert(padded ~= source and padded.data["あ"][1] == "a ")
assert(padded.data["い"][1] == "i " and source.data["い"][1] == "i")
local converted = tables.load("japan", {
	convert = function(codes)
		return vim.tbl_map(string.upper, codes)
	end,
	extra = { ["あ"] = "extra" },
})
assert(converted["あ"][1] == "extra" and converted["い"][1] == "I")
local extended = tables.load("japan", { extra = { a = "ascii" } })
assert(tables.metadata(extended).scope.a == true)
assert(tables.metadata(source.data).scope.a == nil, "extras cannot widen another instance's metadata")
assert(source.data["あ"][1] == "a" and source.data["い"][1] == "i")
local clustered = tables.load("japan", { extra = { ["á"] = "accent", ["👩‍💻"] = "dev" } })
local cluster_scope = assert(tables.metadata(clustered).scope)
assert(cluster_scope["á"] and cluster_scope["👩‍💻"] and not cluster_scope.a and not cluster_scope["👩"])
assert(tables.metadata(source.data).scope["👩‍💻"] == nil)
local scopes = require("flash-any.scope")
local accepts = scopes.describe(cluster_scope)
assert(
	scopes.contains(accepts, "á") and scopes.contains(accepts, "👩‍💻") and not scopes.contains(accepts, "👩")
)
print("ok - external tables share lazy loading, conversion and cache ownership rules")

write("romaji", { 'return function() return { codetable = "japan" } end' })
local romaji = registry.load("romaji")
assert(romaji.data ~= source.data and romaji.data["い"][1] == "i")
assert(require("flash-any.tables.japan").codes["あ"][1] == "a")
print("ok - a source can declare a differently named table with its own cache")

local captured
package.loaded.flash = {
	jump = function(opts)
		captured = opts
	end,
}
local plugin = require("flash-any")
local function run(text, pattern, specs)
	local path = root .. "/test.bin"
	require("flash-any.build").binary({ sources = specs, output = path })
	plugin.setup({ binary = path })
	plugin.jump()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
	return captured.matcher(0, {
		pattern = function()
			return pattern
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } })
end
assert(#run("あい", "ai", { "japan" }) == 1)
assert(#run("あい", "word", { "japan" }) == 0)
assert(#run("あい", "word", { { name = "japan", data = { ["あ"] = "a" } } }) == 0)
assert(#run("あい", "ai", { { name = "japan", matcher = "prefix" } }) == 1)
assert(#run("あ", "x", { { name = "japan", data = { ["あ"] = "x" } } }) == 1)
assert(#run("あ", "a", { { name = "japan", scope = { ["あ"] = false } } }) == 0)
assert(#run("a", "x", { { name = "japan", data = { a = "x" }, scope = "all" } }) == 1)
assert(#run("あ", "a", { { name = "japan", scope = {} } }) == 0)
---@type any Deliberately invalid public input.
local invalid = { name = "japan", matcher = function() end }
assert(not pcall(registry.resolve, { invalid }))
print("ok - an installed source is usable by name with matcher/data/scope overrides")

write("algorithm", { 'return function(opts) return { data = { ["あ"] = { opts.key or "x" } }, fallback = true } end' })
assert(#run("あ", "z", { { name = "algorithm", key = "z" } }) == 1)
assert(#run("あ", "z", { { data = { ["あ"] = "a" } }, { name = "algorithm", key = "z" } }) == 0)
assert(#run("あ", "z", { { data = { ["あ"] = "a" } }, { name = "algorithm", key = "z", fallback = false } }) == 1)
write("invalid_factory", { "return {}" })
write("invalid_result", { "return function() return false end" })
write("invalid_codetable", { "return function() return { codetable = {} } end" })
write("conflicting_data", { 'return function() return { codetable = "japan", data = {} } end' })
write("missing_table", { 'return function() return { codetable = "missing" } end' })
write("broken", { 'error("source initialization failed")' })
assert(not pcall(registry.load, "missing"))
assert(not pcall(registry.load, "invalid_factory"))
assert(not pcall(registry.load, "invalid_result"))
for _, name in ipairs({ "invalid_codetable", "conflicting_data", "missing_table" }) do
	assert(not pcall(registry.load, name))
end
local ok, err = pcall(registry.load, "broken")
assert(not ok and tostring(err):find("source initialization failed", 1, true))
print("ok - invalid and broken source factories report their errors")

vim.fn.delete(root, "rf")
print("all source extension tests passed")

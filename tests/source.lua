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
vim.fn.writefile({ 'return { ["あ"] = { "a" } }' }, root .. "/lua/flash-any/tables/japan.lua")
vim.fn.writefile({ "あ\ta", "い\ti" }, root .. "/lua/flash-any/tables/japan.tsv")
write("japan", {
  'return function() return { data = require("flash-any.table").load("japan"), matcher = "full_code" } end',
})
assert(vim.tbl_contains(registry.available(), "japan"))
assert(package.loaded["flash-any.tables.japan"] == nil)
local source = registry.load("japan")
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
assert(source.data["あ"][1] == "a" and source.data["い"][1] == "i")
print("ok - external tables share lazy loading, conversion and cache ownership rules")

local captured
package.loaded.flash = {
  jump = function(opts)
    captured = opts
  end,
}
local plugin = require("flash-any")
local function run(text, pattern, specs)
  plugin.setup({ sources = specs })
  plugin.jump()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  return captured.matcher(0, {
    pattern = function()
      return pattern
    end,
  }, { from = { 1, 0 }, to = { 1, 0 } })
end
assert(#run("あい", "ai", { "japan" }) == 1)
assert(#run("あい", "ai", { { name = "japan", matcher = "prefix" } }) == 1)
assert(#run("あ", "x", { { name = "japan", data = { ["あ"] = "x" } } }) == 1)
print("ok - an installed source is usable by name with configuration overrides")

write("algorithm", {
  "return function(opts)",
  '  local key = opts.key or "x"',
  "  return { fallback = true, matcher = function(text, stream, source, emit)",
  '    if text:get(1) ~= "あ" then return false end',
  '    if stream:get() == "" then emit(key)',
  "    elseif stream:get():sub(1, 1) == key then emit(1) end",
  "    return true",
  "  end }",
  "end",
})
assert(#run("あ", "z", { { name = "algorithm", key = "z" } }) == 1)
assert(#run("あ", "z", {
  { data = { ["あ"] = "a" } },
  { name = "algorithm", key = "z" },
}) == 0)
assert(#run("あ", "z", {
  { data = { ["あ"] = "a" } },
  { name = "algorithm", key = "z", fallback = false },
}) == 1)
assert(#run("あ", "q", {
  { name = "algorithm", data = { ["あ"] = "q" }, matcher = "full_code" },
}) == 1)
print("ok - table-free sources receive custom options; user matcher and fallback take precedence")

write("invalid_factory", { "return {}" })
write("invalid_result", { "return function() return false end" })
write("broken", { 'error("source initialization failed")' })
assert(not pcall(registry.load, "missing"))
assert(not pcall(registry.load, "invalid_factory"))
assert(not pcall(registry.load, "invalid_result"))
local ok, err = pcall(registry.load, "broken")
assert(not ok and tostring(err):find("source initialization failed", 1, true))
print("ok - invalid and broken source factories report their errors")

vim.fn.delete(root, "rf")
print("all source extension tests passed")

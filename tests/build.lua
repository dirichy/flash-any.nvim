#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local build = require("flash-any.build")
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
local source = write("source.csv", '"中","ab"\n"国","cd"\n"中","ab"\n"中国","word"\n')
local common = write("common.lua", 'return {\n  ["中"] = {"old"},\n}\n')
local opts = { source = source, lua = root .. "/out.lua", tsv = root .. "/out.tsv", common = common, format = "csv" }
local n, all = build.table(opts)
assert(n == 1 and all == 2)
assert(vim.deep_equal(dofile(opts.lua), { ["中"] = { "ab" } }))
assert(read(opts.tsv) == "中\tab\n国\tcd\n")
opts.common = write("empty.lua", "return {}\n")
n, all = build.table(opts)
assert(n == 0 and all == 2 and next(dofile(opts.lua)) == nil)
opts.common = write("single-quoted.lua", "return {['中'] = {'old'}}\n")
n, all = build.table(opts)
assert(n == 1 and all == 2)
opts.common = nil
n, all = build.table(opts)
assert(n == 2 and all == 2)
opts.common = root .. "/missing.lua"
assert(not pcall(build.table, opts))
opts.common = nil
opts.format = "typo"
assert(not pcall(build.table, opts))
opts.format = "rime"
opts.source = write("rime.yaml", "---\ncolumns:\n  - code\n  - text\n...\nab\t中\ncd\t国\nef\t中国\n")
n, all = build.table(opts)
assert(n == 2 and all == 2 and read(opts.tsv) == "中\tab\n国\tcd\n")
for _, code in ipairs({ "中", "a,b" }) do
  opts.source = write("invalid.tsv", "中\t" .. code .. "\n")
  opts.format = "tsv"
  assert(not pcall(build.table, opts))
end
package.loaded.flash = { jump = function() end }
require("flash-any")
local command_source = write("command.csv", '"中","ab"\n')
local command_lua, command_tsv = root .. "/command.lua", root .. "/command.tsv"
vim.cmd("FlashAnyBuildTable " .. table.concat({ command_source, command_lua, command_tsv, "-", "csv", "utf-8" }, " "))
assert(vim.deep_equal(dofile(command_lua), { ["中"] = { "ab" } }))
assert(read(command_tsv) == "中\tab\n")
print("all build API tests passed")

#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local tsv = require("flash-any.tsv")
local function fixture(content)
  local path = vim.fn.tempname()
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
  return path
end
local entries = { ["a"] = { "ab", "cd" }, ["中"] = { "zhong" }, ["😀"] = { "emoji" }, ["𠀀"] = { "rare" } }
local keys = vim.tbl_keys(entries)
table.sort(keys)
for _, newline in ipairs({ "\n", "\r\n" }) do
  local rows = {}
  for _, key in ipairs(keys) do rows[#rows + 1] = key .. "\t" .. table.concat(entries[key], ",") end
  local lookup = tsv.loader(fixture(table.concat(rows, newline) .. newline), {
    decode = function(value) return vim.split(value, ",", { plain = true }) end,
  })
  for _, key in ipairs(keys) do assert(vim.deep_equal(lookup(key), entries[key]), key) end
  assert(lookup("missing") == nil)
end
assert(tsv.loader(fixture(""))("a") == nil)
assert(vim.deep_equal(tsv.loader(fixture("中||ab"), { separator = "||" })("中"), { "ab" }))
local rows = {}
for cp = 0x4E00, 0x4E00 + 511 do rows[#rows + 1] = vim.fn.nr2char(cp) .. "\t" .. tostring(cp) end
local lookup = tsv.loader(fixture(table.concat(rows, "\n")))
for cp = 0x4E00, 0x4E00 + 511 do
  assert(vim.deep_equal(lookup(vim.fn.nr2char(cp)), { tostring(cp) }))
end
print("all TSV lookup tests passed")

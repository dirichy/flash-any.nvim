#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local literal = require("flash-any.match.literal")
local args = { source = literal }

assert(vim.deep_equal(literal.matcher("a", "abc", args), { { consumed = 1 } }))
assert(vim.deep_equal(literal.matcher("a", "", args), { { next = { a = true } } }))
assert(vim.deep_equal(literal.matcher("a", "b", args), {}))
for _, char in ipairs({ "中", "😀", string.char(0x80), string.char(0xE4, 0xB8) }) do
  for _, stream in ipairs({ "", "z", char }) do assert(literal.matcher(char, stream, args) == nil) end
end
for byte = 0, 127 do
  local char = string.char(byte)
  assert(vim.deep_equal(literal.matcher(char, char .. "x", args), { { consumed = 1 } }))
  assert(vim.deep_equal(literal.matcher(char, "", args), { { next = { [char] = true } } }))
end

print("all literal source tests passed")

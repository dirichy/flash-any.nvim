#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local Cursor = require("flash-any.cursor")
local literal = require("flash-any.sources.literal")()
local source = { matcher = literal.matcher }
local function check(char, stream, expected_known, expected)
  local values = {}
  local known = literal.matcher(Cursor.new(char), Cursor.new(stream), source, function(value, chars)
    assert(chars == nil or chars == 1)
    values[#values + 1] = value
  end)
  assert(known == expected_known and vim.deep_equal(values, expected), vim.inspect({ char, stream, known, values }))
end

check("", "", false, {})
check("a", "abc", true, { 1 })
check("a", "", true, { "a" })
check("a", "b", true, {})
for _, char in ipairs({ "中", "😀", string.char(0x80), string.char(0xE4, 0xB8) }) do
  for _, stream in ipairs({ "", "z", char }) do
    check(char, stream, false, {})
  end
end
for byte = 0, 127 do
  local char = string.char(byte)
  check(char, char .. "x", true, { 1 })
  check(char, "", true, { char })
end
print("all literal source tests passed")

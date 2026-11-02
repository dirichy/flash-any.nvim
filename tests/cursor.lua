#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local utf8 = require("flash-any.utf8")
-- Count actual UTF-8 decoding, not calls to get or cursor movement.
local iter_offset, decodes = utf8.iter_offset, 0
rawset(utf8, "iter_offset", function(...)
  local iter, str, offset = iter_offset(...)
  return function(value, col)
    decodes = decodes + 1
    return iter(value, col)
  end, str, offset
end)
local Cursor = require("flash-any.cursor")
rawset(utf8, "iter_offset", iter_offset)

local text = Cursor.new("あい🙂é")
assert(text.offset == 0 and decodes == 0)
assert(vim.deep_equal({ text:get(2) }, { "あい", 6, 3 }))
assert(text.offset == 0 and decodes == 2)
assert(text:get(2) == "あい" and decodes == 2)
assert(text:get(3) == "あい🙂" and decodes == 3)
assert(text:shift(2) and text.offset == 6 and decodes == 3)
assert(text:get(1) == "🙂" and decodes == 3)
assert(text:get(2) == "🙂e" and decodes == 4)
text:set_offset(3)
assert(text:get(3) == "い🙂e" and decodes == 4)
text:set_offset(0)
assert(text:get(3) == "あい🙂" and decodes == 4)
assert(text:shift(3) and text.offset == 10 and decodes == 4)
assert(text:shift() and text.offset == 11 and decodes == 4)
assert(text:get(1) == "́" and decodes == 5)
assert(not text:shift(2) and text.offset == 11 and decodes == 5)
assert(text:shift() and text.offset == #text.value and decodes == 5)
assert(text:get(1) == "" and not text:shift() and decodes == 5)
assert(text:get(99) == "" and decodes == 5)
print("ok - get, shift and set_offset share decoded boundaries across offsets and lengths")

local empty = Cursor.new("")
assert(empty:get() == "" and empty:get(1) == "" and not empty:shift())
empty:set_offset(0)
for _, invalid in ipairs({ 0, -1, 0.5, "1", false, math.huge }) do
  assert(not pcall(text.get, text, invalid))
  assert(not pcall(text.shift, text, invalid))
end
for _, invalid in ipairs({ -1, 1, 0.5, "1", false, #text.value + 1, math.huge }) do
  assert(not pcall(text.set_offset, text, invalid))
  assert(text.offset == #text.value)
end
print("ok - failed reads and moves preserve the cursor; offsets must be byte boundaries")

-- Compare every requested span against Neovim's codepoint boundaries, including
-- malformed sequences; no grapheme-cluster interpretation is involved.
for _, value in ipairs({
  "abc",
  "a\0中🙂",
  "é👩‍💻",
  string.char(0xE4, 0xB8),
  "a" .. string.char(0xFF) .. "中",
}) do
  local view = Cursor.new(value)
  local count = utf8.len(value)
  for index = 0, count do
    view:set_offset(math.min(#value, utf8.byteidx(value, index)))
    for n = 1, count + 1 do
      local span, after, last = view:get(n)
      if index + n <= count then
        assert(span == utf8.sub(value, index, n))
        assert(after == math.min(#value, utf8.byteidx(value, index + n)))
        assert(last == math.min(#value, utf8.byteidx(value, index + n - 1)))
      else
        local start = math.min(#value, utf8.byteidx(value, index))
        assert(span == value:sub(start + 1) and after == nil and last == nil)
      end
    end
  end
end
local before = decodes
local stream = Cursor.new("a中🙂")
assert(stream:get(1) == "a" and decodes == before + 1)
assert(vim.deep_equal({ stream:get() }, { "a中🙂" }))
assert(decodes == before + 1 and stream.offset == 0)
assert(stream:get(3) == "a中🙂" and decodes == before + 3)
assert(stream:shift() and stream.offset == 1)
assert(stream:get() == "中🙂" and decodes == before + 3)
assert(stream:shift() and stream.offset == 4)
assert(stream:get() == "🙂" and decodes == before + 3)
stream:set_offset(0)
assert(stream:get() == "a中🙂" and decodes == before + 3)
assert(stream:shift(3) and stream:get() == "" and stream:get(1) == "")
assert(not stream:shift() and stream.offset == 8)
print("ok - get defaults to all remaining Unicode; shift still defaults to one codepoint")

local suffixes = Cursor.new("a中🙂")
before = decodes
assert(suffixes:get() == "a中🙂" and decodes == before)
assert(suffixes:get() == "a中🙂" and decodes == before)
assert(suffixes:get(1) == "a" and decodes == before + 1)
assert(suffixes:shift() and decodes == before + 1)
assert(suffixes:get() == "中🙂" and decodes == before + 1)
assert(suffixes:get(2) == "中🙂" and decodes == before + 3)
assert(suffixes:get() == "中🙂" and decodes == before + 3)
print("ok - whole-suffix reads never decode Unicode; bounded reads remain lazy")
local short = Cursor.new("中🙂")
before = decodes
assert(vim.deep_equal({ short:get(9) }, { "中🙂" }))
assert(short.offset == 0 and decodes == before + 2)
assert(short:get(99) == "中🙂" and decodes == before + 2)
assert(not short:shift(3) and short.offset == 0)
assert(short:shift() and short:get(9) == "🙂")
assert(not short:shift(2) and short.offset == 3)
assert(short:shift() and short:get(9) == "" and not short:shift())
print("ok - short reads return the available suffix; shifts still require the full count")
print("all cursor tests passed")

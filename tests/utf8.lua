#!/usr/bin/env -S nvim -l
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path

vim.opt.runtimepath:prepend(vim.uv.cwd())
local utf8 = require("reference.utf8")

local function check(str)
	local index, offset = 0, 0
	for next_offset, char in utf8.iter_char(str) do
		assert(next_offset and char)
		assert(offset == utf8.byteidx(str, index))
		assert(char == utf8.sub(str, index, 1))
		assert(next_offset == offset + #char)
		index, offset = index + 1, next_offset
	end
	assert(index == utf8.len(str) and offset == #str)
end

for _, str in ipairs({
	"",
	"abc",
	"a\0中😀",
	"é👩‍💻",
	string.char(0xE4, 0xB8),
	string.char(0xF0, 0x9F, 0x98),
}) do
	check(str)
end
for first = 0, 255 do
	for second = 0, 255 do
		check(string.char(first, second))
	end
	check("a" .. string.char(first) .. string.rep(string.char(0x80), 5))
	check("a" .. string.char(first) .. "b中😀")
end
print("ok - iterator agrees with native boundaries for valid and malformed UTF-8")

local iter, state, offset = utf8.iter_char("a中😀")
local same_iter = utf8.iter_char("other")
assert(iter == same_iter and state == "a中😀" and offset == 0)
local next_offset, char = iter(state, offset)
assert(next_offset == 1 and char == "a")
assert(vim.deep_equal({ iter(state, offset) }, { 1, "a" }))
local resumed = {}
for next_col, value in utf8.iter_char(state, 1) do
	resumed[#resumed + 1] = { next_col, value }
end
assert(vim.deep_equal(resumed, { { 4, "中" }, { 8, "😀" } }))
local resumed_iter, resumed_state, resumed_offset = utf8.iter_char(state, 4)
assert(resumed_iter == iter and resumed_state == state and resumed_offset == 4)
assert(vim.deep_equal({ resumed_iter(resumed_state, resumed_offset) }, { 8, "😀" }))
local middle = {}
for next_col, value in utf8.iter_char(state, 2) do
	middle[#middle + 1] = { next_col, value }
end
assert(vim.deep_equal(middle, { { 3, string.char(0xB8) }, { 4, string.char(0xAD) }, { 8, "😀" } }))
assert(iter(state, #state) == nil)
print("ok - iterator is stateless and resumes from a byte offset")

print("all utf8 tests passed")

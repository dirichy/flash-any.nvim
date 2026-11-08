-- Maintainer only: regenerate after updating Unicode data.
local pages = dofile("scripts/data/grapheme_data.lua")
local offsets, ranges = {}, {}
for page = 0, 0x10FF do
	offsets[#offsets + 1] = tostring(#ranges)
	local values = pages[page] or {}
	assert(#values % 3 == 0)
	for i = 1, #values, 3 do
		ranges[#ranges + 1] = ("{%d,%d,%d},"):format(values[i], values[i + 1], values[i + 2])
	end
end
offsets[#offsets + 1] = tostring(#ranges)
assert(#ranges < 65536)
local lines = {
	"/* Generated from scripts/data/grapheme_data.lua; Unicode 17; licenses/Unicode-3.0.txt. */",
	"#include <stdint.h>",
	"static const uint16_t page_offsets[] = {" .. table.concat(offsets, ",") .. "};",
	"static const uint8_t ranges[][3] = {",
}
vim.list_extend(lines, ranges)
lines[#lines + 1] = "};"
assert(vim.fn.writefile(lines, "src/grapheme_data.h") == 0)

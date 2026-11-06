local M = {}

---@param str string
---@param offset integer 0-based byte offset
---@return integer? next_offset
local function next_offset(str, offset)
	local size = #str
	if offset >= size then
		return
	end
	local pos = offset + 1
	local b = str:byte(pos)
	-- Match Neovim's utf8len_tab, including legacy 5/6-byte sequences.
	local len = b < 0xC0 and 1
		or b < 0xE0 and 2
		or b < 0xF0 and 3
		or b < 0xF8 and 4
		or b < 0xFC and 5
		or b < 0xFE and 6
		or 1
	if len > 1 then
		for i = 1, math.min(len - 1, size - pos) do
			local byte = str:byte(pos + i)
			if byte < 0x80 or byte >= 0xC0 then
				len = 1
				break
			end
		end
	end
	return math.min(offset + len, size)
end

---@param str string
---@param offset integer 0-based byte offset
---@return integer? next_offset
---@return string? char
local function next_char(str, offset)
	local no = next_offset(str, offset)
	if no then
		return no, str:sub(offset + 1, no)
	end
end

---@param str string
---@param offset? integer Initial 0-based byte offset, defaults to 0
---@return fun(str: string, offset: integer): integer?, string? iter
---@return string state
---@return integer offset Initial 0-based byte offset
function M.iter_char(str, offset)
	return next_char, str, offset or 0
end

---@param str string
---@param offset? integer Initial 0-based byte offset, defaults to 0
---@return fun(str: string, offset: integer): integer? iter
---@return string state
---@return integer offset Initial 0-based byte offset
function M.iter_offset(str, offset)
	return next_offset, str, offset or 0
end

-- Native helpers for character counts/random access and iterator reference tests.
---@param str string
---@return number
function M.len(str)
	return vim.str_utfindex(str, "utf-32")
end

---@param str string
---@param index number 0-based character index
---@param count number
---@return string
function M.sub(str, index, count)
	local start_byte = vim.str_byteindex(str, "utf-32", index, false)
	local end_byte = vim.str_byteindex(str, "utf-32", index + count, false)
	return str:sub(start_byte + 1, end_byte)
end

---@param str string
---@param index number 0-based character index
---@return number 0-based byte index
function M.byteidx(str, index)
	return vim.str_byteindex(str, "utf-32", index, false)
end

return M

-- Frozen Lua reference for differential tests; never loaded by the plugin.
local M = {}
local tables = require("reference.table")
-- Code-table encodings are ASCII; buffer characters may be UTF-8.
-- Matching has three modes: full_code, initial and prefix.

---@param codes string[]
---@param input string
---@param emit ReferenceEmit
---@param mode "full_code"|"initial"|"prefix"
---@param chars integer
local function match_codes(codes, input, emit, mode, chars)
	local initial, prefix = false, 0
	local n = #input
	for _, code in ipairs(codes) do
		local length = #code
		local common = 0
		while common < math.min(n, length) and input:byte(common + 1) == code:byte(common + 1) do
			common = common + 1
		end
		if length > n and common == n then
			emit(code:sub(n + 1, n + 1), chars)
		end
		if length > 0 and common == length then
			if mode == "full_code" or (mode == "initial" and length > 1) then
				emit(length, chars)
			end
		end
		if mode == "initial" and common > 0 then
			initial = true
		elseif mode == "prefix" then
			prefix = math.max(prefix, common)
		end
	end
	if initial then
		emit(1, chars)
	end
	-- Prefix intervals all begin at 1; their union needs only the largest boundary.
	for bytes = 1, prefix do
		emit(bytes, chars)
	end
end

---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param source ReferenceSource
---@param emit ReferenceEmit
---@param mode "full_code"|"initial"|"prefix"
---@return boolean
local function match(text, stream, source, emit, mode)
	local data = source.data
	if not data then
		return false
	end
	local input = stream:get()
	local maximum = source.max_chars or tables.metadata(data).max_chars
	if maximum == 1 then
		local codes = data[text:get(1)]
		if type(codes) ~= "table" then
			return false
		end
		match_codes(codes, input, emit, mode, 1)
		return true
	end
	local known, offset = false, nil
	local chars = 1
	while chars <= maximum do
		local key, after = text:get(chars)
		if not after then
			break
		end
		local codes
		codes, offset = tables.lookup(data, key, offset)
		if codes then
			known = true
			match_codes(codes, input, emit, mode, chars)
		end
		if offset == false then
			break
		end
		chars = chars + 1
	end
	return known
end

---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param source ReferenceSource
---@param emit ReferenceEmit
---@return boolean
function M.full_code(text, stream, source, emit)
	return match(text, stream, source, emit, "full_code")
end

---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param source ReferenceSource
---@param emit ReferenceEmit
---@return boolean
function M.initial(text, stream, source, emit)
	return match(text, stream, source, emit, "initial")
end

---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param source ReferenceSource
---@param emit ReferenceEmit
---@return boolean
function M.prefix(text, stream, source, emit)
	return match(text, stream, source, emit, "prefix")
end

return M

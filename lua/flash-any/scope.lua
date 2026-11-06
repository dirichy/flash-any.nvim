local M = {}
local grapheme = require("flash-any.grapheme")

---@alias FlashAnyScopeBound integer|string
---@alias FlashAnyScopeTable table<integer|string, any> Numeric keys contain ranges; grapheme keys use Lua truthiness.
---@alias FlashAnyScope "all"|"ascii"|"chinese"|"unicode"|"private_use"|FlashAnyScopeTable

---Normalize bounds once; ranges compare complete graphemes in UTF-8 byte order.
---@param value FlashAnyScopeBound
---@return string
local function bound(value)
	if type(value) == "number" then
		assert(value >= 0 and value <= 0x10FFFF and value % 1 == 0, "scope codepoints must be integers in 0..0x10FFFF")
		return value == 0 and "\0" or vim.fn.nr2char(value)
	end
	assert(type(value) == "string" and value ~= "", "scope bounds must be single graphemes or numeric codepoints")
	assert(grapheme.len(value) == 1, "scope bounds and character keys must contain one grapheme")
	return value
end

local declarations

---@param spec? FlashAnyScope
---@return {chars: table<string, boolean>, ranges: string[][]}?
function M.describe(spec)
	if spec == nil or spec == "all" then
		return
	end
	if type(spec) == "string" then
		spec = assert(declarations[spec], "unknown source scope: " .. spec)
	end
	assert(type(spec) == "table", "binary scope must be a declaration, not a Lua callback")
	---@type table<string, boolean>
	local chars = {}
	---@type string[][]
	local ranges = {}
	for key, value in pairs(spec) do
		if type(key) == "number" then
			assert(key >= 1 and key % 1 == 0, "scope range keys must be positive integers")
			assert(type(value) == "table" and vim.islist(value) and #value == 2, "scope ranges require two bounds")
			local first, last = bound(value[1]), bound(value[2])
			assert(first <= last, "scope range start must not exceed its end")
			ranges[#ranges + 1] = { first, last }
		else
			assert(type(key) == "string", "scope character keys must be strings")
			chars[bound(key)] = not not value
		end
	end
	return { chars = chars, ranges = ranges }
end

local chinese = {
	{ 0x3400, 0x4DBF },
	{ 0x4E00, 0x9FFF },
	{ 0x20000, 0x323AF },
}
for char in pairs(require("flash-any.tables.punctuation")) do
	chinese[char] = true
end

declarations = {
	ascii = { { 0, 0x7F } },
	chinese = chinese,
	unicode = { { 0xA0, 0x10FFFF } },
	private_use = { { 0xE000, 0xF8FF }, { 0xF0000, 0xFFFFD }, { 0x100000, 0x10FFFD } },
}
---@param scope {chars: table<string, boolean>, ranges: string[][]}?
---@param key string Complete grapheme.
---@return boolean
function M.contains(scope, key)
	if key == "" then
		return false
	end
	if not scope then
		return true
	end
	if scope.chars[key] ~= nil then
		return scope.chars[key]
	end
	for _, range in ipairs(scope.ranges) do
		if range[1] <= key and key <= range[2] then
			return true
		end
	end
	return false
end

return M

-- Frozen Lua reference for differential tests; never loaded by the plugin.
local M = {}
local grapheme = require("reference.grapheme")

---@alias ReferenceScopeFn fun(text: ReferenceCursor): boolean
---@alias ReferenceScopeBound integer|string
---@alias ReferenceScopeTable table<integer|string, any> Numeric keys contain ranges; grapheme keys use Lua truthiness.
---@alias ReferenceScope "all"|"ascii"|"chinese"|"unicode"|"private_use"|ReferenceScopeTable|ReferenceScopeFn

---Normalize bounds once; ranges compare complete graphemes in UTF-8 byte order.
---@param value ReferenceScopeBound
---@return string
local function bound(value)
	if type(value) == "number" then
		assert(value >= 0 and value <= 0x10FFFF and value % 1 == 0, "scope codepoints must be integers in 0..0x10FFFF")
		return vim.fn.nr2char(value)
	end
	assert(type(value) == "string" and value ~= "", "scope bounds must be single graphemes or numeric codepoints")
	assert(grapheme.len(value) == 1, "scope bounds and character keys must contain one grapheme")
	return value
end

local declarations

---@param spec? ReferenceScope
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

---@param spec ReferenceScopeTable
---@return ReferenceScopeFn
local function compile(spec)
	local data = assert(M.describe(spec))
	local chars, ranges = data.chars, data.ranges
	return function(text)
		local char = text:get(1)
		if char == "" then
			return false
		end
		local listed = chars[char]
		if listed ~= nil then
			return listed
		end
		for _, range in ipairs(ranges) do
			if range[1] <= char and char <= range[2] then
				return true
			end
		end
		return false
	end
end

---@type ReferenceScopeTable
local chinese = {
	{ 0x3400, 0x4DBF },
	{ 0x4E00, 0x9FFF },
	{ 0x20000, 0x323AF },
}
-- Character coverage is independent of input-method key mappings.
for _, char in
	ipairs(
		vim.fn.split("，。、；：？！“”‘’（）【】《》〈〉「」『』〔〕…—·￥", "\\zs")
	)
do
	chinese[char] = true
end

declarations = {
	ascii = { { 0, 0x7F } },
	chinese = chinese,
	unicode = { { 0xA0, 0x10FFFF } },
	private_use = { { 0xE000, 0xF8FF }, { 0xF0000, 0xFFFFD }, { 0x100000, 0x10FFFD } },
}
---@type table<string, ReferenceScopeFn>
local strategies = {}
for name, spec in pairs(declarations) do
	strategies[name] = compile(spec)
end

---Compile declarations before matching; nil/all leaves the source unrestricted.
---@param spec? ReferenceScope
---@return ReferenceScopeFn?
function M.resolve(spec)
	if spec == nil or spec == "all" then
		return nil
	end
	if type(spec) == "string" then
		return assert(strategies[spec], "unknown source scope: " .. spec)
	end
	if type(spec) == "function" then
		return spec
	end
	assert(type(spec) == "table", "scope must be a strategy name, table or function")
	return compile(spec)
end

return M

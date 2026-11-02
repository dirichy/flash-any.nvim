local M = {}
local utf8 = require("flash-any.utf8")

-- 码表统一为 UTF-8 字符 → ASCII 编码数组；同一字符可有多个编码。
---@alias FlashAnyTable table<string, string[]>

---在 data 原表上添加按字符懒加载；查询结果和未命中（false）都缓存在原表。
---@param data FlashAnyTable
---@param loader fun(char: string): string[]?
---@return FlashAnyTable
function M.lazy(data, loader)
	return setmetatable(data, {
		__index = function(self, char)
			local value = loader(char)
			rawset(self, char, value or false)
			return value
		end,
	})
end

---为短于 below 的编码追加一个空格；返回新数组。
---@param codes string[]?
---@param below integer
---@return string[]?
local function space_codes(codes, below)
	if not codes then
		return nil
	end
	local ret = {}
	for _, code in ipairs(codes) do
		ret[#ret + 1] = #code < below and code .. " " or code
	end
	return ret
end

---短码补空格；未指定阈值时返回原表，否则创建独立码表并保留懒加载。
---@param data FlashAnyTable
---@param below? integer
---@return FlashAnyTable
function M.append_space(data, below)
	if below == nil then
		return data
	end
	-- data may be a shared default cache; keep transformed arrays separate.
	assert(type(below) == "number" and below > 0 and below % 1 == 0,
		"append_space_below must be a positive integer")
	local ret = {}
	for char, codes in pairs(data) do
		ret[char] = space_codes(codes, below)
	end
	return M.lazy(ret, function(char)
		return space_codes(data[char], below)
	end)
end

---把单编码字符串转为数组，并复制 map 和数组，避免修改调用方或 require 缓存。
---@param map table<string, string|string[]>
---@return FlashAnyTable
function M.normalize(map)
	local ret = {}
	for char, codes in pairs(map) do
		assert(type(char) == "string", "code-table keys must be UTF-8 characters")
		local iter, str, offset = utf8.iter_offset(char)
		assert(iter(str, offset) == #char, "code-table key must be one character: " .. char)
		if type(codes) == "string" then
			ret[char] = { codes }
		else
			assert(type(codes) == "table" and vim.islist(codes), "codes must be a string or array: " .. char)
			ret[char] = vim.deepcopy(codes)
		end
		for _, code in ipairs(ret[char]) do
			assert(type(code) == "string" and #code > 0 and not code:find("[\128-\255]"),
				"codes must be nonempty ASCII strings: " .. char)
		end
	end
	return ret
end

---拆分 TSV 值列中用逗号分隔的 ASCII 编码；这里不处理 CSV 引号语法。
---@param value string
---@return string[]
local function csv(value)
	local ret = {}
	for item in value:gmatch("[^,]+") do
		ret[#ret + 1] = item
	end
	return ret
end

---@class FlashAnyTableOptions
---@field convert? fun(codes: string[]?): string[]?
---@field extra? table<string, string|string[]> Added after conversion; overrides common entries.

---从 runtimepath 加载常用字 Lua 表和可选的完整 TSV；每次创建私有缓存。
---@param name string 码表文件名，不含扩展名
---@param opts? FlashAnyTableOptions
---@return FlashAnyTable
function M.load(name, opts)
	local convert = opts and opts.convert
	local common = M.normalize(require("flash-any.tables." .. name))
	if convert then
		for char, codes in pairs(common) do
			common[char] = convert(codes)
		end
	end
	if opts and opts.extra then
		for char, codes in pairs(M.normalize(opts.extra)) do
			common[char] = codes
		end
	end
	local files = vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".tsv", false)
	if not files[1] then return common end
	local decode = csv
	if convert then
		decode = function(value)
			return convert(csv(value)) or {}
		end
	end
	return M.lazy(common, require("flash-any.tsv").loader(files[1], { decode = decode }))
end

---加载用户指定的 Lua 码表，复制后按需挂接 TSV；不复用内置方案缓存。
---@param lua_path string
---@param tsv_path string?
---@return FlashAnyTable
function M.from_files(lua_path, tsv_path)
	local common = M.normalize(dofile(vim.fn.expand(lua_path)))
	if not tsv_path then
		return common
	end
	local lookup = require("flash-any.tsv").loader(tsv_path, { decode = csv })
	return M.lazy(common, lookup)
end

return M

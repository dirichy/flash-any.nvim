local M = {}
local utf8 = require("flash-any.utf8")

-- Nonempty UTF-8 text -> ASCII encodings. Prefix metadata belongs to the map.
---@alias FlashAnyTable table<string, string[]>
---@alias FlashAnyTableMap table<string, string|string[]>
---@class FlashAnyMultiTable
---@field codes FlashAnyTableMap
---@field prefixes table<string, true> Proper prefixes, including those with codes.
---@field max_chars? integer Maximum text codepoints in the full table, including TSV.
---@alias FlashAnyTableInput FlashAnyTableMap|FlashAnyMultiTable
---@alias FlashAnyTableLoader fun(key: string, offset?: number, prefix_lookup?: boolean): string[]?, (number|boolean)?
-- Continuations share the map's lifetime: true for Lua prefixes, numeric TSV
-- positions, or false for cached terminal TSV queries.
---@type table<FlashAnyTable, table<string, number|boolean>>
local offsets = setmetatable({}, { __mode = "k" })
---@type table<FlashAnyTable, FlashAnyTableLoader>
local loaders = setmetatable({}, { __mode = "k" })
---@type table<FlashAnyTable, integer>
local limits = setmetatable({}, { __mode = "k" })

---Read table metadata; compact single-codepoint maps default to one.
---@param data FlashAnyTable
---@return integer
function M.max_chars(data)
	return limits[data] or 1
end

---Read codes and whether longer text keys exist. An earlier prefix supplies the TSV offset.
---@param data FlashAnyTable
---@param key string
---@param offset? number|boolean Continuation from an earlier prefix; only numeric file offsets are passed to loaders.
---@return string[]? codes
---@return number|boolean offset File position, true for a plain Lua map, or false to prune.
function M.lookup(data, key, offset)
	local loader = loaders[data]
	local cache = offsets[data]
	if not cache then
		cache = {}
		offsets[data] = cache
	end
	if loader and cache[key] == nil then
		local codes, after = loader(key, type(offset) == "number" and offset or nil, true)
		if rawget(data, key) == nil then
			rawset(data, key, codes or false)
		end
		cache[key] = after or false
	end
	return data[key] or nil, cache and cache[key] or false
end

---Cache exact hits/misses and prefix continuation metadata in the owning map.
---@param data FlashAnyTable
---@param loader FlashAnyTableLoader
---@return FlashAnyTable
function M.lazy(data, loader)
	loaders[data] = loader
	offsets[data] = nil
	return setmetatable(data, {
		__index = function(self, key)
			if offsets[self] then
				return (M.lookup(self, key))
			end
			local codes = loader(key)
			rawset(self, key, codes or false)
			return codes
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
	assert(type(below) == "number" and below > 0 and below % 1 == 0, "append_space_below must be a positive integer")
	local ret = {}
	limits[ret] = limits[data]
	for char, codes in pairs(data) do
		ret[char] = space_codes(codes, below)
	end
	if not loaders[data] then
		if offsets[data] then
			offsets[ret] = vim.deepcopy(offsets[data])
		end
		return ret
	end
	return M.lazy(ret, function(char, offset, prefix_lookup)
		if not prefix_lookup then
			return space_codes(data[char], below)
		end
		local codes, after = M.lookup(data, char, offset)
		return space_codes(codes, below), after
	end)
end

---把单编码字符串转为数组，并复制 map 和数组，避免修改调用方或 require 缓存。
---@param map FlashAnyTableInput
---@return FlashAnyTable
function M.normalize(map)
	local prefixes, maximum
	local values = map
	if type(map.codes) == "table" and type(map.prefixes) == "table" then
		---@cast map FlashAnyMultiTable
		maximum, prefixes, values = map.max_chars, map.prefixes, map.codes
	elseif not loaders[map] then
		prefixes, maximum = offsets[map], limits[map]
	end
	---@cast values FlashAnyTableMap
	assert(
		maximum == nil or (type(maximum) == "number" and maximum >= 1 and maximum % 1 == 0),
		"max_chars must be a positive integer"
	)
	local length = 1
	local ret = {}
	for char, codes in pairs(values) do
		assert(type(char) == "string" and char ~= "", "code-table keys must be nonempty strings")
		if prefixes then
			length = math.max(length, utf8.len(char))
		end
		if type(codes) == "string" then
			ret[char] = { codes }
		else
			assert(type(codes) == "table" and vim.islist(codes), "codes must be a string or array: " .. char)
			ret[char] = vim.deepcopy(codes)
		end
		for _, code in ipairs(ret[char]) do
			assert(
				type(code) == "string" and #code > 0 and not code:find("[\128-\255]"),
				"codes must be nonempty ASCII strings: " .. char
			)
		end
	end
	if prefixes then
		local cache = {}
		for key, longer in pairs(prefixes) do
			assert(
				type(key) == "string" and key ~= "" and longer == true,
				"prefixes must map nonempty text keys to true"
			)
			cache[key] = true
			length = math.max(length, utf8.len(key) + 1)
		end
		offsets[ret] = cache
		assert(maximum == nil or maximum >= length, "max_chars is shorter than the Lua entries or prefixes")
		limits[ret] = maximum or length
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
---@field extra? FlashAnyTableMap Added after conversion; overrides common entries.

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
	if not files[1] then
		return common
	end
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

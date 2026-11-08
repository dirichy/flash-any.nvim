local M = {}
local grapheme = require("flash-any.grapheme")

-- Nonempty UTF-8 text -> ASCII encodings. Prefix metadata belongs to the map.
---@alias FlashAnyTable table<string, string[]>
---@alias FlashAnyTableMap table<string, string|string[]>
---@class FlashAnyTableDefinition
---@field codes FlashAnyTableMap
---@field prefixes? table<string, true> Proper prefixes, including those with codes.
---@field max_chars? integer Maximum text graphemes in the full table, including TSV.
---@field scope? FlashAnyScopeTable Coarse first-grapheme filter, covering the complete input.
---@alias FlashAnyTableInput FlashAnyTableMap|FlashAnyTableDefinition
---@alias FlashAnyTableLoader fun(key: string, offset?: number, prefix_lookup?: boolean): string[]?, (number|boolean)?
-- Continuations share the map's lifetime: true for Lua prefixes, numeric TSV
-- positions, or false for cached terminal TSV queries.
---@type table<FlashAnyTable, table<string, number|boolean>>
local offsets = setmetatable({}, { __mode = "k" })
---@type table<FlashAnyTable, FlashAnyTableLoader>
local loaders = setmetatable({}, { __mode = "k" })
---@class FlashAnyTableMetadata
---@field max_chars integer
---@field scope? FlashAnyScopeTable
---@type table<FlashAnyTable, FlashAnyTableMetadata>
local metadata = setmetatable({}, { __mode = "k" })
-- Complete-file readers are owned alongside lazy caches; only build.binary uses them.
---@type table<FlashAnyTable, fun(): FlashAnyTable>
local readers = setmetatable({}, { __mode = "k" })
local defaults = { max_chars = 1 }

---Read metadata owned by this map; callers treat it as immutable.
---@param data FlashAnyTable
---@return FlashAnyTableMetadata
function M.metadata(data)
	return metadata[data] or defaults
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
	offsets[data], readers[data] = nil, nil
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
---@param groups? table<string, string[]>
---@return string[]?
local function space_codes(codes, below, groups)
	if not codes then
		return nil
	end
	local ret = {}
	for _, code in ipairs(codes) do
		ret[#ret + 1] = not (groups and groups[code]) and #code < below and code .. " " or code
	end
	return ret
end

---短码补空格；未指定阈值时返回原表，否则创建独立码表并保留懒加载。
---@param data FlashAnyTable
---@param below? integer
---@param groups? table<string, string[]>
---@return FlashAnyTable
---@return table<string, string[]>?
function M.append_space(data, below, groups)
	if below == nil then
		return data, groups
	end
	-- data may be a shared default cache; keep transformed arrays separate.
	assert(type(below) == "number" and below > 0 and below % 1 == 0, "append_space_below must be a positive integer")
	local padded_groups
	if groups then
		padded_groups = {}
		for name, spellings in pairs(groups) do
			padded_groups[name] = space_codes(spellings, below)
		end
	end
	local ret = {}
	if metadata[data] then
		metadata[ret] = vim.deepcopy(metadata[data])
	end
	for char, codes in pairs(data) do
		ret[char] = space_codes(codes, below, groups)
	end
	local read = readers[data]
	if not loaders[data] then
		if offsets[data] then
			offsets[ret] = vim.deepcopy(offsets[data])
		end
		return ret, padded_groups
	end
	M.lazy(ret, function(char, offset, prefix_lookup)
		if not prefix_lookup then
			return space_codes(data[char], below, groups)
		end
		local codes, after = M.lookup(data, char, offset)
		return space_codes(codes, below, groups), after
	end)
	if read then
		readers[ret] = function()
			local values = read()
			for key, codes in pairs(values) do
				values[key] = space_codes(codes, below, groups)
			end
			return values
		end
	end
	return ret, padded_groups
end

---把单编码字符串转为数组，并复制 map 和数组，避免修改调用方或 require 缓存。
---@param map FlashAnyTableInput
---@return FlashAnyTable
function M.normalize(map)
	local prefixes, maximum, scope
	local values = map
	local structured = type(map.codes) == "table"
	if structured then
		---@cast map FlashAnyTableDefinition
		maximum, prefixes, scope, values = map.max_chars, map.prefixes, map.scope, map.codes
		assert(prefixes == nil or type(prefixes) == "table", "prefixes must be a table")
		assert(scope == nil or type(scope) == "table", "table scope must be a character/range table")
	else
		local properties = metadata[map]
		if properties then
			maximum, scope = properties.max_chars, properties.scope
		end
		if not loaders[map] then
			prefixes = offsets[map]
		end
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
		if structured or prefixes then
			length = math.max(length, grapheme.len(char))
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
			length = math.max(length, grapheme.len(key) + 1)
		end
		offsets[ret] = cache
	end
	assert(maximum == nil or maximum >= length, "max_chars is shorter than the Lua entries or prefixes")
	metadata[ret] = { max_chars = maximum or length, scope = scope and vim.deepcopy(scope) or nil }
	return ret
end

---Read a dictionary through the build parser and retain single-grapheme entries.
---@param path string
---@param opts? FlashAnySourceConfig
---@return FlashAnyTable
---@return table<string, table<string, {weight: number, order: number}>>? ranks
function M.from_file(path, opts)
	opts = opts or {}
	local convert
	if opts.converter then
		assert(type(opts.converter) == "string", "converter must be a Lua file path")
		convert = dofile(vim.fn.expand(opts.converter))
		assert(type(convert) == "function", "converter file must return a function")
	end
	local rows, ranks = require("flash-any.build").read(path, opts)
	local skipped = 0
	for char, codes in pairs(rows) do
		if grapheme.len(char) ~= 1 then
			rows[char], skipped = nil, skipped + 1
		elseif convert then
			local converted = convert(codes)
			assert(
				converted == nil or (type(converted) == "table" and vim.islist(converted)),
				"converter must return a code array or nil"
			)
			rows[char] = converted and #converted > 0 and converted or nil
		end
	end
	if skipped > 0 then
		vim.notify(("flash-any: skipped %d multi-grapheme dictionary entries"):format(skipped), vim.log.levels.INFO)
	end
	return M.normalize(rows), ranks
end

---@class FlashAnyTableOptions
---@field convert? fun(codes: string[]?): string[]?
---@field extra? FlashAnyTableMap Added after conversion; overrides existing entries.

---加载命名码表：完整 TSV，或 Lua 表及其可选 TSV 伴随文件。
---@param name string 码表文件名，不含扩展名
---@param opts? FlashAnyTableOptions
---@return FlashAnyTable
function M.load(name, opts)
	local convert = opts and opts.convert
	local lua_files = vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".lua", false)
	local files = vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".tsv", false)
	assert(lua_files[1] or files[1], "code table not found: " .. name)
	local data = lua_files[1] and M.normalize(require("flash-any.tables." .. name))
		or M.from_file(assert(files[1]), { format = "tsv" })
	if convert then
		for char, codes in pairs(data) do
			data[char] = convert(codes) or (not lua_files[1] and {} or nil)
		end
	end
	if opts and opts.extra then
		for char, codes in pairs(M.normalize(opts.extra)) do
			data[char] = codes
			local scope = metadata[data].scope
			if scope then
				local first
				grapheme.each(char, function(_, after)
					if not first then
						first = char:sub(1, after)
					end
				end)
				scope[assert(first)] = true
			end
		end
	end
	if not files[1] or not lua_files[1] then
		return data
	end
	local decode = function(value)
		return { value }
	end
	if convert then
		decode = function(value)
			return convert({ value }) or {}
		end
	end
	local path = files[1]
	M.lazy(data, require("flash-any.tsv").loader(path, { decode = decode }))
	readers[data] = function()
		return require("flash-any.tsv").read(path, decode)
	end
	return data
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
	local lookup = require("flash-any.tsv").loader(tsv_path, {
		decode = function(value)
			return { value }
		end,
	})
	M.lazy(common, lookup)
	readers[common] = function()
		return require("flash-any.tsv").read(tsv_path, function(value)
			return { value }
		end)
	end
	return common
end

---Snapshot complete known table data for binary compilation, preserving Lua overrides.
---@param data FlashAnyTable
---@return FlashAnyTable
function M.materialize(data)
	assert(not loaders[data] or readers[data], "binary build cannot enumerate a custom Lua loader")
	local ret = readers[data] and readers[data]() or {}
	for key, codes in pairs(data) do
		ret[key] = codes and vim.deepcopy(codes) or nil
	end
	return ret
end

return M

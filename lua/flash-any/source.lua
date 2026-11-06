local M = {}
local tables = require("flash-any.table")

---@class FlashAnySourceDefinition
---@field codetable? string Table name under flash-any.tables; mutually exclusive with data.
---@field data? FlashAnyTable Prepared data; may have a lazy __index.
---@field matcher? "full_code"|"initial"|"prefix"
---@field scope? FlashAnyScope
---@field fallback? boolean

-- Only default instances are shared; configured instances own their data and caches.
---@type table<string, FlashAnySourceDefinition>
local cache = {}

---Load a source factory from runtimepath; options are passed through to the factory.
---@param name string
---@param opts? table
---@return FlashAnySourceDefinition
function M.load(name, opts)
	if not opts and cache[name] then
		return cache[name]
	end
	local factory = require("flash-any.sources." .. name)
	assert(type(factory) == "function", "source module must return a factory: " .. name)
	local source = factory(opts or {})
	assert(type(source) == "table", "source factory must return a table: " .. name)
	if source.codetable ~= nil then
		assert(type(source.codetable) == "string", "codetable must be a table name: " .. name)
		assert(source.data == nil, "codetable and data are mutually exclusive: " .. name)
		source.data = tables.load(source.codetable)
		source.codetable = nil
	end
	assert(
		source.matcher == nil
			or source.matcher == "full_code"
			or source.matcher == "initial"
			or source.matcher == "prefix",
		"Lua matcher functions are not supported"
	)
	if source.data then
		source.data = tables.append_space(source.data, opts and opts.append_space_below)
	end
	if not opts then
		cache[name] = source
	end
	return source
end

---Discover names without requiring factories or loading their tables.
---@return string[]
function M.available()
	local names = {}
	for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/flash-any/sources/*.lua", true)) do
		names[#names + 1] = vim.fn.fnamemodify(path, ":t:r")
	end
	table.sort(names)
	return names
end

-- Source declarations are resolved only during binary compilation.
---@class FlashAnySourceConfig
---@field name? string
---@field matcher? "full_code"|"initial"|"prefix"
---@field scheme? string
---@field fuzzy? boolean|table
---@field scope? FlashAnyScope
---@field fallback? boolean
---@field data? FlashAnyTableInput
---@field lua? string
---@field tsv? string
---@field append_space_below? integer

---@alias FlashAnySourceSpec string|FlashAnySourceConfig|FlashAnyTableInput

---@param matcher? string
---@return string
local function source_mode(matcher)
	if matcher == nil then
		matcher = "full_code"
	end
	assert(
		matcher == "full_code" or matcher == "initial" or matcher == "prefix",
		"matcher must be full_code, initial or prefix; Lua matcher functions are not supported"
	)
	return matcher
end

---@class FlashAnySource
---@field data? FlashAnyTable
---@field mode string
---@field scope_spec? FlashAnyScope
---@field fallback? boolean
---@field name? string

---@param values FlashAnySourceSpec[]
---@return FlashAnySource[]
function M.resolve(values)
	assert(type(values) == "table" and vim.islist(values), "opts.sources is required and must be a list")
	local ret, has_pinyin = { { name = "literal", mode = "literal" } }, false
	for _, value in ipairs(values) do
		assert(type(value) == "string" or type(value) == "table", "source must be a name or configuration table")
		local name = type(value) == "string" and value or value.name
		if name == "pinyin" then
			assert(not has_pinyin, "configure only one pinyin source; select its encoding with scheme")
			has_pinyin = true
		end
		local named_only = type(value) == "string"
		if named_only then
			value = { name = value }
		end
		if not value.name and type(value.codes) == "table" then
			value = { data = value }
		end
		if value.name or value.matcher or value.scope ~= nil or value.data or value.lua or value.loader then
			---@cast value FlashAnySourceConfig
			assert(value.fallback == nil or type(value.fallback) == "boolean", "fallback must be a boolean")
			assert(rawget(value, "loader") == nil, "custom loaders are not supported; provide a complete code table")
			local defaults = value.name and M.load(value.name, not named_only and value or nil) or {}
			local data = defaults.data
			if value.lua then
				data = tables.append_space(tables.from_files(value.lua, value.tsv), value.append_space_below)
			elseif value.data then
				data = tables.append_space(tables.normalize(value.data), value.append_space_below)
			end
			local matcher = value.matcher
			if matcher == nil then
				matcher = defaults.matcher
			end
			local metadata = data and tables.metadata(data)
			local scope = value.scope
			if scope == nil then
				scope = defaults.scope
			end
			if scope == nil and metadata then
				scope = metadata.scope
			end
			local fallback = value.fallback
			if fallback == nil then
				fallback = defaults.fallback
			end
			assert(fallback == nil or type(fallback) == "boolean", "fallback must be a boolean")
			local mode = source_mode(matcher)
			ret[#ret + 1] = {
				data = data,
				mode = mode,
				scope_spec = scope,
				name = value.name,
				fallback = fallback,
			}
		else
			---@cast value FlashAnyTableInput
			local data = tables.normalize(value)
			local metadata = tables.metadata(data)
			ret[#ret + 1] = { data = data, mode = "full_code", scope_spec = metadata.scope }
		end
	end
	return ret
end

return M

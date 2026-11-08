-- Frozen Lua reference for differential tests; never loaded by the plugin.
local M = {}
local tables = require("reference.table")
local codetable = require("reference.codetable")
local scopes = require("reference.scope")

---@class ReferenceSourceDefinition
---@field codetable? string Table name under flash-any.tables; mutually exclusive with data.
---@field data? ReferenceTable Prepared data; may have a lazy __index.
---@field matcher? "full_code"|"initial"|"prefix"|ReferenceMatcher
---@field scope? ReferenceScope
---@field fallback? boolean

-- Only default instances are shared; configured instances own their data and caches.
---@type table<string, ReferenceSourceDefinition>
local cache = {}

---Load a source factory from runtimepath; options are passed through to the factory.
---@param name string
---@param opts? table
---@return ReferenceSourceDefinition
function M.load(name, opts)
	if not opts and cache[name] then
		return cache[name]
	end
	local factory = (name == "literal" or name == "pinyin") and require("reference." .. name)
		or require("flash-any.sources." .. name)
	assert(type(factory) == "function", "source module must return a factory: " .. name)
	---@type ReferenceSourceDefinition
	local source = factory(opts or {})
	assert(type(source) == "table", "source factory must return a table: " .. name)
	if source.codetable ~= nil then
		assert(type(source.codetable) == "string", "codetable must be a table name: " .. name)
		assert(source.data == nil, "codetable and data are mutually exclusive: " .. name)
		source.data = tables.load(source.codetable)
		source.codetable = nil
	end
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

-- Source declarations are resolved once for runtime Lua or binary compilation.
---@class ReferenceSourceConfig
---@field name? string
---@field matcher? "full_code"|"initial"|"prefix"|ReferenceMatcher
---@field scheme? string
---@field fuzzy? boolean|table
---@field scope? ReferenceScope
---@field fallback? boolean
---@field data? ReferenceTableInput
---@field lua? string
---@field tsv? string
---@field loader? ReferenceTableLoader
---@field append_space_below? integer

---@alias ReferenceSourceSpec string|ReferenceSourceConfig|ReferenceTableInput

---@param matcher? string|ReferenceMatcher
---@return ReferenceMatcher
---@return string? mode
local function source_matcher(matcher)
	if type(matcher) == "function" then
		for mode, fn in pairs(codetable) do
			if fn == matcher then
				return matcher, mode
			end
		end
		return matcher
	end
	if matcher == nil then
		matcher = "full_code"
	end
	assert(type(matcher) == "string", "matcher must be a mode name or function")
	return assert(codetable[matcher], "invalid code-table matcher: " .. matcher), matcher
end

---@param values ReferenceSourceSpec[]
---@return ReferenceSource[]
function M.resolve(values)
	assert(type(values) == "table" and vim.islist(values), "opts.sources is required and must be a list")
	local literal = M.load("literal")
	local ret, has_pinyin =
		{ {
			name = "literal",
			matcher = source_matcher(literal.matcher),
			scope = scopes.resolve(literal.scope),
			mode = "literal",
			scope_spec = literal.scope,
		} }, false
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
			---@cast value ReferenceSourceConfig
			assert(value.fallback == nil or type(value.fallback) == "boolean", "fallback must be a boolean")
			assert(value.loader == nil or type(value.loader) == "function", "loader must be a function")
			local defaults = value.name and M.load(value.name, not named_only and value or nil) or {}
			local data = defaults.data
			if value.lua then
				data = tables.append_space(tables.from_files(value.lua, value.tsv), value.append_space_below)
			elseif value.data then
				data = tables.append_space(tables.normalize(value.data), value.append_space_below)
			end
			if value.loader then
				data = tables.lazy(data or {}, value.loader)
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
			local fn, mode = source_matcher(matcher)
			if matcher == literal.matcher then
				mode = "literal"
			end
			ret[#ret + 1] = {
				data = data,
				matcher = fn,
				mode = mode,
				scope_spec = scope,
				max_chars = metadata and metadata.max_chars or 1,
				scope = scopes.resolve(scope),
				name = value.name,
				fallback = fallback,
			}
		else
			---@cast value ReferenceTableInput
			local data = tables.normalize(value)
			local metadata = tables.metadata(data)
			ret[#ret + 1] = {
				data = data,
				matcher = codetable.full_code,
				mode = "full_code",
				scope_spec = metadata.scope,
				max_chars = metadata.max_chars,
				scope = scopes.resolve(metadata.scope),
			}
		end
	end
	return ret
end

return M

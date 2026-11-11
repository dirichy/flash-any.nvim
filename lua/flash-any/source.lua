local M = {}
local tables = require("flash-any.table")

---@class FlashAnySourceDefinition
---@field codetable? string Table name under flash-any.tables; mutually exclusive with data.
---@field data? FlashAnyTable Prepared data; may have a lazy __index.
---@field file? string Weighted dictionary path; mutually exclusive with codetable/data.
---@field format? string
---@field columns? string[]
---@field encoding? string
---@field selection? FlashAnySelection|false
---@field matcher? "full_code"|"initial"|"prefix"|"letter"
---@field fallback? boolean
---@field prepared? boolean Factory owns data overrides and padding.
---@field groups? table<string, string[]> Shared spelling alternatives keyed by code.

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
	local module = "flash-any.sources." .. name
	assert(
		#vim.api.nvim_get_runtime_file("lua/flash-any/sources/" .. name .. ".lua", false) > 0 or package.preload[module],
		"source '" .. name .. "' is not installed; load its source plugin before setup"
	)
	local factory = require(module)
	assert(type(factory) == "function", "source module must return a factory: " .. name)
	local source = factory(opts or {})
	assert(type(source) == "table", "source factory must return a table: " .. name)
	assert(
		not source.file or (type(source.file) == "string" and not source.data and not source.codetable),
		"file must be a path and cannot be combined with codetable or data: " .. name
	)
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
			or source.matcher == "prefix"
			or source.matcher == "letter",
		"Lua matcher functions are not supported"
	)
	if opts and opts.groups ~= nil then
		source.groups = opts.groups
	end
	assert(source.groups == nil or type(source.groups) == "table", "groups must map codes to spelling lists")
	if source.data and not source.prepared then
		source.data, source.groups = tables.append_space(source.data, opts and opts.append_space_below, source.groups)
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

---@class FlashAnySelection
---@field keys? string[] Ranked suffixes; required for direct files, factories may supply defaults.

-- Source declarations are resolved only during binary compilation.
---@class FlashAnySourceConfig
---@field [string] any Source-defined build options are validated by its factory.
---@field name? string
---@field matcher? "full_code"|"initial"|"prefix"|"letter"
---@field fallback? boolean
---@field data? FlashAnyTableInput
---@field lua? string
---@field tsv? string Complete TSV companion for lua.
---@field file? string External dictionary path.
---@field format? "auto"|"tsv"|"tab"|"space"|"csv"|"rime"|"fcitx"|"ibus"
---@field columns? string[] Column labels including text and code.
---@field encoding? string
---@field header? boolean Skip the first CSV record.
---@field converter? string Lua file returning fun(codes: string[]): string[]?; external file only.
---@field selection? FlashAnySelection|false Optional suffixes ranked by file weights.
---@field groups? table<string, string[]> Shared spelling alternatives keyed by code.
---@field append_space_below? integer

---@alias FlashAnySourceSpec string|FlashAnySourceConfig|FlashAnyTableInput

---@param matcher? string
---@return string
local function source_mode(matcher)
	if matcher == nil then
		matcher = "full_code"
	end
	assert(
		matcher == "full_code" or matcher == "initial" or matcher == "prefix" or matcher == "letter",
		"matcher must be full_code, initial, prefix or letter; Lua matcher functions are not supported"
	)
	return matcher
end

---@class FlashAnySource
---@field data? FlashAnyTable
---@field mode string
---@field fallback? boolean
---@field name? string
---@field groups? table<string, string[]> Shared spelling alternatives keyed by code.
---@field selectors? table<string, table<string, string>>

---@param values FlashAnySourceSpec[]
---@return FlashAnySource[]
function M.resolve(values)
	assert(type(values) == "table" and vim.islist(values), "opts.sources is required and must be a list")
	local ret = { { name = "literal", mode = "literal" } }
	for _, value in ipairs(values) do
		assert(type(value) == "string" or type(value) == "table", "source must be a name or configuration table")
		local named_only = type(value) == "string"
		if named_only then
			value = { name = value }
		end
		if not value.name and type(value.codes) == "table" then
			value = { data = value }
		end
		if
			value.name
			or value.matcher
			or value.data
			or value.lua
			or value.tsv
			or value.file
			or value.converter
			or value.loader
		then
			---@cast value FlashAnySourceConfig
			assert(value.fallback == nil or type(value.fallback) == "boolean", "fallback must be a boolean")
			assert(rawget(value, "loader") == nil, "custom loaders are not supported; provide a complete code table")
			assert(
				not value.converter or (value.file and not value.lua and not value.data),
				"converter requires an external file"
			)
			assert(not value.tsv or value.lua, "tsv requires a Lua companion; use file for external dictionaries")
			assert(
				not value.file or (not value.lua and not value.data and not value.tsv),
				"file cannot be combined with lua, data or tsv"
			)
			assert(
				value.selection == nil or value.selection == false or type(value.selection) == "table",
				"selection must be a table or false"
			)
			assert(value.groups == nil or type(value.groups) == "table", "groups must map codes to spelling lists")
			local defaults = value.name and M.load(value.name, not named_only and value or nil) or {}
			-- Factories declare file metadata; the same reader/ranking path serves direct files.
			if defaults.file then
				local configured = vim.tbl_extend("force", defaults, value)
				if type(defaults.selection) == "table" and type(value.selection) == "table" then
					configured.selection = vim.tbl_extend("force", defaults.selection, value.selection)
				end
				if type(value.file) == "string" then
					-- An override is a different dictionary, whose header/format may differ.
					for _, field in ipairs({ "format", "columns", "encoding", "header" }) do
						configured[field] = value[field]
					end
				end
				if value.data or value.lua then
					configured.file = nil
					configured.groups = value.groups
				elseif value.file == false then
					configured.file = defaults.file
				end
				value = configured
			end
			local data = defaults.data
			local selectors
			local groups = defaults.groups
			if not value.name or value.data or value.lua or value.file then
				groups = value.groups
			end
			if not defaults.prepared then
				if value.lua then
					data, groups =
						tables.append_space(tables.from_files(value.lua, value.tsv), value.append_space_below, groups)
				elseif value.file then
					assert(not value.data and not value.tsv, "file cannot be combined with data or tsv")
					if value.selection then
						assert(
							value.matcher == nil or value.matcher == "full_code",
							"selection requires full_code matching"
						)
						assert(
							not value.converter and value.append_space_below == nil,
							"selection cannot be combined with converter or append_space_below"
						)
						local ranks
						data, ranks = tables.from_file(value.file, vim.tbl_extend("force", value, { weights = true }))
						selectors = require("flash-any.build").selectors(
							data,
							assert(ranks),
							assert(value.selection.keys, "selection.keys is required for file sources")
						)
					else
						data, groups =
							tables.append_space(tables.from_file(value.file, value), value.append_space_below, groups)
					end
				elseif value.data then
					data, groups = tables.append_space(tables.normalize(value.data), value.append_space_below, groups)
				end
			end
			if value.selection and not defaults.prepared then
				assert(value.file, "ranked selection requires a weighted file")
				assert(type(value.selection) == "table", "selection must be a table or false")
			end
			local matcher = value.matcher
			if matcher == nil then
				matcher = defaults.matcher
			end
			local fallback = value.fallback
			if fallback == nil then
				fallback = defaults.fallback
			end
			assert(fallback == nil or type(fallback) == "boolean", "fallback must be a boolean")
			local mode = source_mode(matcher)
			if value.selection and not defaults.prepared then
				assert(mode == "full_code", "selection requires full_code matching")
			end
			ret[#ret + 1] = {
				data = data,
				mode = mode,
				name = value.name,
				fallback = fallback,
				selectors = selectors,
				groups = groups,
			}
		else
			---@cast value FlashAnyTableInput
			local data = tables.normalize(value)
			ret[#ret + 1] = { data = data, mode = "full_code" }
		end
	end
	return ret
end

return M

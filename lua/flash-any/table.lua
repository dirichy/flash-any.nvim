local M = {}

-- Complete text -> ASCII encodings or group references, with no runtime lookup state.
---@alias FlashAnyTable table<string, string[]>
---@alias FlashAnyTableMap table<string, string|string[]>
---@class FlashAnyTableDefinition
---@field codes FlashAnyTableMap
---@alias FlashAnyTableInput FlashAnyTableMap|FlashAnyTableDefinition

---Resolve an exact group name first, then a space-separated sequence of known groups.
---@param code string
---@param groups? table<string, string[]>
---@return string[]?
function M.group_sequence(code, groups)
	if not groups then
		return nil
	end
	if groups[code] ~= nil then
		return { code }
	end
	if not code:find(" ", 1, true) then
		return nil
	end
	local parts = vim.split(code, " ", { plain = true })
	if #parts < 2 then
		return nil
	end
	for _, part in ipairs(parts) do
		if part == "" or groups[part] == nil then
			return nil
		end
	end
	return parts
end

local function space_codes(codes, below, groups)
	local ret = {}
	for _, code in ipairs(codes) do
		ret[#ret + 1] = not M.group_sequence(code, groups) and #code < below and code .. " " or code
	end
	return ret
end

---Pad short inline codes and group spellings without modifying shared source data.
---@param data FlashAnyTable
---@param below? integer
---@param groups? table<string, string[]>
---@return FlashAnyTable
---@return table<string, string[]>?
function M.append_space(data, below, groups)
	if below == nil then
		return data, groups
	end
	assert(type(below) == "number" and below > 0 and below % 1 == 0, "append_space_below must be a positive integer")
	local padded_groups
	if groups then
		padded_groups = {}
		for name, spellings in pairs(groups) do
			padded_groups[name] = space_codes(spellings, below)
		end
	end
	local ret = {}
	for text, codes in pairs(data) do
		ret[text] = space_codes(codes, below, groups)
	end
	return ret, padded_groups
end

---Copy a complete map and normalize single encodings to arrays.
---@param map FlashAnyTableInput
---@param groups? table<string, string[]>
---@return FlashAnyTable
function M.normalize(map, groups)
	local values = type(map.codes) == "table" and map.codes or map
	---@cast values FlashAnyTableMap
	local ret = {}
	for text, codes in pairs(values) do
		assert(type(text) == "string" and text ~= "", "code-table keys must be nonempty strings")
		if type(codes) == "string" then
			codes = { codes }
		end
		assert(type(codes) == "table" and vim.islist(codes), "codes must be a string or array: " .. text)
		local copy = {}
		for i, code in ipairs(codes) do
			assert(
				type(code) == "string"
					and code ~= ""
					and not code:find("%z")
					and (not code:find("[\128-\255]") or M.group_sequence(code, groups) ~= nil),
				"codes must be nonempty ASCII strings or known group references without NUL: " .. text
			)
			copy[i] = code
		end
		ret[text] = copy
	end
	return ret
end

---Read a complete dictionary, including multi-grapheme phrases.
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
	local rows, ranks = require("flash-any.reader").read(path, opts)
	for char, codes in pairs(rows) do
		if convert then
			local converted = convert(codes)
			assert(
				converted == nil or (type(converted) == "table" and vim.islist(converted)),
				"converter must return a code array or nil"
			)
			rows[char] = converted and #converted > 0 and converted or nil
		end
	end
	return M.normalize(rows, opts.groups), ranks
end

---@class FlashAnyTableOptions
---@field convert? fun(codes: string[]): string[]?
---@field extra? FlashAnyTableMap Added after conversion; overrides existing entries.
---@field groups? table<string, string[]> Group names recognized while loading codes.

---Read complete named TSV/Lua data, with converted Lua overrides and extra entries last.
---@param name string
---@param opts? FlashAnyTableOptions
---@return FlashAnyTable
function M.load(name, opts)
	local lua = vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".lua", false)[1]
	local tsv = vim.api.nvim_get_runtime_file("lua/flash-any/tables/" .. name .. ".tsv", false)[1]
	assert(lua or tsv, "code table not found: " .. name)
	local groups, convert = opts and opts.groups, opts and opts.convert
	local data = tsv and require("flash-any.reader").read(tsv, { format = "tsv" }) or {}
	if lua then
		local overrides = M.normalize(require("flash-any.tables." .. name), groups)
		if convert then
			-- Preserve the TSV row conversion contract; Lua overrides convert their whole list.
			for text, codes in pairs(data) do
				local converted = {}
				for _, code in ipairs(codes) do
					vim.list_extend(converted, convert({ code }) or {})
				end
				data[text] = converted
			end
			for text, codes in pairs(overrides) do
				overrides[text] = convert(codes)
			end
		end
		for text, codes in pairs(overrides) do
			data[text] = codes
		end
	else
		data = M.normalize(data, groups)
		if convert then
			for text, codes in pairs(data) do
				data[text] = convert(codes) or {}
			end
		end
	end
	if opts and opts.extra then
		for text, codes in pairs(M.normalize(opts.extra, groups)) do
			data[text] = codes
		end
	end
	return M.normalize(data, groups)
end

---Read both complete files; every Lua key, including an empty code list, overrides TSV.
---@param lua_path string
---@param tsv_path? string
---@param groups? table<string, string[]>
---@return FlashAnyTable
function M.from_files(lua_path, tsv_path, groups)
	local data = tsv_path and M.from_file(tsv_path, { format = "tsv", groups = groups }) or {}
	for text, codes in pairs(M.normalize(dofile(vim.fn.expand(lua_path)), groups)) do
		data[text] = codes
	end
	return data
end

---Assign optional suffixes by descending weight, then original order.
---@param data FlashAnyTable
---@param ranks table<string, table<string, {weight: number, order: number}>>
---@param keys string[]
---@return table<string, table<string, string>>
function M.selectors(data, ranks, keys)
	assert(type(keys) == "table" and vim.islist(keys) and #keys > 0, "selection.keys must be a nonempty list")
	local used = {}
	for _, key in ipairs(keys) do
		assert(
			type(key) == "string" and #key > 0 and #key < 128 and not key:find("[%z\128-\255]"),
			"selection keys must be nonempty ASCII strings without NUL shorter than 128 bytes"
		)
		assert(not used[key], "selection keys must be distinct")
		used[key] = true
	end
	local selectors = {}
	for code, candidates in pairs(ranks) do
		local ordered = {}
		for text, rank in pairs(candidates) do
			if data[text] then
				ordered[#ordered + 1] = { text = text, weight = rank.weight, order = rank.order }
			end
		end
		table.sort(ordered, function(a, b)
			return a.weight > b.weight
				or (a.weight == b.weight and (a.order < b.order or (a.order == b.order and a.text < b.text)))
		end)
		for index, candidate in ipairs(ordered) do
			if keys[index] then
				selectors[candidate.text] = selectors[candidate.text] or {}
				selectors[candidate.text][code] = keys[index]
			end
		end
	end
	return selectors
end

return M

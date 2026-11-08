local M = {}

local function add(rows, char, code, literal)
	char = char and (literal and char or char:gsub("^%s+", ""):gsub("%s+$", ""))
	code = code and code:gsub("^%s+", ""):gsub("%s+$", "")
	if not char or char == "" or not code or code == "" then
		return
	end
	assert(not char:find("[\t\r\n]"), "table text must not contain tabs or newlines")
	assert(not code:find("[\t\r\n]"), "code must not contain tabs or newlines: " .. code)
	rows[char] = rows[char] or {}
	rows[char][code] = true
end

local function csv_fields(line)
	-- Fields may contain UTF-8. Only ASCII CSV syntax needs bytewise inspection.
	local fields, field, quoted = {}, {}, false
	local i = 1
	while i <= #line do
		local char = line:sub(i, i)
		if char == '"' then
			if quoted and line:sub(i + 1, i + 1) == '"' then
				field[#field + 1] = '"'
				i = i + 1
			else
				quoted = not quoted
			end
		elseif char == "," and not quoted then
			fields[#fields + 1] = table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
			field = {}
		else
			field[#field + 1] = char
		end
		i = i + 1
	end
	assert(not quoted, "unterminated CSV quote")
	fields[#fields + 1] = table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
	return fields
end

-- Read only Rime's columns/import_tables metadata, not schema spelling or encoders.
local function header(lines)
	local columns, imports, section = nil, {}, nil
	local first = 1
	if not vim.tbl_contains(lines, "---") and not vim.tbl_contains(lines, "...") then
		return first, columns, imports
	end
	for index, line in ipairs(lines) do
		if line:match("^%.%.%.%s*$") then
			return index + 1, columns, imports
		end
		local key, rest = line:match("^(columns):%s*(.*)$")
		if not key then
			key, rest = line:match("^(import_tables):%s*(.*)$")
		end
		if key then
			section = key
			if key == "columns" then
				columns = {}
			end
			local list = key == "columns" and columns or imports
			if rest ~= "" and not rest:match("^#") then
				local inline = assert(rest:match("^%[(.-)%]%s*#?.*$"), "unsupported Rime list: " .. line)
				for value in inline:gmatch("[^,]+") do
					list[#list + 1] = vim.trim(value):gsub("^['\"]", ""):gsub("['\"]$", "")
				end
			end
		elseif section then
			local value = line:match("^%s+%-%s+([^#]+)")
			if value then
				local list = section == "columns" and columns or imports
				list[#list + 1] = vim.trim(value):gsub("^['\"]", ""):gsub("['\"]$", "")
			elseif line:match("^%S") and not line:match("^#") then
				section = nil
			end
		end
	end
	error("Rime header is missing ...")
end

local function files(path, opts, header_only)
	local result, seen, active = {}, {}, {}
	local function visit(input, format)
		input = vim.fn.fnamemodify(vim.fn.expand(input), ":p")
		assert(not active[input], "cyclic Rime import: " .. input)
		if seen[input] then
			return
		end
		active[input], seen[input] = true, true
		if format == "auto" and input:match("%.csv$") then
			format = "csv"
		end
		local bytes = ""
		local encoded = opts.encoding and opts.encoding:lower() ~= "utf-8" and opts.encoding:lower() ~= "utf8"
		if not header_only or format == "rime" or format == "auto" then
			local handle = assert(io.open(input, "rb"))
			if header_only and not encoded then
				local prefix = {}
				-- Dependency discovery stops at the YAML terminator or the first data row.
				for line in handle:lines() do
					line = line:gsub("\r$", ""):gsub("^\239\187\191", "")
					prefix[#prefix + 1] = line
					if line:match("^%.%.%.%s*$") then
						break
					end
					if
						not (
							line:match("^%s*$")
							or line:match("^%s*#")
							or line:match("^%-%-%-%s*$")
							or line:match("^[%a_][%w_]*:")
							or line:match("^%s")
						)
					then
						break
					end
				end
				bytes = table.concat(prefix, "\n")
			else
				-- Non-UTF-8 headers share the reader's whole-file decoding path.
				bytes = handle:read("*a")
			end
			handle:close()
		end
		-- Decode before splitting: UTF-16 contains zero bytes and two-byte newlines.
		if encoded then
			bytes = assert(vim.iconv(bytes, opts.encoding, "utf-8"), "invalid input encoding")
		end
		local lines = vim.split(bytes, "\n", { plain = true })
		for index, line in ipairs(lines) do
			lines[index] = line:gsub("\r$", "")
		end
		lines[1] = lines[1]:gsub("^\239\187\191", "")
		local first, columns, imports = 1, nil, {}
		local rime_header = vim.tbl_contains(lines, "---")
		if format == "auto" and not rime_header and vim.tbl_contains(lines, "...") then
			for _, line in ipairs(lines) do
				if line:match("^name:%s*") then
					rime_header = true
					break
				end
			end
		end
		if format == "rime" or (format == "auto" and rime_header) then
			format = "rime"
			first, columns, imports = header(lines)
		end
		result[#result + 1] = { path = input, lines = lines, first = first, columns = columns, format = format }
		for _, name in ipairs(imports) do
			visit(vim.fn.fnamemodify(input, ":h") .. "/" .. name .. ".dict.yaml", "rime")
		end
		active[input] = nil
	end
	visit(path, opts.format or "auto")
	return result
end

---Fingerprint file metadata, following Rime headers to include imported dictionaries.
---@param path string
---@param opts? table
---@return string
function M.fingerprint(path, opts)
	local inputs = {}
	for _, file in ipairs(files(path, opts or {}, true)) do
		inputs[#inputs + 1] = require("flash-any.stamp")(file.path)
	end
	return vim.fn.sha256(table.concat(inputs, "\n"))
end

---Read one encoding per row; duplicate text rows collect independent codes.
---@param path string
---@param opts? {format?: string, columns?: string[], encoding?: string, header?: boolean, weights?: boolean}
---@return table<string, string[]>
---@return table<string, table<string, {weight: number, order: number}>>? ranks
function M.read(path, opts)
	opts = opts or {}
	assert(
		vim.tbl_contains({ "auto", "csv", "tab", "tsv", "rime", "space", "fcitx", "ibus" }, opts.format or "auto"),
		"unknown input format: " .. tostring(opts.format)
	)
	local rows, ranks, sequence = {}, opts.weights and {} or nil, 0
	for _, file in ipairs(files(path, opts)) do
		local format = file.format
		if format == "auto" then
			if vim.tbl_contains(file.lines, "BEGIN_TABLE") then
				format = "ibus"
			elseif vim.tbl_contains(file.lines, "[数据]") or vim.tbl_contains(file.lines, "[Data]") then
				format = "fcitx"
			end
		end
		local columns = opts.columns or file.columns
		---@type integer?, integer?
		local text_index, code_index = 1, 2
		---@type integer?, integer?
		local weight_index, order_index = 3, nil
		if format == "fcitx" or format == "ibus" then
			text_index, code_index = 2, 1
		end
		if columns then
			text_index, code_index, weight_index = nil, nil, nil
			for index, column in ipairs(columns) do
				if column == "text" then
					text_index = index
				end
				if column == "code" then
					code_index = index
				end
				if column == "weight" then
					weight_index = index
				end
				if column == "order" then
					order_index = index
				end
			end
			assert(text_index and code_index, "columns must contain text and code")
		end
		local in_data = format ~= "fcitx" and format ~= "ibus"
		local first_record, prefixes = true, {}
		for index = file.first, #file.lines do
			local line = file.lines[index]:gsub("\r$", "")
			if format == "fcitx" and not in_data then
				local prefix = line:match("^%s*Prompt=%s*(%S+)")
					or line:match("^%s*提示=%s*(%S+)")
					or line:match("^%s*ConstructPhrase=%s*(%S+)")
					or line:match("^%s*构词=%s*(%S+)")
				if prefix then
					prefixes[#prefixes + 1] = prefix
				end
			end
			if line == "[数据]" or line == "[Data]" or line == "BEGIN_TABLE" then
				if format == "auto" then
					format = line == "BEGIN_TABLE" and "ibus" or "fcitx"
					if not columns then
						text_index, code_index = 2, 1
					end
				end
				in_data = true
			elseif line == "END_TABLE" or (format == "fcitx" and (line == "[Phrase]" or line == "[词组]")) then
				in_data = false
			elseif format == "auto" and (line == "BEGIN_DEFINITION" or line:match("^键码=")) then
				format, in_data = line == "BEGIN_DEFINITION" and "ibus" or "fcitx", false
				if not columns then
					text_index, code_index = 2, 1
				end
			elseif
				in_data
				and not line:match("^%s*$")
				and (
					format == "fcitx"
					or (format == "ibus" and not line:match("^%s*###"))
					or (format ~= "ibus" and not line:match("^%s*#"))
				)
			then
				local fields, literal
				local kind = format
				if kind == "auto" then
					if line:find("\t", 1, true) then
						kind = "tsv"
					elseif line:sub(1, 1) == '"' or (line:find(",", 1, true) and not line:find("%s")) then
						kind = "csv"
					else
						kind = "space"
					end
					format = kind
				end
				if kind == "csv" then
					fields = csv_fields(line)
				elseif kind == "fcitx" then
					local code, value = line:match("^%s*(%S+)%s+(.+)$")
					if code then
						value = vim.trim(value)
						if value:sub(1, 1) == '"' then
							-- Fcitx quoted values use JSON-compatible quote/backslash/control escapes.
							value, literal = vim.json.decode(value), true
						end
						fields = { code, value }
					else
						fields = {}
					end
				elseif kind == "space" then
					fields = vim.split(vim.trim(line), "%s+")
				else
					fields = vim.split(line, "\t", { plain = true })
				end
				local omit = first_record and kind == "csv" and opts.header
				first_record = false
				if kind == "fcitx" then
					for _, prefix in ipairs(prefixes) do
						if fields[1] and fields[1]:sub(1, #prefix) == prefix then
							omit = true
						end
					end
				else
					assert(
						fields[text_index] and fields[code_index],
						"missing text/code at " .. file.path .. ":" .. index
					)
				end
				if not omit then
					add(rows, fields[text_index], fields[code_index], literal)
					if ranks and fields[text_index] and fields[code_index] then
						local text, code = fields[text_index], vim.trim(fields[code_index])
						text = literal and text or vim.trim(text)
						if text ~= "" and code ~= "" then
							sequence = sequence + 1
							local raw = weight_index and fields[weight_index]
							local weight = raw
									and raw ~= ""
									and assert(tonumber(raw), "ranking requires numeric weights")
								or 0
							assert(
								weight == weight and math.abs(weight) ~= math.huge,
								"ranking requires finite weights"
							)
							local order = order_index and tonumber(fields[order_index]) or sequence
							ranks[code] = ranks[code] or {}
							local old = ranks[code][text]
							if not old or weight > old.weight then
								ranks[code][text] = { weight = weight, order = order }
							end
						end
					end
				end
			end
		end
	end
	for key, codes in pairs(rows) do
		rows[key] = vim.fn.sort(vim.tbl_keys(codes))
	end
	return rows, ranks
end

local function quote(value)
	return string.format("%q", value)
end

---@param opts table
---@return integer common Number of entries written to Lua.
---@return integer full Number of distinct entries in the complete input.
---@return integer multi Number of distinct multi-grapheme entries in the complete input.
function M.table(opts)
	local grapheme = require("flash-any.grapheme")
	assert(opts and opts.source and opts.lua, "source and lua are required")
	local rows = require("flash-any.table").normalize(M.read(opts.source, {
		format = opts.format or opts.separator,
		columns = opts.columns,
		encoding = opts.encoding,
		header = opts.header,
	}))
	local all = vim.tbl_keys(rows)
	table.sort(all)
	local multi, maximum = 0, 1
	for _, key in ipairs(all) do
		local count = grapheme.len(key)
		if count > 1 then
			multi = multi + 1
		end
		maximum = math.max(maximum, count)
	end
	local keys = all
	if opts.common then
		local common = dofile(vim.fn.expand(opts.common))
		assert(type(common) == "table", "common Lua file must return a table")
		if type(common.codes) == "table" then
			common = common.codes
		end
		keys = vim.tbl_keys(common)
		table.sort(keys)
	end

	local common, prefixes = 0, {}
	for _, key in ipairs(keys) do
		if rows[key] then
			common = common + 1
			grapheme.each(key, function(_, offset)
				if offset < #key then
					prefixes[key:sub(1, offset)] = true
				end
			end)
		end
	end
	local lua = assert(io.open(vim.fn.expand(opts.lua), "wb"))
	lua:write("return {\n  codes = {\n")
	for _, key in ipairs(keys) do
		if rows[key] then
			local codes = vim.deepcopy(rows[key])
			table.sort(codes)
			lua:write(string.format("    [%s] = {%s},\n", quote(key), table.concat(vim.tbl_map(quote, codes), ", ")))
		end
	end
	lua:write("  },\n  prefixes = {\n")
	local prefix_keys = vim.tbl_keys(prefixes)
	table.sort(prefix_keys)
	for _, key in ipairs(prefix_keys) do
		lua:write(string.format("    [%s] = true,\n", quote(key)))
	end
	lua:write(("  },\n  max_chars = %d,\n"):format(maximum))
	lua:write("}\n")
	lua:close()

	if opts.tsv then
		local tsv = assert(io.open(vim.fn.expand(opts.tsv), "wb"))
		for _, char in ipairs(all) do
			local codes = vim.deepcopy(rows[char])
			table.sort(codes)
			for _, code in ipairs(codes) do
				tsv:write(char, "\t", code, "\n")
			end
		end
		tsv:close()
	end
	return common, #all, multi
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
			type(key) == "string" and #key > 0 and #key < 128 and not key:find("[\128-\255]"),
			"selection keys must be nonempty ASCII strings shorter than 128 bytes"
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

---Compile ordered sources into one complete-grapheme dictionary.
---@param opts {sources: FlashAnySourceSpec[], output: string}
---@return integer sources Number of build-time sources, including literal.
---@return integer entries Number of merged graphemes with matchable encodings.
function M.binary(opts)
	local grapheme = require("flash-any.grapheme")
	assert(type(opts) == "table" and type(opts.output) == "string", "sources and output are required")
	assert(type(opts.sources) == "table" and vim.islist(opts.sources), "sources must be a list")
	local values = {}
	for i, value in ipairs(opts.sources) do
		values[i] = type(value) == "string" and { name = value } or value
	end
	local sources = require("flash-any.source").resolve(values)
	local tables = require("flash-any.table")
	local native = require("flash-any.native")
	local modes = native.modes
	local known, merged, groups, group_ids = {}, {}, {}, {}
	for _, source in ipairs(sources) do
		local mode =
			assert(modes[source.mode], "binary build requires a built-in matcher mode; Lua matchers cannot be compiled")
		local aliases = {}
		if source.groups then
			assert(type(source.groups) == "table", "groups must map codes to spelling lists")
			local names = vim.tbl_keys(source.groups)
			for _, name in ipairs(names) do
				assert(
					type(name) == "string" and name ~= "" and not name:find("[\128-\255]"),
					"group names must be nonempty ASCII strings"
				)
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local variants = source.groups[name]
				assert(type(variants) == "table" and vim.islist(variants), "group spellings must be lists")
				local set = {}
				for _, spelling in ipairs(variants) do
					assert(
						type(spelling) == "string"
							and #spelling > 0
							and #spelling <= 255
							and not spelling:find("[\128-\255]"),
						"group spellings must be ASCII strings of 1..255 bytes"
					)
					set[spelling] = true
				end
				local spellings = vim.tbl_keys(set)
				table.sort(spellings)
				-- Intern by contents: equal local names in different sources may mean different groups.
				local identity = vim.json.encode(spellings)
				if group_ids[identity] == nil then
					group_ids[identity] = #groups
					groups[#groups + 1] = spellings
				end
				aliases[name] = group_ids[identity]
			end
		end
		local data = mode ~= 0 and source.data and tables.materialize(source.data) or {}
		if mode == 0 then
			for byte = 0, 127 do
				local key = string.char(byte)
				data[key] = { key }
			end
		end
		for key, codes in pairs(data) do
			assert(
				type(key) == "string" and key ~= "" and grapheme.len(key) == 1,
				"binary keys must contain exactly one complete grapheme: " .. tostring(key)
			)
			if not source.fallback or not known[key] then
				-- Recognition precedes matching: even an empty list blocks later fallbacks.
				known[key] = true
				local set = merged[key] or {}
				merged[key] = set
				for _, code in ipairs(codes) do
					assert(
						type(code) == "string" and code ~= "" and not code:find("[\128-\255]"),
						"binary codes must be nonempty ASCII strings"
					)
					local kind, parameters, value = mode, "", code
					if aliases[code] ~= nil then
						kind, value = mode + modes.group, aliases[code]
					end
					local selectors = source.selectors and source.selectors[key]
					if mode == modes.full_code and selectors and selectors[code] then
						assert(aliases[code] == nil, "shared groups cannot carry optional suffixes")
						kind = modes.suffix
						parameters = selectors[code]
					end
					local group = tostring(kind) .. ":" .. parameters
					set[group] = set[group] or { mode = kind, parameters = parameters, codes = {} }
					set[group].codes[value] = true
				end
			end
		end
	end
	local keys = {}
	for key, codes in pairs(merged) do
		if next(codes) then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local lists = {}
	for i, key in ipairs(keys) do
		local codes = {}
		for _, group in pairs(merged[key]) do
			for code in pairs(group.codes) do
				codes[#codes + 1] = { group.mode, code, group.parameters }
			end
		end
		table.sort(codes, function(a, b)
			return a[1] < b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and a[3] < b[3])))
		end)
		lists[i] = codes
	end
	native.write(vim.fn.expand(opts.output), keys, lists, #groups > 0 and groups or nil)
	return #sources, #keys
end

function M.command(opts)
	local ok, common, full, multi = pcall(M.table, opts)
	if not ok then
		vim.notify("flash-any: " .. common, vim.log.levels.ERROR)
		return
	end
	local message = ("flash-any: wrote %d Lua entries"):format(common)
	if opts.tsv then
		message = message .. (" and %d TSV entries"):format(full)
	end
	local level = vim.log.levels.INFO
	if multi > 0 then
		message = message .. ("; %d multi-grapheme entries must be filtered before binary compilation"):format(multi)
		level = vim.log.levels.WARN
	end
	vim.notify(message, level)
end

return M

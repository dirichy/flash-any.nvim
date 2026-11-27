local M = {}

-- Keep the build helpers available at their original public entry points.
local reader = require("flash-any.reader")
M.read = reader.read
M.fingerprint = reader.fingerprint
M.selectors = require("flash-any.table").selectors

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
	local multi = 0
	for _, key in ipairs(all) do
		local count = grapheme.len(key)
		if count > 1 then
			multi = multi + 1
		end
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

	local common = 0
	for _, key in ipairs(keys) do
		if rows[key] then
			common = common + 1
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
	lua:write("  },\n")
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

---Compile ordered sources into one complete-grapheme dictionary.
---@param opts {sources: FlashAnySourceSpec[], output: string}
---@return integer sources Number of build-time sources, including literal.
---@return integer entries Number of merged text keys with matchable encodings.
function M.binary(opts)
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
					type(name) == "string" and name ~= "" and not name:find("%z"),
					"group names must be nonempty strings without NUL"
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
							and not spelling:find("[%z\128-\255]"),
						"group spellings must be ASCII strings of 1..255 bytes without NUL"
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
		local data = mode ~= 0 and source.data or {}
		if mode == 0 then
			for byte = 1, 127 do
				local key = string.char(byte)
				data[key] = { key }
			end
		end
		for key, codes in pairs(data) do
			assert(type(key) == "string" and key ~= "", "binary keys must be nonempty text: " .. tostring(key))
			if not source.fallback or not known[key] then
				-- Recognition precedes matching: even an empty list blocks later fallbacks.
				known[key] = true
				local set = merged[key] or {}
				merged[key] = set
				for _, code in ipairs(codes) do
					assert(type(code) == "string" and code ~= "" and not code:find("%z"), "invalid binary code")
					local kind, parameters = mode, ""
					---@type string|integer[]
					local value = code
					local sequence = tables.group_sequence(code, source.groups)
					if sequence then
						local ids = {}
						for _, name in ipairs(sequence) do
							ids[#ids + 1] = assert(aliases[name])
						end
						kind, value = mode + modes.group, ids
					else
						assert(not code:find("[\128-\255]"), "inline binary codes must be ASCII")
					end
					local selectors = source.selectors and source.selectors[key]
					if mode == modes.full_code and selectors and selectors[code] then
						assert(not sequence, "shared groups cannot carry optional suffixes")
						kind = modes.suffix
						parameters = selectors[code]
					end
					local group = tostring(kind) .. ":" .. parameters
					set[group] = set[group] or { mode = kind, parameters = parameters, codes = {} }
					local identity = type(value) == "table" and table.concat(value, ",") or value
					set[group].codes[identity] = value
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
			for identity, code in pairs(group.codes) do
				codes[#codes + 1] = { group.mode, code, group.parameters, identity }
			end
		end
		table.sort(codes, function(a, b)
			return a[1] < b[1] or (a[1] == b[1] and (a[4] < b[4] or (a[4] == b[4] and a[3] < b[3])))
		end)
		for _, code in ipairs(codes) do
			code[4] = nil
		end
		lists[i] = codes
	end
	native.write(vim.fn.expand(opts.output), keys, lists, #groups > 0 and groups or nil)
	return #sources, #keys
end

---Run a builder in an isolated headless Nvim, preserving runtimepath and local cwd.
---@param kind "binary"|"table"
---@param opts table
---@param done fun(err: string?, result: integer[]?)
function M.async(kind, opts, done)
	local request = vim.fn.tempname()
	local worker = assert(vim.api.nvim_get_runtime_file("lua/flash-any/build_worker.lua", false)[1])
	local request_bytes = vim.mpack.encode({ kind = kind, opts = opts, runtimepath = vim.o.runtimepath })
	local handle = assert(io.open(request, "wb"))
	handle:write(request_bytes)
	handle:close()
	local ok, err = pcall(vim.system, { vim.v.progpath, "--clean", "-l", worker, request }, {
		cwd = vim.fn.getcwd(),
		text = true,
	}, function(process)
		vim.schedule(function()
			local result
			if process.code == 0 then
				local file = io.open(request, "rb")
				if file then
					local bytes = file:read("*a")
					file:close()
					local decoded, value = pcall(vim.mpack.decode, bytes)
					if decoded then
						result = value
					end
				end
			end
			vim.uv.fs_unlink(request)
			done(not result and (process.stderr ~= "" and process.stderr or "dictionary worker failed") or nil, result)
		end)
	end)
	if not ok then
		vim.uv.fs_unlink(request)
		error(err)
	end
end

function M.command(opts)
	M.async("table", opts, function(err, result)
		if err then
			vim.notify("flash-any: " .. err, vim.log.levels.ERROR)
			return
		end
		local common, full, multi = unpack(assert(result))
		local message = ("flash-any: wrote %d Lua entries"):format(common)
		if opts.tsv then
			message = message .. (" and %d TSV entries"):format(full)
		end
		if multi > 0 then
			message = message .. ("; %d multi-grapheme entries"):format(multi)
		end
		vim.notify(message, vim.log.levels.INFO)
	end)
	vim.notify("flash-any: building tables in background", vim.log.levels.INFO)
end

return M

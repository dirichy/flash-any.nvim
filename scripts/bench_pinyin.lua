dofile("scripts/source_path.lua")
-- Isolated full-pinyin prototypes. Invoked by bench_pinyin.py; no production API changes.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local output, task = assert(arg[1]), assert(arg[2])
local load =
	assert(package.loadlib(vim.env.FLASH_ANY_PINYIN_NATIVE or output .. "/native.so", "luaopen_flash_any_native"))
local prototype = load()
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local native = require("flash-any.native")
local function path(mode, fuzzy, unicode, matcher)
	return output
		.. "/"
		.. mode
		.. "-"
		.. fuzzy
		.. (unicode and "-unicode" or "")
		.. (matcher and matcher ~= "initial" and "-" .. matcher or "")
		.. ".bin"
end
local function write(pathname, value)
	local f = assert(io.open(pathname, "wb"))
	f:write(value)
	f:close()
end
local function read(pathname)
	local f = assert(io.open(pathname, "rb"))
	local value = f:read("*a")
	f:close()
	return value
end
local function book(mode, fuzzy, unicode, matcher)
	matcher = matcher or "initial"
	if mode == "expanded" or mode == "shared" then
		local pathname = output
			.. "/production-"
			.. mode
			.. "-"
			.. fuzzy
			.. (unicode and "-unicode" or "")
			.. (matcher == "initial" and "" or "-" .. matcher)
			.. ".bin"
		return native.load(pathname):new_state(), 0
	end
	local engine = prototype.open(path(mode == "ondemand" and "syllables" or mode, fuzzy, unicode, matcher))
	local memory = 0
	if mode == "syllables" or mode == "ondemand" then
		memory =
			engine:pinyin(read(output .. "/" .. fuzzy .. ".syllables"), mode == "ondemand", prototype.modes[matcher])
	end
	return engine:new_state(), memory
end

if task == "build" then
	local registry, tables = require("flash-any.source"), require("flash-any.table")
	local source = registry.resolve({ { name = "pinyin" } })[2]
	local original = tables.materialize(source.data)
	local spelling_set, examples = {}, {}
	for text, codes in pairs(original) do
		for _, code in ipairs(codes) do
			if code:match("^[a-z]+$") then
				spelling_set[code] = true
				if not examples[code] or text < examples[code] then
					examples[code] = text
				end
			end
		end
	end
	local syllables = vim.tbl_keys(spelling_set)
	table.sort(syllables)
	local ids = {}
	for index, spelling in ipairs(syllables) do
		ids[spelling] = index - 1
	end
	local parts = require("flash-any.pinyin.parts")
	local function optional_byte(spelling, fuzzy)
		if not fuzzy then
			return spelling
		end
		local initial, final = parts.initial[spelling], parts.final[spelling]
		local initial_base = ({ zh = "z", z = "z", ch = "c", c = "c", sh = "s", s = "s" })[initial]
		local final_base = ({ ang = "an", an = "an", eng = "en", en = "en", ing = "in", ["in"] = "in" })[final]
		return (initial_base and initial_base .. string.char(0xA0) .. "h" or initial)
			.. (final_base and final_base .. string.char(0xA0) .. "g" or final)
	end
	local sizes = {}
	for _, fuzzy in ipairs({ "plain", "fuzzy" }) do
		-- Capture the existing build-time converter, keeping the fuzzy rules identical.
		local reference_tables = require("reference.table")
		local table_load, convert = reference_tables.load, nil
		rawset(reference_tables, "load", function(_, opts)
			convert = opts.convert
			return {}
		end)
		require("reference.pinyin")({ fuzzy = fuzzy == "fuzzy" and true or {} })
		rawset(reference_tables, "load", table_load)
		local forms, coverage = {}, {}
		for index, spelling in ipairs(syllables) do
			local set = {}
			for _, variant in ipairs(assert(convert)({ spelling })) do
				set[variant] = true
			end
			forms[index] = vim.tbl_keys(set)
			table.sort(forms[index])
			coverage[index] = { text = examples[spelling], spellings = forms[index] }
		end
		local profile = prototype.pack_pinyin(forms)
		write(output .. "/" .. fuzzy .. ".syllables", profile)
		write(output .. "/" .. fuzzy .. ".coverage.json", vim.json.encode(coverage))
		local expanded =
			require("reference.table").materialize(require("reference.pinyin")({ fuzzy = fuzzy == "fuzzy" }).data)
		for _, unicode in ipairs({ false, true }) do
			for _, mode in ipairs({ "expanded", "syllables", "skip" }) do
				local rows = {}
				for byte = 0, 127 do
					local char = string.char(byte)
					rows[char] = { { prototype.modes.literal, char } }
				end
				for text, codes in pairs(mode == "expanded" and expanded or original) do
					rows[text] = rows[text] or {}
					for _, code in ipairs(codes) do
						local kind, value = prototype.modes.initial, code
						if mode == "syllables" and ids[code] ~= nil then
							kind, value = prototype.modes.pinyin, ids[code]
						elseif mode == "skip" and ids[code] ~= nil then
							value = optional_byte(code, fuzzy == "fuzzy")
							kind = value:find(string.char(0xA0), 1, true) and prototype.modes.skip or kind
						end
						rows[text][#rows[text] + 1] = { kind, value }
					end
					if unicode then
						rows[text][#rows[text] + 1] =
							{ prototype.modes.full_code, ("u%04x"):format(vim.fn.char2nr(text)) }
					end
				end
				local keys, records = vim.tbl_keys(rows), {}
				table.sort(keys)
				for _, text in ipairs(keys) do
					local unique = {}
					for _, record in ipairs(rows[text]) do
						unique[record[1] .. ":" .. record[2]] = record
					end
					local items = vim.tbl_values(unique)
					table.sort(items, function(a, b)
						return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
					end)
					records[#records + 1] = items
				end
				local name = mode .. "-" .. fuzzy .. (unicode and "-unicode" or "")
				prototype.write(keys, records, path(mode, fuzzy, unicode))
				if mode == "expanded" then
					native.write(output .. "/production-" .. name .. ".bin", keys, records)
				end
				if mode == "syllables" then
					for _, matcher in ipairs({ "initial", "full_code", "prefix" }) do
						local converted = vim.deepcopy(records)
						for _, row in ipairs(converted) do
							for _, record in ipairs(row) do
								if record[1] == prototype.modes.pinyin then
									record[1] = native.modes[matcher] + native.modes.group
								elseif record[1] == prototype.modes.initial then
									record[1] = native.modes[matcher]
								end
							end
						end
						local target = output
							.. "/production-shared-"
							.. fuzzy
							.. (unicode and "-unicode" or "")
							.. (matcher == "initial" and "" or "-" .. matcher)
							.. ".bin"
						native.write(target, keys, converted, forms)
						if matcher == "initial" then
							sizes[#sizes + 1] = {
								name = "shared-" .. fuzzy .. (unicode and "-unicode" or ""),
								entries = #keys,
								bytes = assert(vim.uv.fs_stat(target)).size,
								profile_bytes = #profile,
								syllables = #syllables,
							}
						end
					end
				end
				if mode == "expanded" or mode == "syllables" then
					for _, matcher in ipairs({ "full_code", "prefix" }) do
						local converted = vim.deepcopy(records)
						for _, row in ipairs(converted) do
							for _, record in ipairs(row) do
								if record[1] == prototype.modes.initial then
									record[1] = prototype.modes[matcher]
								end
							end
						end
						if mode == "expanded" then
							native.write(output .. "/production-" .. name .. "-" .. matcher .. ".bin", keys, converted)
						else
							prototype.write(keys, converted, path(mode, fuzzy, unicode, matcher))
						end
					end
				end
				sizes[#sizes + 1] = {
					name = name,
					entries = #keys,
					bytes = assert(vim.uv.fs_stat(path(mode, fuzzy, unicode))).size
						+ (mode == "syllables" and #profile or 0),
					profile_bytes = mode == "syllables" and #profile or 0,
					syllables = #syllables,
				}
			end
		end
	end
	io.write(vim.json.encode(sizes), "\n")
	return
end

local function scan(engine, lines, query, tick, cached, motion)
	if motion then
		local result = {}
		for row, line in ipairs(lines) do
			local items = engine:scan(0, 0, (tick or 1) + row, 1, 1, { line }, query, nil, motion)
			vim.list_extend(result, items)
		end
		return result
	end
	return engine:scan(0, 0, tick or 1, 1, #lines, not cached and lines or nil, query, { "a", "s", "d" }, motion)
end
if task == "check" then
	local comparisons = 0
	local lines = {
		"中国人民学习中文，ASCII flash_any 混合文本。",
		"张赞战藏上桑生森心星安昂我你，人间人间，先西安。",
		"á👩‍💻\255中国;z中国。",
		"中国……，？！—：；《》ASCII",
	}
	local queries = {
		"",
		"z",
		"zh",
		"zho",
		"zhon",
		"zhong",
		"zhongguo",
		"zg",
		"s",
		"si",
		"shi",
		"san",
		"shang",
		"zangan",
		"xian",
		"xi'an",
		"sisi",
		"ascii",
		"u4e2d",
		"zhong;",
		"\255",
		"...",
		"-",
		";",
		"?",
	}
	local random = 17
	for _ = 1, 120 do
		local q = ""
		for _ = 1, random % 8 + 1 do
			random = (random * 48271) % 2147483647
			q = q .. ("zhsacengio;xy"):sub(random % 12 + 1, random % 12 + 1)
		end
		queries[#queries + 1] = q
	end
	for _, fuzzy in ipairs({ "plain", "fuzzy" }) do
		for _, unicode in ipairs({ false, true }) do
			for _, matcher in ipairs({ "initial", "full_code", "prefix" }) do
				local engines = {
					(book("expanded", fuzzy, unicode, matcher)),
					(book("shared", fuzzy, unicode, matcher)),
					(book("syllables", fuzzy, unicode, matcher)),
					(book("ondemand", fuzzy, unicode, matcher)),
				}
				if matcher == "initial" then
					engines[#engines + 1] = book("skip", fuzzy, unicode)
				end
				for _, query in ipairs(queries) do
					for _, motion in ipairs({ false, "f", "F", "t", "T" }) do
						local expected = scan(engines[1], lines, query, comparisons + 1, false, motion or nil)
						for index = 2, #engines do
							local actual = scan(engines[index], lines, query, comparisons + 1, false, motion or nil)
							assert(
								vim.deep_equal(expected, actual),
								("mismatch %s %s %s %s\n%s\n%s"):format(
									fuzzy,
									tostring(unicode),
									query,
									index,
									vim.inspect(expected),
									vim.inspect(actual)
								)
							)
							comparisons = comparisons + 1
						end
					end
				end
				for _, case in ipairs(vim.json.decode(read(output .. "/" .. fuzzy .. ".coverage.json"))) do
					local prefixes = {}
					for _, spelling in ipairs(case.spellings) do
						for size = 1, #spelling do
							prefixes[spelling:sub(1, size)] = true
						end
						prefixes[spelling .. spelling] = true
						prefixes[spelling .. "q"] = true
					end
					for query in pairs(prefixes) do
						local text = { case.text, case.text .. case.text, case.text .. ";" .. case.text }
						local expected = scan(engines[1], text, query, comparisons + 1)
						for index = 2, #engines do
							local actual = scan(engines[index], text, query, comparisons + 1)
							assert(
								vim.deep_equal(expected, actual),
								("coverage mismatch %s %s %s"):format(case.text, query, index)
							)
							comparisons = comparisons + 1
						end
					end
				end
			end
		end
	end
	io.write(vim.json.encode({ comparisons = comparisons }), "\n")
	return
end

assert(task == "scan")
local mode, fuzzy, nlines = assert(arg[3]), assert(arg[4]), assert(tonumber(arg[5]))
local lines = {}
for i = 1, nlines do
	lines[i] = ("中国人民学习中文，ASCII flash_any 混合文本。"):rep(4)
end
collectgarbage("collect")
local start = os.clock()
local engine, profile_memory = book(mode, fuzzy)
local load_cpu_ms = (os.clock() - start) * 1000
local queries = { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
local runs, counts = {}, {}
for sample = 1, 25 do
	collectgarbage("collect")
	local wall, cpu = vim.uv.hrtime(), os.clock()
	counts[1] = #scan(engine, lines, queries[1], sample)
	local cold_wall, cold_cpu = (vim.uv.hrtime() - wall) / 1e6, (os.clock() - cpu) * 1000
	wall, cpu = vim.uv.hrtime(), os.clock()
	for i = 2, #queries do
		counts[i] = #scan(engine, lines, queries[i], sample, true)
	end
	runs[#runs + 1] = {
		cold_cpu_ms = cold_cpu,
		cold_wall_ms = cold_wall,
		typing_cpu_ms = (os.clock() - cpu) * 1000,
		typing_wall_ms = (vim.uv.hrtime() - wall) / 1e6,
	}
end
local result = {
	mode = mode,
	fuzzy = fuzzy,
	lines = nlines,
	counts = counts,
	load_cpu_ms = load_cpu_ms,
	profile_memory = profile_memory,
}
for _, key in ipairs({ "cold_cpu_ms", "cold_wall_ms", "typing_cpu_ms", "typing_wall_ms" }) do
	local values = {}
	for _, value in ipairs(runs) do
		values[#values + 1] = value[key]
	end
	table.sort(values)
	result[key] = values[math.ceil(#values / 2)]
end
io.write(vim.json.encode(result), "\n")

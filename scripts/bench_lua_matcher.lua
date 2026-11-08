-- ROOT LIBRARY OUT MODE CASE cold|warm ROWS; experimental callback, no Cursor/emit API.
vim.opt.runtimepath:prepend(assert(arg[1]))
local library, output, mode, case, phase, rows =
	assert(arg[2]), assert(arg[3]), assert(arg[4]), assert(arg[5]), assert(arg[6]), assert(tonumber(arg[7]))
local codes = {
	["中"] = "zhong",
	["国"] = "guo",
	["人"] = "ren",
	["民"] = "min",
	["学"] = "xue",
	["习"] = "xi",
	["文"] = "wen",
	["混"] = "hun",
	["合"] = "he",
	["本"] = "ben",
	["👩‍💻"] = "dev",
	["á"] = "accent",
	["🇨🇳"] = "flag",
	["👍🏽"] = "thumb",
}
if mode == "build" then
	local build = require("flash-any.build")
	build.binary({ sources = { { data = codes } }, output = output .. "/full.bin" })
	build.binary({ sources = {}, output = output .. "/literal.bin" })
	print("{}")
	return
end
local native = assert(package.loadlib(library, "luaopen_flash_any_native"))()
local micro_route, micro_count = mode:match("^multi_micro_(%a+)_(%d+)$")
if micro_route then
	local count = assert(tonumber(micro_count))
	local glyphs, input, rounds = { "中", "国", "á", "👩‍💻" }, "zhongguo", 100000
	local functions = {}
	for i = 1, count do
		local id = i
		functions[i] = function(glyph, value, pos)
			return pos + #value + id, #glyph
		end
	end
	local function batch(glyph, value, pos)
		local bytes, key = 0, 0
		for i = 1, #functions do
			local a, b = functions[i](glyph, value, pos)
			bytes, key = bytes + a, key + b
		end
		return bytes, key
	end
	local callback = micro_route == "direct" and functions or batch
	for _ = 1, 3 do
		native.bench_calls(callback, glyphs, input, rounds)
	end
	collectgarbage("collect")
	local samples, checksum = {}, nil
	for _ = 1, 7 do
		local start = vim.uv.hrtime()
		local found = native.bench_calls(callback, glyphs, input, rounds)
		samples[#samples + 1] = (vim.uv.hrtime() - start) / rounds
		assert(not checksum or checksum == found)
		checksum = found
	end
	print(vim.json.encode({ mode = mode, ns_per_group = samples, checksum = checksum }))
	return
end
if mode == "micro_c" or mode == "micro_lua" then
	local glyphs, input, rounds = { "中", "国", "á", "👩‍💻" }, "zhongguo", 500000
	local function callback(glyph, value, pos)
		return pos + #value, #glyph
	end
	local function run()
		if mode == "micro_c" then
			return native.bench_calls(callback, glyphs, input, rounds)
		end
		local sum = 0
		for i = 0, rounds - 1 do
			local a, b = callback(glyphs[i % #glyphs + 1], input, i % 3 + 1)
			sum = sum + a + b
		end
		return sum
	end
	for _ = 1, 5 do
		run()
	end
	collectgarbage("collect")
	local samples, checksum = {}, nil
	for _ = 1, 11 do
		local start = vim.uv.hrtime()
		local found = run()
		samples[#samples + 1] = (vim.uv.hrtime() - start) / rounds
		assert(not checksum or checksum == found)
		checksum = found
	end
	print(vim.json.encode({ mode = mode, ns_per_call = samples, checksum = checksum }))
	return
end

-- One full ASCII code per complete grapheme. Partial input returns its next byte.
local function make_matcher(map)
	return function(glyph, input, pos)
		local code = map[glyph]
		if not code then
			return
		end
		local size, common = #input - pos + 1, 0
		while common < size and common < #code and code:byte(common + 1) == input:byte(pos + common) do
			common = common + 1
		end
		if common == #code then
			return #code
		end
		if common == size then
			return nil, code:byte(common + 1)
		end
	end
end
local matcher = make_matcher(codes)
local function noop() end
---@alias BenchLuaMatcher fun(glyph: string, input: string, pos: integer): integer?, integer?
---@type BenchLuaMatcher|BenchLuaMatcher[]|nil
local callback = mode == "lua_match" and matcher or mode:find("^noop") and noop or nil
local route, body, matcher_count = mode:match("^multi_(%a+)_(%a+)_(%d+)$")
if route then
	local count = assert(tonumber(matcher_count))
	local keys, functions = vim.tbl_keys(codes), {}
	table.sort(keys)
	for i = 1, count do
		local map = {}
		for j, key in ipairs(keys) do
			if body == "repeat" or (body == "split" and (j - 1) % count + 1 == i) then
				map[key] = codes[key]
			end
		end
		functions[i] = body == "noop" and function() end or make_matcher(map)
	end
	local function batch(glyph, input, pos)
		local bytes, key
		for i = 1, #functions do
			local consumed, next_key = functions[i](glyph, input, pos)
			bytes, key = consumed or bytes, next_key or key
		end
		return bytes, key
	end
	callback = route == "direct" and functions or batch
end
local callback_mode = mode == "noop_glyph" and 1 or 2
local lua_only = mode == "lua_match" or body == "split" or body == "repeat"
local book = native.open(output .. (lua_only and "/literal.bin" or "/full.bin"))
local engine = book:new_state()
local lines = {}
for row = 1, rows do
	lines[row] = (
		case == "complex" and "á👩‍💻🇨🇳👍🏽 中国 á👩‍💻 "
		or "中国人民学习中文，ASCII flash_any 混合文本。"
	):rep(4)
end
local queries = case == "complex" and { "a", "ac", "acc", "accent", "accentd", "accentde", "accentdev", "dev" }
	or { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
local labels = { "a", "s", "d", "f", "j", "k", "l" }
local function scan(query, fn)
	return engine:scan(
		1,
		1,
		1,
		1,
		rows,
		not engine:has(1, 1, 1, 1, rows) and lines or nil,
		query,
		labels,
		nil,
		fn,
		callback_mode
	)
end
if phase == "warm" then
	for _ = 1, 30 do
		for _, query in ipairs(queries) do
			scan(query, callback)
		end
	end
end
collectgarbage("collect")
local samples, last = {}, {}
for _ = 1, phase == "cold" and 1 or 30 do
	local elapsed, cpu, counts = {}, {}, {}
	for i, query in ipairs(queries) do
		local start, clock = vim.uv.hrtime(), os.clock()
		local matches = scan(query, callback)
		elapsed[i], cpu[i] = (vim.uv.hrtime() - start) / 1e6, (os.clock() - clock) * 1000
		counts[i], last[i] = #matches, matches
	end
	samples[#samples + 1] = { elapsed_ms = elapsed, cpu_ms = cpu, counts = counts }
	assert(vim.deep_equal(samples[1].counts, counts))
end
local signatures, counts, calls = {}, {}, {}
for i, matches in ipairs(last) do
	counts[i] = #matches
	local canonical = {}
	for j, match in ipairs(matches) do
		local next_keys = vim.tbl_keys(match.next)
		table.sort(next_keys)
		canonical[j] = { match.pos, match.end_pos, match.label or "", next_keys }
	end
	signatures[i] = vim.fn.sha256(vim.inspect(canonical))
end
if callback then
	engine = book:new_state()
	for i, query in ipairs(queries) do
		local count = 0
		if type(callback) == "table" then
			local counted = {}
			for j, fn in ipairs(callback) do
				counted[j] = function(...)
					count = count + 1
					return fn(...)
				end
			end
			scan(query, counted)
		else
			scan(query, function(...)
				count = count + 1
				return callback(...)
			end)
		end
		calls[i] = count
	end
	local ok, err = pcall(scan, "~", function()
		error("callback-test-error")
	end)
	assert(not ok and tostring(err):find("callback%-test%-error"))
	assert(#scan(queries[1], callback) == counts[1], "scan failed after callback error")
end
print(vim.json.encode({
	mode = mode,
	case = case,
	phase = phase,
	rows = rows,
	samples = samples,
	signatures = signatures,
	counts = counts,
	callbacks = calls,
}))

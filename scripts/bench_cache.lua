-- LIBRARY PACKAGE ROWS typing_cached|typing_rebuild|result_cached|result_rescan
local library, path, rows, mode = assert(arg[1]), assert(arg[2]), assert(tonumber(arg[3])), assert(arg[4])
local native = assert(package.loadlib(library, "luaopen_flash_any_native"))()
local book = native.open(path)
local engine = book:new_state()
local lines = {}
for row = 1, rows do
	lines[row] = ("中国人民学习中文，ASCII flash_any 混合文本。"):rep(4)
end
local queries = mode:find("^typing") and { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
	or { "zhong" }
local labels = { "a", "s", "d", "f", "j", "k", "l" }
engine:scan(1, 1, 1, 1, rows, lines, queries[1], labels)
local function cycle()
	local elapsed, cpu, counts = {}, {}, {}
	for _, query in ipairs(queries) do
		local start, clock = vim.uv.hrtime(), os.clock()
		local matches = engine:scan(1, 1, 1, 1, rows, mode == "typing_rebuild" and lines or nil, query, labels)
		elapsed[#elapsed + 1] = (vim.uv.hrtime() - start) / 1e6
		cpu[#cpu + 1] = (os.clock() - clock) * 1000
		counts[#counts + 1] = #matches
	end
	return { elapsed_ms = elapsed, cpu_ms = cpu, counts = counts }
end
for _ = 1, 30 do
	cycle()
end
collectgarbage("collect")
local samples = {}
for _ = 1, 50 do
	samples[#samples + 1] = cycle()
	assert(vim.deep_equal(samples[1].counts, samples[#samples].counts))
end
print(vim.json.encode({ rows = rows, mode = mode, samples = samples }))

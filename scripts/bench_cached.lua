dofile("scripts/source_path.lua")
-- ROOT PACKAGE lua|binary pinyin|all cold|warm|new_jump ROWS
vim.opt.runtimepath:prepend(assert(arg[1]))
local path, backend, case, phase, rows =
	assert(arg[2]), assert(arg[3]), assert(arg[4]), assert(arg[5]), tonumber(arg[6]) or 40
local tsv = require("flash-any.tsv")
local make_loader, lookups = tsv.loader, 0
rawset(tsv, "loader", function(...)
	local load = make_loader(...)
	return function(...)
		lookups = lookups + 1
		return load(...)
	end
end)
local scan
package.loaded.flash = {
	jump = function(opts)
		scan = opts.matcher
	end,
}
if backend == "lua" and #vim.api.nvim_get_runtime_file("lua/flash-any/cursor.lua", false) == 0 then
	package.path = arg[1] .. "/tests/?.lua;" .. package.path
	local sources = require("reference.source").resolve(
		case == "all" and { "pinyin", "tiger", "wubi86", "nerdfont", "unicode" } or { "pinyin" }
	)
	local reference = require("reference.match")
	scan = function(win, state, range)
		return reference.get(win, state, range, sources)
	end
else
	local plugin = require("flash-any")
	plugin.setup(
		backend == "binary" and { binary = path }
			or { sources = case == "all" and { "pinyin", "tiger", "wubi86", "nerdfont", "unicode" } or { "pinyin" } }
	)
	plugin.jump()
end
local lines = {}
for i = 1, rows do
	lines[i] = ("中国人民学习中文，ASCII flash_any 混合文本。"):rep(4)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local queries = { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
local pattern = queries[1]
local function new_state()
	return {
		pattern = function()
			return pattern
		end,
		labels = function()
			return { "a", "s", "d", "f", "j", "k", "l" }
		end,
	}
end
local state = new_state()
local range = { from = { 1, 0 }, to = { rows, 0 } }
if phase ~= "cold" then
	for _ = 1, 30 do
		for _, value in ipairs(queries) do
			pattern = value
			scan(0, state, range)
		end
	end
end
collectgarbage("collect")
local samples = {}
local result_counts
for _ = 1, phase == "cold" and 1 or 30 do
	if phase == "new_jump" then
		state = new_state()
	end
	local elapsed, cpus, counts = {}, {}, {}
	for _, value in ipairs(queries) do
		pattern = value
		local start, cpu = vim.uv.hrtime(), os.clock()
		counts[#counts + 1] = #scan(0, state, range)
		elapsed[#elapsed + 1], cpus[#cpus + 1] = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
	end
	assert(not result_counts or vim.deep_equal(counts, result_counts))
	result_counts = counts
	samples[#samples + 1] = { elapsed_ms = elapsed, cpu_ms = cpus }
end
assert(lookups == 0, "common-character fixture unexpectedly queried TSV " .. lookups .. " times")
print(vim.json.encode({
	backend = backend,
	case = case,
	phase = phase,
	rows = rows,
	tsv_queries = lookups,
	counts = result_counts,
	samples = samples,
}))

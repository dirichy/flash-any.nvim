dofile("scripts/source_path.lua")
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
-- Run independently: nvim --clean -l scripts/bench_native.lua lua|binary PACKAGE cold|warm
vim.opt.runtimepath:prepend(arg[4] or vim.uv.cwd())
local mode, path, phase = assert(arg[1]), assert(arg[2]), arg[3] or "cold"
local lines = {}
for i = 1, 40 do
	lines[i] = ("中国人民学习中文，ASCII flash_any 混合文本。"):rep(4)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local pattern, state = "z", {}
state.pattern = function()
	return pattern
end
state.labels = function()
	return { "a", "s", "d", "f", "j", "k", "l" }
end
local range = { from = { 1, 0 }, to = { #lines, 0 } }
local start, cpu = vim.uv.hrtime(), os.clock()
local scan
if mode == "binary" then
	local native = require("flash-any.native")
	local engine = native.load(path)
	scan = function()
		return native.get(0, state, range, engine)
	end
else
	local sources = require("reference.source").resolve({ "pinyin" })
	local match = require("reference.match")
	scan = function()
		return match.get(0, state, range, sources)
	end
end
local load_ms, load_cpu = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
local queries = { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
if phase == "warm" then
	for _ = 1, 30 do
		for _, query in ipairs(queries) do
			pattern = query
			scan()
		end
	end
	collectgarbage("collect")
end
pattern = queries[1]
start, cpu = vim.uv.hrtime(), os.clock()
local count = #scan()
local first_ms, first_cpu = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
local elapsed, cpus = {}, {}
for i = 2, #queries do
	pattern = queries[i]
	start, cpu = vim.uv.hrtime(), os.clock()
	count = count + #scan()
	elapsed[#elapsed + 1], cpus[#cpus + 1] = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
end
print(vim.json.encode({
	mode = mode,
	phase = phase,
	load_ms = load_ms,
	load_cpu = load_cpu,
	first_ms = first_ms,
	first_cpu = first_cpu,
	continuation_ms = elapsed,
	continuation_cpu = cpus,
	matches = count,
}))

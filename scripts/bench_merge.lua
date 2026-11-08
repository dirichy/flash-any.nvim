dofile("scripts/source_path.lua")
-- nvim --clean -l scripts/bench_merge.lua ROOT OUT build|cold|warm CASE
vim.opt.runtimepath:prepend(assert(arg[1]))
local output, phase, case = assert(arg[2]), assert(arg[3]), arg[4]
local fixtures = {
	pinyin = { "pinyin" },
	all = { "pinyin", "tiger", "wubi86", "nerdfont", "unicode" },
	graphemes = {
		{
			data = {
				["á"] = { "accent", "acute" },
				["👩‍💻"] = { "dev", "coder" },
				["🇨🇳"] = "flag",
				["1️⃣"] = "one",
				["👍🏽"] = "thumb",
			},
			matcher = "initial",
		},
		{ data = { ["á"] = "aa", ["👩‍💻"] = "tech" }, matcher = "prefix" },
		{ data = { ["á"] = "fallback", ["Ω"] = "omega" }, fallback = true },
	},
}
if phase == "build" then
	for _, name in ipairs({ "pinyin", "all", "graphemes" }) do
		collectgarbage("collect")
		local start = vim.uv.hrtime()
		local sources, entries =
			require("flash-any.build").binary({ sources = fixtures[name], output = output .. "/" .. name .. ".bin" })
		print(vim.json.encode({
			case = name,
			entries = entries,
			sources = sources,
			bytes = assert(vim.uv.fs_stat(output .. "/" .. name .. ".bin")).size,
			build_ms = (vim.uv.hrtime() - start) / 1e6,
		}))
	end
	return
end
local lines = {}
for i = 1, 40 do
	lines[i] = (
		case == "graphemes" and "á👩‍💻🇨🇳1️⃣👍🏽 x Ω "
		or "中国人民学习中文，ASCII flash_any 混合文本。󰊢😀"
	):rep(4)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local queries = case == "graphemes" and { "a", "ac", "acc", "acce", "accen", "accent", "accentd", "accentdev" }
	or { "z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo" }
local query = queries[1]
local state = {
	pattern = function()
		return query
	end,
	labels = function()
		return { "a", "s", "d", "f", "j", "k", "l" }
	end,
}
local range = { from = { 1, 0 }, to = { #lines, 0 } }
collectgarbage("collect")
local heap = collectgarbage("count")
local start, cpu = vim.uv.hrtime(), os.clock()
local native = require("flash-any.native")
local book = native.load(output .. "/" .. case .. ".bin")
local load_ms, load_cpu = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
collectgarbage("collect")
local dictionary_kib = collectgarbage("count") - heap
if phase == "warm" then
	for _ = 1, 30 do
		for _, value in ipairs(queries) do
			query = value
			native.get(0, state, range, book)
		end
	end
	collectgarbage("collect")
end
local elapsed, cpus, counts = {}, {}, {}
for _, value in ipairs(queries) do
	query = value
	start, cpu = vim.uv.hrtime(), os.clock()
	counts[#counts + 1] = #native.get(0, state, range, book)
	elapsed[#elapsed + 1], cpus[#cpus + 1] = (vim.uv.hrtime() - start) / 1e6, (os.clock() - cpu) * 1000
end
print(vim.json.encode({
	case = case,
	phase = phase,
	load_ms = load_ms,
	load_cpu = load_cpu,
	dictionary_kib = dictionary_kib,
	elapsed_ms = elapsed,
	cpu_ms = cpus,
	counts = counts,
}))

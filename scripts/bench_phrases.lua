-- Complete native scan timing. Called by bench_phrases.py in isolated processes.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local library, data_root, name, mode = assert(arg[1]), assert(arg[2]), assert(arg[3]), arg[4]
local native = assert(package.loadlib(library, "luaopen_flash_any_native"))()
local started = vim.uv.hrtime()
local book = native.open(data_root .. "/" .. name .. ".bin")
local load_ms = (vim.uv.hrtime() - started) / 1e6
local file = assert(io.open(data_root .. "/workloads.json", "rb"))
local workloads = vim.json.decode(file:read("*a"))[name]
file:close()
if mode == "prepare" then
	io.write(vim.json.encode({ load_ms = load_ms }))
	return
end

local signatures, rows = {}, {}
for _, kind in ipairs({ "lines", "misses", "repeats" }) do
	local lines, queries = workloads[kind], workloads.queries
	local state = book:new_state()
	local function run(query, snapshot)
		return state:scan(0, 1, 1, 1, #lines, snapshot, query, { "a", "s", "d", "f", "j", "k", "l", ";" })
	end
	local counts, signature = {}, {}
	for i, query in ipairs(queries) do
		local found = run(query, lines)
		counts[i] = #found
		signature[#signature + 1] = query
		for _, match in ipairs(found) do
			local next_keys = vim.tbl_keys(match.next)
			table.sort(next_keys)
			signature[#signature + 1] = table.concat({
				match.pos[1],
				match.pos[2],
				match.end_pos[2],
				table.concat(next_keys, "\1"),
				match.label or "",
			}, "\2")
		end
	end
	signatures[kind] = vim.fn.sha256(table.concat(signature, "\3"))
	local function measure(rounds)
		local cpu, wall = os.clock(), vim.uv.hrtime()
		local total = 0
		for _ = 1, rounds do
			for _, query in ipairs(queries) do
				total = total + #run(query)
			end
		end
		return (os.clock() - cpu) * 1e3 / rounds / #queries, (vim.uv.hrtime() - wall) / 1e6 / rounds / #queries, total
	end
	measure(2)
	local rounds = 1
	while select(2, measure(rounds)) * rounds * #queries < 30 do
		rounds = rounds * 2
	end
	local cpu_samples, wall_samples = {}, {}
	for i = 1, 3 do
		collectgarbage("collect")
		cpu_samples[i], wall_samples[i] = measure(rounds)
	end
	table.sort(cpu_samples)
	table.sort(wall_samples)
	local bytes = 0
	for _, line in ipairs(lines) do
		bytes = bytes + #line
	end
	rows[#rows + 1] = {
		kind = kind,
		cpu_ms = cpu_samples[2],
		elapsed_ms = wall_samples[2],
		counts = counts,
		line_count = #lines,
		text_bytes = bytes,
		queries = queries,
	}
end
local status = assert(io.open("/proc/self/status", "rb"))
local memory = status:read("*a")
status:close()
io.write(vim.json.encode({
	load_ms = load_ms,
	rows = rows,
	signatures = signatures,
	rss_kib = tonumber(memory:match("VmRSS:%s+(%d+)")),
	peak_rss_kib = tonumber(memory:match("VmHWM:%s+(%d+)")),
}))

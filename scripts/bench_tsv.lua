-- Independent processes: nvim --clean -l scripts/bench_tsv.lua [root|offset]
-- Local lookup CPU only; no matcher, UI, or result caching. File pages are warmed.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local mode = arg[1] or "offset"
assert(mode == "root" or mode == "offset")
local path = vim.fn.tempname()
local file = assert(io.open(path, "wb"))
local keys = {}
for cp = 0x4E00, 0x4E00 + 4095 do
	local root = vim.fn.nr2char(cp)
	keys[#keys + 1] = root
	for _, suffix in ipairs({ "", "ab", "abc", "abd" }) do
		file:write(root, suffix, "\tcode\n")
	end
end
file:close()
local search = require("flash-any.tsv").loader(path)
local function run()
	for _, key in ipairs(keys) do
		local offset
		for _, suffix in ipairs({ "", "a", "ab", "abc" }) do
			local codes
			codes, offset = search(key .. suffix, mode == "offset" and offset or nil)
			assert(suffix == "a" or codes)
			assert(suffix == "abc" or offset ~= false)
		end
	end
end
run()
local start = os.clock()
for _ = 1, 3 do
	run()
end
print(("%s: %.2f ms / 49152 prefix queries"):format(mode, (os.clock() - start) * 1000))
vim.fn.delete(path)

-- One cold load per process: nvim --clean -l scripts/bench_binary_load.lua NAME lua|binary PATH
vim.opt.runtimepath:prepend(vim.uv.cwd())
local name, mode, path = assert(arg[1]), assert(arg[2]), arg[3]
assert(mode == "lua" or mode == "binary")
collectgarbage("collect")
local before = collectgarbage("count")
local start, cpu = vim.uv.hrtime(), os.clock()
local value
if mode == "binary" then
  value = require("flash-any.native").load(assert(path))
else
  value = require("flash-any.source").resolve({ name })
end
local cpu_ms = (os.clock() - cpu) * 1000
local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
collectgarbage("collect")
local retained_kib = collectgarbage("count") - before
assert(value)
io.write(vim.json.encode({name=name, mode=mode, load_ms=elapsed_ms, cpu_ms=cpu_ms, retained_kib=retained_kib}), "\n")

-- Invoked only by build.async via nvim --clean -l.
local path = assert(arg[1])
local input = assert(io.open(path, "rb"))
local request = vim.mpack.decode(input:read("*a"))
input:close()
vim.o.runtimepath = request.runtimepath
assert(request.kind == "binary" or request.kind == "table", "unknown builder")
local result = { require("flash-any.build")[request.kind](request.opts) }
local output = assert(io.open(path, "wb"))
output:write(vim.mpack.encode(result))
output:close()

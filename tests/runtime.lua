vim.opt.runtimepath:prepend(vim.uv.cwd())
if arg[1] == "build" then
	require("flash-any.build").binary({ sources = { { data = { ["甲"] = "x", ["乙"] = "y" } } }, output = arg[2] })
	return
end
local path = vim.fn.tempname() .. ".bin"
local built = vim.system({ vim.v.progpath, "--clean", "-l", "tests/runtime.lua", "build", path }):wait()
assert(built.code == 0, built.stderr)
local options
package.loaded.flash = {
	jump = function(opts)
		options = opts
	end,
}
local plugin = require("flash-any")
plugin.setup({ binary = path })
plugin.jump()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙" })
assert(#options.matcher(0, {
	pattern = function()
		return "xy"
	end,
}, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
for _, module in ipairs({ "cursor", "match", "source", "table", "grapheme", "grapheme_data", "tsv", "scope" }) do
	assert(package.loaded["flash-any." .. module] == nil, "runtime loaded build/legacy module: " .. module)
end
assert(package.loaded["reference.match"] == nil)
assert(not pcall(plugin.setup, { binary = path, matcher = function() end }))
vim.uv.fs_unlink(path)
print("runtime uses C without loading Lua scanners or build-time modules")

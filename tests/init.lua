vim.opt.runtimepath:prepend(vim.uv.cwd())
local jump, remote
package.loaded.flash = {
	jump = function(opts)
		jump = opts
		return opts
	end,
	remote = function(opts)
		remote = opts
		return opts
	end,
}
local plugin = require("flash-any")
local build = require("flash-any.build")
local path, other = vim.fn.tempname() .. ".bin", vim.fn.tempname() .. ".bin"
build.binary({ sources = { "pinyin" }, output = path })
build.binary({ sources = { { data = { ["中"] = "x" } } }, output = other })
assert(not pcall(plugin.jump) and not pcall(plugin.remote))
assert(not pcall(plugin.setup, {}))
assert(not pcall(plugin.setup, { binary = path, sources = "pinyin" }))
plugin.setup({ binary = path, labels = "abc", search = { wrap = false } })
plugin.jump()
assert(jump.labels == "abc" and jump.binary == nil and jump.sources == nil)
local matcher = jump.matcher
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国" })
local state = {
	pattern = function()
		return "zg"
	end,
}
assert(#matcher(0, state, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
plugin.remote()
assert(remote.matcher == matcher)
plugin.jump({ binary = other, labels = "xyz" })
assert(jump.labels == "xyz" and jump.search == nil and jump.matcher ~= matcher)
assert(#jump.matcher(0, {
	pattern = function()
		return "x"
	end,
}, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
plugin.jump()
assert(jump.matcher == matcher and jump.labels == "abc")
assert(package.loaded["flash-any.cursor"] == nil and package.loaded["flash-any.match"] == nil)
vim.uv.fs_unlink(path)
vim.uv.fs_unlink(other)
print("C-only runtime setup/jump/remote tests passed")

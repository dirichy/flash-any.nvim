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
local path = vim.fn.tempname() .. ".bin"
build.binary({ sources = { { data = { ["中"] = "zhong", ["国"] = "guo" }, matcher = "initial" } }, output = path })
assert(not pcall(plugin.jump) and not pcall(plugin.remote) and not pcall(plugin.search))
assert(not pcall(plugin.setup, {}))
assert(not pcall(plugin.setup, { binary = path, char = "yes" }))
assert(not pcall(plugin.setup, { binary = path, sources = "pinyin" }))
plugin.setup({ binary = path, labels = "abc", search = { wrap = false } })
plugin.jump()
assert(jump.labels == "abc" and jump.binary == nil and jump.sources == nil and jump.char == nil)
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
plugin.jump({ labels = "xyz", search = { forward = false } })
assert(jump.labels == "xyz" and jump.search.forward == false and jump.search.wrap == false)
assert(jump.matcher == matcher, "per-call Flash options must retain the setup dictionary")
plugin.remote({ labels = "remote", jump = { autojump = false } })
assert(remote.labels == "remote" and remote.jump.autojump == false and remote.matcher == matcher)
for _, method in ipairs({ plugin.jump, plugin.remote, plugin.search }) do
	for _, opts in ipairs({ { sources = {} }, { binary = path }, { char = true }, { matcher = function() end } }) do
		local ok, err = pcall(method, opts)
		local expected = opts.matcher and "custom matchers" or "setup()"
		assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
	end
end
plugin.jump()
assert(jump.matcher == matcher and jump.labels == "abc" and jump.search.wrap == false and jump.search.forward == nil)
local cache = vim.fn.tempname()
local cache_home, notify = vim.env.XDG_CACHE_HOME, vim.notify
vim.env.XDG_CACHE_HOME = cache
local warnings = 0
rawset(vim, "notify", function(message, level)
	if level == vim.log.levels.INFO then
		return
	end
	assert(level == vim.log.levels.WARN and message:find("inline data exceeds 200 entries", 1, true))
	warnings = warnings + 1
end)
local data = {}
for i = 1, 200 do
	data[vim.fn.nr2char(0x20000 + i)] = { "x", "alias" }
end
require("flash-any.native").load(nil, { { data = data } })
assert(warnings == 0, "200 entries should not warn; aliases must not count separately")
data["甲"] = "x"
require("flash-any.native").load(nil, { { data = { codes = data } } })
assert(warnings == 1, "large structured data should warn")
require("flash-any.native").load(nil, { { data = data } })
assert(warnings == 1, "large data warning should appear only once per process")
rawset(vim, "notify", notify)
vim.env.XDG_CACHE_HOME = cache_home
vim.fn.delete(cache, "rf")
vim.uv.fs_unlink(path)
print("C-only runtime setup/jump/remote tests passed")

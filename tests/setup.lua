-- A failed Flash integration must allow retry; a second setup must not alter a working configuration.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local path = vim.fn.tempname() .. ".bin"
require("flash-any.build").binary({ sources = { { data = { ["中"] = "x" } } }, output = path })
local calls, fail = 0, true
local plugin
package.loaded["flash.config"] = {
	get = function()
		return { modes = { char = { enabled = false, multi_line = false } } }
	end,
}
package.loaded.flash = {
	jump = function(opts)
		return opts
	end,
	setup = function(opts)
		calls = calls + 1
		assert(opts.modes.char.enabled == false and opts.modes.char.multi_line == false)
		assert(opts.modes.char.matcher == plugin.char)
		local ok, err = pcall(plugin.setup, { binary = path })
		assert(not ok and tostring(err):find("only be called once", 1, true), "reentrant setup must fail")
		assert(not pcall(plugin.jump), "unfinished setup must not publish runtime options")
		if fail then
			error("Flash setup fixture failed")
		end
	end,
}
plugin = require("flash-any")
local ok, err = pcall(plugin.setup, { binary = path, char = true })
assert(not ok and tostring(err):find("Flash setup fixture failed", 1, true))
assert(not pcall(plugin.jump), "failed setup must not commit partial options")
fail = false
plugin.setup({ binary = path, char = true, labels = "ab" })
ok, err = pcall(plugin.setup, { binary = path, char = false })
assert(not ok and tostring(err):find("only be called once", 1, true))
assert(plugin.jump().labels == "ab", "rejected setup must preserve the original options")
assert(calls == 2, "duplicate setup must not touch Flash integration")
vim.uv.fs_unlink(path)
print("single setup, reentrancy, failed initialization retry and atomic publication tests passed")

vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
vim.fn.writefile({
	"return function(opts)",
	"  assert(vim.g.main_process_only == nil)",
	"  vim.uv.sleep(opts.delay or 300)",
	"  assert(not opts.fail, 'fixture build failure')",
	"  return { data = { ['中'] = { opts.code } } }",
	"end",
}, root .. "/lua/flash-any/sources/slow.lua")
vim.opt.runtimepath:append(root)
vim.g.main_process_only = true
local notifications = {}
---@type table?
local options
rawset(vim, "notify", function(message, level)
	notifications[#notifications + 1] = { message, level }
end)
package.loaded.flash = {
	jump = function(opts)
		options = opts
	end,
}
local plugin = require("flash-any")
local builds, active = 0, 0
local builder = require("flash-any.build")
local async = builder.async
rawset(builder, "async", function(kind, opts, done)
	builds, active = builds + 1, active + 1
	return async(kind, opts, function(...)
		active = active - 1
		done(...)
	end)
end)
local function setup(code, delay, fail)
	plugin.setup({
		sources = { { name = "slow", code = code, delay = delay, fail = fail } },
		binary = root .. "/" .. code .. ".bin",
	})
	plugin.jump()
	return assert(options).matcher
end
local query = "中"
local state = {
	pattern = function()
		return query
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中 abc" })
local first = setup("x", 300)
assert(active == 1 and notifications[1][1]:find("building dictionary", 1, true))
-- Main-loop timers must run while the worker is still sleeping.
local responsive = false
vim.defer_fn(function()
	responsive = active == 1
end, 20)
assert(
	vim.wait(200, function()
		return responsive
	end),
	"build blocked the main loop"
)
assert(#first(0, state, range) == 1, "first build must retain Unicode literal matching")
query = "x"
assert(#first(0, state, range) == 0)
assert(#notifications == 2, "pending notification should occur once per search")
assert(notifications[2][1]:find("literal matching only", 1, true))
assert(vim.wait(10000, function()
	return active == 0
end))
assert(#first(0, state, range) == 1, "worker result was not installed")
local second = setup("y", 300)
assert(#second(0, state, range) == 1, "reconfiguration must retain old dictionary")
assert(notifications[#notifications][1]:find("previous dictionary", 1, true))
assert(vim.wait(10000, function()
	return active == 0
end))
query = "y"
assert(#second(0, state, range) == 1)
query = "x"
assert(#first(0, state, range) == 1, "existing matcher must keep its snapshot")
local failed = setup("bad", 100, true)
assert(vim.wait(10000, function()
	return active == 0
end))
query = "y"
assert(#failed(0, { pattern = state.pattern }, range) == 1)
assert(notifications[#notifications][1]:find("build failed; using previous dictionary", 1, true))
assert(not vim.uv.fs_stat(root .. "/bad.bin"))
-- Duplicate requests share one worker; an older completion cannot replace newer setup.
setup("old", 500)
local current = setup("new", 100)
setup("new", 100)
assert(builds == 5, "duplicate setup spawned another worker")
assert(vim.wait(10000, function()
	return active == 0
end))
query = "new"
assert(#current(0, { pattern = state.pattern }, range) == 1)
plugin.jump()
assert(#assert(options).matcher(0, { pattern = state.pattern }, range) == 1)
assert(package.loaded["flash-any.sources.slow"] == nil, "factory ran in main process")
vim.fn.delete(root, "rf")
print("background build responsiveness, literal/old fallbacks, failures and concurrent setup passed")

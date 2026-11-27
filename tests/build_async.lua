vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
vim.fn.writefile({
	"return function(opts)",
	"  assert(vim.g.main_process_only == nil)",
	"  local input = dofile(opts.config)",
	"  vim.uv.sleep(input.delay or 300)",
	"  assert(not input.fail, 'fixture build failure')",
	"  return { data = { ['中'] = { input.code } } }",
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
local input = root .. "/input.lua"
local function write(code, delay, fail)
	vim.fn.writefile(
		vim.split("return " .. vim.inspect({ code = code, delay = delay, fail = fail }), "\n", { plain = true }),
		input
	)
end
local query = "中"
local state = {
	pattern = function()
		return query
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中 abc" })
write("x", 300)
plugin.setup({ sources = { { name = "slow", config = input } }, binary = root .. "/dictionary.bin" })
plugin.jump()
local first = assert(options).matcher
assert(active == 1 and notifications[1][1]:find("building dictionary", 1, true))
assert(not pcall(plugin.setup, { sources = {} }), "setup must also reject duplicates while building")
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
assert(#first(0, state, range) == 0, "unchanged query must retain its literal snapshot")
assert(#first(0, { pattern = state.pattern }, range) == 1, "a new search must use the completed dictionary")
query = "xx"
first(0, state, range)
query = "x"
assert(#first(0, state, range) == 1, "changed input must select the completed dictionary")
local pinned = {
	pattern = function()
		return "x"
	end,
}
assert(#first(0, pinned, range) == 1)
write("y", 300)
plugin.rebuild()
local second = first
state = { pattern = state.pattern }
assert(#second(0, state, range) == 1, "rebuild must retain old dictionary")
assert(notifications[#notifications][1]:find("previous dictionary", 1, true))
assert(vim.wait(10000, function()
	return active == 0
end))
query = "y"
assert(#second(0, state, range) == 1)
query = "x"
assert(#first(0, pinned, range) == 1, "existing query must keep its snapshot")
write("bad", 100, true)
plugin.rebuild()
local failed = first
assert(vim.wait(10000, function()
	return active == 0
end))
query = "y"
assert(#failed(0, { pattern = state.pattern }, range) == 1)
assert(notifications[#notifications][1]:find("build failed; using previous dictionary", 1, true))
assert(vim.uv.fs_stat(root .. "/dictionary.bin"), "failed rebuild must retain the existing binary")
-- Repeated requests reuse one worker, and a second setup is rejected.
write("new", 100)
plugin.rebuild()
plugin.rebuild()
assert(not pcall(plugin.setup, { sources = {} }))
assert(builds == 4, "duplicate rebuild spawned another worker")
assert(vim.wait(10000, function()
	return active == 0
end))
query = "new"
assert(#first(0, { pattern = state.pattern }, range) == 1)
assert(package.loaded["flash-any.sources.slow"] == nil, "factory ran in main process")
vim.fn.delete(root, "rf")
print("background build responsiveness, literal/old fallbacks, failures and repeated rebuild passed")

#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(arg[1] or (vim.uv.cwd() .. "/.dev/flash.nvim"))
vim.o.lines = 40
vim.o.columns = 100
local State = require("flash.state")
local Search = require("flash-any.search")
local lines = {}
for _ = 1, 1000 do
	lines[#lines + 1] = "text"
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local visits, switched = {}, false
local get, finish = Search.new(function(win, state, range)
	local pattern, row = state.pattern(), range.from[1]
	assert(not switched or pattern ~= "old", "a cancelled query resumed")
	visits[pattern] = (visits[pattern] or 0) + 1
	-- Make each batch observable without depending on the machine's scan speed.
	local until_time = vim.uv.hrtime() + 100000
	while vim.uv.hrtime() < until_time do
	end
	if pattern == "new" and row == 900 then
		return { { win = win, pos = { row, 0 }, end_pos = { row, 0 } } }
	end
	return {}
end)
local state = State.new({
	matcher = get,
	labels = "",
	labeler = function() end,
	search = { mode = "search", incremental = true, multi_window = false },
})
state:update({ pattern = "old" })
assert(not visits.old, "typing must not scan synchronously")
assert(vim.wait(1000, function()
	return (visits.old or 0) > 0
end, 1))
assert(visits.old < 1000, "the first batch must yield")
switched = true
state:update({ pattern = "new" })
assert(not visits.new, "a new query must wait for its own batch")
local target = finish(state)
assert(target and target.pos[1] == 900, "Enter must finish a pending query synchronously")
state:hide()
local completed = visits.new
vim.wait(20, function()
	return false
end, 1)
assert(visits.new == completed, "completed/hidden jobs must stop")

-- Esc stops pending work, and buffer edits discard the old snapshot.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
switched = false
state = State.new({
	matcher = get,
	labels = "",
	labeler = function() end,
	search = { mode = "search", incremental = true, multi_window = false },
})
state:update({ pattern = "old" })
state:hide()
local cancelled = visits.old
vim.wait(20, function()
	return false
end, 1)
assert(visits.old == cancelled)
state:show()
state:update({ pattern = "new" })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
assert(not finish(state), "Enter must refresh an edited buffer instead of jumping to row 900")
state:hide()
assert(vim.v.errmsg == "", vim.v.errmsg)
print("asynchronous search scheduling, cancellation and commit tests passed")

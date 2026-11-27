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
-- Complete dictionary construction between coroutine batches. Both preview completion
-- and Enter must finish with the same dictionary that scanned the first batch.
local plugin = require("flash-any")
local build = require("flash-any.build")
local native = require("flash-any.native")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local old_path = root .. "/old.bin"
build.binary({ sources = { { data = { ["中"] = "x" } } }, output = old_path })
local async, scan, loop = build.async, native.get, State.loop
for _, commit in ipairs({ false, true }) do
	local complete, enter
	rawset(build, "async", function(_, opts, done)
		complete = function()
			local result = { build.binary(opts) }
			done(nil, result)
		end
	end)
	rawset(State, "loop", function(_, opts)
		enter = opts.actions["<CR>"]
	end)
	plugin.setup({ binary = old_path })
	plugin.setup({ sources = { { data = { ["国"] = "x" } } }, binary = root .. "/" .. tostring(commit) .. ".bin" })
	local dictionaries, scanned = {}, 0
	rawset(native, "get", function(win, current, range, dictionary)
		scanned = scanned + 1
		dictionaries[#dictionaries + 1] = dictionary
		local until_time = vim.uv.hrtime() + 100000
		while vim.uv.hrtime() < until_time do
		end
		return scan(win, current, range, dictionary)
	end)
	local text = {}
	for _ = 1, 1000 do
		text[#text + 1] = "中国"
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	local current = plugin.search()
	current:update({ pattern = "x", check_jump = false })
	local win = current.win
	local view = current.cache:get(win)
	local range = { from = { view.topline, 0 }, to = { view.botline + 1, 0 } }
	assert(vim.wait(1000, function()
		return scanned > 0
	end, 1))
	assert(current:get_matcher(win):find({ pos = current.pos }) == nil, "dictionary test must pause between batches")
	local first_batch = scanned
	assert(complete)()
	if commit then
		assert(enter)(current)
	else
		assert(vim.wait(10000, function()
			return current:get_matcher(vim.api.nvim_get_current_win()):find({ pos = current.pos }) ~= nil
		end, 1))
	end
	assert(scanned > first_batch, "the same job must resume after dictionary construction")
	for _, dictionary in ipairs(dictionaries) do
		assert(dictionary == dictionaries[1], "one search job mixed dictionary snapshots")
	end
	local results = current.opts.matcher(win, current, range)
	assert(#results > 0, "completed query must publish its matches")
	for _, match in ipairs(results) do
		assert(match.pos[2] == 0, "current query must keep old dictionary results")
	end
	if not commit then
		local old = dictionaries[1]
		-- A forced refresh with unchanged input must retain the query snapshot.
		current:update({ force = true, check_jump = false })
		assert(dictionaries[#dictionaries] == old)
		dictionaries = {}
		current:update({ pattern = "xx", check_jump = false })
		assert(vim.wait(1000, function()
			return #dictionaries > 0
		end, 1))
		assert(dictionaries[1] ~= old, "changed input must select the new dictionary")
		current:update({ pattern = "x", check_jump = false })
		assert(
			vim.wait(10000, function()
				local matches = current.opts.matcher(win, current, range)
				return matches[1] and matches[1].pos[2] == 3
			end, 1),
			"new query did not publish new dictionary results"
		)
	end
	current:hide()
end
rawset(build, "async", async)
rawset(native, "get", scan)
rawset(State, "loop", loop)
vim.fn.delete(root, "rf")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("asynchronous search scheduling, cancellation, dictionary snapshots and commit tests passed")

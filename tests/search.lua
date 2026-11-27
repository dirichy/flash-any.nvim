#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(arg[1] or (vim.uv.cwd() .. "/.dev/flash.nvim"))
vim.o.lines = 40
vim.o.columns = 100
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local fixture = require("fixture")
local plugin = require("flash-any")
local base = {
	sources = { { data = { ["中"] = "vs", ["国"] = { "go", "other" } } } },
	labels = "abc",
	jump = { autojump = true },
}
fixture.setup(base)

local function search(lines, pos, input, expected, opts)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, pos)
	vim.api.nvim_feedkeys(vim.keycode(input), "t", false)
	local state = plugin.search(opts)
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), expected), vim.inspect(vim.api.nvim_win_get_cursor(0)))
	assert(not state.visible and state.opts.labels == "")
	for _, match in ipairs(state.results) do
		assert(not match.label)
	end
	return state
end

-- Full queries must reach the matcher even with a unique intermediate result.
local state = search({ "a中国 ab abc" }, { 1, 0 }, "vsgo<CR>", { 1, 1 })
assert(state.pattern() == "vsgo")
search({ "a中 中" }, { 1, 1 }, "vs<CR>", { 1, 5 })
search({ "a中 中" }, { 1, 5 }, "vs<CR>", { 1, 1 })
search({ "a中国 ab abc" }, { 1, 0 }, "abc<CR>", { 1, 11 })
search({ "a中国" }, { 1, 0 }, "vsx<BS>go<CR>", { 1, 1 })
search({ "a[b a.b" }, { 1, 0 }, "[b<CR>", { 1, 1 })
search({ "a中国" }, { 1, 0 }, "vs<BS><CR>", { 1, 1 })
search({ "a中国" }, { 1, 0 }, "vs<BS><BS><CR>", { 1, 0 })
search({ "a中国" }, { 1, 0 }, "vsgo<Esc>", { 1, 0 })
search({ "a中国" }, { 1, 0 }, "vs<BS><BS>go<CR>", { 1, 4 })
-- Zero visible matches must not terminate input; the target can be offscreen.
local lines = { "start" }
for _ = 2, 150 do
	lines[#lines + 1] = ""
end
lines[150] = "中国"
search(lines, { 1, 0 }, "vsgo<CR>", { 150, 0 })
search(lines, { 1, 0 }, "vsgo<Esc>", { 1, 0 })
search({ "a中" }, { 1, 0 }, "vsnomatch<CR>", { 1, 0 })
search({ "nothing" }, { 1, 2 }, "missing<BS><CR>", { 1, 2 })
search({ "aX x" }, { 1, 0 }, "x<CR>", { 1, 3 })
vim.go.ignorecase = true
search({ "aX x" }, { 1, 0 }, "x<CR>", { 1, 1 })
vim.go.smartcase = true
search({ "ax X" }, { 1, 0 }, "X<CR>", { 1, 3 })
vim.go.ignorecase, vim.go.smartcase = false, false
-- Per-call Flash options reuse the configured dictionary.
search({ "a中国" }, { 1, 0 }, "other<CR>", { 1, 4 })
search({ "a中国" }, { 1, 0 }, "vs<CR>", { 1, 1 })
search({ "a中 中" }, { 1, 5 }, "vs<CR>", { 1, 1 }, { search = { forward = false, wrap = false } })
search({ "a中 中" }, { 1, 5 }, "vs<CR>", { 1, 5 }, { search = { wrap = false } })
-- Matches in another window must not steal the current buffer's search target.
vim.cmd("vnew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国" })
vim.cmd("wincmd p")
local win = vim.api.nvim_get_current_win()
search({ "a中国" }, { 1, 0 }, "vsgo<CR>", { 1, 1 })
assert(vim.api.nvim_get_current_win() == win)
vim.cmd("only!")
-- Preview actually moves before confirmation, and cancellation restores the view.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a中国" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local State = require("flash.state")
local loop = State.loop
State.loop = function(self)
	self:update({ pattern = "vsgo" })
	assert(vim.wait(1000, function()
		return vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 })
	end, 1))
	self:restore()
	self:hide()
end
plugin.search()
State.loop = loop
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }))
assert(vim.v.errmsg == "", vim.v.errmsg)
print("real Flash search integration tests passed")

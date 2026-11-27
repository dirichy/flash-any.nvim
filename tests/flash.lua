#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
-- Tests run in a fresh Neovim process with a local checkout of flash.nvim.
vim.opt.runtimepath:prepend(arg[1] or (vim.uv.cwd() .. "/.dev/flash.nvim"))
vim.o.lines = 40
vim.o.columns = 100
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local fixture = require("fixture")
local plugin = require("flash-any")
local State = require("flash.state")
local loop = State.loop
rawset(State, "loop", function() end)
fixture.setup({ sources = { { data = { ["甲"] = "x", ["乙"] = "x", ["甲乙"] = "x" } } } })
local state
-- Adjacent scalar matches must keep distinct default after-labels even when a
-- same-code phrase spans both. Exercise Flash's actual extmarks and jump target.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|甲乙|" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

state = plugin.jump()
state:update({ pattern = "x", check_jump = false, force = true })
assert(#state.results == 2)
local labels = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, state.ns, 0, -1, { details = true })) do
	if mark[4].virt_text then
		labels[mark[3]] = mark[4].virt_text[1][1]
	end
end
for index, col in ipairs({ 1, 4 }) do
	local match = state.results[index]
	assert(match.pos[2] == col and match.end_pos[2] == col)
	assert(labels[col + 3] == match.label, "each scalar must have its own trailing label")
end
state:jump(state.results[2])
assert(vim.api.nvim_win_get_cursor(0)[2] == 4, "the second label must jump to 乙")
state:hide()
State.loop = loop
-- Real input arrives by codepoint. Keep previewing until the complete grapheme is entered.
for _, text in ipairs({ "👩‍💻x", "éx", "1️⃣", "🇨🇳", "中国" }) do
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|" .. text .. "|" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.api.nvim_feedkeys(text .. string.char(27), "t", true)

	state = plugin.jump()
	assert(state.pattern() == text and #state.results == 1, vim.inspect({ text, state.pattern(), state.results }))
end
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Flash label placement and codepoint input regressions passed")

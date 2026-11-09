#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
-- Tests run in a fresh Neovim process with a local checkout of flash.nvim.
vim.opt.runtimepath:prepend(arg[1] or (vim.uv.cwd() .. "/.dev/flash.nvim"))
vim.o.lines = 40
vim.o.columns = 100
local lines = { "a中国人民 😀", "中国 abcd", "rare 㐀" }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local fixture = require("fixture")
local plugin = require("flash-any")
local State = require("flash.state")
local loop = State.loop
State.loop = function() end
fixture.setup({ sources = { { data = { ["中"] = "vs", ["国"] = "go", ["珠"] = "vu", ["㐀"] = "qq" } } } })
local state = plugin.jump()
assert(state.opts.matcher and state.opts.labeler)
for _, pattern in ipairs({ "v", "vs", "vsg", "vsgo", "a", "ab", "q", "qq", "中", "中国", "中go", "vs国" }) do
	state:update({ pattern = pattern, check_jump = false, force = true })
	if
		pattern == "v"
		or pattern == "vs"
		or pattern == "中"
		or pattern == "中国"
		or pattern == "中go"
		or pattern == "vs国"
	then
		assert(#state.results == 2)
	end
	if pattern == "vsgo" then
		assert(#state.results == 2 and state.results[1].end_pos[2] == 4)
	end
	if pattern == "qq" then
		assert(#state.results == 1)
	end
end
state:hide()
-- New Flash searches read current options even when the query is unchanged.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "v V 中" })
for _, case in ipairs({
	{ false, false, "v", 2 },
	{ true, false, "v", 3 },
	{ true, true, "v", 3 },
	{ true, true, "V", 1 },
	{ true, false, "V", 2 },
}) do
	vim.go.ignorecase, vim.go.smartcase = case[1], case[2]
	state = plugin.jump()
	state:update({ pattern = case[3], check_jump = false, force = true })
	assert(#state.results == case[4], vim.inspect(state.results))
	state:hide()
end
vim.go.ignorecase, vim.go.smartcase = false, false
-- Verify multi-codepoint ranges against the real Flash state and highlighter.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "👩‍💻x" })
state = plugin.jump(fixture.config({ sources = { { data = { ["👩‍💻"] = "dev" } } } }))
for _, pattern in ipairs({ "d", "de", "dev", "devx", "👩‍💻", "👩‍💻x" }) do
	state:update({ pattern = pattern, check_jump = false, force = true })
	assert(#state.results == 1, vim.inspect(state.results))
	assert(state.results[1].pos[2] == 0)
	assert(state.results[1].end_pos[2] == (pattern:sub(-1) == "x" and 11 or 7))
end
state:update({ pattern = "👩", check_jump = false, force = true })
assert(#state.results == 1 and state.results[1].end_pos[2] == 7, "literal prefixes keep the whole emoji")
state:hide()
-- Bundled Latin data integrates with the real state and consumes combining suffixes.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "café æx" })
vim.go.ignorecase = true
state = plugin.jump(fixture.config({ sources = { "latin" } }))
state:update({ pattern = "CAFE AEX", check_jump = false, force = true })
assert(#state.results == 1 and state.results[1].end_pos[2] == #"café æx" - 1)
vim.go.smartcase = true
state:update({ pattern = "CAFE", check_jump = false, force = true })
assert(#state.results == 0)
state:hide()
vim.go.ignorecase, vim.go.smartcase = false, false
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
State.loop = loop
-- Exercise the real input loop, including a next key that must not become a label.
vim.api.nvim_feedkeys("vs" .. string.char(27), "t", false)
state = plugin.jump()
assert(state.pattern() == "vs" and #state.results == 2)
assert(not state.visible)
-- Real input arrives by codepoint. Keep previewing until the complete grapheme is entered.
for _, text in ipairs({ "👩‍💻x", "éx", "1️⃣", "🇨🇳", "中国" }) do
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|" .. text .. "|" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.api.nvim_feedkeys(text .. string.char(27), "t", true)
	state = plugin.jump(fixture.config({ sources = {} }))
	assert(state.pattern() == text and #state.results == 1, vim.inspect({ text, state.pattern(), state.results }))
end
assert(vim.v.errmsg == "", vim.v.errmsg)
print("real Flash integration tests passed")

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
rawset(State, "loop", function() end)
local base = { sources = { { data = { ["中"] = "vs", ["国"] = "go", ["珠"] = "vu", ["㐀"] = "qq" } } } }
fixture.setup(base)
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
-- Adjacent scalar matches must keep distinct default after-labels even when a
-- same-code phrase spans both. Exercise Flash's actual extmarks and jump target.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|甲乙|" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
fixture.setup({ sources = { { data = { ["甲"] = "x", ["乙"] = "x", ["甲乙"] = "x" } } } })
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
-- New Flash searches read current options even when the query is unchanged.
fixture.setup(base)
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
fixture.setup({ sources = { { data = { ["👩‍💻"] = "dev" } } } })
state = plugin.jump()
for _, pattern in ipairs({ "d", "de", "dev", "devx", "👩‍💻", "👩‍💻x" }) do
	state:update({ pattern = pattern, check_jump = false, force = true })
	assert(#state.results == 1, vim.inspect(state.results))
	assert(state.results[1].pos[2] == 0)
	assert(state.results[1].end_pos[2] == (pattern:sub(-1) == "x" and 11 or 7))
end
state:update({ pattern = "👩", check_jump = false, force = true })
assert(#state.results == 1 and state.results[1].end_pos[2] == 7, "literal prefixes keep the whole emoji")
state:hide()
-- Word codes and their continuations use the same real Flash result ranges.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国人民 中国" })
fixture.setup({
	sources = { { data = { ["中国"] = "zg", ["中国人民"] = "zgrm", ["人民"] = "rm" } } },
})
state = plugin.jump()
for _, case in ipairs({ { "zg", 2, 3 }, { "zgrm", 1, 9 } }) do
	state:update({ pattern = case[1], check_jump = false, force = true })
	assert(#state.results == case[2], vim.inspect(state.results))
	assert(state.results[1].pos[2] == 0 and state.results[1].end_pos[2] == case[3])
end
state:hide()
-- Bundled Latin data integrates with the real state and consumes combining suffixes.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "café æx" })
vim.go.ignorecase = true
fixture.setup({ sources = { "latin" } })
state = plugin.jump()
state:update({ pattern = "CAFE AEX", check_jump = false, force = true })
assert(#state.results == 1 and state.results[1].end_pos[2] == #"café æx" - 1)
vim.go.smartcase = true
state:update({ pattern = "CAFE", check_jump = false, force = true })
assert(#state.results == 0)
state:hide()
vim.go.ignorecase, vim.go.smartcase = false, false
fixture.setup(base)
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
	fixture.setup({ sources = {} })
	state = plugin.jump()
	assert(state.pattern() == text and #state.results == 1, vim.inspect({ text, state.pattern(), state.results }))
end
-- A real Flash session can preview literals while a worker builds, then use its result.
local pending_root = vim.fn.tempname()
vim.fn.mkdir(pending_root, "p")
vim.fn.writefile({ "中\tx" }, pending_root .. "/input.tsv")
vim.fn.writefile({ "return function(codes) vim.uv.sleep(300); return codes end" }, pending_root .. "/converter.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|中|" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
rawset(State, "loop", function() end)
plugin.setup({
	sources = { { file = pending_root .. "/input.tsv", converter = pending_root .. "/converter.lua" } },
	binary = pending_root .. "/out.bin",
})
state = plugin.jump()
state:update({ pattern = "中", check_jump = false, force = true })
assert(#state.results == 1)
assert(
	vim.wait(10000, function()
		-- Flash may reuse results for unchanged input; exercise a new query after loading.
		state:update({ pattern = "", check_jump = false, force = true })
		state:update({ pattern = "x", check_jump = false, force = true })
		return #state.results == 1
	end),
	"background dictionary did not become usable in Flash"
)
state:hide()
State.loop = loop
vim.fn.delete(pending_root, "rf")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("real Flash integration tests passed")

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
local Char = require("flash.plugins.char")
local Pos = require("flash.search.pos")
require("flash").setup({ modes = { char = { matcher = plugin.char, multi_line = false } } })
fixture.setup({ sources = { { name = "pinyin", scheme = "flypy" } } })

local function reset(lines, pos)
	if Char.state then
		Char.state:hide()
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, pos or { 1, 0 })
end

local function keys(input, pos)
	vim.api.nvim_feedkeys(input, "xt", false)
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), pos), vim.inspect(vim.api.nvim_win_get_cursor(0)))
end

reset({ "a中珠v end" })
keys("fv", { 1, 1 })
keys("f", { 1, 4 })
keys(";", { 1, 7 })
keys(",", { 1, 4 })
reset({ "a中珠v end" })
keys("2fv", { 1, 4 })
reset({ "a中珠v end" }, { 1, 7 })
keys("Fv", { 1, 4 })
keys(";", { 1, 1 })
reset({ "a国中珠 end" })
keys("tv", { 1, 1 }) -- Stop on the previous UTF-8 character.
keys(";", { 1, 4 })
reset({ "a国中珠 end" }, { 1, 11 })
keys("Tv", { 1, 10 })
keys(";", { 1, 7 })
reset({ "a中珠v end" })
keys("dfv", { 1, 0 })
assert(vim.api.nvim_get_current_line() == "珠v end")

reset({ "abc", "中" })
keys("fv", { 1, 0 }) -- multi_line=false must not find the next line.
require("flash").setup({ modes = { char = { matcher = plugin.char, multi_line = true } } })
local lines = { "a" }
for _ = 1, 100 do
	lines[#lines + 1] = "nothing"
end
lines[#lines + 1] = "中"
reset(lines)
keys("fv", { 102, 0 }) -- Counts and repeats can find offscreen targets too.

-- Instrument a real Flash state: drawing and nearby jumps must not touch far rows.
local visited, allow_far = {}, false
fixture.setup({ sources = { { data = { ["甲"] = "v", ["乙"] = "v", ["丙"] = "v", ["终"] = "v" } } } })
lines = {}
for _ = 1, 1000 do
	lines[#lines + 1] = ""
end
lines[1], lines[2], lines[70], lines[140], lines[900] = "a", "甲", "乙", "丙", "终"
reset(lines)
vim.cmd("normal! zt")
Char.motion = "f"
local get_lines = vim.api.nvim_buf_get_lines
rawset(vim.api, "nvim_buf_get_lines", function(buf, first, after, strict)
	if after == first + 1 then
		local row = first + 1
		assert(row ~= 900 or allow_far, "eagerly fetched a distant target")
		visited[row] = (visited[row] or 0) + 1
	end
	return get_lines(buf, first, after, strict)
end)
local state = require("flash.state").new({ mode = "char", matcher = plugin.char, pattern = "v" })
local matcher = state:get_matcher(vim.api.nvim_get_current_win())
assert(visited[2] and not visited[70], vim.inspect(visited))
assert(matcher:find({ pos = Pos({ 1, 0 }), count = 2, forward = true, wrap = false }).pos[1] == 70)
assert(visited[70] == 1 and not visited[140])
assert(matcher:find({ pos = Pos({ 100, 0 }), forward = false, wrap = false }).pos[1] == 70)
assert(visited[70] == 1)
assert(matcher:find({ pos = Pos({ 70, 0 }), count = 0 }).pos[1] == 70)
assert(matcher:find({ pos = Pos({ 70, 0 }), current = true, wrap = false }).pos[1] == 70)
local found = matcher:find({ pos = Pos({ 1, 0 }), wrap = false })
assert(matcher:find({ match = found, forward = true, wrap = false }).pos[1] == 70)
allow_far = true
assert(matcher:find({ pos = Pos({ 1, 0 }), count = 4, forward = true, wrap = false }).pos[1] == 900)
assert(matcher:find({ pos = Pos({ 1, 0 }), count = 1000002, forward = true, wrap = true }).pos[1] == 70)
vim.api.nvim_buf_set_lines(0, 69, 70, false, { "" })
assert(matcher:find({ pos = Pos({ 1, 0 }), count = 2, forward = true, wrap = false }).pos[1] == 140)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "none" })
assert(not matcher:find({ wrap = true }))
state:hide()
rawset(vim.api, "nvim_buf_get_lines", get_lines)

require("flash").setup({
	modes = {
		char = {
			matcher = plugin.char,
			multi_line = false,
			jump_labels = true,
			labels = "ab",
			label = { exclude = "", uppercase = false },
		},
	},
})
fixture.setup({ sources = { { data = { ["中"] = "va", ["珠"] = "vb" } } } })
reset({ "a中珠" })
vim.api.nvim_feedkeys("v" .. string.char(27), "t", false)
local label_state = Char.jump("f")
assert(label_state and label_state.opts.labeler == Char.labeler)
assert(label_state.results[1].label == "a" or label_state.results[2].label == "a")
assert(vim.v.errmsg == "", vim.v.errmsg)
-- Till motions must not land inside the preceding or matched grapheme.
require("flash").setup({ modes = { char = { matcher = plugin.char, multi_line = false, jump_labels = false } } })
fixture.setup({ sources = { { data = { ["中"] = "v" } } } })
reset({ "xá中" })
keys("tv", { 1, 1 })
reset({ "x👩‍💻中" })
keys("tv", { 1, 1 })
fixture.setup({ sources = { { data = { ["👩‍💻"] = "v" } } } })
reset({ "👩‍💻ab" }, { 1, #"👩‍💻a" })
keys("Tv", { 1, #"👩‍💻" })
print("real Flash char integration tests passed")

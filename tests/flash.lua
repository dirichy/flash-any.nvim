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
fixture.setup({ sources = { { name = "pinyin", scheme = "flypy" } } })
local state = plugin.jump()
assert(state.opts.matcher and state.opts.labeler)
for _, pattern in ipairs({ "v", "vs", "vsg", "vsgo", "a", "ab", "q", "qq" }) do
	state:update({ pattern = pattern, check_jump = false, force = true })
	if pattern == "v" or pattern == "vs" then
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
-- Verify multi-codepoint ranges against the real Flash state and highlighter.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "👩‍💻x" })
state = plugin.jump(fixture.config({ sources = { { data = { ["👩‍💻"] = "dev" } } } }))
for _, pattern in ipairs({ "d", "de", "dev", "devx" }) do
	state:update({ pattern = pattern, check_jump = false, force = true })
	assert(#state.results == 1, vim.inspect(state.results))
	assert(state.results[1].pos[2] == 0)
	assert(state.results[1].end_pos[2] == (pattern == "devx" and 11 or 7))
end
state:hide()
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
State.loop = loop
-- Exercise the real input loop, including a next key that must not become a label.
vim.api.nvim_feedkeys("vs" .. string.char(27), "t", false)
state = plugin.jump()
assert(state.pattern() == "vs" and #state.results == 2)
assert(not state.visible)
assert(vim.v.errmsg == "", vim.v.errmsg)
print("real Flash integration tests passed")

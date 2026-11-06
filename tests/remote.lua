-- Run with: nvim --clean --headless -u tests/remote.lua
-- Use Neovim's input loop so Flash can cancel and re-enter the pending operator.
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(vim.env.FLASH_NVIM_PATH or (vim.uv.cwd() .. "/.dev/flash.nvim"))
vim.o.lines, vim.o.columns = 40, 120
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local fixture = require("fixture")
local plugin = require("flash-any")
---@type Flash.State?
local state
vim.keymap.set("o", "r", function()
	state = plugin.remote()
end)

local cases = {
	{ sources = { "pinyin" }, input = "yrzga", target = "中国 target", text = "中国" },
	{
		sources = { { name = "pinyin", scheme = "flypy" } },
		input = "drvsgoa",
		target = "中国 target",
		text = "中国",
		after = " target",
	},
	{ sources = { "pinyin" }, input = "yrzga", target = "中国 target", text = "中国", split = true },
}
local index = 0
local next_case
local function fail(err)
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
end

local function wait_for(predicate, done)
	local started = vim.uv.hrtime()
	local function check()
		local ok, err = pcall(function()
			if predicate() then
				return done()
			end
			assert(vim.uv.hrtime() - started < 2e9, "remote operation timed out in case " .. index)
			vim.defer_fn(check, 10)
		end)
		if not ok then
			fail(err)
		end
	end
	vim.defer_fn(check, 10)
end

next_case = function()
	index = index + 1
	local case = cases[index]
	if not case then
		print("real Flash remote integration tests passed")
		return vim.cmd("qa!")
	end
	vim.cmd("only!")
	local origin = vim.api.nvim_get_current_win()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "origin here", case.split and "no target here" or case.target })
	vim.api.nvim_win_set_cursor(origin, { 1, 0 })
	local target = origin
	if case.split then
		vim.cmd("vnew")
		target = vim.api.nvim_get_current_win()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "other window", case.target })
		vim.api.nvim_set_current_win(origin)
	end
	local buf = vim.api.nvim_win_get_buf(target)
	fixture.setup({ sources = case.sources, labels = "a", label = { uppercase = false } })
	state = nil
	vim.api.nvim_input(case.input)
	wait_for(function()
		return state
			and vim.fn.mode(true):sub(1, 2) == "no"
			and vim.api.nvim_get_current_win() == target
			and vim.deep_equal(vim.api.nvim_win_get_cursor(target), { 2, 0 })
	end, function()
		assert(state and state.opts.remote_op.motion and state.opts.remote_op.restore)
		vim.api.nvim_input("iw")
		wait_for(function()
			return vim.fn.mode() == "n"
				and vim.api.nvim_get_current_win() == origin
				and vim.deep_equal(vim.api.nvim_win_get_cursor(origin), { 1, 0 })
		end, function()
			assert(vim.fn.getreg('"') == case.text, vim.inspect(vim.fn.getreg('"')))
			assert(vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == (case.after or case.target))
			assert(vim.v.errmsg == "", vim.v.errmsg)
			next_case()
		end)
	end)
end

vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = next_case })
vim.defer_fn(function()
	fail("remote integration watchdog timed out")
end, 8000)

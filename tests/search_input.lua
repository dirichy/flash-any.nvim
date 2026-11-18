-- Run with: nvim --clean --headless -u tests/search_input.lua
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(vim.env.FLASH_NVIM_PATH or (vim.uv.cwd() .. "/.dev/flash.nvim"))
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
require("fixture").setup({ sources = { { data = { ["中"] = "vs", ["国"] = "go" } } } })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a中国" })

vim.schedule(function()
	local ok, err = pcall(function()
		local previewed = false
		vim.defer_fn(function()
			previewed = vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 })
			vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "t", false)
		end, 100)
		vim.api.nvim_feedkeys("vsgo", "t", false)
		require("flash-any").search()
		assert(previewed, "preview must run while getcharstr() waits for input")
		assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }), "Esc must restore the origin")
		assert(vim.v.errmsg == "", vim.v.errmsg)
	end)
	if not ok then
		io.stderr:write(tostring(err) .. "\n")
		return vim.cmd("cquit 1")
	end
	print("real asynchronous Flash input-loop test passed")
	vim.cmd("qa!")
end)

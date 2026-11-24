local M = {}
function M.config(opts)
	local config = vim.deepcopy(opts)
	local path = vim.fn.tempname() .. ".bin"
	assert(config.sources)
	require("flash-any.build").binary({ sources = config.sources, output = path })
	config.binary = path
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			vim.uv.fs_unlink(path)
		end,
	})
	return config
end
function M.setup(opts)
	require("flash-any").setup(M.config(opts))
end
return M

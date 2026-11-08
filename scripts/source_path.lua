-- Developer tools only: opt in to separately installed source packages.
local root = vim.env.FLASH_ANY_SOURCE_PATH
if root then
	assert(vim.fn.isdirectory(root) == 1, "FLASH_ANY_SOURCE_PATH must contain source plugin directories")
	for _, path in ipairs(vim.fn.glob(root .. "/flash-any-*.nvim", false, true)) do
		if vim.fn.isdirectory(path .. "/lua") == 1 then
			vim.opt.runtimepath:append(path)
		end
	end
end

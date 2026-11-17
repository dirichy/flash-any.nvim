-- Development configuration: copy to the source package's minimal.lua.
-- Replace the quoted "SOURCE" below, keeping the environment variable names.
local core = assert(vim.env.FLASH_ANY_ROOT, "set FLASH_ANY_ROOT to the core checkout")
local flash = assert(vim.env.FLASH_NVIM_PATH, "set FLASH_NVIM_PATH to the flash.nvim checkout")
local source = assert(vim.env.FLASH_ANY_SOURCE_ROOT, "set FLASH_ANY_SOURCE_ROOT to the source package")
vim.opt.runtimepath:prepend(core)
vim.opt.runtimepath:prepend(flash)
vim.opt.runtimepath:append(source)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
require("flash-any").setup({ sources = { "SOURCE" } })
vim.keymap.set({ "n", "x", "o" }, "s", function()
	require("flash-any").jump()
end)

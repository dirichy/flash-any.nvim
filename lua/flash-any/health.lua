local M = {}

local function has_module(name)
	local ok = pcall(require, name)
	return ok
end

function M.check()
	vim.health.start("flash-any.nvim")

	if vim.fn.has("nvim-0.11.0") == 1 then
		vim.health.ok("Neovim >= 0.11")
	else
		vim.health.error("Neovim >= 0.11 is required")
	end

	if has_module("flash") then
		vim.health.ok("flash.nvim is available")
	else
		vim.health.error("flash.nvim is not available", {
			"Install folke/flash.nvim and add it as a dependency",
		})
	end

	local native_ok, native_error = pcall(require, "flash-any.native")
	if native_ok then
		vim.health.ok("C matching core is available")
	else
		vim.health.error("Unable to load the C matching core: " .. tostring(native_error), {
			"Install make and a C toolchain (GCC or Clang); CC may select the compiler",
			"Configure the plugin manager's build hook to run make, or run make in the plugin directory",
		})
	end

	local ok, registry = pcall(require, "flash-any.source")
	if not ok then
		vim.health.error("Unable to load source registry: " .. tostring(registry))
		return
	end

	local sources = registry.available()
	if #sources > 0 then
		vim.health.ok("Available sources: " .. table.concat(sources, ", "))
	else
		vim.health.ok("Unicode literal matching is available; optional sources are installed separately")
	end

	if vim.tbl_contains(vim.fn.getcompletion("flash-any", "help"), "flash-any") then
		vim.health.ok("Help tags are available")
	else
		vim.health.warn("Help tags are missing; run :helptags doc")
	end
end

return M

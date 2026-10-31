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

  local ok, tables = pcall(require, "flash-any.table")
  if not ok then
    vim.health.error("Unable to load source registry: " .. tostring(tables))
    return
  end

  local sources = tables.available()
  table.insert(sources, 1, "literal")
  if #sources > 0 then
    vim.health.ok("Available sources: " .. table.concat(sources, ", "))
  else
    vim.health.warn("No built-in source is available")
  end

  if vim.tbl_contains(vim.fn.getcompletion("flash-any", "help"), "flash-any") then
    vim.health.ok("Help tags are available")
  else
    vim.health.warn("Help tags are missing; run :helptags doc")
  end
end

return M

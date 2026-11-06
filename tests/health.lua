#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
package.loaded.flash = {}
vim.cmd("checkhealth flash-any")
local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(report:find("Help tags are available", 1, true), report)
assert(report:find("Available sources: nerdfont", 1, true), report)
assert(not report:find("ERROR", 1, true) and not report:find("WARNING", 1, true), report)
print("all health API tests passed")

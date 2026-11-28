#!/usr/bin/env -S nvim -l
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(arg[1] or (vim.uv.cwd() .. "/.dev/flash.nvim"))
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local plugin = require("flash-any")
for _, key in ipairs({ "n", "N", "gn", "gN" }) do
	assert(vim.fn.maparg(key, "n") == "", "loading the plugin must not install mappings")
end
local config = {
	sources = { { data = { ["中"] = "vs", ["国"] = "go", ["👩‍💻"] = "em" } } },
}
if arg[2] == "preserve" then
	config.clear_search_register = false
end
require("fixture").setup(config)

local function reset(text, pos)
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, type(text) == "table" and text or { text })
	vim.api.nvim_win_set_cursor(0, pos or { 1, 0 })
end

local function search(input, opts)
	vim.api.nvim_feedkeys(vim.keycode(input), "t", false)
	return plugin.search(opts)
end

local function keys(input, pos)
	vim.api.nvim_feedkeys(vim.keycode(input), "xt", false)
	if pos then
		assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), pos), vim.inspect(vim.api.nvim_win_get_cursor(0)))
	end
end

for _, key in ipairs({ "n", "N", "gn", "gN" }) do
	vim.keymap.set({ "n", "x", "o" }, key, function()
		if vim.fn.getreg("/") ~= "" then
			return key
		end
		return ("<Cmd>lua require('flash-any').search_repeat(%q)<CR>"):format(key)
	end, { expr = true })
end

reset("foo foo")
vim.cmd("s/foo/foo/")
vim.fn.setreg("/", "")
keys("n", { 1, 4 }) -- No Flash Any query yet: retain native substitute fallback.

reset("a中 中 中")
vim.fn.setreg("/", "native")
search("vs<CR>")
if arg[2] == "preserve" then
	assert(vim.fn.getreg("/") == "native", "setup must preserve the native pattern when disabled")
	search("vs<CR>", { clear_search_register = true })
	assert(vim.fn.getreg("/") == "", "per-call true must override setup false")
	print("global search-register opt-out and per-call override passed")
	return
end
assert(vim.fn.getreg("/") == "")
assert(not pcall(plugin.search, { clear_search_register = "yes" }))
keys("n", { 1, 5 })
keys("N", { 1, 1 })
keys("2n", { 1, 9 })
keys("n", { 1, 1 }) -- wrap
keys("Nn", { 1, 1 }) -- N must not change n's direction.

vim.fn.setreg("/", "native")
search("vs<Esc>")
assert(vim.fn.getreg("/") == "native")
search("<CR>")
assert(vim.fn.getreg("/") == "native")
search("vs<CR>", { clear_search_register = false })
assert(vim.fn.getreg("/") == "native")
-- A failed but confirmed query still supersedes the previous search.
search("missing<CR>")
assert(vim.fn.getreg("/") == "")
reset("a missing missing")
keys("n", { 1, 2 })

reset("a中 中 中", { 1, 9 })
search("vs<CR>", { search = { forward = false } })
keys("n", { 1, 1 })
keys("N", { 1, 5 })
keys("gn", { 1, 5 }) -- gn always searches forward, even after a backward search.
assert(vim.fn.mode() == "v")
keys("<Esc>")
plugin.search_repeat("n", { forward = true })
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 9 }))

reset("a中国 中国 中国")
search("vsgo<CR>")
keys("gny")
assert(vim.fn.getreg('"') == "中国")
keys("2gny")
assert(vim.fn.getreg('"') == "中国")
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, #"a中国 " }))
reset("a中国 中国 中国")
keys("cgnX<Esc>.")
assert(vim.api.nvim_get_current_line() == "aX X 中国", vim.api.nvim_get_current_line())
keys(".")
assert(vim.api.nvim_get_current_line() == "aX X X")
assert(vim.fn.getreg("/") == "", "native selection must not leak its temporary pattern")
reset("a中国 bar 中国 bar")
keys("cgnX<Esc>")
keys("/bar<CR>.")
assert(vim.api.nvim_get_current_line() == "aX X 中国 bar", vim.api.nvim_get_current_line())
vim.fn.setreg("/", "")

reset("a中国 中国 中国")
keys("dgn")
assert(vim.api.nvim_get_current_line() == "a 中国 中国")
reset("a中国 中国 中国")
keys("dn")
assert(vim.api.nvim_get_current_line() == "中国 中国 中国", "dn is an exclusive motion")
reset("a中国 中国 中国", { 1, #"a中国 " })
keys("dN")
assert(vim.api.nvim_get_current_line() == "a中国 中国", vim.api.nvim_get_current_line())

reset("a中国 中国 中国")
keys("gngny")
assert(vim.fn.getreg('"') == "中国 中国", vim.inspect(vim.fn.getreg('"')))
reset("a中国 中国 中国", { 1, #"a中国 中国 " })
keys("gNgNy")
assert(vim.fn.getreg('"') == "中国 中国", vim.inspect(vim.fn.getreg('"')))
vim.o.selection = "exclusive"
reset("a中国 中国")
keys("gny")
assert(vim.fn.getreg('"') == "中国", "native gn must respect exclusive selection")
vim.o.selection = "inclusive"

reset("a👩‍💻 👩‍💻")
search("em<CR>")
keys("gny")
assert(vim.fn.getreg('"') == "👩‍💻", vim.inspect(vim.fn.getreg('"')))
vim.o.magic = false
reset("xá á")
search("a<CR>")
keys("gny")
assert(vim.fn.getreg('"') == "á")
vim.o.magic = true
reset("a👩‍💻 👩‍💻")
search("em<CR>")

-- Repeat in the current buffer, recomputing after edits and beyond the viewport.
local lines = { "a" }
for _ = 1, 100 do
	lines[#lines + 1] = "nothing"
end
lines[#lines + 1] = "👩‍💻"
vim.cmd("enew!")
reset(lines)
keys("n", { 102, 0 })
vim.api.nvim_buf_set_lines(0, 101, 102, false, { "none" })
vim.api.nvim_buf_set_lines(0, 79, 80, false, { "👩‍💻" })
keys("N", { 80, 0 })

-- With no wrap, failed motions must not delete text or move the cursor.
vim.o.wrapscan = false
reset("a中")
search("vs<CR>")
keys("dn", { 1, 1 })
assert(vim.api.nvim_get_current_line() == "a中")
vim.o.wrapscan = true
keys("n", { 1, 1 })
vim.o.wrapscan = false
search("vs<CR>", { search = { wrap = true } })
reset("a中 中z", { 1, 5 })
keys("gny", { 1, 5 })
keys("gny", { 1, 5 })
vim.api.nvim_win_set_cursor(0, { 1, 8 })
keys("gny", { 1, 1 })
assert(not vim.o.wrapscan, "range selection must restore wrapscan")
vim.o.wrapscan = true

-- Native searches reclaim all mappings simply by populating the register.
reset("foo bar foo bar")
keys("/bar<CR>n", { 1, 12 })
keys("Ngny")
assert(vim.fn.getreg('"') == "bar")
reset("foo bar foo bar")
search("foo<CR>")
keys("*", { 1, 0 })
assert(vim.fn.getreg("/") ~= "")
keys("n", { 1, 8 })

-- Run the actual documented fixed-direction maps, after a backward search.
local readme = table.concat(vim.fn.readfile("README.md"), "\n")
for block in readme:gmatch("```lua\n(.-)\n```") do
	if block:find('local forward = key == "n"', 1, true) then
		assert(loadstring(block))()
	end
end
reset("a中 中 中", { 1, 9 })
search("vs<CR>", { search = { forward = false } })
keys("n", { 1, 9 })
keys("N", { 1, 5 })
keys("n", { 1, 9 })
reset("foo bar foo bar")
keys("?bar<CR>", { 1, 12 })
keys("n", { 1, 4 })
keys("N", { 1, 12 })
assert(vim.v.errmsg == "", vim.v.errmsg)
print("search repeats, native dispatch, operators, dot, selection, counts and register lifecycle passed")

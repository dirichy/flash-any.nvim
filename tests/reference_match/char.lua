#!/usr/bin/env -S nvim -l
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
local match = require("reference.match")
local codetable = require("reference.codetable")
local literal = require("reference.literal")()
local literal_source = { matcher = literal.matcher, scope = require("reference.scope").resolve(literal.scope) }
local calls = 0
local sources = {
	literal_source,
	{
		data = { ["中"] = { "vs", "va" }, ["珠"] = { "vu" }, ["国"] = { "go" } },
		matcher = function(text, stream, args, emit)
			assert(stream:get() == "v", "char search must not query the next character")
			calls = calls + 1
			return codetable.full_code(text, stream, args, emit)
		end,
	},
	{ data = { ["国"] = { "v" }, ["😀"] = { "vname" } }, matcher = codetable.prefix, fallback = true },
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中珠v国😀" })
local state = {
	pattern = function()
		return "v"
	end,
	labels = function()
		error("Flash owns char labels")
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
local matches = match.char(0, state, range, sources)
assert(#matches == 4)
for i, col in ipairs({ 0, 3, 6, 10 }) do
	assert(matches[i].pos[2] == col and matches[i].end_pos[2] == col)
	assert(matches[i].label == nil and next(matches[i].next) == nil)
end
local previous_calls = calls
matches[1].pos[2] = 99
matches = match.char(0, state, range, sources)
assert(calls == previous_calls and matches[1].pos[2] == 0)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "国中" })
matches = match.char(0, state, range, sources)
assert(calls > previous_calls and #matches == 1 and matches[1].pos[2] == 3)
assert(#match.char(0, state, range, { literal_source }) == 0)
assert(#match.char(0, {
	pattern = function()
		return ""
	end,
}, range, sources) == 0)
print("single-character matcher tests passed")

-- Reuse cached recognition while changing f/F/t/T; shifts stay on grapheme starts.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "á👩‍💻🇨🇳" })
local cluster_calls = 0
local cluster_sources =
	{ {
		matcher = function(_, _, _, emit)
			cluster_calls = cluster_calls + 1
			emit("")
			return true
		end,
	} }
local cluster_state = {
	pattern = function()
		return "x"
	end,
}
local starts = { 0, #"á", #"á👩‍💻" }
local full = match.char(0, cluster_state, range, cluster_sources)
local before = match.char(0, cluster_state, range, cluster_sources, "t")
local after = match.char(0, cluster_state, range, cluster_sources, "T")
assert(#full == 3 and #before == 2 and #after == 2 and cluster_calls == 3)
for i = 1, 2 do
	assert(before[i].pos[2] == starts[i] and after[i].pos[2] == starts[i + 1])
end
print("ok - t/T reuse cached neighboring grapheme positions and reject line edges")

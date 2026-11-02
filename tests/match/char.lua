#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
local match = require("flash-any.match")
local codetable = require("flash-any.match.codetable")
local literal = require("flash-any.sources.literal")()
local literal_source = { matcher = literal.matcher, scope = require("flash-any.scope").resolve(literal.scope) }
local calls = 0
local sources = {
  literal_source,
  { data = { ["中"] = { "vs", "va" }, ["珠"] = { "vu" }, ["国"] = { "go" } },
    matcher = function(text, stream, args, emit)
      assert(stream:get() == "v", "char search must not query the next character")
      calls = calls + 1
      return codetable.full_code(text, stream, args, emit)
    end },
  { data = { ["国"] = { "v" }, ["😀"] = { "vname" } },
    matcher = codetable.prefix, fallback = true },
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中珠v国😀" })
local state = { pattern = function() return "v" end,
  labels = function() error("Flash owns char labels") end }
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
assert(#match.char(0, { pattern = function() return "" end }, range, sources) == 0)
print("single-character matcher tests passed")

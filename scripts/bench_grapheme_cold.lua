-- One cold sample per process, no warmup:
-- nvim --clean -l scripts/bench_grapheme_cold.lua ROOT ascii|chinese
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(assert(arg[1], "implementation root required"))
local start = vim.uv.hrtime()
local scanner = require("flash-any.match")
local pinyin = require("flash-any.sources.pinyin")()
local sources = {
  require("flash-any.sources.literal")(),
  {
    data = pinyin.data,
    matcher = require("flash-any.match.codetable").initial,
    scope = require("flash-any.scope").resolve(pinyin.scope),
  },
}
local setup_ms = (vim.uv.hrtime() - start) / 1e6
local fixtures = {
  ascii = "local result = cursor:get(1) -- English words and numbers 12345; ",
  chinese = "普通中文正文用于检查字符扫描开销，今天写代码，明天做研究。包含 English words 12345。",
}
local value = assert(fixtures[arg[2]], "unknown fixture"):rep(2)
local lines = {}
for i = 1, 40 do
  lines[i] = value
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local labels = vim.split("asdfghjklqwertyuiopzxcvbnm", "")
local state = {
  pattern = function()
    return "c"
  end,
  labels = function()
    return labels
  end,
}
start = vim.uv.hrtime()
local result = scanner.get(0, state, { from = { 1, 0 }, to = { 40, 0 } }, sources)
local scan_ms = (vim.uv.hrtime() - start) / 1e6
local expected = arg[2] == "ascii" and 160 or 80
assert(#result == expected, "unexpected match count")
io.write(vim.json.encode({ fixture = arg[2], setup_ms = setup_ms, scan_ms = scan_ms, matches = #result }), "\n")

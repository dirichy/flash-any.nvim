-- Isolated f-mode recording; no personal configuration or replacement keymaps.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.FLASH_NVIM_PATH or (root .. "/.dev/flash.nvim"))
vim.opt.runtimepath:prepend(vim.env.TOKYONIGHT_PATH or (root .. "/.dev/tokyonight.nvim"))
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.signcolumn = "no"
vim.opt.cursorline = true
vim.opt.scrolloff = 2
vim.opt.laststatus = 3
vim.opt.showmode = false
vim.opt.showcmd = true
vim.opt.ruler = false
vim.opt.shortmess:append("I")
vim.opt.winbar = "  flash-any.nvim   /   f: first-code jumps"
vim.opt.statusline = "  fz: 中 / 这 / 字 / z   |   f and ; next   |   , previous%=%l:%c  "
vim.cmd.colorscheme("tokyonight-night")

local plugin = require("flash-any")
plugin.setup({ sources = { "pinyin" } })
require("flash").setup({ modes = { char = { matcher = plugin.char, multi_line = false } } })

local original = vim.fn.readfile(root .. "/demos/char-sample.txt")
local row, cols
for line, text in ipairs(original) do
  if text:find("中文", 1, true) then
    row, cols = line, {}
    for _, char in ipairs({ "中", "这", "字", "z" }) do
      cols[#cols + 1] = assert(text:find(char, 1, true)) - 1
    end
  end
end
assert(row and cols, "missing f-mode fixture")
-- Begin at the target line so f searches its words, not the explanatory text.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function() vim.api.nvim_win_set_cursor(0, { row, 0 }) end,
})

-- Recording-only observer of Flash's real state; never changes results or input.
local demo = { cursors = {}, candidates = {} }
local timer = assert(vim.uv.new_timer())
timer:start(0, 40, vim.schedule_wrap(function()
  local state = require("flash.plugins.char").state
  if not state or not state.visible or state.pattern() ~= "z" then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local previous = demo.cursors[#demo.cursors]
  if not previous or not vim.deep_equal(previous, cursor) then
    demo.cursors[#demo.cursors + 1] = cursor
  end
  demo.candidates = vim.tbl_map(function(item)
    return { unpack(item.pos) }
  end, state.results)
end))

function demo.verify()
  timer:stop()
  timer:close()
  local ok, err = pcall(function()
    local expected = {}
    for _, index in ipairs({ 1, 2, 3, 4, 3 }) do expected[#expected + 1] = { row, cols[index] } end
    assert(vim.deep_equal(demo.cursors, expected), "unexpected jumps: " .. vim.inspect(demo.cursors))
    assert(#demo.candidates == 4, "expected all four first-code matches")
    for i, col in ipairs(cols) do
      assert(vim.deep_equal(demo.candidates[i], { row, col }), "unexpected candidate")
    end
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original), "fixture changed")
    assert(not vim.bo.modified, "fixture modified")
    assert(vim.v.errmsg == "", vim.v.errmsg)
  end)
  vim.fn.writefile({ vim.json.encode({ verified = ok, error = not ok and tostring(err) or nil,
    cursors = demo.cursors, candidates = demo.candidates }) }, root .. "/demos/output/char-verification.json")
  if not ok then error(err) end
end

_G.FlashAnyCharDemo = demo

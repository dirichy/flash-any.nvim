-- Isolated recording configuration; run from the repository root.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.FLASH_NVIM_PATH or (root .. "/.dev/flash.nvim"))
vim.opt.runtimepath:prepend(vim.env.TOKYONIGHT_PATH or (root .. "/.dev/tokyonight.nvim"))
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.cursorline = true
vim.opt.scrolloff = 2
vim.opt.laststatus = 3
vim.opt.showmode = false
vim.opt.showcmd = false
vim.opt.ruler = false
vim.opt.shortmess:append("I")
vim.cmd.colorscheme("tokyonight-night")
vim.opt.winbar = "  flash-any.nvim   /   Double pinyin + Unicode names"
vim.opt.statusline = "  Press s to search%=%l:%c  "

local plugin = require("flash-any")
plugin.setup({
  sources = { { name = "pinyin", scheme = "flypy" }, "unicode" },
  label = { style = "inline" },
})

local demo = { seen = {}, jumps = {} }
local stages = {
  "Double pinyin   |   s  >  vsgo  >  a",
  "Unicode letter  |   s  >  alpha  >  a",
  "Emoji by name   |   s  >  grin  >  a",
}

vim.keymap.set("n", "s", function()
  vim.opt.statusline = "  " .. stages[#demo.jumps + 1] .. "%=%l:%c  "
  local state = plugin.jump()
  demo.jumps[#demo.jumps + 1] = {
    pattern = state.pattern(),
    cursor = vim.api.nvim_win_get_cursor(0),
  }
end)

-- Observe actual live search results without changing them or their labels.
local timer = assert(vim.uv.new_timer())
timer:start(0, 40, vim.schedule_wrap(function()
  local state = require("flash.repeat")._states.jump
  if state and state.visible then
    local pattern = state.pattern()
    if pattern ~= "" then
      demo.seen[pattern] = vim.tbl_map(function(match)
        return { pos = { unpack(match.pos) }, label = match.label }
      end, state.results)
    end
  end
end))

function demo.verify()
  timer:stop()
  timer:close()
  local ok, err = pcall(function()
    assert(#demo.seen.vs == 4, "vs must find 中 and the zhong reading of 重")
    assert(#demo.seen.vsgo == 1, "vsgo must narrow to 中国")
    assert(#demo.seen.alpha == 1, "alpha must find α")
    assert(#demo.seen.grin == 1, "grin must find 😀")
    local expected = {
      { "vsgo", { 6, 3 } },
      { "alpha", { 14, 3 } },
      { "grin", { 16, 3 } },
    }
    assert(#demo.jumps == #expected, "all three jumps must finish")
    for i, item in ipairs(expected) do
      assert(demo.jumps[i].pattern == item[1], "unexpected jump pattern")
      assert(vim.deep_equal(demo.jumps[i].cursor, item[2]), "unexpected cursor position")
      assert(demo.seen[item[1]][1].label == "a", "the displayed a label must select the target")
    end
    assert(not vim.bo.modified, "demo must leave the fixture unchanged")
    assert(vim.v.errmsg == "", vim.v.errmsg)
  end)
  vim.fn.writefile({ vim.json.encode({ verified = ok, error = not ok and tostring(err) or nil,
    seen = demo.seen, jumps = demo.jumps }) }, root .. "/demos/output/verification.json")
  if not ok then error(err) end
end

_G.FlashAnyDemo = demo

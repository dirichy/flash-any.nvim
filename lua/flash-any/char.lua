local Match = require("flash-any.match")
local Matcher = require("flash.search.matcher")
local Pos = require("flash.search.pos")
local utf8 = require("flash-any.utf8")
local M = {}

---@param win integer
---@param state Flash.State
---@param sources FlashAnySource[]
---@return Flash.Matcher
function M.new(win, state, sources)
  local matcher = Matcher.new(win)
  local motion = require("flash.plugins.char").motion
  local origin = vim.api.nvim_win_get_cursor(win)[1]
  ---@type {multi_line: boolean}
  local char_opts = state.opts

  local function bounds()
    local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    return char_opts.multi_line and 1 or math.min(origin, last), char_opts.multi_line and last or math.min(origin, last)
  end

  local function get_line(row, filter)
    local matches = Match.char(win, state, { from = { row, 0 }, to = { row, 0 } }, sources)
    if motion == "t" or motion == "T" then
      local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), row - 1, row, false)[1]
      local shifted = {}
      for _, item in ipairs(matches) do
        local col = item.pos[2]
        local index = vim.str_utfindex(text, "utf-32", col) + (motion == "t" and -1 or 1)
        if index >= 0 then
          local target = utf8.byteidx(text, index)
          if target < #text then
            item.pos[2], item.end_pos[2] = target, target
            shifted[#shifted + 1] = item
          end
        end
      end
      matches = shifted
    end
    if filter and state.opts.filter then matches = state.opts.filter(matches, state) or matches end
    for _, item in ipairs(matches) do
      item.pos, item.end_pos = Pos(item.pos), Pos(item.end_pos)
    end
    return matches
  end

  matcher.get = function(_, opts)
    local first, last = bounds()
    -- Flash's range can extend back to the original cursor after repeated jumps.
    local view = vim.fn.getwininfo(win)[1]
    first, last = math.max(first, view.topline), math.min(last, view.botline)
    opts = opts or {}
    local ret = {}
    for row = math.max(first, opts.from and opts.from[1] or first), math.min(last, opts.to and opts.to[1] or last) do
      vim.list_extend(ret, get_line(row))
    end
    return Matcher.filter(ret, {
      from = opts.from or Pos({ first, 0 }),
      to = opts.to or Pos({ last, math.huge }),
    })
  end

  matcher.find = function(_, opts)
    if state.pattern:empty() then return end
    opts = Matcher.defaults(opts)
    local start = Pos(opts.match and opts.match.pos or opts.pos)
    local first, last = bounds()
    local forward = opts.forward
    local step = forward and 1 or -1
    local row = math.max(first, math.min(last, start[1]))
    local remaining = math.max(opts.count, 1)
    local initial, wrapped, cycle_count = true, false, 0
    while true do
      local matches = get_line(row, true)
      for i = forward and 1 or #matches, forward and #matches or 1, step do
        local item = matches[i]
        local at_start = item.pos == start
        if opts.count == 0 then
          if at_start then return item end
        elseif not initial or (forward and start < item.pos) or (not forward and item.pos < start)
          or (at_start and opts.current and not opts.match) then
          remaining = remaining - 1
          cycle_count = cycle_count + 1
          if remaining == 0 then return item end
        end
      end
      if opts.count == 0 then return end
      row = row + step
      if row < first or row > last then
        if not opts.wrap then return end
        if wrapped then
          if cycle_count == 0 then return end
          remaining = (remaining - 1) % cycle_count + 1
        end
        row = forward and first or last
        wrapped, cycle_count = true, 0
      end
      initial = false
    end
  end

  return matcher
end

return M

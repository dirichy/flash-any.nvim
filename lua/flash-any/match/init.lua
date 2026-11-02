local M = {}
local utf8 = require("flash-any.utf8")

-- 跨 source 和扫描器共用的 matcher 协议；具体实现只引用这些类型。
---@alias FlashAnyNext table<string, boolean>

-- Each result is one branch: either consume bytes and move to the next character,
-- or finish the input with next. nil means unknown character; an empty list
-- means a known character whose input did not match.
-- Matchers are prefix-closed: appended input cannot revive a failed branch.
---@class FlashAnyMatcherResult
---@field consumed? integer Bytes consumed before moving to the next character.
---@field next? FlashAnyNext Input fully matched; may be an empty set.

---@class FlashAnyMatcherArgs
---@field source FlashAnySource

---@alias FlashAnyMatcher fun(char: string, stream: string, args: FlashAnyMatcherArgs): FlashAnyMatcherResult[]?

-- 初始化后的运行时 source；scheme、fuzzy 等配置已用于构建 data 和 matcher。
---@class FlashAnySource
---@field data? table<string, string[]>
---@field matcher FlashAnyMatcher
---@field fallback? boolean Only run if every earlier configured source returned nil.
---@field name? string

---@param char string
---@param stream string
---@param sources FlashAnySource[]
---@return FlashAnyMatcherResult[]
local function match_char(char, stream, sources)
  -- Buffer characters are UTF-8; each configured matcher owns its input format.
  local ret, known = {}, false
  for _, source in ipairs(sources) do
    if not known or not source.fallback then
      local results = source.matcher(char, stream, { source = source })
      if results ~= nil then
        known = true
        for _, item in ipairs(results) do
          ret[#ret + 1] = item
        end
      end
    end
  end
  return ret
end

-- Buffer byte column -> input byte offset -> earliest match start column.
---@alias FlashAnyRequests table<integer, table<integer, integer>>

---@param requests FlashAnyRequests
---@param col integer
---@param offset integer
---@param start integer
local function add_request(requests, col, offset, start)
  local at = requests[col]
  if not at then
    at = {}
    requests[col] = at
  end
  at[offset] = math.min(at[offset] or start, start)
end

---@class FlashAnyInternalMatch
---@field line integer
---@field start_col integer
---@field end_col integer Last character's starting byte column
---@field next FlashAnyNext

---@param text string
---@param line integer
---@param pattern string
---@param sources FlashAnySource[]
---@param suffixes table<integer, string> Shared across starts, lines and windows.
---@param resume? FlashAnyRequests Only these states can survive appended input.
---@return FlashAnyInternalMatch[], FlashAnyRequests
local function scan_line(text, line, pattern, sources, suffixes, resume)
  if resume and next(resume) == nil then return {}, {} end
  local matches = {}
  local requests, frontier = {}, {}
  local first = 0
  if resume then
    first = #text
    for col, offsets in pairs(resume) do
      first = math.min(first, col)
      for offset, start in pairs(offsets) do add_request(requests, col, offset, start) end
    end
  end
  ---@type FlashAnyInternalMatch?
  local waiting
  for next_col, char in utf8.iter_char(text, first) do
    if next_col and char then
      local col = next_col - #char
      if waiting then
        -- Completed ranges end at the previous character. Query this character
        -- once for their next keys without adding it to those ranges.
        for _, item in ipairs(match_char(char, "", sources)) do
          for key in pairs(item.next or {}) do
            waiting.next[key] = true
          end
        end
        waiting = nil
      end
      -- New starts and streams left by the previous character share one queue.
      if not resume then add_request(requests, col, 0, col) end
      ---@type FlashAnyInternalMatch?
      local at_end
      local pending = requests[col]
      if pending then
        for offset, start in pairs(pending) do
          local stream = suffixes[offset]
          if not stream then
            stream = pattern:sub(offset + 1)
            suffixes[offset] = stream
          end
          for _, item in ipairs(match_char(char, stream, sources)) do
            local complete = item.consumed == #stream
            if item.next then add_request(frontier, col, offset, start) end
            if item.next or complete then
              -- All successes here end at col. Merge their display range now;
              -- continuation requests above keep distinct stream offsets.
              if not at_end then
                at_end = { line = line, start_col = start, end_col = col, next = {} }
                matches[#matches + 1] = at_end
              else
                at_end.start_col = math.min(at_end.start_col, start)
              end
              if item.next then
                for value in pairs(item.next) do at_end.next[value] = true end
              end
              if complete and next_col < #text then
                add_request(frontier, next_col, #pattern, start)
                waiting = at_end
              end
            elseif next_col < #text then
              local consumed = item.consumed
              ---@cast consumed integer
              add_request(requests, next_col, offset + consumed, start)
            end
          end
        end
        requests[col] = nil
      end
      if resume and not waiting and next(requests) == nil then break end
    end
  end
  -- Branch enumeration must not change label order.
  table.sort(matches, function(a, b)
    if a.start_col == b.start_col then return a.end_col < b.end_col end
    return a.start_col < b.start_col
  end)
  return matches, frontier
end

---@class FlashAnyDisplayMatch
---@field win integer
---@field pos integer[]
---@field end_pos integer[]
---@field next FlashAnyNext
---@field label? string

---@param win integer
---@param state table
---@param opts table
---@param sources FlashAnySource[]
---@return FlashAnyDisplayMatch[]
function M.get(win, state, opts, sources)
  local pattern = state.pattern()
  if pattern == "" then return {} end
  state._flash_any_cache = state._flash_any_cache or {}
  local input = state._flash_any_streams
  if not input or input.pattern ~= pattern then
    input = { pattern = pattern, suffixes = { [0] = pattern, [#pattern] = "" } }
    state._flash_any_streams = input
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local from, to = opts.from[1], opts.to[1]
  local cache = state._flash_any_cache[win]
  if not cache or cache.buf ~= buf or cache.from ~= from or cache.to ~= to or cache.tick ~= tick then
    cache = { buf = buf, from = from, to = to, tick = tick,
      lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false) }
    state._flash_any_cache[win] = cache
  end
  if cache.pattern ~= pattern or cache.sources ~= sources then
    local previous = cache.pattern
    local incremental = cache.sources == sources
      and previous and previous ~= "" and #pattern > #previous and pattern:sub(1, #previous) == previous
    if incremental then
      -- A newly appended continuation byte can repair a previously invalid
      -- codepoint; that is an input replacement rather than character append.
      local byte = pattern:byte(#previous + 1)
      incremental = byte < 0x80 or byte >= 0xC0
    end
    local matches, frontiers = {}, {}
    for i, text in ipairs(cache.lines) do
      local found, frontier = scan_line(text, from + i - 1, pattern, sources,
        input.suffixes, incremental and cache.frontiers[i] or nil)
      vim.list_extend(matches, found)
      frontiers[i] = frontier
    end
    cache.matches, cache.frontiers = matches, frontiers
    cache.pattern, cache.sources = pattern, sources
  end
  local ret = {}
  for _, match in ipairs(cache.matches) do
    ret[#ret + 1] = {
      win = win,
      pos = { match.line, match.start_col },
      end_pos = { match.line, match.end_col },
      next = match.next,
    }
  end
  if state.labels then
    local labels = state:labels()
    local blocked = {}
    for _, item in ipairs(ret) do
      for value in pairs(item.next) do blocked[value] = true end
    end
    local label_index = 1
    for _, item in ipairs(ret) do
      while label_index <= #labels and blocked[labels[label_index]] do
        label_index = label_index + 1
      end
      if label_index <= #labels then
        item.label = labels[label_index]
        label_index = label_index + 1
      end
    end
  end
  return ret
end

---Single-character search; lines are loaded and cached only when requested.
---@param win integer
---@param state table
---@param opts table
---@param sources FlashAnySource[]
---@return FlashAnyDisplayMatch[]
function M.char(win, state, opts, sources)
  local pattern = state.pattern()
  if pattern == "" then return {} end
  local buf = vim.api.nvim_win_get_buf(win)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  state._flash_any_char_cache = state._flash_any_char_cache or {}
  local cache = state._flash_any_char_cache[win]
  if not cache or cache.buf ~= buf or cache.tick ~= tick or cache.pattern ~= pattern or cache.sources ~= sources then
    cache = { buf = buf, tick = tick, pattern = pattern, sources = sources, lines = {} }
    state._flash_any_char_cache[win] = cache
  end
  local ret = {}
  local last = math.min(opts.to[1], vim.api.nvim_buf_line_count(buf))
  for row = math.max(1, opts.from[1]), last do
    local matches = cache.lines[row]
    if not matches then
      matches = {}
      local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      for next_col, char in utf8.iter_char(text) do
        if next_col and char and #match_char(char, pattern, sources) > 0 then
          matches[#matches + 1] = next_col - #char
        end
      end
      cache.lines[row] = matches
    end
    for _, col in ipairs(matches) do
      ret[#ret + 1] = { win = win, pos = { row, col }, end_pos = { row, col }, next = {} }
    end
  end
  return ret
end

return M

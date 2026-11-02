-- Unicode 17.0.0 extended grapheme clusters, UAX #29 rev. 47.
-- Invalid UTF-8 bytes are isolated; no normalization or font shaping is applied.
local M = {}
local pages = require("flash-any.grapheme_data")
local band = bit.band

local function property(cp)
  if cp < 128 then
    if cp == 13 then
      return 1
    end
    if cp == 10 then
      return 2
    end
    return (cp < 32 or cp == 127) and 3 or 0
  end
  if cp >= 0xAC00 and cp <= 0xD7A3 then
    return (cp - 0xAC00) % 28 == 0 and 12 or 13
  end
  local page = pages[math.floor(cp / 256)]
  if not page then
    return 0
  end
  local low, left, right = cp % 256, 1, #page / 3
  while left <= right do
    local middle = math.floor((left + right) / 2)
    local i = middle * 3 - 2
    if low < page[i] then
      right = middle - 1
    elseif low > page[i + 1] then
      left = middle + 1
    else
      return page[i + 2]
    end
  end
  return 0
end

-- Return scalar and next 1-based byte index; malformed bytes consume one byte.
local function decode(value, i)
  local a, b, c, d = value:byte(i, i + 3)
  if a < 128 then
    return a, i + 1
  end
  if a < 0xC2 or a > 0xF4 or not b or b < 0x80 or b > 0xBF then
    return -1, i + 1
  end
  if a < 0xE0 then
    return (a - 0xC0) * 64 + b - 0x80, i + 2
  end
  if not c or c < 0x80 or c > 0xBF or a == 0xE0 and b < 0xA0 or a == 0xED and b >= 0xA0 then
    return -1, i + 1
  end
  if a < 0xF0 then
    return (a - 0xE0) * 4096 + (b - 0x80) * 64 + c - 0x80, i + 3
  end
  if not d or d < 0x80 or d > 0xBF or a == 0xF0 and b < 0x90 or a == 0xF4 and b >= 0x90 then
    return -1, i + 1
  end
  return (a - 0xF0) * 262144 + (b - 0x80) * 4096 + (c - 0x80) * 64 + d - 0x80, i + 4
end

-- Callback: start/end 0-based byte offsets (end exclusive), codepoint count,
-- and the final codepoint's starting byte offset (for editor match ranges).
-- Always scan from line start to preserve RI parity and Indic/ZWJ lookbehind.
---@param value string
---@param emit fun(first: integer, after: integer, count: integer, last: integer)
function M.each(value, emit)
  local i, start, chars, previous, last = 1, 0, 0, nil, 0
  local ri, pictographic, zwj_after_pic, conjunct = 0, false, false, 0
  while i <= #value do
    local cp, after = decode(value, i)
    local prop = cp < 0 and 3 or property(cp)
    local g, incb, pic = band(prop, 15), band(prop, 96), band(prop, 16) ~= 0
    local boundary = true
    if previous then
      if previous == 1 and g == 2 then
        boundary = false -- GB3
      elseif previous >= 1 and previous <= 3 or g >= 1 and g <= 3 then
        boundary = true -- GB4/5
      elseif previous == 9 and (g == 9 or g == 10 or g == 12 or g == 13) then
        boundary = false -- GB6
      elseif (previous == 12 or previous == 10) and (g == 10 or g == 11) then
        boundary = false -- GB7
      elseif (previous == 13 or previous == 11) and g == 11 then
        boundary = false -- GB8
      elseif g == 4 or g == 5 or g == 8 or previous == 7 then
        boundary = false -- GB9/9a/9b
      elseif conjunct == 2 and incb == 32 then
        boundary = false -- GB9c
      elseif previous == 5 and zwj_after_pic and pic then
        boundary = false -- GB11
      elseif previous == 6 and g == 6 and ri % 2 == 1 then
        boundary = false
      end -- GB12/13
      if boundary then
        emit(start, i - 1, chars, last)
        start, chars = i - 1, 0
        ri, pictographic, conjunct = 0, false, 0
      end
    end
    zwj_after_pic = g == 5 and pictographic
    if pic then
      pictographic = true
    elseif g ~= 4 then
      pictographic = false
    end
    ri = g == 6 and ri + 1 or 0
    if incb == 32 then
      conjunct = 1
    elseif incb == 96 and conjunct > 0 then
      conjunct = 2
    elseif incb ~= 64 then
      conjunct = 0
    end
    last = i - 1
    previous, chars, i = g, chars + 1, after
  end
  if previous then
    emit(start, #value, chars, last)
  end
end

---@param value string
---@return string[]
function M.split(value)
  local clusters = {}
  M.each(value, function(first, after)
    clusters[#clusters + 1] = value:sub(first + 1, after)
  end)
  return clusters
end

---@param value string
---@return integer
function M.len(value)
  local count = 0
  M.each(value, function()
    count = count + 1
  end)
  return count
end

return M

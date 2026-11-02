local M = {}
M.__index = M
local each = require("flash-any.grapheme").each

---A cached Unicode string with a movable cursor. Sources only call get.
---@class FlashAnyCursor
---@field value string Complete, immutable text or input.
---@field offset integer Current 0-based byte column.
---@field private _index integer Current index in _offsets.
---@field private _offsets integer[] Extended grapheme cluster boundaries, starting with 0.
---@field private _indices table<integer, integer> Byte boundary -> index in _offsets.
---@field private _lasts integer[] Final codepoint start for each cluster, for Neovim match endpoints.
---@field private _values table<integer, table<integer, string>> Count -> start index -> text; count 0 caches whole suffixes.
local Cursor = M

---@param value string
---@return FlashAnyCursor
function M.new(value)
  local offsets, indices, lasts = { 0 }, { [0] = 1 }, {}
  -- Segment once from the start: RI parity and Indic/ZWJ rules need context.
  each(value, function(_, after, _, last)
    offsets[#offsets + 1] = after
    indices[after] = #offsets
    lasts[#lasts + 1] = last
  end)
  return setmetatable({
    value = value,
    offset = 0,
    _index = 1,
    _offsets = offsets,
    _indices = indices,
    _lasts = lasts,
    _values = {},
  }, Cursor)
end

---Move to a 0-based grapheme boundary; the string end is allowed.
---@param offset integer
function Cursor:set_offset(offset)
  assert(
    type(offset) == "number" and offset >= 0 and offset <= #self.value and offset % 1 == 0,
    "offset must be a byte boundary within the string"
  )
  local index = self._indices[offset]
  assert(index, "offset must be a grapheme boundary")
  self.offset, self._index = offset, index
end

---Read without advancing: all remaining text, or up to count graphemes.
---Unicode 17 extended grapheme clusters; malformed UTF-8 bytes are isolated.
---@overload fun(self: FlashAnyCursor): string
---@param count integer Omit for all remaining text; otherwise must be positive.
---@return string text Remaining text if fewer than count graphemes remain.
---@return integer? after 0-based byte offset after a complete count-grapheme span.
---@return integer? last Last codepoint's starting byte offset, only for a complete span.
function Cursor:get(count)
  ---@type integer?, integer?
  local after, last
  if count ~= nil then
    assert(type(count) == "number" and count > 0 and count % 1 == 0, "grapheme count must be a positive integer")
    local target = self._index + count
    after = self._offsets[target]
    if not after then
      return self:get()
    end
    last = self._lasts[target - 1]
  end

  -- Most callers read a few short lengths across many positions.
  local key = count or 0
  local values = self._values[key]
  if not values then
    values = {}
    self._values[key] = values
  end
  local value = values[self._index]
  local suffixes = self._values[0]
  if not value and after == #self.value and suffixes then
    value = suffixes[self._index]
  end
  if not value then
    value = self.value:sub(self.offset + 1, after)
    values[self._index] = value
  end
  if after == #self.value then
    if not suffixes then
      suffixes = {}
      self._values[0] = suffixes
    end
    suffixes[self._index] = value
  end
  if count == nil then
    return value
  end
  return value, after, last
end

---Move forward by count graphemes. Leave offset on failure.
---@param count? integer Defaults to 1; must be positive.
---@return boolean moved
function Cursor:shift(count)
  if count == nil then
    count = 1
  end
  assert(type(count) == "number" and count > 0 and count % 1 == 0, "grapheme count must be a positive integer")
  local index = self._index + count
  local offset = self._offsets[index]
  if not offset then
    return false
  end
  self.offset, self._index = offset, index
  return true
end

return M

local M = {}
M.__index = M
local next_offset = require("flash-any.utf8").iter_offset("")

---A cached Unicode string with a movable cursor. Sources only call get.
---@class FlashAnyCursor
---@field value string Complete, immutable text or input.
---@field offset integer Current 0-based byte column.
---@field private _index integer Current index in _offsets.
---@field private _offsets integer[] Decoded codepoint boundaries, starting with 0.
---@field private _indices table<integer, integer> Byte boundary -> index in _offsets.
---@field private _values table<integer, table<integer, string>> Count -> start index -> text; count 0 caches whole suffixes.
local Cursor = M

---@param value string
---@return FlashAnyCursor
function M.new(value)
  return setmetatable({
    value = value,
    offset = 0,
    _index = 1,
    _offsets = { 0 },
    _indices = { [0] = 1 },
    _values = {},
  }, Cursor)
end

-- Each boundary is decoded once, shared by all offsets and requested lengths.
---@private
---@return boolean
function Cursor:_extend()
  local offset = self._offsets[#self._offsets]
  if offset == #self.value then
    return false
  end
  local after = next_offset(self.value, offset)
  if not after then
    return false
  end
  local index = #self._offsets + 1
  self._offsets[index] = after
  self._indices[after] = index
  return true
end

---Move to a 0-based byte boundary; the string end is allowed.
---@param offset integer
function Cursor:set_offset(offset)
  assert(
    type(offset) == "number" and offset >= 0 and offset <= #self.value and offset % 1 == 0,
    "offset must be a byte boundary within the string"
  )
  while self._offsets[#self._offsets] < offset do
    self:_extend()
  end
  local index = self._indices[offset]
  assert(index, "offset must be a codepoint boundary")
  self.offset, self._index = offset, index
end

---Read without advancing: all remaining text, or up to count codepoints.
---Byte boundaries follow Neovim, including malformed and truncated UTF-8.
---@overload fun(self: FlashAnyCursor): string
---@param count integer Omit for all remaining text; otherwise must be positive.
---@return string text Remaining text if fewer than count codepoints remain.
---@return integer? after 0-based byte offset after a complete count-codepoint span.
---@return integer? last Last codepoint's starting byte offset, only for a complete span.
function Cursor:get(count)
  ---@type integer?, integer?
  local after, last
  if count ~= nil then
    assert(type(count) == "number" and count > 0 and count % 1 == 0, "codepoint count must be a positive integer")
    local target = self._index + count
    while #self._offsets < target do
      if not self:_extend() then
        return self:get()
      end
    end
    after, last = self._offsets[target], self._offsets[target - 1]
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

---Move forward by count codepoints, sharing get's cache. Leave offset on failure.
---@param count? integer Defaults to 1; must be positive.
---@return boolean moved
function Cursor:shift(count)
  if count == nil then
    count = 1
  end
  local _, after = self:get(count)
  if not after then
    return false
  end
  self:set_offset(after)
  return true
end

return M

-- Frozen Lua reference for differential tests; never loaded by the plugin.
local M = {}
M.__index = M
local each = require("flash-any.grapheme").each

---A cached Unicode string with a movable cursor. Sources only read.
---@class ReferenceCursor
---@field value string Complete, immutable text or input.
---@field offset integer Current 0-based byte column.
---@field private _index integer Current index in _graphemes.
---@field private _graphemes integer[] Grapheme boundary -> 1-based codepoint index, including the string end.
---@field private _offsets integer[] Codepoint boundary -> 0-based byte offset, including the string end.
---@field private _codepoints integer[] Decoded scalars; malformed UTF-8 bytes are -1.
---@field private _values table<integer, table<integer, string>> Count -> start index -> text; count 0 caches whole suffixes.
local Cursor = M

---@param value string
---@return ReferenceCursor
function M.new(value)
	local graphemes, offsets, codepoints = { 1 }, { 0 }, {}
	-- Segment once from the start: RI parity and Indic/ZWJ rules need context.
	each(value, function(_, _, count)
		graphemes[#graphemes + 1] = graphemes[#graphemes] + count
	end, function(codepoint, after)
		codepoints[#codepoints + 1] = codepoint
		offsets[#offsets + 1] = after
	end)
	return setmetatable({
		value = value,
		offset = 0,
		_index = 1,
		_graphemes = graphemes,
		_offsets = offsets,
		_codepoints = codepoints,
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
	-- Scans advance in order; backward resumes walk the existing boundaries again.
	local graphemes, offsets = self._graphemes, self._offsets
	local index = offset >= self.offset and self._index or 1
	while offsets[graphemes[index]] < offset do
		index = index + 1
	end
	assert(offsets[graphemes[index]] == offset, "offset must be a grapheme boundary")
	self.offset, self._index = offset, index
end

---Read without advancing: all remaining text, or up to count graphemes.
---Unicode 17 extended grapheme clusters; malformed UTF-8 bytes are isolated.
---@overload fun(self: ReferenceCursor): string
---@param count integer Omit for all remaining text; otherwise must be positive.
---@return string text Remaining text if fewer than count graphemes remain.
---@return integer? after 0-based byte offset after a complete count-grapheme span.
---@return integer? last Last codepoint's starting byte offset, only for a complete span.
function Cursor:get(count)
	---@type integer?, integer?
	local after, last
	if count ~= nil then
		assert(type(count) == "number" and count > 0 and count % 1 == 0, "grapheme count must be a positive integer")
		local target = self._graphemes[self._index + count]
		after = target and self._offsets[target]
		if not after then
			return self:get()
		end
		last = self._offsets[target - 1]
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

---Read a Unicode codepoint relative to the current position, without advancing.
---@param pos? integer Codepoint offset: 0 is current (default), 1 is next, -1 is previous.
---@return integer? codepoint Unicode scalar, -1 for a malformed UTF-8 byte, nil outside the string.
function Cursor:get_codepoint(pos)
	if pos == nil then
		pos = 0
	end
	assert(type(pos) == "number" and pos % 1 == 0, "codepoint offset must be an integer")
	return self._codepoints[self._graphemes[self._index] + pos]
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
	local codepoint_index = self._graphemes[index]
	if not codepoint_index then
		return false
	end
	local offset = self._offsets[codepoint_index]
	self.offset, self._index = offset, index
	return true
end

return M

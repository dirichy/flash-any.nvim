-- Build-time adapters; C owns UTF-8 decoding and Unicode grapheme boundaries.
local native = require("flash-any.native").grapheme
local M = { each = native.each, len = native.len }

---@param value string
---@return string[]
function M.split(value)
	local clusters = {}
	M.each(value, function(first, after)
		clusters[#clusters + 1] = value:sub(first + 1, after)
	end)
	return clusters
end

return M

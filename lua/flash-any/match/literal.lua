local M = {}

---@param char string
---@param stream string
---@param _ FlashAnyMatcherArgs
---@return FlashAnyMatcherResult[]?
function M.matcher(char, stream, _)
  -- This source recognizes ASCII buffer characters only; stream may be UTF-8.
  local byte = char:byte()
  if byte >= 0x80 then return nil end
  if stream == "" then return { { next = { [char] = true } } } end
  if stream:byte() == byte then return { { consumed = 1 } } end
  return {}
end

return M

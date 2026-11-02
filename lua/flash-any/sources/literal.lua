---@param text FlashAnyCursor
---@param stream FlashAnyCursor
---@param _ FlashAnySource
---@param emit FlashAnyEmit
---@return boolean
local function matcher(text, stream, _, emit)
  local char = text:get(1)
  if char == "" then
    return false
  end
  if char:byte() >= 0x80 then
    return false
  end
  local input = stream:get(1)
  if input == "" then
    emit(char)
  elseif input == char then
    emit(1)
  end
  return true
end

---@return { matcher: FlashAnyMatcher, scope?: FlashAnyScope }
return function()
  return { matcher = matcher }
end

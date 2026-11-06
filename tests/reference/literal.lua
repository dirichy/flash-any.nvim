-- Frozen Lua reference for differential tests; never loaded by the plugin.
---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param _ ReferenceSource
---@param emit ReferenceEmit
---@return boolean
local function matcher(text, stream, _, emit)
	local char = text:get(1)
	if #char ~= 1 then
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

---@param _? table
---@return ReferenceSourceDefinition
return function(_)
	return { matcher = matcher }
end

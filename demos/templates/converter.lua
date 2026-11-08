-- Optional build-time converter. Return nil or {} to omit a grapheme.
return function(codes)
	local result = {}
	for _, code in ipairs(codes) do
		result[#result + 1] = code:lower()
	end
	return result
end

-- Test-only canonical TSV input. The Lua oracle owns its data and prefix checks;
-- it does not call a production parser, lookup engine or native matcher.
local M = {}

---@param path string
---@param decode fun(value: string): string[]
---@return ReferenceTable
function M.read(path, decode)
	local file = assert(io.open(vim.fn.expand(path), "rb"))
	local rows, seen = {}, {}
	for line in file:lines() do
		local text, code = line:gsub("\r$", ""):match("^([^\t]+)\t([^\t]+)")
		if text and code then
			seen[text] = seen[text] or {}
			if not seen[text][code] then
				seen[text][code] = true
				rows[text] = rows[text] or {}
				vim.list_extend(rows[text], decode(code))
			end
		end
	end
	file:close()
	return rows
end

---@param path string
---@param opts {decode: fun(value: string): string[]}
---@return ReferenceTableLoader
function M.loader(path, opts)
	local rows, prefixes = M.read(path, opts.decode), {}
	for text in pairs(rows) do
		for byte = 1, #text - 1 do
			prefixes[text:sub(1, byte)] = true
		end
	end
	return function(text)
		return rows[text], prefixes[text] or false
	end
end

return M

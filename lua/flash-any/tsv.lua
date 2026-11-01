local M = {}

--- parser tsv line
---@param line string
---@param separator string
---@return string?,string?
local function split(line, separator)
	local pos = line:find(separator, 0, true)
	if pos then
		-- read("*l") removes LF but keeps the CR in CRLF files.
		local last = line:byte(-1) == 13 and -2 or -1
		return line:sub(1, pos - 1), line:sub(pos + #separator, last)
	end
end

local function read_at(file, position, aligned)
	file:seek("set", position)
	if position > 0 and not aligned then
		local _ = file:read("*l")
	end
	local start = file:seek()
	return start, file:read("*l")
end

---@param path string
---@param opts? { separator?: string, decode?: fun(value: string): string[] }
---@return fun(char: string): string[]? loader Owns the file handle; results are not cached here.
function M.loader(path, opts)
	opts = opts or {}
	local separator = opts.separator or "\t"
	local decode = opts.decode or function(value)
		return { value }
	end
	local file = assert(io.open(vim.fn.expand(path), "rb"))
	local size = file:seek("end")
	-- Heap indices 1..63 cover the first six binary-search levels.
	---@type table<integer, { key?: string, position: number, after: number }>
	local nodes = {}

	return function(char)
		-- Keys are UTF-8 sorted by bytes; decoded code-table values are ASCII.
		local low, high, index = 0, size, 1
		local found
		while high - low > 64 do
			local middle = math.floor((low + high) / 2)
			local node = nodes[index]
			local position, key, after
			if node then
				position, key, after = node.position, node.key, node.after
			else
				local line
				position, line = read_at(file, middle, false)
				key = line and split(line, separator)
				after = file:seek()
				if index < 64 then
					nodes[index] = { key = key, position = position, after = after }
				end
			end
			if key == char then
				found = position
				break
			elseif key and key < char then
				low = after
				index = index * 2 + 1
			else
				-- read_at may skip the row containing middle. Shrink by the
				-- byte midpoint so that row remains a possible candidate.
				high = middle
				index = index * 2
			end
		end

		local _, line = read_at(file, found or low, true)
		local result = {}
		while line do
			local key, value = split(line, separator)
			if not key or key > char then
				break
			elseif key == char then
				for _, item in ipairs(decode(value)) do
					result[#result + 1] = item
				end
			end
			line = file:read("*l")
		end
		return #result > 0 and result or nil
	end
end

return M

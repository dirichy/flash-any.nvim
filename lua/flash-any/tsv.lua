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
		local value = line:sub(pos + #separator, last)
		if separator == "\t" then
			value = value:match("^[^\t]*")
		end
		return line:sub(1, pos - 1), value
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
---@return fun(key: string, offset?: number): string[]?, number|false loader Codes and continuation offset; false prunes longer prefixes.
function M.loader(path, opts)
	opts = opts or {}
	local separator = opts.separator or "\t"
	local decode = opts.decode or function(value)
		return { value }
	end
	local file = assert(io.open(vim.fn.expand(path), "rb"))
	local size = file:seek("end")
	-- Keep the first six binary-search levels and every exact-hit node.
	-- Per-key continuation offsets belong to table.lookup, alongside decoded codes.
	---@type table<integer, { key?: string, position: number, after: number }>
	local nodes = {}

	return function(char, offset)
		-- Keys are UTF-8 sorted by bytes; decoded code-table values are ASCII.
		local low, high, index = offset or 0, size, 1
		local cached = offset == nil
		-- A parent prefix often leaves us directly on the next candidate row.
		local _, first = read_at(file, low, true)
		local first_key = first and split(first, separator)
		if first_key and first_key >= char then
			high = low
		end
		while high - low > 64 do
			local middle = math.floor((low + high) / 2)
			local node = cached and nodes[index]
			local position, key, after
			if node then
				position, key, after = node.position, node.key, node.after
			else
				local line
				position, line = read_at(file, middle, false)
				key = line and split(line, separator)
				after = file:seek()
				if cached and (index < 64 or key == char) then
					nodes[index] = { key = key, position = position, after = after }
				end
			end
			if key and key < char then
				low = after
				index = index * 2 + 1
			else
				-- read_at may skip the row containing middle. Shrink by the
				-- byte midpoint so that row remains a possible candidate.
				high = middle
				index = index * 2
			end
		end

		local position, line = read_at(file, low, true)
		local result = {}
		while line do
			local key, value = split(line, separator)
			if not key or key > char then
				return #result > 0 and result or nil, key ~= nil and key:sub(1, #char) == char and position or false
			elseif key == char then
				for _, item in ipairs(decode(value)) do
					result[#result + 1] = item
				end
			end
			position = file:seek()
			line = file:read("*l")
		end
		return #result > 0 and result or nil, false
	end
end

---Materialize canonical sorted TSV through the shared build parser.
---@param path string
---@param decode fun(value: string): string[]
---@return table<string, string[]>
function M.read(path, decode)
	local rows = require("flash-any.build").read(path, { format = "tsv" })
	for key, values in pairs(rows) do
		local codes = {}
		for _, value in ipairs(values) do
			vim.list_extend(codes, decode(value))
		end
		rows[key] = codes
	end
	return rows
end

return M

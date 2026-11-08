local M = {}

---@class FlashAnyDisplayMatch
---@field win integer
---@field pos integer[]
---@field end_pos integer[]
---@field next table<string, boolean>
---@field label? string

---@class FlashAnyNativeEngine
---@field new_state fun(self: FlashAnyNativeEngine): FlashAnyNativeEngine
---@field has fun(self: FlashAnyNativeEngine, win: integer, buf: integer, tick: integer, from: integer, to: integer): boolean
---@field scan fun(self: FlashAnyNativeEngine, win: integer, buf: integer, tick: integer, from: integer, to: integer, lines: string[]?, pattern: string, labels: string[]?, motion?: string): FlashAnyDisplayMatch[]

---@class FlashAnyNativeModule
---@field grapheme FlashAnyGrapheme
---@field modes table<string, integer>
---@field version string
---@field open fun(path: string): FlashAnyNativeEngine
---@field write fun(keys: string[], codes: table[][], path: string, groups?: string[][])

local file = assert(vim.api.nvim_get_runtime_file("lua/flash-any/native.lua", false)[1])
local root = vim.fn.fnamemodify(file, ":h:h:h")
local library = root .. "/lua/flash-any/native.so"
local loader, load_error = package.loadlib(library, "luaopen_flash_any_native")
assert(loader, "Unable to load flash-any C module; run make in " .. root .. ":\n" .. tostring(load_error))
---@type FlashAnyNativeModule
local native = loader()
M.modes = native.modes
---@class FlashAnyGrapheme
---@field len fun(value: string): integer
---@field each fun(value: string, emit: fun(first: integer, after: integer, count: integer, last: integer), emit_codepoint?: fun(codepoint: integer, after: integer))
M.grapheme = native.grapheme

local stamp = require("flash-any.stamp")

local package_hash
local warned_data = false
local DATA_WARNING_LIMIT = 200
local function package_fingerprint()
	if not package_hash then
		local inputs = {}
		-- Track installed build code and bundled tables without executing source factories.
		-- These modules have require caches too; package updates take effect after restarting Nvim.
		local paths = vim.api.nvim_get_runtime_file("lua/flash-any/**/*.lua", true)
		vim.list_extend(paths, vim.api.nvim_get_runtime_file("lua/flash-any/**/*.tsv", true))
		table.sort(paths)
		for _, path in ipairs(paths) do
			inputs[#inputs + 1] = stamp(path)
		end
		package_hash = vim.fn.sha256(table.concat(inputs, "\n"))
	end
	return package_hash
end

---@param path? string
---@param sources? FlashAnySourceSpec[]
---@return FlashAnyNativeEngine
function M.load(path, sources)
	if not path then
		assert(sources, "provide sources or a compiled binary")
		local inputs = { native.version, package_fingerprint() }
		local data_count = 0
		-- Follow the reader's import graph so a changed sub-dictionary selects a new snapshot.
		for _, source in ipairs(sources) do
			if type(source) == "table" then
				---@cast source FlashAnySourceConfig
				local data = source.data
				if not warned_data and type(data) == "table" then
					local codes = rawget(data, "codes")
					if type(codes) == "table" then
						data = codes
					end
					for _ in pairs(data) do
						data_count = data_count + 1
						if data_count > DATA_WARNING_LIMIT then
							warned_data = true
							vim.notify(
								(
									"flash-any: inline data exceeds %d entries; setup copies and hashes the table. "
									.. "Use file for large dictionaries so cache checks only inspect file metadata."
								):format(DATA_WARNING_LIMIT),
								vim.log.levels.WARN
							)
							break
						end
					end
				end
				if source.file then
					assert(type(source.file) == "string", "file must be a dictionary path")
					inputs[#inputs + 1] = require("flash-any.build").fingerprint(source.file, source)
				end
				for _, field in ipairs({ "lua", "tsv", "converter" }) do
					if source[field] then
						inputs[#inputs + 1] = stamp(source[field])
					end
				end
			end
		end
		inputs[#inputs + 1] = vim.inspect(sources)
		local key = vim.fn.sha256(table.concat(inputs, "\n"))
		path = vim.fn.stdpath("cache") .. "/flash-any/" .. key .. ".bin"
	end
	path = vim.fn.expand(path)
	if not vim.uv.fs_stat(path) then
		assert(sources, "binary is missing; provide sources to build it automatically: " .. path)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		require("flash-any.build").binary({ sources = sources, output = path })
	end
	return native.open(path)
end

---Build-time only; C owns serialization, indexes and atomic file replacement.
---@param path string
---@param keys string[]
---@param codes table[][]
---@param groups? string[][]
function M.write(path, keys, codes, groups)
	native.write(keys, codes, path, groups)
end

---@param state table
---@param book FlashAnyNativeEngine
---@return FlashAnyNativeEngine
local function session_for(state, book)
	local session = state._flash_any_native
	if not session or session.book ~= book then
		session = { book = book, engine = book:new_state() }
		state._flash_any_native = session
	end
	return session.engine
end

---@param win integer
---@param state table
---@param range table
---@param engine FlashAnyNativeEngine
---@return FlashAnyDisplayMatch[]
function M.get(win, state, range, engine)
	local pattern = state.pattern()
	if pattern == "" then
		return {}
	end
	engine = session_for(state, engine)
	local buf = vim.api.nvim_win_get_buf(win)
	local from, to = math.max(1, range.from[1]), math.min(range.to[1], vim.api.nvim_buf_line_count(buf))
	if from > to then
		return {}
	end
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local lines = not engine:has(win, buf, tick, from, to) and vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
		or nil
	return engine:scan(win, buf, tick, from, to, lines, pattern, state.labels and state:labels() or nil)
end

---@param win integer
---@param state table
---@param range table
---@param engine FlashAnyNativeEngine
---@param motion? string
---@return FlashAnyDisplayMatch[]
function M.char(win, state, range, engine, motion)
	local pattern = state.pattern()
	if pattern == "" then
		return {}
	end
	engine = session_for(state, engine)
	local buf = vim.api.nvim_win_get_buf(win)
	local first, last = math.max(1, range.from[1]), math.min(range.to[1], vim.api.nvim_buf_line_count(buf))
	local tick, ret = vim.api.nvim_buf_get_changedtick(buf), {}
	for row = first, last do
		local lines = not engine:has(win, buf, tick, row, row) and vim.api.nvim_buf_get_lines(buf, row - 1, row, false)
			or nil
		vim.list_extend(ret, engine:scan(win, buf, tick, row, row, lines, pattern, nil, motion or "f"))
	end
	return ret
end

return M

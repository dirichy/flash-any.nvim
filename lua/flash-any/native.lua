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
---@field scan fun(self: FlashAnyNativeEngine, win: integer, buf: integer, tick: integer, from: integer, to: integer, lines: string[]?, pattern: string, labels: string[]?, motion?: string, ignorecase?: boolean): FlashAnyDisplayMatch[]

---@class FlashAnyNativeModule
---@field grapheme FlashAnyGrapheme
---@field modes table<string, integer>
---@field version string
---@field open fun(path: string): FlashAnyNativeEngine
---@field write fun(keys: string[], codes: table[][], path: string, groups?: string[][])

local compiler = require("flash-any.compiler")
---@type FlashAnyNativeModule?
local native
---@class FlashAnyGrapheme
---@field len fun(value: string): integer
---@field each fun(value: string, emit: fun(first: integer, after: integer, count: integer, last: integer), emit_codepoint?: fun(codepoint: integer, after: integer))

-- Build tools use these fields synchronously; setup uses load's asynchronous path.
setmetatable(M, {
	__index = function(_, key)
		if key == "modes" or key == "grapheme" then
			native = assert(compiler.load())
			M.modes, M.grapheme = native.modes, native.grapheme
			return rawget(M, key)
		end
	end,
})

function M.ready()
	return native ~= nil
end

local stamp = require("flash-any.stamp")

-- Bump when Lua compilation changes without a native format/version change.
local CACHE_VERSION = 2
local warned_data = false
local DATA_WARNING_LIMIT = 200

local pending = {}

---@param path? string
---@param sources? FlashAnySourceSpec[]
---@overload fun(path?: string, sources?: FlashAnySourceSpec[]): FlashAnyNativeEngine
---@param ready fun(engine: FlashAnyNativeEngine?, err: string?)
---@param force? boolean
---@return FlashAnyNativeEngine?
function M.load(path, sources, ready, force)
	if not native then
		local core = compiler.load(ready and function(value, err)
			if not value then
				vim.notify("flash-any: " .. tostring(err), vim.log.levels.ERROR)
				ready(nil, err)
				return
			end
			native = value
			local ok, engine = pcall(M.load, path, sources, ready, force)
			if not ok then
				vim.notify("flash-any: " .. tostring(engine), vim.log.levels.ERROR)
				ready(nil, tostring(engine))
			elseif engine then
				ready(engine)
			end
		end or nil)
		if not core then
			return
		end
		native = core
	end
	if not path then
		assert(sources, "provide sources or a compiled binary")
		local inputs = { native.version, tostring(CACHE_VERSION) }
		local data_count = 0
		-- Follow the reader's import graph so a changed sub-dictionary selects a new snapshot.
		for _, source in ipairs(sources) do
			local name = type(source) == "string" and source or type(source) == "table" and source.name
			if name then
				assert(type(name) == "string", "source name must be a string")
				local _, version = require("flash-any.factory").load(name)
				inputs[#inputs + 1] = vim.inspect({ name, version })
			end
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
					inputs[#inputs + 1] = require("flash-any.reader").fingerprint(source.file, source)
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
	if ready and pending[path] then
		pending[path][#pending[path] + 1] = ready
		return
	end
	if force or not vim.uv.fs_stat(path) then
		assert(sources, "binary is missing; provide sources to build it automatically: " .. path)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		if ready then
			pending[path] = { ready }
			local ok, err = pcall(
				require("flash-any.build").async,
				"binary",
				{ sources = sources, output = path },
				function(err)
					local callbacks = pending[path]
					pending[path] = nil
					local opened, engine = false, nil
					if not err then
						opened, engine = pcall(native.open, path)
						err = not opened and tostring(engine) or nil
					end
					if err then
						vim.notify("flash-any: " .. err, vim.log.levels.ERROR)
					end
					for _, callback in ipairs(callbacks) do
						callback(not err and engine or nil, err)
					end
				end
			)
			if not ok then
				pending[path] = nil
				error(err)
			end
			vim.notify("flash-any: building dictionary in background", vim.log.levels.INFO)
			return
		end
		require("flash-any.build").binary({ sources = sources, output = path })
	end
	return native.open(path)
end

local literal

---A small literal-only snapshot for first-build searches; no source factories are loaded.
---@return FlashAnyNativeEngine
function M.literal()
	native = native or assert(compiler.load())
	if not literal then
		local keys, codes = {}, {}
		for byte = 1, 127 do
			local key = string.char(byte)
			keys[byte], codes[byte] = key, { { native.modes.literal, key, "" } }
		end
		local path = vim.fn.tempname()
		native.write(keys, codes, path)
		literal = native.open(path)
		vim.uv.fs_unlink(path)
	end
	return literal
end

---Build-time only; C owns serialization, indexes and atomic file replacement.
---@param path string
---@param keys string[]
---@param codes table[][]
---@param groups? string[][]
function M.write(path, keys, codes, groups)
	native = native or assert(compiler.load())
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

-- Smartcase follows uppercase query letters; each C rule decides whether to fold case.
---@param pattern string
---@return boolean
local function ignorecase(pattern)
	return vim.go.ignorecase and not (vim.go.smartcase and pattern:find("[A-Z]"))
end

---Reuse cached lines when the window, buffer revision and range are unchanged.
---@param engine FlashAnyNativeEngine
---@param win integer
---@param buf integer
---@param tick integer
---@param from integer
---@param to integer
---@return string[]?
local function cached_lines(engine, win, buf, tick, from, to)
	if not engine:has(win, buf, tick, from, to) then
		return vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
	end
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
	return engine:scan(
		win,
		buf,
		tick,
		from,
		to,
		cached_lines(engine, win, buf, tick, from, to),
		pattern,
		state.labels and state:labels() or nil,
		nil,
		ignorecase(pattern)
	)
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
	local insensitive = ignorecase(pattern)
	for row = first, last do
		local lines = cached_lines(engine, win, buf, tick, row, row)
		vim.list_extend(ret, engine:scan(win, buf, tick, row, row, lines, pattern, nil, motion or "f", insensitive))
	end
	return ret
end

return M

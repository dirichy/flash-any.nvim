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
---@field modes table<string, integer>
---@field version string
---@field open fun(path: string): FlashAnyNativeEngine
---@field write fun(keys: string[], codes: table[][], path: string)

local file = assert(vim.api.nvim_get_runtime_file("lua/flash-any/native.lua", false)[1])
local root = vim.fn.fnamemodify(file, ":h:h:h")
-- Make owns dependency tracking, including rebuilding the module after updates.
local built = vim.system({ "make" }, { cwd = root, text = true }):wait()
assert(built.code == 0, "flash-any native build failed:\n" .. (built.stderr or "") .. (built.stdout or ""))
local library = root .. "/lua/flash-any/native.so"
local loader, load_error = package.loadlib(library, "luaopen_flash_any_native")
assert(loader, load_error)
---@type FlashAnyNativeModule
local native = loader()
M.modes = native.modes

---@param path? string
---@param sources? FlashAnySourceSpec[]
---@return FlashAnyNativeEngine
function M.load(path, sources)
	if not path then
		assert(sources, "provide sources or a compiled binary")
		local key = vim.fn.sha256(native.version .. vim.inspect(sources))
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
function M.write(path, keys, codes)
	native.write(keys, codes, path)
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

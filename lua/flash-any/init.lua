local flash = require("flash")
local M = {}

vim.api.nvim_create_user_command("FlashAnyBuildTable", function(command)
	local args = command.fargs
	require("flash-any.build").command({
		source = args[1],
		lua = args[2],
		tsv = args[3] ~= "-" and args[3] or nil,
		common = args[4] ~= "-" and args[4] or nil,
		format = args[5] or "auto",
		encoding = args[6] or "utf-8",
	})
end, {
	nargs = "+",
	complete = "file",
	desc = "Build flash-any Lua and optional sorted TSV tables",
})
---@type table?
local default_opts = nil
---@type FlashAnyScan?
local default_char = nil
---@type {engine?: FlashAnyNativeEngine, pending: boolean, error?: string}?
local default_book
local char_attached = false
---@type (fun(win: integer, state: Flash.State, range: {from: Pos, to: Pos}): Flash.Match[])|nil
local previous_char_matcher

---@class FlashAnyCharOptions: Flash.State.Config
---@field multi_line? boolean
---@field jump_labels? boolean

---完整配置在此校验、构建；运行层不合并默认配置或解释简写。
---@param opts table? sources 自动编译，或 binary 加载现有码表；其余字段交给 Flash。
---@return table
---@return FlashAnyScan
---@return {engine?: FlashAnyNativeEngine, pending: boolean, error?: string}
local function build_opts(opts)
	assert(type(opts) == "table", "provide complete opts or call setup before jump()")
	opts = vim.deepcopy(opts)
	assert(opts.char == nil or type(opts.char) == "boolean", "char must be a boolean")
	assert(
		opts.sources == nil or (type(opts.sources) == "table" and vim.islist(opts.sources)),
		"sources must be a list"
	)
	assert(opts.matcher == nil, "custom matchers are not supported; configure code tables in build.binary()")
	assert(opts.binary == nil or type(opts.binary) == "string", "binary must be a path")
	assert(opts.sources ~= nil or opts.binary ~= nil, "provide sources or a compiled binary")
	local native = require("flash-any.native")
	local book = { engine = default_book and default_book.engine, pending = true }
	local engine = native.load(opts.binary, opts.sources, function(value, err)
		book.engine = value or book.engine
		book.pending, book.error = false, err
	end)
	if engine then
		book.engine, book.pending = engine, false
	end
	local function dictionary_for(state)
		local snapshot = state._flash_any_dictionary
		local pattern = state.pattern()
		-- Pin the immutable dictionary across rows, windows and coroutine resumes.
		-- A completed build becomes visible only when input changes or a new state starts.
		if not snapshot or snapshot.book ~= book or snapshot.pattern ~= pattern then
			snapshot = { book = book, pattern = pattern, engine = book.engine or native.literal() }
			state._flash_any_dictionary = snapshot
		end
		if (book.pending or book.error) and state._flash_any_build_notice ~= book then
			state._flash_any_build_notice = book
			vim.notify(
				"flash-any: "
					.. (book.error and "dictionary build failed" or "dictionary is building")
					.. (book.engine and "; using previous dictionary" or "; using literal matching only"),
				vim.log.levels.WARN
			)
		end
		return snapshot.engine
	end
	local get = function(win, state, range)
		return native.get(win, state, range, dictionary_for(state))
	end
	local char = function(win, state, range, motion)
		return native.char(win, state, range, dictionary_for(state), motion)
	end
	opts.sources, opts.binary, opts.char = nil, nil, nil
	opts.labeler = function() end
	opts.matcher = get
	return opts, char, book
end

---@param opts table
function M.setup(opts)
	default_opts, default_char, default_book = build_opts(opts)
	if opts.char or char_attached then
		-- Reuse Flash's public setup with its current options, preserving user settings.
		local config = require("flash.config").get()
		local char = config.modes.char --[[@as FlashAnyCharOptions]]
		if opts.char then
			if char.matcher ~= M.char then
				previous_char_matcher = char.matcher
			end
			char.matcher = M.char
		elseif char.matcher == M.char then
			char.matcher = previous_char_matcher
		end
		flash.setup(config)
		char_attached = opts.char == true
		if not char_attached then
			previous_char_matcher = nil
		end
	end
end

---@param opts table? 完整的单次配置；nil 使用 setup 保存的配置。
---@return Flash.State
function M.jump(opts)
	local config = opts == nil and default_opts or build_opts(opts)
	return flash.jump(config)
end

---Search with the configured sources, then perform a remote operator via Flash.
---@param opts table? 完整的单次配置；nil 使用 setup 保存的配置。
---@return Flash.State
function M.remote(opts)
	local config = opts == nil and default_opts or build_opts(opts)
	return flash.remote(config)
end

---Incrementally search the current buffer without jump labels.
---@param opts table? 完整的单次配置；nil 使用 setup 保存的配置。
---@return Flash.State
function M.search(opts)
	local config = opts == nil and default_opts or build_opts(opts)
	assert(config, "call setup before search()")
	config = vim.deepcopy(config)
	local get, finish = require("flash-any.search").new(config.matcher)
	config = vim.tbl_deep_extend("force", config, {
		labels = "",
		multi_line = true,
		search = { mode = "search", incremental = true, multi_window = false, trigger = "", max_length = false },
		jump = { autojump = false, history = false, register = false },
		highlight = { backdrop = false },
	}) --[[@as table]]
	config.matcher = get
	local state = require("flash.state").new(config)
	state:loop({
		actions = {
			["<CR>"] = function(current)
				-- Commit from the original position so the jumplist and operators
				-- use the search origin; an empty/failed query restores it too.
				local target = finish(current)
				current:restore()
				if target then
					current:jump(target)
				end
				return false
			end,
		},
	})
	return state
end

---Use as flash.nvim's modes.char.matcher; Flash owns keys, repeats and labels.
---@param win integer
---@param state Flash.State
---@param range table
---@return Flash.Match[]
function M.char(win, state, range)
	assert(default_char, "call setup before using the char matcher")
	return require("flash-any.matcher").get(win, state, range, default_char, require("flash.plugins.char").motion)
end

return M

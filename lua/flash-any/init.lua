local flash = require("flash")
local M = {}

-- Our scanners receive whole-line ranges; Flash also filters by column.
local function flash_scan(win, state, range)
	local search = require("flash.search").new(win, state)
	local Pos = require("flash.search.pos")
	return search:get({ from = Pos({ range.from[1], 0 }), to = Pos({ range.to[1], math.huge }) }), search
end

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
---@class FlashAnyBook
---@field engine? FlashAnyNativeEngine
---@field pending boolean
---@field error? string
---@field rebuild fun()

---@type FlashAnyBook?
local default_book
local setting_up = false

---@class FlashAnyCharOptions: Flash.State.Config
---@field multi_line? boolean
---@field jump_labels? boolean

---Setup validates and builds the dictionary; runtime calls only merge Flash options.
---@param opts table? sources 自动编译，或 binary 加载现有码表；其余字段交给 Flash。
---@return table
---@return FlashAnyScan
---@return FlashAnyBook
local function build_opts(opts)
	assert(type(opts) == "table", "setup requires an options table")
	opts = vim.deepcopy(opts)
	assert(opts.char == nil or type(opts.char) == "boolean", "char must be a boolean")
	assert(
		opts.clear_search_register == nil or type(opts.clear_search_register) == "boolean",
		"clear_search_register must be a boolean"
	)
	assert(
		opts.sources == nil or (type(opts.sources) == "table" and vim.islist(opts.sources)),
		"sources must be a list"
	)
	assert(opts.matcher == nil, "custom matchers are not supported; configure code tables in build.binary()")
	assert(opts.labeler == nil, "custom labelers are not supported; configure labels instead")
	assert(opts.binary == nil or type(opts.binary) == "string", "binary must be a path")
	assert(opts.sources ~= nil or opts.binary ~= nil, "provide sources or a compiled binary")
	local native = require("flash-any.native")
	local sources, binary = opts.sources, opts.binary
	local book = { pending = false }
	local function load(force)
		if book.pending then
			return
		end
		if force then
			assert(sources, "rebuild requires sources in setup; a binary alone cannot be rebuilt")
		end
		local engine = native.load(binary, sources, function(value, err)
			book.engine = value or book.engine
			book.pending, book.error = false, err
		end, force)
		book.pending, book.error = true, nil
		if engine then
			book.engine, book.pending = engine, false
		end
	end
	book.rebuild = function()
		load(true)
	end
	load()
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

---Configure once per Neovim session. Failed synchronous initialization may be retried.
---@param opts table
function M.setup(opts)
	assert(
		not default_opts and not setting_up,
		"flash-any: setup() may only be called once; use rebuild() to refresh dictionaries"
	)
	setting_up = true
	local ok, options, scan, book = pcall(function()
		local config, char, dictionary = build_opts(opts)
		if opts.char then
			-- Flash owns keys and repeats; preserve all other character-mode options.
			local flash_opts = require("flash.config").get()
			local char_opts = flash_opts.modes.char --[[@as FlashAnyCharOptions]]
			char_opts.matcher = M.char
			flash.setup(flash_opts)
		end
		return config, char, dictionary
	end)
	setting_up = false
	if not ok then
		error(options)
	end
	default_opts, default_char, default_book = options, scan, book
end

---Rebuild setup's sources asynchronously, retaining the current dictionary.
function M.rebuild()
	assert(default_book, "call setup before rebuild()")
	default_book.rebuild()
end

---@param opts? table Flash options only; dictionary configuration belongs to setup.
---@return table
local function get_opts(opts)
	local config = assert(default_opts, "call setup before using flash-any")
	local ready = require("flash-any.native").ready()
	if opts == nil and ready then
		return config
	end
	if opts == nil then
		opts = {}
	end
	assert(type(opts) == "table", "Flash options must be a table")
	assert(
		opts.clear_search_register == nil or type(opts.clear_search_register) == "boolean",
		"clear_search_register must be a boolean"
	)
	assert(
		opts.sources == nil and opts.binary == nil and opts.char == nil,
		"configure sources, binary and char in setup()"
	)
	assert(opts.matcher == nil, "custom matchers are not supported")
	assert(opts.labeler == nil, "custom labelers are not supported; configure labels instead")
	local merged = vim.tbl_deep_extend("force", config, opts)
	if not ready then
		-- Let Flash select its native search and labeler for this entire invocation.
		merged.matcher, merged.labeler = nil, nil
	end
	return merged --[[@as table]]
end

---@param opts? table Single-call Flash options merged with setup.
---@return Flash.State
function M.jump(opts)
	local config = get_opts(opts)
	return flash.jump(config)
end

---Search with the configured sources, then perform a remote operator via Flash.
---@param opts? table Single-call Flash options merged with setup.
---@return Flash.State
function M.remote(opts)
	local config = get_opts(opts)
	return flash.remote(config)
end

---Incrementally search the current buffer without jump labels.
---@param opts? table Flash options and clear_search_register, merged with setup.
---@return Flash.State
function M.search(opts)
	local config = get_opts(opts)
	config = vim.deepcopy(config)
	local clear = config.clear_search_register ~= false
	config.clear_search_register = nil
	local Search = require("flash-any.search")
	local scan = config.matcher or flash_scan
	local get, finish = Search.new(scan)
	config = vim.tbl_deep_extend("force", config, {
		labels = "",
		multi_line = true,
		search = { mode = "search", incremental = true, multi_window = false, trigger = "", max_length = false },
		jump = { autojump = false, history = false, register = false },
		highlight = { backdrop = false },
	}) --[[@as table]]
	local wrap = config.search.wrap
	if config.search.wrap == nil then
		config.search.wrap = vim.o.wrapscan
	end
	config.matcher = get
	local state = require("flash.state").new(config)
	state:loop({
		actions = {
			["<CR>"] = function(current)
				-- Commit from the original position so the jumplist and operators
				-- use the search origin; an empty/failed query restores it too.
				local target = finish(current)
				current:restore()
				if not current.pattern:empty() then
					Search.remember(current, scan, wrap)
					if clear then
						vim.fn.setreg("/", "")
					end
				end
				if target then
					current:jump(target)
				end
				return false
			end,
		},
	})
	return state
end

---Repeat the native search when its register is nonempty, otherwise Flash Any's.
---@param key "n"|"N"|"gn"|"gN"
---@param opts? {forward?: boolean} Override the absolute direction.
---@return Flash.Match?
function M.search_repeat(key, opts)
	assert(default_opts, "call setup before using flash-any")
	return require("flash-any.search").repeat_search(key, opts)
end

---Use as flash.nvim's modes.char.matcher; Flash owns keys, repeats and labels.
---@param win integer
---@param state Flash.State
---@param range table
---@return Flash.Match[]
function M.char(win, state, range)
	assert(default_char, "call setup before using the char matcher")
	if not require("flash-any.native").ready() then
		local matches, search = flash_scan(win, state, range)
		state:get_matcher(win).find = function(_, opts)
			return search:find(opts) --[[@as Flash.Match]]
		end
		return matches
	end
	return require("flash-any.matcher").get(win, state, range, default_char, require("flash.plugins.char").motion)
end

return M

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
---@type FlashAnyCharScan?
local default_char = nil

---完整配置在此校验、构建；运行层不合并默认配置或解释简写。
---@param opts table? sources 自动编译，或 binary 加载现有码表；其余字段交给 Flash。
---@return table
---@return FlashAnyCharScan
local function build_opts(opts)
	assert(type(opts) == "table", "provide complete opts or call setup before jump()")
	opts = vim.deepcopy(opts)
	assert(
		opts.sources == nil or (type(opts.sources) == "table" and vim.islist(opts.sources)),
		"sources must be a list"
	)
	assert(opts.matcher == nil, "custom matchers are not supported; configure code tables in build.binary()")
	assert(opts.binary == nil or type(opts.binary) == "string", "binary must be a path")
	assert(opts.sources ~= nil or opts.binary ~= nil, "provide sources or a compiled binary")
	local native = require("flash-any.native")
	local engine = native.load(opts.binary, opts.sources)
	local get = function(win, state, range)
		return native.get(win, state, range, engine)
	end
	local char = function(win, state, range, motion)
		return native.char(win, state, range, engine, motion)
	end
	opts.sources, opts.binary = nil, nil
	opts.labeler = function() end
	opts.matcher = get
	return opts, char
end

---@param opts table
function M.setup(opts)
	default_opts, default_char = build_opts(opts)
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

---Use as flash.nvim's modes.char.matcher; Flash owns keys, repeats and labels.
---@param win integer
---@param state Flash.State
---@param range table
---@return Flash.Match[]
function M.char(win, state, range)
	assert(default_char, "call setup before using the char matcher")
	local matcher = state:get_matcher(win)
	-- HACK: Flash wraps callbacks with Matcher.from(), whose find() only searches
	-- the last visible list. Replace this instance's find() to scan on demand.
	-- Depends on State:get_matcher() and the get/find protocol in flash.search.matcher.
	---@class FlashAnyCharMatcher: Flash.Matcher
	---@field _flash_any_char? Flash.Matcher
	---@cast matcher FlashAnyCharMatcher
	local char = matcher._flash_any_char
	if not char then
		char = require("flash-any.char").new(win, state, default_char)
		matcher._flash_any_char = char
		matcher.find = char.find
	end
	return char:get(range)
end

return M

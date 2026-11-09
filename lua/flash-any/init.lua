local flash = require("flash")
local match = require("flash-any.match")
local tables = require("flash-any.table")
local build = require("flash-any.build")
local codetable = require("flash-any.match.codetable")
local registry = require("flash-any.source")
local scopes = require("flash-any.scope")
local M = {}

vim.api.nvim_create_user_command("FlashAnyBuildTable", function(command)
	local args = command.fargs
	build.command({
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
-- 用户配置只在本模块解析；match 模块接收构建完成的 FlashAnySource。
---@class FlashAnySourceConfig
---@field name? string
---@field matcher? "full_code"|"initial"|"prefix"|FlashAnyMatcher
---@field scheme? string
---@field fuzzy? boolean|table
---@field scope? FlashAnyScope
---@field fallback? boolean
---@field data? FlashAnyTableInput
---@field lua? string
---@field tsv? string
---@field loader? FlashAnyTableLoader
---@field append_space_below? integer

---@alias FlashAnySourceSpec string|FlashAnySourceConfig|FlashAnyTableInput

---@type table?
local default_opts = nil
---@type FlashAnySource[]?
local default_sources = nil

---@param matcher? string|FlashAnyMatcher
---@return FlashAnyMatcher
local function source_matcher(matcher)
	if type(matcher) == "function" then
		return matcher
	end
	if matcher == nil then
		matcher = "full_code"
	end
	assert(type(matcher) == "string", "matcher must be a mode name or function")
	return assert(codetable[matcher], "invalid code-table matcher: " .. matcher)
end

---@param values FlashAnySourceSpec[]
---@return FlashAnySource[]
local function load_sources(values)
	assert(type(values) == "table" and vim.islist(values), "opts.sources is required and must be a list")
	local literal = registry.load("literal")
	local ret, has_pinyin =
		{ {
			name = "literal",
			matcher = source_matcher(literal.matcher),
			scope = scopes.resolve(literal.scope),
		} }, false
	for _, value in ipairs(values) do
		assert(type(value) == "string" or type(value) == "table", "source must be a name or configuration table")
		local name = type(value) == "string" and value or value.name
		if name == "pinyin" then
			assert(not has_pinyin, "configure only one pinyin source; select its encoding with scheme")
			has_pinyin = true
		end
		local named_only = type(value) == "string"
		if named_only then
			value = { name = value }
		end
		if not value.name and type(value.codes) == "table" then
			value = { data = value }
		end
		if value.name or value.matcher or value.scope ~= nil or value.data or value.lua or value.loader then
			---@cast value FlashAnySourceConfig
			assert(value.fallback == nil or type(value.fallback) == "boolean", "fallback must be a boolean")
			assert(value.loader == nil or type(value.loader) == "function", "loader must be a function")
			local defaults = value.name and registry.load(value.name, not named_only and value or nil) or {}
			local data = defaults.data
			if value.lua then
				data = tables.append_space(tables.from_files(value.lua, value.tsv), value.append_space_below)
			elseif value.data then
				data = tables.append_space(tables.normalize(value.data), value.append_space_below)
			end
			if value.loader then
				data = tables.lazy(data or {}, value.loader)
			end
			local matcher = value.matcher
			if matcher == nil then
				matcher = defaults.matcher
			end
			local metadata = data and tables.metadata(data)
			local scope = value.scope
			if scope == nil then
				scope = defaults.scope
			end
			if scope == nil and metadata then
				scope = metadata.scope
			end
			local fallback = value.fallback
			if fallback == nil then
				fallback = defaults.fallback
			end
			assert(fallback == nil or type(fallback) == "boolean", "fallback must be a boolean")
			ret[#ret + 1] = {
				data = data,
				matcher = source_matcher(matcher),
				max_chars = metadata and metadata.max_chars or 1,
				scope = scopes.resolve(scope),
				name = value.name,
				fallback = fallback,
			}
		else
			---@cast value FlashAnyTableInput
			local data = tables.normalize(value)
			local metadata = tables.metadata(data)
			ret[#ret + 1] = {
				data = data,
				matcher = codetable.full_code,
				max_chars = metadata.max_chars,
				scope = scopes.resolve(metadata.scope),
			}
		end
	end
	return ret
end

---完整配置在此校验、构建；运行层不合并默认配置或解释简写。
---@param opts table? sources 必须显式提供，其余字段直接传给 Flash。
---@return table
---@return FlashAnySource[]
local function build_opts(opts)
	assert(type(opts) == "table", "provide complete opts or call setup before jump()")
	opts = vim.deepcopy(opts)
	local sources = load_sources(opts.sources)
	opts.sources = nil
	opts.labeler = function() end
	opts.matcher = function(win, state, range)
		return match.get(win, state, range, sources)
	end
	return opts, sources
end

---@param opts table
function M.setup(opts)
	default_opts, default_sources = build_opts(opts)
	vim.notify(
		"此分支不再维护，可切换到 main 分支获取更好体验，见 https://github.com/dirichy/flash-any.nvim \n 之后默认分支可能会改为 main，需要用旧版请手动设置branch='master'\n 新分支有更快（5倍）的速度，建议切换到新分支",
		vim.log.levels.WARN
	)
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
	assert(default_sources, "call setup before using the char matcher")
	local matcher = state:get_matcher(win)
	-- HACK: Flash wraps callbacks with Matcher.from(), whose find() only searches
	-- the last visible list. Replace this instance's find() to scan on demand.
	-- Depends on State:get_matcher() and the get/find protocol in flash.search.matcher.
	---@class FlashAnyCharMatcher: Flash.Matcher
	---@field _flash_any_char? Flash.Matcher
	---@cast matcher FlashAnyCharMatcher
	local char = matcher._flash_any_char
	if not char then
		char = require("flash-any.char").new(win, state, default_sources)
		matcher._flash_any_char = char
		matcher.find = char.find
	end
	return char:get(range)
end

return M

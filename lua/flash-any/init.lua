local flash = require("flash")
local match = require("flash-any.match")
local tables = require("flash-any.table")
local build = require("flash-any.build")
local codetable = require("flash-any.match.codetable")
local literal = require("flash-any.match.literal")
local M = {}

vim.api.nvim_create_user_command("FlashAnyBuildTable", function(command)
  local args = command.fargs
  build.command({
    source = args[1],
    lua = args[2],
    tsv = args[3],
    common = args[4] ~= "-" and args[4] or nil,
    format = args[5] or "auto",
    encoding = args[6] or "utf-8",
  })
end, {
  nargs = "+",
  complete = "file",
  desc = "Build flash-any Lua and sorted TSV tables",
})
-- 用户配置只在本模块解析；match 模块接收构建完成的 FlashAnySource。
---@class FlashAnySourceConfig
---@field name? string
---@field matcher? "full_code"|"initial"|"prefix"|FlashAnyMatcher
---@field scheme? string
---@field fuzzy? boolean|table
---@field fallback? boolean
---@field data? table<string, string|string[]>
---@field lua? string
---@field tsv? string
---@field loader? fun(char: string): string[]?
---@field append_space_below? integer

---@alias FlashAnySourceSpec string|FlashAnySourceConfig|table<string, string|string[]>

---@type table?
local default_opts = nil

-- Unicode and Nerd Font names are meant to be discoverable from any prefix;
-- ordinary code tables require an exact code unless they opt into another
-- matcher explicitly.
---@param name? string
---@param matcher? string|FlashAnyMatcher
---@param scheme? string
---@return FlashAnyMatcher
local function source_matcher(name, matcher, scheme)
  if type(matcher) == "function" then return matcher end
  if matcher == nil then
    if name == "literal" then return literal.matcher end
    matcher = name == "pinyin" and not scheme and "initial"
      or (name == "unicode" or name == "nerdfont") and "prefix" or "full_code"
  end
  assert(type(matcher) == "string", "matcher must be a mode name or function")
  return assert(codetable[matcher], "invalid code-table matcher: " .. matcher)
end

---@param values FlashAnySourceSpec[]
---@return FlashAnySource[]
local function load_sources(values)
  assert(type(values) == "table" and vim.islist(values), "opts.sources is required and must be a list")
  local ret, has_pinyin = { { name = "literal", matcher = literal.matcher } }, false
  for _, value in ipairs(values) do
    assert(type(value) == "string" or type(value) == "table", "source must be a name or configuration table")
    local name = type(value) == "string" and value or value.name
    if name == "pinyin" then
      assert(not has_pinyin, "configure only one pinyin source; select its encoding with scheme")
      has_pinyin = true
    end
    if type(value) == "string" then
      ret[#ret + 1] = {
        data = value ~= "literal" and tables.load(value) or nil,
        matcher = source_matcher(value),
        name = value,
        fallback = value == "unicode",
      }
    elseif value.name or value.matcher or value.data or value.lua or value.loader then
      ---@cast value FlashAnySourceConfig
      assert(value.fallback == nil or type(value.fallback) == "boolean", "fallback must be a boolean")
      assert(value.loader == nil or type(value.loader) == "function", "loader must be a function")
      local matcher = source_matcher(value.name, value.matcher, value.scheme)
      local fallback = value.fallback
      if fallback == nil then fallback = value.name == "unicode" end
      local data
      if value.lua then
        data = tables.append_space(tables.from_files(value.lua, value.tsv), value.append_space_below)
      elseif value.data then
        data = tables.append_space(tables.normalize(value.data), value.append_space_below)
      elseif value.name and value.name ~= "literal" then
        data = tables.load(value.name, value)
      end
      if value.loader then
        data = tables.lazy(data or {}, value.loader)
      end
      ret[#ret + 1] = {
        data = data,
        matcher = matcher,
        name = value.name,
        fallback = fallback,
      }
    else
      ret[#ret + 1] = { data = tables.normalize(value), matcher = codetable.full_code }
    end
  end
  return ret
end

---完整配置在此校验、构建；运行层不合并默认配置或解释简写。
---@param opts table? sources 必须显式提供，其余字段直接传给 Flash。
---@return table
local function build_opts(opts)
  assert(type(opts) == "table", "provide complete opts or call setup before jump()")
  opts = vim.deepcopy(opts)
  local sources = load_sources(opts.sources)
  opts.sources = nil
  opts.labeler = function() end
  opts.matcher = function(win, state, range)
    return match.get(win, state, range, sources)
  end
  return opts
end

---@param opts table
function M.setup(opts)
  default_opts = build_opts(opts)
end

---@param opts table? 完整的单次配置；nil 使用 setup 保存的配置。
---@return Flash.State
function M.jump(opts)
  return flash.jump(opts == nil and default_opts or build_opts(opts))
end

return M

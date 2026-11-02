local M = {}
local tables = require("flash-any.table")

---@class FlashAnySourceDefinition
---@field codetable? string Table name under flash-any.tables; mutually exclusive with data.
---@field data? FlashAnyTable Prepared data; may have a lazy __index.
---@field matcher? "full_code"|"initial"|"prefix"|FlashAnyMatcher
---@field scope? FlashAnyScope
---@field fallback? boolean

-- Only default instances are shared; configured instances own their data and caches.
---@type table<string, FlashAnySourceDefinition>
local cache = {}

---Load a source factory from runtimepath; options are passed through to the factory.
---@param name string
---@param opts? table
---@return FlashAnySourceDefinition
function M.load(name, opts)
  if not opts and cache[name] then
    return cache[name]
  end
  local factory = require("flash-any.sources." .. name)
  assert(type(factory) == "function", "source module must return a factory: " .. name)
  local source = factory(opts or {})
  assert(type(source) == "table", "source factory must return a table: " .. name)
  if source.codetable ~= nil then
    assert(type(source.codetable) == "string", "codetable must be a table name: " .. name)
    assert(source.data == nil, "codetable and data are mutually exclusive: " .. name)
    source.data = tables.load(source.codetable)
    source.codetable = nil
  end
  if source.data then
    source.data = tables.append_space(source.data, opts and opts.append_space_below)
  end
  if not opts then
    cache[name] = source
  end
  return source
end

---Discover names without requiring factories or loading their tables.
---@return string[]
function M.available()
  local names = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/flash-any/sources/*.lua", true)) do
    names[#names + 1] = vim.fn.fnamemodify(path, ":t:r")
  end
  table.sort(names)
  return names
end

return M

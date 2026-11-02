local M = {}
local grapheme = require("flash-any.grapheme")

local function add(rows, char, code)
  char = char and char:gsub("^%s+", ""):gsub("%s+$", "")
  code = code and code:gsub("^%s+", ""):gsub("%s+$", "")
  if not char or char == "" or not code or code == "" then
    return
  end
  assert(not char:find("[\t\r\n]"), "table text must not contain tabs or newlines")
  assert(not code:find("[,\t\r\n\128-\255]"), "code must be ASCII without comma, tab or newline: " .. code)
  rows[char] = rows[char] or {}
  rows[char][code] = true
end

local function csv_fields(line)
  -- Fields may contain UTF-8. Only ASCII CSV syntax needs bytewise inspection.
  local fields, field, quoted = {}, {}, false
  local i = 1
  while i <= #line do
    local char = line:sub(i, i)
    if char == '"' then
      if quoted and line:sub(i + 1, i + 1) == '"' then
        field[#field + 1] = '"'
        i = i + 1
      else
        quoted = not quoted
      end
    elseif char == "," and not quoted then
      fields[#fields + 1] = table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
      field = {}
    else
      field[#field + 1] = char
    end
    i = i + 1
  end
  fields[#fields + 1] = table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
  return fields
end

local function parse_line(line, format)
  if line == "" or line:match("^%s*#") or line:match("^%s*---") then
    return
  end
  if format == "csv" or (format == "auto" and line:find(",", 1, true) and not line:find("\t", 1, true)) then
    local fields = csv_fields(line)
    if #fields >= 2 then
      return fields[1], fields[2]
    end
  elseif
    format == "tab"
    or format == "tsv"
    or format == "rime"
    or (format == "auto" and line:find("\t", 1, true))
  then
    local char, code = line:match("^([^\t]+)\t([^\t]+)")
    return char, code, format ~= "rime"
  else
    return line:match("^(%S+)%s+(%S+)")
  end
end

local function read_rows(path, format, encoding)
  local rows = {}
  local columns, in_columns, in_header = nil, false, false
  for raw in io.lines(vim.fn.expand(path)) do
    local line = raw
    local input = line
    if encoding and encoding:lower() ~= "utf-8" and encoding:lower() ~= "utf8" then
      input = assert(vim.iconv(line, encoding, "utf-8"), "invalid " .. encoding .. " input")
    end
    line = input
    if (format == "rime" or format == "auto") and line:match("^%s*---%s*$") then
      in_header = true
    end
    if line:match("^columns:%s*$") then
      columns, in_columns = {}, true
    elseif in_columns then
      local column = line:match("^%s*%-%s*([%w_]+)%s*$")
      if column then
        columns[#columns + 1] = column
      else
        in_columns = false
      end
    end
    if line:match("^%.%.%.%s*$") then
      in_columns, in_header = false, false
    end
    if not in_header and line ~= "" and not line:match("^%s*#") and not line:match("^%s*---") then
      local char, code, multiple
      local use_rime_columns = columns and #columns > 0 and line:find("\t", 1, true)
      if use_rime_columns then
        local fields = vim.split(line, "\t", { plain = true })
        local text_index, code_index
        for index, column in ipairs(columns or {}) do
          if column == "text" then
            text_index = index
          end
          if column == "code" then
            code_index = index
          end
        end
        if text_index and code_index then
          char, code = fields[text_index], fields[code_index]
        end
      else
        char, code, multiple = parse_line(line, format)
      end
      if char and code then
        if multiple then
          -- TSV shares the runtime table format; each token uses the same validation.
          for item in code:gmatch("[^,]+") do
            add(rows, char, item)
          end
        else
          add(rows, char, code)
        end
      end
    end
  end
  return rows
end

local function quote(value)
  return string.format("%q", value)
end

---@param opts table
---@return integer common Number of entries written to Lua.
---@return integer full Number of distinct entries in the complete input.
---@return integer multi Number of distinct multi-grapheme entries in the complete input.
function M.table(opts)
  assert(opts and opts.source and opts.lua, "source and lua are required")
  local separator = opts.format or opts.separator or "auto"
  assert(
    vim.tbl_contains({ "auto", "csv", "tab", "tsv", "rime", "space" }, separator),
    "unknown input format: " .. tostring(separator)
  )
  local rows = read_rows(opts.source, separator, opts.encoding or "utf-8")
  local all = vim.tbl_keys(rows)
  table.sort(all)
  local multi, maximum = 0, 1
  local first, last
  for _, key in ipairs(all) do
    local count = 0
    grapheme.each(key, function(start, after)
      count = count + 1
      if start == 0 then
        local char = key:sub(1, after)
        if not first or char < first then first = char end
        if not last or char > last then last = char end
      end
    end)
    if count > 1 then
      multi = multi + 1
    end
    maximum = math.max(maximum, count)
  end
  local keys = all
  if opts.common then
    local common = dofile(vim.fn.expand(opts.common))
    assert(type(common) == "table", "common Lua file must return a table")
    if type(common.codes) == "table" then
      common = common.codes
    end
    keys = vim.tbl_keys(common)
    table.sort(keys)
  end

  local common, prefixes = 0, {}
  for _, key in ipairs(keys) do
    if rows[key] then
      common = common + 1
      grapheme.each(key, function(_, offset)
        if offset < #key then
          prefixes[key:sub(1, offset)] = true
        end
      end)
    end
  end
  local lua = assert(io.open(vim.fn.expand(opts.lua), "wb"))
  lua:write("return {\n  codes = {\n")
  for _, key in ipairs(keys) do
    if rows[key] then
      local codes = vim.tbl_keys(rows[key])
      table.sort(codes)
      lua:write(
        string.format("    [%s] = {%s},\n", quote(key), table.concat(vim.tbl_map(quote, codes), ", "))
      )
    end
  end
  lua:write("  },\n  prefixes = {\n")
  local prefix_keys = vim.tbl_keys(prefixes)
  table.sort(prefix_keys)
  for _, key in ipairs(prefix_keys) do
    lua:write(string.format("    [%s] = true,\n", quote(key)))
  end
  lua:write(("  },\n  max_chars = %d,\n"):format(maximum))
  if first then
    -- Whole-key order can differ from first-grapheme order (a💻 vs á).
    lua:write(("  scope = { { %s, %s } },\n"):format(quote(first), quote(last)))
  else
    lua:write("  scope = {},\n")
  end
  lua:write("}\n")
  lua:close()

  if opts.tsv then
    local tsv = assert(io.open(vim.fn.expand(opts.tsv), "wb"))
    for _, char in ipairs(all) do
      local codes = vim.tbl_keys(rows[char])
      table.sort(codes)
      tsv:write(char, "\t", table.concat(codes, ","), "\n")
    end
    tsv:close()
  end
  return common, #all, multi
end

function M.command(opts)
  local ok, common, full, multi = pcall(M.table, opts)
  if not ok then
    vim.notify("flash-any: " .. common, vim.log.levels.ERROR)
    return
  end
  local message = ("flash-any: wrote %d Lua entries"):format(common)
  if opts.tsv then message = message .. (" and %d TSV entries"):format(full) end
  local level = vim.log.levels.INFO
  if multi > 0 then
    message = message .. ("; %d multi-grapheme entries use word-prefix matching"):format(multi)
    level = vim.log.levels.WARN
  end
  vim.notify(message, level)
end

return M

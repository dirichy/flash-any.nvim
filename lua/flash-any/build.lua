local M = {}
local utf8 = require("flash-any.utf8")

local function add(rows, char, code)
  char = char and char:gsub("^%s+", ""):gsub("%s+$", "")
  code = code and code:gsub("^%s+", ""):gsub("%s+$", "")
  if not char or not code or code == "" then return end
  -- char is UTF-8; accept one codepoint, not a multi-character word.
  local iter, str, offset = utf8.iter_offset(char)
  if iter(str, offset) ~= #char then return end
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
        field[#field + 1] = '"'; i = i + 1
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
  if line == "" or line:match("^%s*#") or line:match("^%s*---") then return end
  if format == "csv" or (format == "auto" and line:find(",", 1, true) and not line:find("\t", 1, true)) then
    local fields = csv_fields(line)
    if #fields >= 2 then return fields[1], fields[2] end
  elseif format == "tab" or format == "tsv" or format == "rime" or (format == "auto" and line:find("\t", 1, true)) then
    return line:match("^([^\t]+)\t([^\t]+)")
  else
    return line:match("^(%S+)%s+(%S+)")
  end
end

local function read_rows(path, format, encoding)
  local rows = {}
  local columns, in_columns = nil, false
  for raw in io.lines(vim.fn.expand(path)) do
    local line = raw
    local input = line
    if encoding and encoding:lower() ~= "utf-8" and encoding:lower() ~= "utf8" then
      input = assert(vim.iconv(line, encoding, "utf-8"), "invalid " .. encoding .. " input")
    end
    line = input
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
    if line == "..." then
      in_columns = false
    end
    if line ~= "" and not line:match("^%s*#") and not line:match("^%s*---") then
      local char, code
      local use_rime_columns = columns and #columns > 0 and line:find("\t", 1, true)
      if use_rime_columns then
        local fields = vim.split(line, "\t", { plain = true })
        local text_index, code_index
        for index, column in ipairs(columns or {}) do
          if column == "text" then text_index = index end
          if column == "code" then code_index = index end
        end
        if text_index and code_index then
          char, code = fields[text_index], fields[code_index]
        end
      else
        char, code = parse_line(line, format)
      end
      if char and code then add(rows, char, code) end
    end
  end
  return rows
end

local function quote(value)
  return string.format("%q", value)
end

---@param opts table
---@return number, number
function M.table(opts)
  assert(opts and opts.source and opts.lua and opts.tsv, "source, lua and tsv are required")
  local separator = opts.format or opts.separator or "auto"
  assert(vim.tbl_contains({ "auto", "csv", "tab", "tsv", "rime", "space" }, separator),
    "unknown input format: " .. tostring(separator))
  local rows = read_rows(opts.source, separator, opts.encoding or "utf-8")
  local keys
  if opts.common then
    local common = dofile(vim.fn.expand(opts.common))
    assert(type(common) == "table", "common Lua file must return a table")
    keys = vim.tbl_keys(common)
  else
    keys = vim.tbl_keys(rows)
  end
  table.sort(keys)

  local lua = assert(io.open(vim.fn.expand(opts.lua), "wb"))
  lua:write("return {\n")
  local common = 0
  for _, char in ipairs(keys) do
    if rows[char] then
      local codes = vim.tbl_keys(rows[char])
      table.sort(codes)
      lua:write(string.format("  [%s] = {%s},\n", quote(char), table.concat(vim.tbl_map(quote, codes), ", ")))
      common = common + 1
    end
  end
  lua:write("}\n")
  lua:close()

  local all = vim.tbl_keys(rows)
  table.sort(all)
  local tsv = assert(io.open(vim.fn.expand(opts.tsv), "wb"))
  for _, char in ipairs(all) do
    local codes = vim.tbl_keys(rows[char])
    table.sort(codes)
    tsv:write(char, "\t", table.concat(codes, ","), "\n")
  end
  tsv:close()
  return common, #all
end

function M.command(opts)
  local ok, common, full = pcall(M.table, opts)
  if not ok then
    vim.notify("flash-any: " .. common, vim.log.levels.ERROR)
    return
  end
  vim.notify(("flash-any: wrote %d common and %d full characters"):format(common, full))
end

return M

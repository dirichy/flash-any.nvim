local M = {}
local punctuation = require("flash-any.table.punctuation")

-- Code-table encodings are ASCII; buffer characters may be UTF-8.
-- Matching has three modes: full_code, initial and prefix.

local function chinese_char(char)
  local cp = vim.fn.char2nr(char)
  return (cp >= 0x3400 and cp <= 0x4DBF)
    or (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0x20000 and cp <= 0x323AF)
    or punctuation[char] ~= nil
end

local function unicode_char(char)
  local cp = vim.fn.char2nr(char)
  return cp >= 0xA0
end

local function private_use_char(char)
  local cp = vim.fn.char2nr(char)
  return (cp >= 0xE000 and cp <= 0xF8FF)
    or (cp >= 0xF0000 and cp <= 0xFFFFD)
    or (cp >= 0x100000 and cp <= 0x10FFFD)
end

-- Reject unrelated characters before a lazy lookup can search the TSV.
local scopes = {
  pinyin = chinese_char,
  tiger = chinese_char,
  wubi86 = chinese_char,
  unicode = unicode_char,
  nerdfont = private_use_char,
}

---@param char string
---@param stream string
---@param args FlashAnyMatcherArgs
---@param mode "full_code"|"initial"|"prefix"
---@return FlashAnyMatcherResult[]?
local function match(char, stream, args, mode)
  local source = args.source
  local accepts = source.name and scopes[source.name]
  -- Built-in scopes exclude ASCII; skip char2nr for these common buffer characters.
  if accepts and (char:byte() < 0x80 or not accepts(char)) then return nil end
  local data = source.data
  ---@type string[]?
  local codes = data and data[char]
  if not codes then return nil end
  local ret, consumed, next = {}, nil, nil
  local n = #stream
  for _, code in ipairs(codes) do
    local length = #code
    local common = 0
    while common < math.min(n, length) and stream:byte(common + 1) == code:byte(common + 1) do
      common = common + 1
    end
    -- All modes accept an input prefix and report its next ASCII key.
    if length > n and common == n then
      next = next or {}
      next[code:sub(n + 1, n + 1)] = true
    end
    -- All modes can finish this character after its complete encoding.
    if length > 0 and common == length then
      consumed = consumed or {}
      consumed[length] = true
    end
    if mode == "initial" and common > 0 then
      consumed = consumed or {}
      consumed[1] = true
    elseif mode == "prefix" and common > 0 then
      consumed = consumed or {}
      for bytes = 1, common do consumed[bytes] = true end
    end
  end
  -- Different encodings/prefixes may consume the same byte count; keep it once.
  if consumed then
    for bytes in pairs(consumed) do ret[#ret + 1] = { consumed = bytes } end
  end
  if next then ret[#ret + 1] = { next = next } end
  return ret
end

---@param char string
---@param stream string
---@param args FlashAnyMatcherArgs
---@return FlashAnyMatcherResult[]?
function M.full_code(char, stream, args)
  return match(char, stream, args, "full_code")
end

---@param char string
---@param stream string
---@param args FlashAnyMatcherArgs
---@return FlashAnyMatcherResult[]?
function M.initial(char, stream, args)
  return match(char, stream, args, "initial")
end

---@param char string
---@param stream string
---@param args FlashAnyMatcherArgs
---@return FlashAnyMatcherResult[]?
function M.prefix(char, stream, args)
  return match(char, stream, args, "prefix")
end

return M

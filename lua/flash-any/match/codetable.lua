local M = {}
local punctuation = require("flash-any.tables.punctuation")

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

---@param text FlashAnyCursor
---@param stream FlashAnyCursor
---@param source FlashAnySource
---@param emit FlashAnyEmit
---@param mode "full_code"|"initial"|"prefix"
---@return boolean
local function match(text, stream, source, emit, mode)
  local char = text:get(1)
  if char == "" then return false end
  local accepts = source.name and scopes[source.name]
  -- Built-in scopes exclude ASCII; skip char2nr for these common buffer characters.
  if accepts and (char:byte() < 0x80 or not accepts(char)) then return false end
  local data = source.data
  ---@type string[]?
  local codes = data and data[char]
  if not codes then return false end
  local initial, prefix = false, 0
  local input = stream:get()
  local n = #input
  for _, code in ipairs(codes) do
    local length = #code
    local common = 0
    while common < math.min(n, length) and input:byte(common + 1) == code:byte(common + 1) do
      common = common + 1
    end
    if length > n and common == n then emit(code:sub(n + 1, n + 1)) end
    if length > 0 and common == length then
      if mode == "full_code" or (mode == "initial" and length > 1) then emit(length) end
    end
    if mode == "initial" and common > 0 then
      initial = true
    elseif mode == "prefix" then
      prefix = math.max(prefix, common)
    end
  end
  if initial then emit(1) end
  -- Prefix intervals all begin at 1; their union needs only the largest boundary.
  for bytes = 1, prefix do emit(bytes) end
  return true
end

---@param text FlashAnyCursor
---@param stream FlashAnyCursor
---@param source FlashAnySource
---@param emit FlashAnyEmit
---@return boolean
function M.full_code(text, stream, source, emit)
  return match(text, stream, source, emit, "full_code")
end

---@param text FlashAnyCursor
---@param stream FlashAnyCursor
---@param source FlashAnySource
---@param emit FlashAnyEmit
---@return boolean
function M.initial(text, stream, source, emit)
  return match(text, stream, source, emit, "initial")
end

---@param text FlashAnyCursor
---@param stream FlashAnyCursor
---@param source FlashAnySource
---@param emit FlashAnyEmit
---@return boolean
function M.prefix(text, stream, source, emit)
  return match(text, stream, source, emit, "prefix")
end

return M

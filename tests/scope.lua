#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local scopes = require("flash-any.scope")
local Cursor = require("flash-any.cursor")
local function accepts(spec, char)
  local scope = scopes.resolve(spec)
  return not scope or scope(Cursor.new(char))
end

for byte = 0, 127 do
  assert(accepts("ascii", string.char(byte)))
end
for _, char in ipairs({ "", "中", "α", "🙂", string.char(0x80) }) do
  assert(not accepts("ascii", char))
end
for _, char in ipairs({ "中", "㐀", "，", "。", "𠀀" }) do
  assert(accepts("chinese", char))
end
for _, char in ipairs({ "a", "α", "🙂", "ぁ", "　" }) do
  assert(not accepts("chinese", char))
end
assert(accepts("unicode", vim.fn.nr2char(0xA0)))
assert(not accepts("unicode", "a") and not accepts("unicode", string.char(0x9F)))
for _, range in ipairs({ { 0xE000, 0xF8FF }, { 0xF0000, 0xFFFFD }, { 0x100000, 0x10FFFD } }) do
  assert(accepts("private_use", vim.fn.nr2char(range[1])))
  assert(accepts("private_use", vim.fn.nr2char(range[2])))
  assert(not accepts("private_use", vim.fn.nr2char(range[1] - 1)))
  assert(not accepts("private_use", vim.fn.nr2char(range[2] + 1)))
end
assert(scopes.resolve("all") == nil and scopes.resolve(nil) == nil)
assert(scopes.resolve("chinese") == scopes.resolve("chinese"))
print("ok - predefined scope strategies preserve character coverage")

local numeric = { { 1, 10000 }, a = false, ["🙂"] = true }
assert(not accepts(numeric, "a") and accepts(numeric, "b"))
assert(accepts(numeric, "🙂") and not accepts(numeric, "字"))
local kana = { { "ぁ", "ヿ" }, ["あ"] = false, ["漢"] = true }
assert(accepts(kana, "ぁ") and accepts(kana, "ヿ") and accepts(kana, "カ"))
assert(not accepts(kana, "あ") and not accepts(kana, "🙂") and accepts(kana, "漢"))
assert(accepts({ { 0x3040, "ヿ" } }, "あ"))
assert(accepts({ ["あ"] = true }, "あ") and not accepts({ ["あ"] = true }, "い"))
assert(not accepts({}, "あ"))
local compiled = assert(scopes.resolve(kana))
kana[1][1], kana["漢"] = "ん", false
assert(compiled(Cursor.new("ぁ")) and compiled(Cursor.new("漢")))
print("ok - mixed scopes check character hashes first and copy numeric/string ranges")

local function custom(text)
  return text:get(2) == "きゃ"
end
assert(scopes.resolve(custom) == custom)
assert(accepts(custom, "きゃ") and not accepts(custom, "き"))
for _, invalid in ipairs({
  false,
  42,
  "missing",
  { { 0x110000, 0x110001 } },
  { { -1, 1 } },
  { { 0.5, 1 } },
  { { "あ" } },
  { { "あ", "a" } },
  { { "ab", "z" } },
  { { "", "z" } },
  { ["ab"] = true },
  { a = 1 },
  { [0] = { 1, 2 } },
}) do
  assert(not pcall(scopes.resolve, invalid), vim.inspect(invalid))
end
print("ok - custom functions receive a cursor; invalid declarations fail during setup")

-- Exercise dispatch independently of tables and built-in source names.
local captured
package.loaded.flash = {
  jump = function(opts)
    captured = opts
  end,
}
local plugin = require("flash-any")
local match = require("flash-any.match")
local range = { from = { 1, 0 }, to = { 1, 0 } }
local reads, calls = 0, 0
local function matcher(_, stream, _, emit)
  calls = calls + 1
  if stream:get() == "" then
    emit("x")
  elseif stream:get(1) == "x" then
    emit(1)
  end
  return true
end
local function run(text, specs)
  plugin.jump({ sources = specs })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  return captured.matcher(0, {
    pattern = function()
      return "x"
    end,
  }, range)
end
local spec = {
  scope = { { "ぁ", "ヿ" }, ["あ"] = false },
  loader = function(char)
    reads = reads + 1
    return { char == "い" and "x" or "z" }
  end,
}
assert(#run("あ🙂", { spec }) == 0 and reads == 0)
assert(#run("い", { spec }) == 1 and reads == 1)
local blocked = {
  matcher = function()
    error("excluded scope called matcher")
  end,
  scope = { a = false },
}
assert(#run("あ", { blocked, { matcher = matcher, fallback = true } }) == 1)
assert(#run("あ", {
  {
    matcher = function()
      return false
    end,
    scope = { ["あ"] = true },
  },
  { matcher = matcher, fallback = true },
}) == 1)
assert(#run("あ", {
  {
    matcher = function()
      return true
    end,
    scope = { ["あ"] = true },
  },
  {
    matcher = function()
      error("recognized position reached fallback")
    end,
    fallback = true,
  },
}) == 0)
local before = calls
assert(#run("あ", { {
  matcher = matcher,
  scope = function()
    return false
  end,
} }) == 0 and calls == before)
assert(#run("あ", { { matcher = matcher, scope = custom } }) == 0)
assert(#run("きゃ", { { matcher = matcher, scope = custom } }) == 1)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "あい" })
assert(#match.char(
  0,
  {
    pattern = function()
      return "x"
    end,
  },
  range,
  {
    { matcher = matcher, scope = scopes.resolve({ ["い"] = true }) },
  }
) == 1)
assert(#run("α", { { name = "pinyin", data = { ["α"] = "x" }, scope = "all" } }) == 1)
print("all generic source scope tests passed")

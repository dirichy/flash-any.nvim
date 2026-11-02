#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local match = require("flash-any.match")
local literal = require("flash-any.sources.literal")()
local literal_source = { matcher = literal.matcher, scope = require("flash-any.scope").resolve(literal.scope) }

local function words(entries)
  return {
    matcher = function(text, stream, _, emit)
      local known = false
      for _, entry in ipairs(entries) do
        local word, code = entry[1], entry[2]
        local chars = vim.str_utfindex(word, "utf-32")
        if text:get(chars) == word then
          known = true
          if #stream:get() < #code and code:sub(1, #stream:get()) == stream:get() then
            emit(code:sub(#stream:get() + 1, #stream:get() + 1), chars)
          elseif stream:get():sub(1, #code) == code then
            emit(#code, chars)
          end
        end
      end
      return known
    end,
  }
end
local range = { from = { 1, 0 }, to = { 1, 0 } }
local kana = words({ { "きゃ", "kya" }, { "き", "ki" }, { "ゃ", "ya" }, { "く", "ku" } })
local sources = { literal_source, kana }
local function run(text, pattern, configured)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  return match.get(0, {
    pattern = function()
      return pattern
    end,
  }, range, configured or sources)
end

local found = run("あきゃく", "ky")
assert(#found == 1 and found[1].pos[2] == 3 and found[1].end_pos[2] == 6 and found[1].next.a)
found = run("あきゃく", "kya")
assert(#found == 1 and found[1].end_pos[2] == 6 and found[1].next.k)
found = run("Aきゃx", "Akyax")
assert(#found == 1 and found[1].pos[2] == 0 and found[1].end_pos[2] == 7)
assert(#run("き", "kya") == 0)
-- Buffer line ends cannot be crossed even if a custom branch asks for more text.
assert(#run("き", "x", { {
  matcher = function(_, _, _, emit)
    emit(1, 2)
    return true
  end,
} }) == 0)
assert(#run("き", "x", { {
  matcher = function(_, _, _, emit)
    emit("", 2)
    return true
  end,
} }) == 0)
found = run("🙂́x", "ex", { words({ { "🙂́", "e" }, { "x", "x" } }) })
assert(#found == 1 and found[1].pos[2] == 0 and found[1].end_pos[2] == 6)
print("ok - word branches consume text codepoints independently of input bytes")

-- Different spans may end at the same codepoint; merge ranges and next keys.
found = run("甲乙丙", "x", { words({ { "甲乙", "x" }, { "乙", "xy" }, { "丙", "z" } }) })
assert(#found == 1 and found[1].pos[2] == 0 and found[1].end_pos[2] == 3)
assert(found[1].next.y and found[1].next.z)
-- A completion starting early can wait for a farther following position.
found = run("甲乙丙丁", "x", { words({ { "甲乙丙", "x" }, { "乙", "x" }, { "丙", "y" }, { "丁", "z" } }) })
assert(#found == 2 and found[1].end_pos[2] == 6 and found[1].next.z)
assert(found[2].pos[2] == 3 and found[2].end_pos[2] == 3 and found[2].next.y)
print("ok - ranges with different spans merge and query the correct following position")

-- Grouped keys and repeated emissions are merged without source-side sets.
found = run("甲乙", "x", {
  {
    matcher = function(text, _, _, emit)
      if text:get(2) ~= "甲乙" then
        return false
      end
      emit(1, 2)
      emit(1, 2)
      emit("aau", 2)
      emit("", 2)
      return true
    end,
  },
})
assert(#found == 1 and found[1].end_pos[2] == 3)
assert(vim.deep_equal(found[1].next, { a = true, u = true }))

local overlapping = {
  words({
    { "甲", "a" },
    { "甲乙", "ab" },
    { "甲乙丙", "abc" },
    { "乙", "b" },
    { "乙丙", "bc" },
    { "丙", "c" },
    { "丁", "d" },
  }),
}
for _, pattern in ipairs({ "abcd", "abx", "abcab", "aa", "bcda" }) do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙丁甲乙丙" })
  local value = ""
  local state = {
    pattern = function()
      return value
    end,
  }
  for i = 1, #pattern do
    value = pattern:sub(1, i)
    local incremental = match.get(0, state, range, overlapping)
    local fresh = match.get(0, {
      pattern = function()
        return value
      end,
    }, range, overlapping)
    assert(vim.deep_equal(incremental, fresh), value .. ": " .. vim.inspect({ incremental, fresh }))
  end
end
print("ok - overlapping multi-codepoint branches agree in fresh and incremental scans")

local seen
local observing = {
  matcher = function(text)
    seen = seen or text
    assert(text == seen, "one object must serve every position and source on this line")
    text:get(3)
    return false
  end,
}
local checking = {
  matcher = function(text, stream, _, emit)
    assert(text == seen)
    if text:get(2) ~= "きゃ" then
      return false
    end
    if stream:get() == "" then
      emit("k", 2)
      return true
    end
    if stream:get():sub(1, 1) == "k" then
      emit(1, 2)
      return true
    end
    return true
  end,
}
local value = "k"
local state = {
  pattern = function()
    return value
  end,
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "きゃきゃ" })
found = match.get(0, state, range, { observing, checking })
assert(#found == 2 and found[1].pos[2] == 0 and found[1].end_pos[2] == 3)
value = "kk"
found = match.get(0, state, range, state._flash_any_cache[0].sources)
assert(#found == 1 and found[1].pos[2] == 0 and found[1].end_pos[2] == 9)
value = "k"
found = match.get(0, state, range, state._flash_any_cache[0].sources)
assert(#found == 2)
local previous_line = seen
seen = nil
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "きゃ" })
match.get(0, state, range, state._flash_any_cache[0].sources)
assert(seen ~= previous_line)
print("ok - line objects survive cursor movement and input changes, then expire with the buffer snapshot")

-- Unicode input uses the same cursor, while emissions still count input bytes.
local unicode_source = {
  matcher = function(text, stream, _, emit)
    assert(getmetatable(text) == getmetatable(stream))
    if text:get(1) ~= "甲" then
      return false
    end
    if stream:get() == "" then
      emit("a")
    elseif stream:get() == "a" then
      emit("")
    else
      local input = stream:get(2)
      if input == "a🙂" then
        emit(#input)
      end
    end
    return true
  end,
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲b" })
local pattern = "a"
local unicode_state = {
  pattern = function()
    return pattern
  end,
}
local unicode_sources = { unicode_source, literal_source }
for _, input_value in ipairs({ "a", "a🙂", "a🙂b" }) do
  pattern = input_value
  local incremental = match.get(0, unicode_state, range, unicode_sources)
  local fresh = match.get(0, {
    pattern = function()
      return input_value
    end,
  }, range, unicode_sources)
  assert(vim.deep_equal(incremental, fresh))
  assert(#incremental == 1 and incremental[1].pos[2] == 0)
  assert(incremental[1].end_pos[2] == (input_value == "a🙂b" and 3 or 0))
end

-- Short get(n) results must not turn an oversized emitted span into a match.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
assert(#match.char(
  0,
  {
    pattern = function()
      return "x"
    end,
  },
  range,
  {
    {
      matcher = function(_, _, _, emit)
        emit(1, 2)
        return true
      end,
    },
  }
) == 0)

-- f/F remain native single-target motions even when their source reads a word.
local char_state = {
  pattern = function()
    return "ky"
  end,
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "きゃきゃ" })
found = match.char(0, char_state, range, sources)
assert(#found == 2 and found[1].pos[2] == 0 and found[1].end_pos[2] == 0 and found[2].pos[2] == 6)
local line = char_state._flash_any_char_cache[0].lines[1]
char_state.pattern = function()
  return "ki"
end
match.char(0, char_state, range, sources)
assert(char_state._flash_any_char_cache[0].lines[1] == line)
print("all multi-codepoint matcher tests passed")

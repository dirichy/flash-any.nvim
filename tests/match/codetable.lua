#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local Cursor = require("flash-any.cursor")
local codetable = require("flash-any.match.codetable")

local function collect(mode, char, stream, source)
  local counts, keys, branches = {}, {}, 0
  local known = codetable[mode](Cursor.new(char), Cursor.new(stream), source, function(value, chars)
    assert(chars == nil or chars == 1)
    branches = branches + 1
    if type(value) == "number" then
      assert(value > 0 and value <= #stream and value % 1 == 0)
      counts[#counts + 1] = value
    else
      for i = 1, #value do
        keys[value:sub(i, i)] = true
      end
    end
  end)
  table.sort(counts)
  return known, counts, keys, branches
end

local function check(name, mode, stream, codes, expected)
  local known, counts, keys, branches =
    collect(mode, "甲", stream, { data = { ["甲"] = codes }, matcher = codetable[mode] })
  assert(known, name .. " recognizes character")
  assert(vim.deep_equal(counts, expected.consumed or {}), name .. " consumed")
  assert(vim.deep_equal(keys, expected.next or {}), name .. " next")
  assert((branches > 0) == (expected.success ~= false), name .. " success")
  print("ok - " .. name)
end

check("full code passes remaining input by byte count", "full_code", "zhongg", { "zhong" }, { consumed = { 5 } })
check("full code prefix finishes input", "full_code", "zh", { "zhong" }, { next = { o = true } })
check("exact full code crosses character boundary", "full_code", "zhong", { "zhong" }, { consumed = { 5 } })
check("failed full code", "full_code", "wrong", { "zhong" }, { success = false })
check("empty input queries initial keys", "full_code", "", { "zhong", "guo" }, { next = { z = true, g = true } })
check(
  "overlapping codes retain both branches",
  "full_code",
  "a",
  { "a", "ab" },
  { consumed = { 1 }, next = { b = true } }
)
check("initial keeps full and initial paths", "initial", "zhongg", { "zhong" }, { consumed = { 1, 5 } })
check("prefix keeps all consumption boundaries", "prefix", "zhongg", { "zhong" }, { consumed = { 1, 2, 3, 4, 5 } })
check("non-ASCII input cannot match ASCII code", "full_code", "中", { "zhong" }, { success = false })
check("overlapping prefix boundaries are deduplicated", "prefix", "ab", { "a", "ab", "abc" }, {
  consumed = { 1, 2 },
  next = { c = true },
})
check("known empty code list returns no matches", "full_code", "a", {}, { success = false })
check("empty encodings cannot consume zero bytes", "prefix", "a", { "" }, { success = false })

for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
  assert(not collect(mode, "甲", "甲", { matcher = codetable[mode] }))
  assert(not collect(mode, "甲", "甲", { data = {}, matcher = codetable[mode] }))
end
print("ok - code-table modes never fall back to the character")

for _, name in ipairs({ "pinyin", "tiger", "wubi86" }) do
  local reads = 0
  local data = setmetatable({}, {
    __index = function()
      reads = reads + 1
      return { "," }
    end,
  })
  local source = { name = name, data = data, matcher = codetable.full_code }
  for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
    local known, counts = collect(mode, "，", ",", source)
    assert(known and vim.deep_equal(counts, { 1 }))
    local _, _, keys = collect(mode, "，", "", source)
    assert(keys[","])
    local _, _, _, branches = collect(mode, "，", "x", source)
    assert(branches == 0)
    local before = reads
    for _, char in ipairs({ "a", "😀", "α", "　" }) do
      assert(not collect(mode, char, ",", source))
    end
    assert(reads == before)
  end
end
print("ok - Chinese scopes admit punctuation without loading unrelated characters")
print("all code-table matcher tests passed")

#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local codetable = require("flash-any.match.codetable")

local function check(name, mode, stream, codes, expected)
  local results = codetable[mode]("甲", stream, { source = { data = { ["甲"] = codes }, matcher = codetable[mode] } })
  assert(results ~= nil, name .. " recognizes character")
  local counts, next_keys = {}, {}
  for _, result in ipairs(results) do
    assert((result.consumed ~= nil) ~= (result.next ~= nil))
    if result.consumed then
      assert(result.consumed > 0 and result.consumed <= #stream and result.consumed % 1 == 0)
      counts[#counts + 1] = result.consumed
    else
      for key in pairs(result.next) do next_keys[key] = true end
    end
  end
  table.sort(counts)
  assert(vim.deep_equal(counts, expected.consumed or {}), name .. " consumed")
  assert(vim.deep_equal(next_keys, expected.next or {}), name .. " next")
  assert((#results > 0) == (expected.success ~= false), name .. " success")
  print("ok - " .. name)
end

check("full code passes remaining input by byte count", "full_code", "zhongg", { "zhong" }, { consumed = { 5 } })
check("full code prefix finishes input", "full_code", "zh", { "zhong" }, { next = { o = true } })
check("exact full code crosses character boundary", "full_code", "zhong", { "zhong" }, { consumed = { 5 } })
check("failed full code", "full_code", "wrong", { "zhong" }, { success = false })
check("empty input queries initial keys", "full_code", "", { "zhong", "guo" }, { next = { z = true, g = true } })
check("overlapping codes retain both branches", "full_code", "a", { "a", "ab" }, { consumed = { 1 }, next = { b = true } })
check("initial keeps full and initial paths", "initial", "zhongg", { "zhong" }, { consumed = { 1, 5 } })
check("prefix keeps all consumption boundaries", "prefix", "zhongg", { "zhong" }, { consumed = { 1, 2, 3, 4, 5 } })
check("non-ASCII input cannot match ASCII code", "full_code", "中", { "zhong" }, { success = false })
check("overlapping prefix boundaries are deduplicated", "prefix", "ab", { "a", "ab", "abc" }, {
  consumed = { 1, 2 }, next = { c = true },
})
check("known empty code list returns no matches", "full_code", "a", {}, { success = false })
check("empty encodings cannot consume zero bytes", "prefix", "a", { "" }, { success = false })

for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
  local missing_data = codetable[mode]("甲", "甲", { source = { matcher = codetable[mode] } })
  local missing_char = codetable[mode]("甲", "甲", { source = { data = {}, matcher = codetable[mode] } })
  assert(missing_data == nil and missing_char == nil)
end
print("ok - code-table modes never fall back to the character")

for _, name in ipairs({ "pinyin", "tiger", "wubi86" }) do
  local reads = 0
  local data = setmetatable({}, { __index = function()
    reads = reads + 1
    return { "," }
  end })
  local args = { source = { name = name, data = data } }
  for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
    assert(codetable[mode]("，", ",", args)[1].consumed == 1)
    assert(codetable[mode]("，", "", args)[1].next[","])
    assert(#codetable[mode]("，", "x", args) == 0)
    local before = reads
    for _, char in ipairs({ "a", "😀", "α", "　" }) do
      assert(codetable[mode](char, ",", args) == nil)
    end
    assert(reads == before)
  end
end
print("ok - Chinese scopes admit punctuation without loading unrelated characters")

print("all code-table matcher tests passed")

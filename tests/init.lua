#!/usr/bin/env -S nvim -l

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())

---@type table<string, any>
local jump = {}
local remote = {}
package.loaded.flash = {
  jump = function(opts) jump = opts end,
  remote = function(opts) remote = opts end,
}
local plugin = require("flash-any")
local unconfigured = jump
assert(not pcall(plugin.jump))
assert(not pcall(plugin.remote))
assert(jump == unconfigured)
plugin.setup({ sources = { { matcher = function(text, stream, _, emit)
  local char = text:get(1)
  if char ~= "中" then return false end
  if stream:get() == "x" then emit(""); return true end
  return true
end } } })
plugin.jump()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" })
local matches = jump.matcher(0, { pattern = function() return "x" end }, { from = { 1, 0 }, to = { 1, 0 } })
assert(#matches == 1 and matches[1].pos[2] == 0)
print("ok - setup loads a matcher without name or data")

local function run(text, pattern, sources)
  plugin.jump({ sources = sources })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  return jump.matcher(0, { pattern = function() return pattern end }, { from = { 1, 0 }, to = { 1, 0 } })
end

for _, source in ipairs({ "pinyin", { name = "pinyin", scheme = "flypy", fuzzy = true }, "tiger", "wubi86" }) do
  for _, pair in ipairs({ { "，", "," }, { "。", "." }, { "、", "/" }, { "、", "\\" }, { "“”", "\"\"" }, { "……", "^^" }, { "——", "__" } }) do
    local found = run(pair[1], pair[2], { source })
    assert(#found == 1 and found[1].pos[2] == 0, vim.inspect({ source, pair }))
  end
end
assert(#run("中国，a。", "zg,a.", { "pinyin" }) == 1)
assert(#run("中国，a。", "vsgo,a.", { { name = "pinyin", scheme = "flypy" } }) == 1)
print("ok - Chinese sources match punctuation and mixed encodings")

assert(package.loaded["flash-any.tables.unicode"] == nil)
assert(#run("α", "alpha", {}) == 0)
assert(package.loaded["flash-any.tables.unicode"] == nil)
assert(#run("α", "alpha", { "unicode" }) == 1)
assert(#run("α", "α", {}) == 0)
assert(#run("abc", "ab", {}) == 1)
assert(#run("abc", "ab", { "literal" }) == 1)
assert(#run("abc", "ab", { { name = "literal" } }) == 1)
assert(#run("中", "中", { "literal" }) == 0)
assert(#run("a", "x", { "literal", { data = { a = { "x" } }, fallback = true } }) == 0)
assert(#run("中", "x", { "literal", { data = { ["中"] = { "x" } }, fallback = true } }) == 1)
assert(#run("a", "a", { { matcher = function() error("default literal must run first") end, fallback = true } }) == 1)
assert(#run("a", "a", { { data = {} }, { name = "literal", fallback = true } }) == 1)
print("ok - literal is prepended by configuration; Unicode remains explicit")

assert(#run("中", "ab", { { data = { ["中"] = "ab" }, matcher = "full_code" } }) == 1)

matches = run("甲", "b", {
  { data = { ["甲"] = { "a" } } },
  { matcher = function() error("recognized character reached fallback") end, fallback = true },
})
assert(#matches == 0)
print("ok - setup preserves recognized-but-unmatched coverage")

matches = run("甲", "b", {
  { matcher = function() return false end },
  { data = { ["甲"] = { "b" } }, fallback = true },
})
assert(#matches == 1)
assert(#run("甲", "name", {
  { data = { ["甲"] = "a" } },
  { name = "unicode", data = { ["甲"] = "name" }, fallback = false },
}) == 1)
assert(#run("甲", "name", {
  { data = { ["甲"] = "a" } },
  { name = "unicode", data = { ["甲"] = "name" } },
}) == 0)
print("ok - setup permits fallback for unknown characters and honors explicit false")

matches = run("🙂", "x", {
  { name = "pinyin", loader = function() error("out-of-scope character reached loader") end },
})
assert(#matches == 0)
print("ok - built-in matcher scope avoids unrelated lazy lookup")

matches = run("🙂", "x", {
  { loader = function(char) if char == "🙂" then return { "x" } end end },
})
assert(#matches == 1)
print("ok - custom loaders support their own character scope")

matches = run("中国", "zg", { { name = "pinyin" } })
assert(#matches == 1 and matches[1].end_pos[2] == 3)
print("ok - full pinyin defaults to initial matching")

matches = run("中国", "v", { { name = "pinyin", scheme = "flypy" } })
assert(#matches == 1 and matches[1].end_pos[2] == 0 and matches[1].next.s and not matches[1].next.g)
matches = run("中国", "vsg", { { name = "pinyin", scheme = "flypy" } })
assert(#matches == 1 and matches[1].end_pos[2] == 3)
print("ok - double pinyin uses full_code matching by default")

matches = run("中国", "vg", { { name = "pinyin", scheme = "flypy", matcher = "initial" } })
assert(#matches == 1 and matches[1].end_pos[2] == 3)
print("ok - pinyin matcher can override the encoding default")

for _, sources in ipairs({
  { "pinyin", { name = "pinyin", scheme = "flypy" } },
  { { name = "pinyin", scheme = "flypy" }, { name = "pinyin", scheme = "natural" } },
}) do
  local ok, err = pcall(plugin.jump, { sources = sources })
  assert(not ok and tostring(err):find("only one pinyin source", 1, true))
end
print("ok - multiple pinyin encodings are mutually exclusive")

plugin.setup({ sources = { { name = "pinyin", scheme = "flypy" } } })
plugin.jump()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" })
matches = jump.matcher(0, { pattern = function() return "vs" end }, { from = { 1, 0 }, to = { 1, 0 } })
assert(#matches == 1)
print("ok - setup selects encoding through the pinyin source")

matches = run("中", "x", { { ["中"] = "x" } })
assert(#matches == 1)
print("ok - source table shorthand is normalized during configuration")

plugin.setup({ sources = { { data = { ["中"] = "a" } } }, labels = "ab", search = { forward = false } })
plugin.jump()
assert(jump.labels == "ab" and jump.search.forward == false)
local defaults = jump
plugin.jump({ sources = { { data = { ["中"] = "b" } } }, labels = "xy" })
assert(jump.labels == "xy" and jump.search == nil)
plugin.jump()
assert(jump == defaults)
plugin.jump({ sources = {} })
assert(jump.labels == nil and jump.search == nil)
for _, options in ipairs({ {}, false, { labels = "xy" }, { table = { ["中"] = "x" } } }) do
  local before = jump
  assert(not pcall(plugin.jump, options))
  assert(jump == before)
end
print("ok - explicit opts replace the whole configuration; only nil selects defaults")

for _, source in ipairs({
  { data = {}, matcher = "missing" },
  { data = {}, matcher = "literal" },
  { data = {}, matcher = false },
  { data = {}, fallback = "yes" },
  { loader = "not a function" },
}) do
  local before = jump
  assert(not pcall(plugin.setup, { sources = { source } }))
  assert(not pcall(plugin.jump, { sources = { source } }))
  assert(jump == before)
end
assert(not pcall(plugin.setup, { sources = { "pinyin", "pinyin" } }))
assert(not pcall(plugin.setup, { sources = { name = "pinyin" } }))
print("ok - invalid configuration fails before reaching Flash")

local spaced = { { data = { ["甲"] = "a", ["乙"] = "bbbb" }, append_space_below = 4 } }
matches = run("甲乙", "a bbbb", spaced)
assert(#matches == 1 and matches[1].end_pos[2] == 3)
assert(#run("甲乙", "abbbb", spaced) == 0)
assert(not pcall(plugin.setup, { sources = { { data = {}, append_space_below = 0 } } }))
print("ok - custom source short codes require a trailing space; threshold-length codes do not")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" })
local calls = 0
plugin.setup({ sources = { { loader = function(char)
  calls = calls + 1
  if char == "中" then return { "x" } end
end } } })
assert(calls == 0)
for _ = 1, 2 do
  plugin.jump()
  matches = jump.matcher(0, { pattern = function() return "x" end }, { from = { 1, 0 }, to = { 1, 0 } })
  assert(#matches == 1)
end
assert(calls == 1)
print("ok - setup builds sources once and preserves lazy lookup caches across jumps")

plugin.remote()
assert(remote == jump)
matches = remote.matcher(0, { pattern = function() return "x" end }, { from = { 1, 0 }, to = { 1, 0 } })
assert(#matches == 1 and calls == 1)
local remote_defaults = remote
plugin.remote({ sources = { { data = { ["中"] = "y" } } }, labels = "ab" })
assert(remote ~= remote_defaults and remote.labels == "ab")
matches = remote.matcher(0, { pattern = function() return "y" end }, { from = { 1, 0 }, to = { 1, 0 } })
assert(#matches == 1)
plugin.remote()
assert(remote == remote_defaults)
assert(not pcall(plugin.remote, {}))
assert(remote == remote_defaults)
print("ok - remote shares configured sources and caches; explicit opts replace defaults")

print("all source setup tests passed")

-- Temporary matcher heap growth only; no scanner, source wrapper, or UI.
-- Optional arguments: implementation root and protocol (emit or nested for baselines).
vim.opt.runtimepath:prepend(arg[1] or vim.uv.cwd())
local shape = arg[2] or "emit"
assert(shape == "emit" or shape == "nested", "protocol must be emit or nested")
local Cursor = require(shape == "nested" and "flash-any.text" or "flash-any.cursor")
local literal = shape == "nested" and require("flash-any.match.literal") or require("flash-any.sources.literal")()
local codetable = require("flash-any.match.codetable")
local fixtures = {
  { name = "literal-complete", matcher = literal.matcher, text = "a", input = "a" },
  { name = "literal-next", matcher = literal.matcher, text = "a", input = "" },
  { name = "literal-mismatch", matcher = literal.matcher, text = "a", input = "z" },
  { name = "full-complete", matcher = codetable.full_code, text = "甲", input = "abc", codes = { "abc" } },
  { name = "full-mismatch", matcher = codetable.full_code, text = "甲", input = "z", codes = { "abc" } },
  {
    name = "prefix-overlap",
    matcher = codetable.prefix,
    text = "甲",
    input = "ab",
    codes = { "a", "ab", "abc", "abcd" },
  },
}
local sink, emissions = nil, 0
local function emit()
  emissions = emissions + 1
end
local function run(fixture)
  if shape == "emit" then
    sink = fixture.matcher(fixture.view, fixture.stream, fixture.args, emit)
  else
    sink = fixture.matcher(fixture.view, fixture.input, fixture.args)
  end
end
for _, fixture in ipairs(fixtures) do
  fixture.view = Cursor.new(fixture.text)
  fixture.view:get(1)
  fixture.stream = Cursor.new(fixture.input)
  fixture.stream:get()
  local source = { matcher = fixture.matcher, data = fixture.codes and { [fixture.text] = fixture.codes } }
  fixture.args = shape == "nested" and { source = source } or source
  run(fixture)
end
-- Disable JIT for heap growth so allocation sinking cannot hide temporary tables.
jit.off()
jit.flush()
for _, fixture in ipairs(fixtures) do
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, 10000 do
    run(fixture)
  end
  local bytes = (collectgarbage("count") - before) * 1024 / 10000
  collectgarbage("restart")
  print(("ALLOC %s bytes/call=%.1f"):format(fixture.name, bytes))
end
assert(sink and (shape ~= "emit" or emissions > 0))

-- Retained Cursor heap and cache bucket counts; no CPU/UI timing.
-- Optional arguments: implementation root, then single/mixed/stream/lengths.
vim.opt.runtimepath:prepend(arg[1] or vim.uv.cwd())
local Cursor = require("flash-any.cursor")
local scenario = arg[2] or "single"
jit.off()
jit.flush()
local positions, lengths
if scenario == "single" then
  positions, lengths = 1000, { 1 }
elseif scenario == "mixed" then
  positions, lengths = 1000, { 1, 2, 4 }
elseif scenario == "stream" then
  positions, lengths = 20, { 0, 1 }
elseif scenario == "lengths" then
  positions, lengths = 1, {}
  for n = 1, 20 do
    lengths[#lengths + 1] = n
  end
else
  error("unknown scenario")
end
local input = ("甲"):rep(math.max(positions, 20))
collectgarbage("collect")
local before = collectgarbage("count")
local cursor = Cursor.new(input)
for position = 1, positions do
  for _, count in ipairs(lengths) do
    local value = count == 0 and cursor:get() or cursor:get(count)
    assert(#value > 0)
  end
  if position < positions then
    assert(cursor:shift())
  end
end
collectgarbage("collect")
local bytes = (collectgarbage("count") - before) * 1024
local buckets = 0
-- Inspect private storage only to count cache buckets in this benchmark.
for _ in pairs(assert(rawget(cursor, "_values"))) do
  buckets = buckets + 1
end
print(("RESULT %s positions=%d cache_tables=%d retained_bytes=%.0f"):format(scenario, positions, buckets, bytes))

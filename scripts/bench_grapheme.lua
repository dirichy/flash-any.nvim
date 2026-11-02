-- Separate processes: nvim --clean -l scripts/bench_grapheme.lua ROOT [FIXTURE [WORKLOAD [off]]]
-- For stable comparisons, isolate one fixture/workload per process; off disables JIT.
-- Measures local CPU only: no process startup, source setup, redraw or input events.
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(assert(arg[1], "implementation root required"))
if arg[4] == "off" then
  jit.off()
  jit.flush()
end
local Cursor = require("flash-any.cursor")
local scanner = require("flash-any.match")
local tables = require("flash-any.table")
local codetable = require("flash-any.match.codetable")
local scopes = require("flash-any.scope")
local emoji = {
  ["👩‍💻"] = "coder",
  ["👨‍💻"] = "coder",
  ["🧑‍💻"] = "coder",
  ["👩‍🔬"] = "science",
  ["👨‍🔬"] = "science",
  ["👩‍❤️‍💋‍👨"] = "kiss",
  ["👩‍👩‍👧‍👦"] = "family",
  ["🏳️‍🌈"] = "rainbow",
  ["🏴‍☠️"] = "pirate",
  ["❤️‍🔥"] = "fire",
  ["❤️"] = "heart",
  ["🇨🇳"] = "flag",
  ["😀"] = "happy",
  ["✅"] = "done",
}
-- Rebuild metadata in each implementation's units; text and ASCII codes stay fixed.
local prefixes, maximum = {}, 1
for key in pairs(emoji) do
  local view, count = Cursor.new(key), 0
  while view:shift() do
    count = count + 1
    if view.offset < #key then
      prefixes[key:sub(1, view.offset)] = true
    end
  end
  maximum = math.max(maximum, count)
end
local pinyin = require("flash-any.sources.pinyin")()
local sources = {
  require("flash-any.sources.literal")(),
  { data = pinyin.data, matcher = codetable.initial, scope = scopes.resolve(pinyin.scope) },
  { data = tables.normalize({ codes = emoji, prefixes = prefixes, max_chars = maximum }), matcher = codetable.prefix },
}
local fixtures = {
  { name = "ascii", text = "local result = cursor:get(1) -- English words and numbers 12345; " },
  {
    name = "chinese",
    text = "普通中文正文用于检查字符扫描开销，今天写代码，明天做研究。包含 English words 12345。",
  },
  {
    name = "mixed",
    text = "工作记录：今天写代码 👩‍💻，明天做研究 👨‍🔬。Hello 😀，完成 ✅，喜欢 ❤️，中国 🇨🇳。",
  },
  {
    name = "zwj",
    text = "👩‍💻👨‍💻🧑‍💻👩‍🔬👨‍🔬👩‍❤️‍💋‍👨👩‍👩‍👧‍👦🏳️‍🌈🏴‍☠️❤️‍🔥",
  },
}
if arg[2] then
  fixtures = vim.tbl_filter(function(fixture)
    return fixture.name == arg[2]
  end, fixtures)
  assert(#fixtures == 1, "unknown fixture")
end
local labels = vim.split("asdfghjklqwertyuiopzxcvbnm", "")
local opts = { from = { 1, 0 }, to = { 40, 0 } }
local function state(pattern)
  local obj = { value = pattern }
  obj.pattern = function()
    return obj.value
  end
  obj.labels = function()
    return labels
  end
  return obj
end
local function get(obj)
  return scanner.get(0, obj, opts, sources)
end
local sink
local function measure(name, fn)
  if arg[3] and name ~= arg[2] .. "/" .. arg[3] then
    return
  end
  jit.flush()
  for _ = 1, 100 do
    sink = fn()
  end
  local n = 1
  repeat
    collectgarbage("collect")
    local start = vim.uv.hrtime()
    for _ = 1, n do
      sink = fn()
    end
    if vim.uv.hrtime() - start >= 30000000 then
      break
    end
    n = n * 2
  until n >= 65536
  local samples = {}
  for _ = 1, 7 do
    collectgarbage("collect")
    local start = vim.uv.hrtime()
    for _ = 1, n do
      sink = fn()
    end
    samples[#samples + 1] = (vim.uv.hrtime() - start) / n / 1e6
  end
  table.sort(samples)
  io.write(
    vim.json.encode({ name = name, median_ms = samples[4], min_ms = samples[1], max_ms = samples[7], n = n }),
    "\n"
  )
  io.flush()
end
io.write(
  vim.json.encode({ neovim = tostring(vim.version()), luajit = jit.version, root = arg[1], emoji_max_chars = maximum }),
  "\n"
)
for _, fixture in ipairs(fixtures) do
  local value, lines = fixture.text:rep(2), {}
  for i = 1, 40 do
    lines[i] = value
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local view, starts = Cursor.new(value), 0
  while view:shift() do
    starts = starts + 1
  end
  io.write(vim.json.encode({ fixture = fixture.name, bytes = #value * 40, starts = starts * 40 }), "\n")
  measure(fixture.name .. "/cursor-new-40", function()
    local cursors = {}
    for i = 1, 40 do
      cursors[i] = Cursor.new(value)
    end
    return cursors
  end)
  measure(fixture.name .. "/cursor-walk-40", function()
    local cursors = {}
    for i = 1, 40 do
      local text = Cursor.new(value)
      repeat
        sink = text:get(1)
      until not text:shift()
      cursors[i] = text
    end
    return cursors
  end)
  measure(fixture.name .. "/fresh-c", function()
    return get(state("c"))
  end)
  for _, word in ipairs({ "shi", "coder" }) do
    measure(fixture.name .. "/type-" .. word, function()
      local obj = state("")
      for i = 1, #word do
        obj.value = word:sub(1, i)
        sink = get(obj)
      end
      return sink
    end)
  end
  collectgarbage("collect")
  local before = collectgarbage("count")
  local obj = state("c")
  local result = get(obj)
  collectgarbage("collect")
  io.write(
    vim.json.encode({ fixture = fixture.name, retained_kib = collectgarbage("count") - before, matches = #result }),
    "\n"
  )
  assert(obj._flash_any_cache and result)
end
assert(sink)

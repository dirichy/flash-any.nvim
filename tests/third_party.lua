vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.env.XDG_CACHE_HOME = root .. "/cache"
local function write(name, lines)
	local path = root .. "/" .. name
	assert(vim.fn.writefile(lines, path) == 0)
	return path
end
local table_path = write("external.tsv", { "国\tguo", "中\tzhong", "中\tzh", "中\tz", "👩‍💻\tdev" })
local converter = write("convert.lua", {
	"vim.g.converter_calls = (vim.g.converter_calls or 0) + 1",
	"return function(codes) return vim.tbl_map(string.upper, codes) end",
})
local source = require("flash-any.source")
local data = source.resolve({ { file = table_path } })[2].data
assert(data and vim.deep_equal(data["中"], { "z", "zh", "zhong" }))
local converted = source.resolve({ { file = table_path, converter = converter } })[2].data
assert(converted and converted["国"][1] == "GUO" and data["国"][1] == "guo")
assert(source.resolve({ { file = table_path, append_space_below = 4 } })[2].data["国"][1] == "guo ")
---@type any Deliberately invalid public input.
local invalid = { file = table_path, matcher = function() end }
assert(not pcall(source.resolve, { invalid }))
assert(not pcall(source.resolve, { { file = table_path, data = {} } }))
assert(not pcall(source.resolve, { { data = {}, converter = converter } }))
local native = require("flash-any.native")
local function matches(book, text, pattern)
	return book:new_state():scan(0, 0, 0, 1, 1, { text }, pattern, "ab")
end
local filtered_file = write("filtered.tsv", { "あ\ta", "⚡\tbolt" })
local filter = write("filter.lua", {
	'return function(codes) if codes[1] == "a" then return nil end return codes end',
})
local filtered_book = native.load(nil, {
	{ file = filtered_file, converter = filter },
	{ data = { ["あ"] = "fallback" }, fallback = true },
})
assert(#matches(filtered_book, "あ", "a") == 0)
assert(#matches(filtered_book, "あ", "fallback") == 1, "converter-removed entries must not suppress fallback")
assert(#matches(filtered_book, "⚡", "bolt") == 1)
local specs = { { file = table_path, converter = converter, matcher = "full_code" } }
local book = native.load(nil, specs)
assert(#matches(book, "中国", "ZHONGGUO") == 1)
assert(#matches(book, "👩‍💻", "DEV") == 1)
local calls = vim.g.converter_calls
assert(#matches(native.load(nil, specs), "中", "ZHONG") == 1)
assert(vim.g.converter_calls == calls, "cached setup executed converter")
write("external.tsv", { "中\tnew" })
assert(#matches(native.load(nil, specs), "中", "NEW") == 1, "TSV edits reused stale binary")
write("convert.lua", { "return function() return {'changed'} end" })
assert(#matches(native.load(nil, specs), "中", "changed") == 1, "converter edits reused stale binary")
assert(#matches(book, "中", "ZHONG") == 1, "new snapshot invalidated an existing engine")
local lua_path = write("table.lua", { "return {['中']='first'}" })
local tsv_path = write("complete.tsv", { "国\tguo" })
local files = { { lua = lua_path, tsv = tsv_path } }
local original = native.load(nil, files)
assert(#matches(original, "中国", "firstguo") == 1)
write("table.lua", { "return {['中']='updated'}" })
assert(#matches(native.load(nil, files), "中国", "updatedguo") == 1, "Lua table edits reused stale binary")
write("complete.tsv", { "国\tnew" })
assert(#matches(native.load(nil, files), "中国", "updatednew") == 1, "companion TSV edits reused stale binary")
assert(#matches(original, "中国", "firstguo") == 1, "file edits invalidated a live snapshot")
-- Warm file-based setup reads metadata only and does not execute the Lua dictionary.
local open = io.open
rawset(io, "open", function()
	error("cached Lua/TSV setup must not read file contents")
end)
local cached_ok, cached = pcall(native.load, nil, files)
rawset(io, "open", open)
assert(cached_ok, cached)
assert(#matches(cached, "中国", "updatednew") == 1)
vim.fn.delete(tsv_path)
assert(not pcall(native.load, nil, files), "missing dependencies must not silently reuse old data")
assert(#matches(native.load(nil, { { file = table_path, matcher = "initial" } }), "中", "n") == 1)
assert(#matches(native.load(nil, { { file = table_path, matcher = "prefix" } }), "中", "ne") == 1)
write("convert.lua", { "return function(codes) if codes[1] == 'skip' then return nil end return codes end" })
write("external.tsv", { "中\tskip", "国\tguo" })
local filtered = source.resolve(specs)[2].data
assert(filtered and filtered["中"] == nil and filtered["国"][1] == "guo")
for _, row in ipairs({ "中" }) do
	write("external.tsv", { row })
	assert(not pcall(source.resolve, { { file = table_path } }), "malformed TSV accepted: " .. row)
end
write("external.tsv", { "中国\tword" })
assert(#matches(native.load(nil, { { file = table_path } }), "中国", "word") == 0)
write("convert.lua", { "return {}" })
assert(not pcall(source.resolve, specs))
vim.fn.delete(root, "rf")
print("standalone TSV, build-time converter, native modes and cache invalidation tests passed")

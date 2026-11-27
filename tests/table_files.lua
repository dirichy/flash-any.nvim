vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables, build = require("flash-any.table"), require("flash-any.build")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/tables", "p")
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
vim.opt.runtimepath:append(root)
local function write(name, lines)
	local path = root .. "/" .. name
	assert(vim.fn.writefile(lines, path) == 0)
	return path
end
local tsv = write("complete.tsv", { "国\tb", "中国\tword", "中\tx", "国\ta", "中\tx", "屏\tfile", "弃\tkeep" })
local lua =
	write("override.lua", { 'return { codes = { ["中"] = {"lua", "second"}, ["屏"] = {}, ["弃"] = {"drop"} } }' })
local merged = tables.from_files(lua, tsv)
assert(getmetatable(merged) == nil)
assert(vim.deep_equal(merged, {
	["中"] = { "lua", "second" },
	["国"] = { "a", "b" },
	["中国"] = { "word" },
	["屏"] = {},
	["弃"] = { "drop" },
}))
assert(merged.missing == nil and rawget(merged, "missing") == nil)
local specs = { { lua = lua, tsv = tsv }, { data = { ["屏"] = "fallback", ["缺"] = "missing" }, fallback = true } }
local resolved = require("flash-any.source").resolve(specs)
assert(getmetatable(resolved[2].data) == nil and rawget(resolved[2].data, "中国")[1] == "word")
local output = root .. "/first.bin"
build.binary({ sources = specs, output = output })
local engine = require("flash-any.native").load(output)
assert(
	#engine:new_state():scan(0, 0, 1, 1, 1, { "屏" }, "fallback", nil) == 0,
	"empty Lua overrides must block fallbacks"
)
assert(#engine:new_state():scan(0, 0, 1, 1, 1, { "缺" }, "missing", nil) == 1)
assert(#engine:new_state():scan(0, 0, 1, 1, 1, { "中国" }, "luab", nil) == 1)
-- Reading a missing key must not create lookup state or change a subsequent export.
assert(resolved[2].data.missing == nil)
build.binary({ sources = { { data = resolved[2].data }, specs[2] }, output = root .. "/second.bin" })
assert(vim.deep_equal(vim.fn.readblob(output), vim.fn.readblob(root .. "/second.bin")))

write("lua/flash-any/tables/overlay.lua", vim.fn.readfile(lua))
write("lua/flash-any/tables/overlay.tsv", vim.fn.readfile(tsv))
local function convert(codes)
	if codes[1] == "drop" then
		return nil
	end
	if #codes == 2 then
		return { "both" }
	end
	return vim.tbl_map(string.upper, codes)
end
local converted = tables.load("overlay", { convert = convert, extra = { ["国"] = "extra" } })
assert(vim.deep_equal(converted["中"], { "both" }), "Lua conversion must receive the whole code list")
assert(vim.deep_equal(converted["国"], { "extra" }), "extra must override both file inputs after conversion")
assert(vim.deep_equal(converted["弃"], { "KEEP" }), "nil Lua conversion must expose its converted TSV fallback")
assert(#converted["屏"] == 0)
local rows = tables.load("overlay", { convert = convert })
assert(vim.deep_equal(rows["国"], { "A", "B" }), "Lua/TSV companions must keep per-row TSV conversion")
write("lua/flash-any/tables/only.tsv", { "国\tb", "国\ta", "弃\tdrop" })
local only = tables.load("only", { convert = convert })
assert(vim.deep_equal(only["国"], { "both" }), "TSV-only conversion must receive all deduplicated codes")
assert(only["弃"] and #only["弃"] == 0, "named table conversion must keep known empty entries")
local converter =
	write("converter.lua", { "return function(codes) if codes[1] == 'drop' then return nil end return codes end" })
local removed = tables.from_file(root .. "/lua/flash-any/tables/only.tsv", { converter = converter })
assert(removed["弃"] == nil, "direct file converters must still remove omitted keys")
assert(tables.load("overlay")["中"][1] == "lua", "conversion must not mutate the module cache")
write(
	"lua/flash-any/sources/prepared.lua",
	{ "return function() return {prepared = true, data = { ['中'] = 'x' }} end" }
)
local prepared = assert(require("flash-any.source").resolve({ "prepared" })[2].data)
assert(getmetatable(prepared) == nil and vim.deep_equal(prepared["中"], { "x" }))
vim.fn.delete(root, "rf")
print("complete file maps, Lua/TSV precedence, empty fallback blockers, conversion and prepared sources passed")

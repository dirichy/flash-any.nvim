-- Preserve source-author conversion contracts and user-visible Lua/TSV fallback behavior.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local tables, build = require("flash-any.table"), require("flash-any.build")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/tables", "p")
vim.opt.runtimepath:append(root)
local function write(name, lines)
	local path = root .. "/" .. name
	assert(vim.fn.writefile(lines, path) == 0)
	return path
end
local tsv = write("complete.tsv", { "国\tb", "中国\tword", "中\tx", "国\ta", "中\tx", "屏\tfile", "弃\tkeep" })
local lua =
	write("override.lua", { 'return { codes = { ["中"] = {"lua", "second"}, ["屏"] = {}, ["弃"] = {"drop"} } }' })
local specs = { { lua = lua, tsv = tsv }, { data = { ["屏"] = "fallback", ["缺"] = "missing" }, fallback = true } }
local output = root .. "/first.bin"
build.binary({ sources = specs, output = output })
local engine = require("flash-any.native").load(output)
assert(
	#engine:new_state():scan(0, 0, 1, 1, 1, { "屏" }, "fallback", nil) == 0,
	"empty Lua overrides must block fallbacks"
)
assert(#engine:new_state():scan(0, 0, 1, 1, 1, { "缺" }, "missing", nil) == 1)
assert(#engine:new_state():scan(0, 0, 1, 1, 1, { "中国" }, "luab", nil) == 1)
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
vim.fn.delete(root, "rf")
print("Lua/TSV precedence, empty fallback blockers and source-author conversion contracts passed")

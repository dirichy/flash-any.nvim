-- Conversion runs once per merged text entry, independent of its file layout.
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
local function convert(codes, text)
	assert(type(text) == "string" and text ~= "")
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
assert(converted["弃"] == nil, "nil Lua conversion must remove the merged entry without exposing TSV")
assert(converted["屏"] == nil, "empty conversion must remove the merged entry")
local rows = tables.load("overlay", { convert = convert })
assert(vim.deep_equal(rows["国"], { "both" }), "Lua/TSV companions must convert the complete list once")
write("lua/flash-any/tables/only.tsv", { "国\tb", "国\ta", "弃\tdrop" })
local only = tables.load("only", { convert = convert })
assert(vim.deep_equal(only["国"], { "both" }), "TSV-only conversion must receive all deduplicated codes")
assert(only["弃"] == nil, "named conversion must remove omitted entries like file conversion")
local converter =
	write("converter.lua", { "return function(codes) if codes[1] == 'drop' then return nil end return codes end" })
local removed = tables.from_file(root .. "/lua/flash-any/tables/only.tsv", { converter = converter })
assert(removed["弃"] == nil, "direct file converters must still remove omitted keys")
assert(tables.load("overlay")["中"][1] == "lua", "conversion must not mutate the module cache")

-- Adding unrelated Lua overrides cannot change how existing TSV entries convert.
write("lua/flash-any/tables/only.lua", { 'return {["另"]="extra"}' })
local paired = tables.load("only", { convert = convert })
assert(vim.deep_equal(paired["国"], only["国"]) and paired["弃"] == nil)

-- Lua raw readings can be Unicode; normalization validates converted output only.
local readings = { ["中国"] = { "中文", "读音" }, ["弃"] = { "丢弃" }, ["空"] = {} }
write("lua/flash-any/tables/readings.lua", vim.split("return " .. vim.inspect(readings), "\n", { plain = true }))
write("lua/flash-any/tables/readings.tsv", { "中国\tshadowed", "弃\tshadowed" })
local calls = {}
local function reading_codes(codes, text)
	calls[text] = (calls[text] or 0) + 1
	if text == "中国" then
		assert(vim.deep_equal(codes, { "中文", "读音" }))
		codes[1] = "changed"
		return { "country" }
	end
	if text == "弃" then
		return nil
	end
	return {}
end
local reading_data = tables.load("readings", { convert = reading_codes, extra = { ["补"] = "outside" } })
assert(vim.deep_equal(reading_data, { ["中国"] = { "country" }, ["补"] = { "outside" } }))
assert(vim.deep_equal(calls, { ["中国"] = 1, ["弃"] = 1, ["空"] = 1 }))
assert(vim.deep_equal(require("flash-any.tables.readings"), readings), "conversion mutated cached Lua input")
-- A dropped entry allows a later fallback; an unconverted explicit empty list still blocks it.
local book_path = root .. "/converted.bin"
build.binary({
	sources = {
		{ data = reading_data },
		{ data = { ["弃"] = "fallback", ["空"] = "empty" }, fallback = true },
	},
	output = book_path,
})
local converted_engine = require("flash-any.native").load(book_path)
assert(#converted_engine:new_state():scan(0, 0, 0, 1, 1, { "弃" }, "fallback", nil) == 1)
assert(#converted_engine:new_state():scan(0, 0, 0, 1, 1, { "空" }, "empty", nil) == 1)

local unicode_file = write("lua/flash-any/tables/raw.tsv", { "中国\t中文", "中国\t读音", "弃\t丢弃" })
local unicode_converter = write("unicode-converter.lua", {
	"return function(codes, text)",
	'  if text == "弃" then return nil end',
	'  assert(text == "中国" and #codes == 2)',
	'  return {"country"}',
	"end",
})
local expected = { ["中国"] = { "country" } }
assert(vim.deep_equal(tables.from_file(unicode_file, { converter = unicode_converter }), expected))
assert(vim.deep_equal(tables.load("raw", { convert = dofile(unicode_converter) }), expected))
write("lua/flash-any/tables/standalone.lua", { 'return {["中国"]={"中文", "读音"}, ["弃"]="丢弃"}' })
assert(vim.deep_equal(tables.load("standalone", { convert = dofile(unicode_converter) }), expected))
-- Validate converter return shapes consistently, including the old single-argument form.
for _, expression in ipairs({ "false", '"bad"', '{named="bad"}', "{1}", '{"读音"}', '{"a\\0b"}' }) do
	local invalid = write("invalid-converter.lua", { "return function(codes) return " .. expression .. " end" })
	assert(not pcall(tables.from_file, unicode_file, { converter = invalid }), expression)
	assert(not pcall(tables.load, "raw", { convert = dofile(invalid) }), expression)
end
vim.fn.delete(root, "rf")
print("Lua/TSV precedence, empty fallback blockers and source-author conversion contracts passed")

vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.env.XDG_CACHE_HOME = root .. "/cache"
local build = require("flash-any.build")
local tables = require("flash-any.table")
local function write(name, text)
	local path = root .. "/" .. name
	local handle = assert(io.open(path, "wb"))
	handle:write(text)
	handle:close()
	return path
end
local comma = write("comma.tsv", "\239\187\191# comment\r\n中\tab,cd\t100\r\n中\t,\t10\r\n中\tab,cd\r\n\r\n")
assert(vim.deep_equal(build.read(comma), { ["中"] = { ",", "ab,cd" } }))
assert(vim.deep_equal(tables.from_file(comma)["中"], { ",", "ab,cd" }))
local csv = write("table.csv", '"中","a,b",100\n"中","a""b",1\n')
assert(vim.deep_equal(build.read(csv)["中"], { 'a"b', "a,b" }))
assert(not pcall(build.read, write("bad.csv", '"中","unterminated\n'), { format = "csv" }))
assert(build.read(write("spaces.csv", "中,a b\n"))["中"][1] == "a b")
assert(build.read(write("semicolon.tsv", ";\tsemi\n"))[";"][1] == "semi")
local reversed = write("reversed.tsv", "a,b\t中\t100\n")
assert(build.read(reversed, { columns = { "code", "text", "weight" } })["中"][1] == "a,b")
local space = write("space.txt", "中 a,b 100\n国 guo 1\n")
assert(build.read(space)["中"][1] == "a,b")
local fcitx = write("fcitx.txt", ";fcitx 版本\n键码=abc\n码长=3\n[组词规则]\ne2=p11+p21\n[数据]\na,b 中\n")
assert(build.read(fcitx)["中"][1] == "a,b")
local english = write(
	"english-fcitx.txt",
	[=[KeyCode=abcdefghijklmnopqrstuvwxyz#;
Prompt=&
ConstructPhrase=^
[Data]
# 井
## 双
; 分
&a 提示
^a 构
sp " "
dq "\""
bs "\\"
[Phrase]
只写词组没有编码
]=]
)
local decoded = build.read(english)
assert(decoded["井"][1] == "#" and decoded["双"][1] == "##" and decoded["分"][1] == ";")
assert(decoded["提示"] == nil and decoded["构"] == nil)
assert(decoded[" "][1] == "sp" and decoded['"'][1] == "dq" and decoded["\\"][1] == "bs")
local csv_header = write("header.csv", "字,码,词频\n中,zhong,100\n")
assert(vim.deep_equal(build.read(csv_header, { header = true }), { ["中"] = { "zhong" } }))
local utf16 = write("utf16.csv", string.char(255, 254) .. vim.iconv("字,码\n中,zhong\n", "utf-8", "utf-16le"))
assert(vim.deep_equal(build.read(utf16, { header = true, encoding = "utf-16le" }), { ["中"] = { "zhong" } }))
local ibus = write(
	"ibus.txt",
	"SCIM_Generic_Table_Phrase_Library_TEXT\nVERSION_1_0\nBEGIN_DEFINITION\nNAME=Demo\nEND_DEFINITION\nBEGIN_TABLE\n### comment\n#\t井\t100\n##\t双\t100\na,b\t中\t100\nEND_TABLE\n"
)
assert(build.read(ibus)["中"][1] == "a,b")
assert(build.read(ibus)["井"][1] == "#" and build.read(ibus)["双"][1] == "##")
write("child.dict.yaml", "---\nname: child\nversion: '1'\n...\n国\tguo\t1\n中国\tword\t1\n")
local rime = write(
	"main.dict.yaml",
	"---\nname: main\nversion: '1'\ncolumns: [code, text, weight]\nimport_tables:\n  - child\n...\na,b\t中\t100\n"
)
local values = build.read(rime)
assert(values["中"][1] == "a,b" and values["国"][1] == "guo" and values["中国"][1] == "word")
local input = { file = rime }
local native = require("flash-any.native")
local book = native.load(nil, { input })
assert(#book:scan(0, 0, 1, 1, 1, { "中国" }, "a,bguo", { "a", "b" }) == 1)
local fingerprint = build.fingerprint(rime)
write("child.dict.yaml", "---\nname: child\nversion: '2'\n...\n国\tnew\n")
assert(build.fingerprint(rime) ~= fingerprint)
local updated = native.load(nil, { input })
assert(#updated:scan(0, 0, 1, 1, 1, { "国" }, "new", { "a", "b" }) == 1)
assert(#book:scan(0, 0, 1, 1, 1, { "国" }, "guo", { "a", "b" }) == 1)
write("child.dict.yaml", "---\nimport_tables: [main]\n...\n")
assert(not pcall(build.read, rime), "cyclic imports must fail")
assert(not pcall(build.read, comma, { columns = { "weight" } }))
write("unicode.tsv", "中\tzhōng\n")
local converter = write("converter.lua", "return function() return {'zhong'} end\n")
assert(tables.from_file(root .. "/unicode.tsv", { converter = converter })["中"][1] == "zhong")
assert(not pcall(tables.from_file, root .. "/unicode.tsv"))
local exported = root .. "/export.tsv"
build.table({ source = comma, lua = root .. "/export.lua", tsv = exported })
assert(vim.deep_equal(build.read(exported), build.read(comma)))
vim.fn.delete(root, "rf")
print("shared dictionary formats, literal commas, Rime imports and native matching tests passed")

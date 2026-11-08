vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local file = root .. "/tiger.dict.yaml"
vim.fn.writefile({
	"name: test",
	"columns: [text, code, weight]",
	"...",
	"，\t,\t0",
	"。\t.\t0",
	"甲\tab\t100",
	"乙\tab\t80",
	"丙\tab\t50",
	"丁\tab\t30",
	"戊\tab\t10",
	"己\tcd\t100",
	"庚\tcd\t80",
	"辛\tef\t0",
	"壬\tef\t0",
	"癸\tef\t0",
	"中国\tab\t200",
	"子\tzz;\t10",
	"丑\txy,z\t10",
	"赤\tgch\t100",
	"羔\tgch\t80",
}, file)
local build, native = require("flash-any.build"), require("flash-any.native")
local serial = 0
local function engine(opts)
	serial = serial + 1
	local spec = vim.tbl_extend("force", { name = "tiger", file = file }, opts or {})
	local output = root .. "/" .. serial .. ".bin"
	build.binary({ sources = { spec }, output = output })
	return native.load(output), output
end
local function scan(book, text, query)
	return book:new_state():scan(0, 0, 1, 1, 1, { text }, query, { "a", " ", ";", "'", ",", "." })
end
local function found(book, text, query)
	return #scan(book, text, query) > 0
end
local book = engine()
for _, text in ipairs({ "甲", "乙", "丙", "丁", "戊" }) do
	assert(found(book, text, "ab"))
	assert(found(book, text .. "己", "abcd"), "bare codes must continue without selectors")
	assert(found(book, text .. "，己", "ab,cd"), "punctuation is an ordinary following glyph")
end
for rank, key in ipairs({ " ", ";" }) do
	for index, text in ipairs({ "甲", "乙", "丙", "丁", "戊" }) do
		assert(found(book, text, "ab" .. key) == (index == rank), "unconsumed selectors naturally fail")
		assert(found(book, text .. key, "ab" .. key), "following literal text may consume any selector")
	end
end
assert(not found(book, "丙", "ab'"), "third-choice key must not be enabled by default")
assert(found(book, "丙'", "ab'"))
assert(found(book, "羔", "gch;") and not found(book, "赤", "gch;"))
assert(found(book, "赤;", "gch;") and found(book, "羔;", "gch;;"))
assert(found(book, "赤羔", "gchgch;") and found(book, "赤羔", "gch gch;"))
assert(found(book, "甲 己", "ab cd"), "both consuming and omitting the suffix must remain possible")
assert(found(book, "乙己", "ab;cd") and not found(book, "甲己", "ab;cd"))
assert(found(book, "庚", "cd;") and not found(book, "己", "cd;"))
assert(found(book, "壬", "ef;"), "weight ties must preserve input order")
local first_next, second_next = scan(book, "甲", "ab")[1].next, scan(book, "乙", "ab")[1].next
assert(first_next[" "] and second_next[";"])
local labels = book:new_state():scan(0, 0, 1, 1, 1, { "甲乙丙" }, "ab", { " ", ";", "a", "b", "c" })
assert(#labels == 3)
for _, result in ipairs(labels) do
	assert(result.label ~= " " and result.label ~= ";", "valid next keys cannot become labels")
end
local custom = engine({ selection = { keys = { "=", ":", "?" } } })
assert(found(custom, "甲", "ab=") and found(custom, "乙", "ab:") and found(custom, "丙", "ab?"))
assert(not found(custom, "乙", "ab;"))
local four = engine({ selection = { keys = { " ", ";", "'", ":" } } })
assert(found(four, "丙", "ab'") and found(four, "丁", "ab:") and not found(four, "戊", "ab:"))
local disabled = engine({ selection = false })
assert(found(disabled, "甲己", "abcd") and not found(disabled, "乙", "ab;"))
assert(found(disabled, "甲;", "ab;"))
for _, opts in ipairs({
	{ selection = { keys = { " ", "aa" } } },
	{ selection = { keys = { " ", ";", ";" } } },
	{ selection = { keys = false } },
	{ append_space_below = 4 },
	{ selection = false, append_space_below = 4 },
	{ selection_keys = { " " } },
	{ force = false },
	{ punctuation = { "," } },
	{ selection = { force = true } },
	{ selection = { force = false } },
	{ selection = { first_omit_before = { "," } } },
}) do
	assert(not pcall(engine, opts))
end
assert(found(book, "子", "zz;") and found(book, "子", "zz; "))
assert(found(book, "丑，", "xy,z,"), "literal code punctuation must remain intact")
local resolved = require("flash-any.source").resolve({ { name = "tiger", file = file } })[2]
assert(vim.deep_equal(resolved.data["甲"], { "ab" }), "base code must be stored only once")
assert(resolved.selectors["甲"].ab == " " and resolved.selectors["乙"].ab == ";")
assert(resolved.selectors["丙"] == nil)
-- The C suffix matcher also handles partial multi-byte ASCII suffixes without expanding aliases.
local valid = root .. "/metadata.bin"
local parameters = ";!"
native.write(valid, { ";", "甲" }, {
	{ { native.modes.literal, ";" } },
	{ { native.modes.suffix, "ab", parameters } },
})
local suffix = native.load(valid)
assert(found(suffix, "甲", "ab") and found(suffix, "甲", "ab;!"))
assert(scan(suffix, "甲", "ab;")[1].next["!"])
assert(not found(suffix, "甲", "ab;?") and found(suffix, "甲;", "ab;!;"))
local handle = assert(io.open(valid, "rb"))
local bytes = handle:read("*a")
handle:close()
local payload = string.char(128 + native.modes.suffix, #parameters) .. parameters .. "ab"
local at = assert(bytes:find(payload, 1, true))
for _, edit in ipairs({ { at + 1, 0 }, { at + 1, 127 }, { at + 2, 255 }, { at, 160 }, { at, 192 }, { 8, 6 } }) do
	local index, replacement = unpack(edit)
	local corrupted = bytes:sub(1, index - 1) .. string.char(replacement) .. bytes:sub(index + 1)
	local output = assert(io.open(root .. "/bad.bin", "wb"))
	output:write(corrupted)
	output:close()
	assert(not pcall(native.load, root .. "/bad.bin"))
end
assert(not pcall(native.write, root .. "/empty.bin", { "甲" }, { { { native.modes.suffix, "ab", "" } } }))
local builtin = engine({ file = false })
assert(found(builtin, "羔", "gch;") and not found(builtin, "赤", "gch;"))
assert(found(builtin, "赤;", "gch;") and found(builtin, "赤羔", "gchgch;"))
assert(found(builtin, "疒", "ab;") and not found(builtin, "交", "ab;"))
assert(found(builtin, "交，", "ab,") and found(builtin, "疒，", "ab,"))
assert(found(builtin, "交", "ab "))
assert(found(builtin, "𤰃", "ty;") and not found(builtin, "⽤", "ty;"))
local table_data = require("flash-any.table").load("tiger")
for _, code in ipairs(table_data["疒"]) do
	assert(not code:find("\t"))
end
vim.fn.delete(root, "rf")
print("Tiger optional suffixes, natural continuation, ranking and binary validation tests passed")

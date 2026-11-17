vim.opt.runtimepath:prepend(vim.uv.cwd())
local native = require("flash-any.native")
local build = require("flash-any.build")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial = 0
local function compile(spec)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = { spec }, output = path })
	return native.load(path)
end
local groups = { ["す"] = { "su", "suu" }, ["し"] = { "shi", "si" }, tail = { "i", "ii" } }
local comparisons = 0
-- Independently expand the mathematical language for each mode. Native full-code
-- matching over those strings is the oracle, including prefixes and next keys.
for _, mode in ipairs({ "full_code", "initial", "prefix", "letter" }) do
	local codes = { "" }
	for _, name in ipairs({ "す", "し", "tail" }) do
		local forms = {}
		for _, spelling in ipairs(groups[name]) do
			forms[spelling] = true
			if mode == "initial" then
				forms[spelling:sub(1, 1)] = true
			elseif mode == "prefix" then
				for n = 1, #spelling do
					forms[spelling:sub(1, n)] = true
				end
			end
		end
		local expanded = {}
		for _, prefix in ipairs(codes) do
			for form in pairs(forms) do
				expanded[#expanded + 1] = prefix .. form
			end
		end
		codes = expanded
	end
	local grouped = compile({ data = { ["寿司"] = "す し tail" }, groups = groups, matcher = mode })
	local inline = compile({ data = { ["寿司"] = codes }, matcher = mode == "letter" and "letter" or "full_code" })
	local queries = { wrong = true, ["s!"] = true, ["sushi!"] = true }
	for _, code in ipairs(codes) do
		for n = 1, #code do
			queries[code:sub(1, n)] = true
		end
		queries[code .. "!"] = true
		queries[code .. "!tail"] = true
		queries[code:upper()] = true
	end
	for query in pairs(queries) do
		for _, ignorecase in ipairs({ false, true }) do
			for _, motion in ipairs({ "search", "f", "F", "t", "T" }) do
				local char = motion ~= "search" and motion or nil
				local lines = { "x寿司!tail 寿司!tail" }
				local a =
					grouped:new_state():scan(0, 0, 1, 1, 1, lines, query, { "s", "i", "!", "x" }, char, ignorecase)
				local b = inline:new_state():scan(0, 0, 1, 1, 1, lines, query, { "s", "i", "!", "x" }, char, ignorecase)
				assert(vim.deep_equal(a, b), mode .. ": " .. query .. " " .. motion .. " " .. vim.inspect({ a, b }))
				comparisons = comparisons + 1
			end
		end
	end
end
local function found(book, text, query)
	return #book:new_state():scan(0, 0, 1, 1, 1, { text }, query, nil) > 0
end
local empty = compile({ data = { ["甲乙"] = "a empty b" }, groups = { a = { "a" }, empty = {}, b = { "b" } } })
assert(not found(empty, "甲乙", "a"), "a later empty group must suppress previews too")
-- Exact names win over tokenization. Unknown tokens leave ordinary ASCII codes intact.
local exact = compile({
	data = { ["甲"] = "a b", ["乙"] = "a unknown", ["丙"] = "a  a" },
	groups = { a = { "x" }, b = { "y" }, ["a b"] = { "exact" } },
})
assert(found(exact, "甲", "exact") and not found(exact, "甲", "xy"))
assert(found(exact, "乙", "a unknown") and found(exact, "丙", "a  a"))
local padded = compile({
	data = { ["甲乙"] = "す し" },
	groups = groups,
	append_space_below = 10,
})
assert(found(padded, "甲乙", "su shi ") and not found(padded, "甲乙", "sushi"))
assert(groups["す"][1] == "su", "padding must not mutate caller-owned groups")
assert(not pcall(compile, { data = { ["甲"] = "す missing" }, groups = groups }))
assert(not pcall(compile, { data = { ["甲"] = "す" } }))
-- File converters may return Unicode group sequences. Lua files and named
-- codetables must resolve exactly the same names as direct data.
local function write(name, text)
	local path = root .. "/" .. name
	assert(vim.fn.writefile(vim.split(text, "\n", { plain = true }), path) == 0)
	return path
end
local file = write("reading.tsv", "寿司\tすし")
local converter = write("convert.lua", 'return function() return {"す し"} end')
assert(found(compile({ file = file, converter = converter, groups = groups }), "寿司", "susi"))
local lua_file = write("table.lua", 'return {["寿司"] = "す し"}')
assert(found(compile({ lua = lua_file, groups = groups }), "寿司", "sushi"))
vim.fn.mkdir(root .. "/lua/flash-any/tables", "p")
write("lua/flash-any/tables/sequence_fixture.tsv", "寿司\tす し")
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
write(
	"lua/flash-any/sources/sequence_fixture.lua",
	[[return function()
return {codetable="sequence_fixture", groups={["す"]={"su"},["し"]={"shi","si"}}}
end]]
)
vim.opt.runtimepath:append(root)
assert(found(compile("sequence_fixture"), "寿司", "susi"))
-- Repeated ambiguous groups have exponentially many spelling combinations but
-- at most input-width reachable positions at each sequence step.
local repeated = {}
for _ = 1, 50 do
	repeated[#repeated + 1] = "a"
end
local dense = compile({ data = { ["甲乙"] = table.concat(repeated, " ") }, groups = { a = { "a", "aa" } } })
assert(found(dense, "甲乙!", string.rep("a", 75) .. "!"))
assert(not found(dense, "甲乙!", string.rep("a", 101) .. "!"))
-- Cross Lua buffer chunks, include low-byte FF, and exercise the final valid ID.
local forms = {}
for i = 1, 65280 do
	forms[i] = { "a" }
end
local ids = { 0, 255, 256, 0x8089, 65279 }
for _ = 1, 5000 do
	ids[#ids + 1] = 255
end
local path = root .. "/limits.bin"
native.write(path, { "甲" }, { { { native.modes.full_code + native.modes.group, ids } } }, forms)
assert(found(native.load(path), "甲", string.rep("a", #ids)))
forms[65281] = { "a" }
assert(not pcall(native.write, path, { "甲" }, { { { 9, { 0 } } } }, forms))
for _, invalid in ipairs({ {}, { -1 }, { 65280 }, { 0.5 }, { math.huge }, { 0 / 0 }, { 0, "bad" } }) do
	assert(not pcall(native.write, path, { "甲" }, { { { 9, invalid } } }, { { "a" } }))
end
vim.fn.delete(root, "rf")
print(("group sequence tests passed (%d comparisons)"):format(comparisons))

-- Compare shared syllable references against fully expanded inline spellings.
vim.opt.runtimepath:prepend(vim.uv.cwd())
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
local native = require("flash-any.native")
local tables = require("flash-any.table")
local parts = require("flash-any.pinyin.parts")
local original = require("reference.pinyin")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local names = vim.tbl_keys(parts.initial)
table.sort(names)
local comparisons = 0
local labels = { "a", "z", ",", "\0" }
for _, fuzzy in ipairs({ false, true }) do
	local expanded = require("reference.table").materialize(original({ fuzzy = fuzzy }).data)
	local production = require("flash-any.sources.pinyin")({ fuzzy = fuzzy })
	local representatives = {}
	for glyph, codes in pairs(tables.materialize(production.data)) do
		for _, code in ipairs(codes) do
			representatives[code] = glyph
		end
	end
	local forms = {}
	for i, name in ipairs(names) do
		forms[i] = production.groups[name]
		assert(representatives[name], name)
		local glyph = representatives[name]
		-- A polyphonic glyph may have extra readings; every shared spelling must exist inline.
		for _, spelling in ipairs(forms[i]) do
			assert(vim.tbl_contains(expanded[glyph], spelling), name .. ": " .. spelling)
		end
	end
	for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
		local keys, shared, inline = {}, {}, {}
		for byte = 0, 127 do
			keys[#keys + 1] = string.char(byte)
		end
		for i in ipairs(names) do
			keys[#keys + 1] = vim.fn.nr2char(0x4E00 + i)
		end
		table.sort(keys)
		local glyphs = {}
		for i, key in ipairs(keys) do
			if #key == 1 then
				shared[i], inline[i] = { { native.modes.literal, key } }, { { native.modes.literal, key } }
			else
				local id = vim.fn.char2nr(key) - 0x4E00
				glyphs[id] = key
				shared[i] = { { native.modes[mode] + native.modes.group, id - 1 } }
				inline[i] = {}
				for _, spelling in ipairs(forms[id]) do
					inline[i][#inline[i] + 1] = { native.modes[mode], spelling }
				end
			end
		end
		native.write(root .. "/shared.bin", keys, shared, forms)
		native.write(root .. "/inline.bin", keys, inline)
		local a, b = native.load(root .. "/shared.bin"):new_state(), native.load(root .. "/inline.bin"):new_state()
		collectgarbage("collect") -- Session owners must retain the shared profile and bytes.
		for id, spellings in ipairs(forms) do
			local glyph = glyphs[id]
			local queries = { [","] = true, ["\255"] = true, ["\0"] = true }
			for _, spelling in ipairs(spellings) do
				for n = 1, #spelling do
					queries[spelling:sub(1, n)] = true
				end
				queries[spelling .. "a"] = true
			end
			for query in pairs(queries) do
				for _, motion in ipairs({ "search", "f", "F", "t", "T" }) do
					local lines = { glyph .. "a" .. glyph .. "," .. glyphs[id % #names + 1] }
					local char = motion ~= "search" and motion or nil
					local found = a:scan(0, 0, id, 1, 1, lines, query, labels, char)
					local expected = b:scan(0, 0, id, 1, 1, lines, query, labels, char)
					assert(vim.deep_equal(found, expected), names[id] .. ": " .. mode .. " " .. vim.inspect(query))
					comparisons = comparisons + 1
				end
			end
		end
	end
end
-- Exercise buffer chunk boundaries, arbitrary ASCII spellings and IDs above 255.
local forms = {}
for i = 1, 300 do
	forms[i] = { string.rep("x", 255), "a;", "\0a", "ab", "a" }
end
native.write(root .. "/large.bin", { "甲" }, { { { native.modes.initial + native.modes.group, 299 } } }, forms)
local large = native.load(root .. "/large.bin")
assert(#large:scan(0, 0, 1, 1, 1, { "甲" }, "a;", nil) == 1)
assert(#large:scan(0, 0, 1, 1, 1, nil, "\0a", nil) == 1)
local function read(path)
	local file = assert(io.open(path, "rb"))
	local bytes = file:read("*a")
	file:close()
	return bytes
end
local bytes = read(root .. "/large.bin")
for _, mode in ipairs({ 8, 12, 13, 31 }) do
	assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { mode, 0 } } }, forms))
	assert(read(root .. "/large.bin") == bytes)
end
for _, id in ipairs({ -1, 300, 0.5, math.huge, 0 / 0 }) do
	assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { 10, id } } }, forms))
end
local function u32(value, offset)
	local a, b, c, d = value:byte(offset + 1, offset + 4)
	return a + b * 256 + c * 65536 + d * 16777216
end
local function change(value, offset, replacement)
	return value:sub(1, offset) .. replacement .. value:sub(offset + #replacement + 1)
end
local profile_at = #bytes - u32(bytes, 32)
local pool_at = 40
	+ u32(bytes, 16) * 16
	+ u32(bytes, 20) * 4
	+ (u32(bytes, 24) > 0 and (0x1100 + u32(bytes, 24) * 256) * 4 or 0)
local code_at = pool_at + u32(bytes, 48)
for _, invalid in ipairs({
	change(bytes, profile_at, "\0\0"), -- Count cannot hide trailing spelling records.
	change(bytes, profile_at + 4, "\0"), -- Empty spelling.
	change(bytes, profile_at + 5, "\255"), -- Non-ASCII spelling.
	change(bytes, code_at + 1, "\255\255"), -- Out-of-range reference.
	change(bytes, code_at, "\136"), -- Literal + syllable is invalid.
	change(bytes, 52, "\2\0\0\0"), -- Truncated u16 reference.
}) do
	local file = assert(io.open(root .. "/bad.bin", "wb"))
	file:write(invalid)
	file:close()
	assert(not pcall(native.load, root .. "/bad.bin"), "corrupt syllable profile must fail")
end
for _, invalid in ipairs({ { { "" } }, { { "中" } }, { { string.rep("a", 256) } }, { false } }) do
	assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { 10, 0 } } }, invalid))
	assert(read(root .. "/large.bin") == bytes)
end
native.write(root .. "/empty.bin", { "甲" }, { { { 10, 0 } } }, { {} })
assert(#native.load(root .. "/empty.bin"):scan(0, 0, 1, 1, 1, { "甲" }, "a", nil) == 0)

-- Custom source overrides are already encoded and must not inherit pinyin references.
local source =
	require("flash-any.source").resolve({ { name = "pinyin", data = { ["中"] = "custom" }, fuzzy = true } })[2]
assert(source.groups == nil and vim.deep_equal(source.data["中"], { "custom" }))
-- Repeated factory names are allowed; aliases stay local to each configured source.
require("flash-any.build").binary({
	sources = {
		{ name = "pinyin", matcher = "full_code", scope = { ["中"] = true } },
		{ name = "pinyin", matcher = "full_code", scope = { ["忠"] = true }, fuzzy = true },
	},
	output = root .. "/combined.bin",
})
local combined = native.load(root .. "/combined.bin")
assert(#combined:scan(0, 0, 1, 1, 1, { "中" }, "zong", nil) == 0)
assert(#combined:scan(0, 0, 2, 1, 1, { "忠" }, "zong", nil) == 1)
assert(#combined:scan(0, 0, 2, 1, 1, nil, "zhong", nil) == 1)
vim.fn.delete(root, "rf")
print(("shared pinyin tests passed (%d differential comparisons)"):format(comparisons))

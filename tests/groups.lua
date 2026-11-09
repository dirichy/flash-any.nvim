vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local groups, data, expanded = {}, {}, {}
for i = 1, 160 do
	local key, name = vim.fn.nr2char(0x4E00 + i), "group" .. i
	local prefix = string.char(96 + i % 26 + 1)
	local variants = { prefix, prefix .. "h", prefix .. "ab", "x" .. prefix, prefix .. "\0;" }
	groups[name], data[key], expanded[key] = variants, name, variants
end
local comparisons = 0
for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
	build.binary({ sources = { { data = data, groups = groups, matcher = mode } }, output = root .. "/groups.bin" })
	build.binary({ sources = { { data = expanded, matcher = mode } }, output = root .. "/inline.bin" })
	local a, b = native.load(root .. "/groups.bin"):new_state(), native.load(root .. "/inline.bin"):new_state()
	collectgarbage("collect")
	for i = 1, 160 do
		local key, name = vim.fn.nr2char(0x4E00 + i), "group" .. i
		local queries = { ["\255"] = true, [","] = true }
		for _, spelling in ipairs(groups[name]) do
			for n = 1, #spelling do
				queries[spelling:sub(1, n)] = true
			end
			queries[spelling .. "a"] = true
		end
		for query in pairs(queries) do
			for _, motion in ipairs({ "search", "f", "F", "t", "T" }) do
				local char = motion ~= "search" and motion or nil
				local lines = { key .. "a" .. key .. ";" .. vim.fn.nr2char(0x4E00 + i % 160 + 1) }
				local labels = { "a", "z", ";" }
				local x = a:scan(0, 0, i, 1, 1, lines, query, labels, char)
				local y = b:scan(0, 0, i, 1, 1, lines, query, labels, char)
				assert(vim.deep_equal(x, y), mode .. ": " .. name .. " " .. vim.inspect(query))
				comparisons = comparisons + 1
			end
		end
	end
end
-- Padding transforms real spellings, independently of the group name's length.
local padded_input = { ["甲"] = "long_alias" }
local padded_groups = { long_alias = { "a", "abcd" } }
build.binary({
	sources = { { data = padded_input, groups = padded_groups, append_space_below = 4 } },
	output = root .. "/padded.bin",
})
local padded = native.load(root .. "/padded.bin")
assert(#padded:scan(0, 0, 1, 1, 1, { "甲" }, "a ", nil) == 1)
assert(padded:scan(0, 0, 1, 1, 1, nil, "a", nil)[1].next[" "])
assert(#padded:scan(0, 0, 1, 1, 1, nil, "abcd", nil) == 1)
assert(padded_input["甲"] == "long_alias" and padded_groups.long_alias[1] == "a")
local serial = 0
local function compile(sources)
	serial = serial + 1
	local path = root .. "/public" .. serial .. ".bin"
	build.binary({ sources = sources, output = path })
	return native.load(path), path
end
local separated = compile({
	{ data = { ["甲"] = "a", ["乙"] = "a " }, groups = { a = { "x" }, ["a "] = { "y" } }, append_space_below = 2 },
})
assert(#separated:scan(0, 0, 1, 1, 1, { "甲" }, "x ", nil) == 1)
assert(#separated:scan(0, 0, 1, 1, 1, { "乙" }, "y ", nil) == 1)
local book, path = compile({
	{ data = { ["甲"] = "same" }, groups = { same = { "ka", "ga" } } },
	{ data = { ["乙"] = "same", ["甲"] = "same" }, groups = { same = { "xi" } } },
	{ data = { ["丙"] = "other" }, groups = { other = { "ga", "ka", "ka" } } },
})
local function found(engine, text, query)
	return #engine:new_state():scan(0, 0, 1, 1, 1, { text }, query, nil) > 0
end
assert(found(book, "甲", "ka") and found(book, "甲", "ga") and found(book, "甲", "xi"))
assert(found(book, "乙", "xi") and not found(book, "乙", "ka"))
assert(found(book, "丙", "ka") and found(book, "丙", "ga"))
local function read(file)
	local handle = assert(io.open(file, "rb"))
	local bytes = handle:read("*a")
	handle:close()
	return bytes
end
local function u32(bytes, offset)
	local a, b, c, d = bytes:byte(offset + 1, offset + 4)
	return a + b * 256 + c * 65536 + d * 16777216
end
local bytes = read(path)
local profile = #bytes - u32(bytes, 32)
assert(bytes:byte(profile + 1) == 2 and bytes:byte(profile + 2) == 0, "groups must be interned by normalized contents")
for _, invalid in ipairs({ false, { a = "abc" }, { a = { "中" } }, { a = { "" } }, { a = { string.rep("a", 256) } } }) do
	assert(not pcall(compile, { { data = { ["甲"] = "a" }, groups = invalid } }))
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
bytes = read(root .. "/large.bin")
for _, mode in ipairs({ 8, 12, 14, 31 }) do
	assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { mode, 0 } } }, forms))
	assert(read(root .. "/large.bin") == bytes)
end
for _, id in ipairs({ -1, 300, 0.5, math.huge, 0 / 0 }) do
	assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { 10, id } } }, forms))
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

vim.fn.delete(root, "rf")
print(("shared group tests passed (%d comparisons)"):format(comparisons))

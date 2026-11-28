-- Corrupt files must fail safely; failed writes and GC must preserve existing snapshots.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial = 0
local function engine(sources)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = sources, output = path })
	return native.load(path), path
end
-- Build is deterministic and failed builds leave the previous package intact.
local first_specs = { { data = { ["中"] = "ab", ["á"] = "accent", ["b́"] = "bee" } } }
local _, path = engine(first_specs)
local function read(file)
	local handle = assert(io.open(file, "rb"))
	local bytes = handle:read("*a")
	handle:close()
	return bytes
end
local first = read(path)
-- Native IO must handle UTF-8 paths and replace files while old snapshots remain live.
do
	local directory = root .. "/中文 path 😀"
	assert(vim.fn.mkdir(directory, "p") == 1)
	local file = directory .. "/码表.bin"
	native.write(file, { "中" }, { { { native.modes.full_code, "old" } } })
	local old = native.load(file)
	native.write(file, { "中" }, { { { native.modes.full_code, "new" } } })
	assert(#old:new_state():scan(0, 1, 0, 1, 1, { "中" }, "old", nil) == 1)
	assert(#native.load(file):new_state():scan(0, 1, 0, 1, 1, { "中" }, "new", nil) == 1)
	assert(not pcall(native.write, file .. "\0", {}, {}))
	assert(not pcall(native.load, file .. "\0"))
	assert(vim.uv.fs_unlink(file))
	assert(vim.uv.fs_rmdir(directory))
end
local function u32(bytes, offset)
	local a, b, c, d = bytes:byte(offset + 1, offset + 4)
	return a + b * 256 + c * 65536 + d * 16777216
end
local function replace(bytes, offset, value)
	local packed = string.char(
		value % 256,
		math.floor(value / 256) % 256,
		math.floor(value / 65536) % 256,
		math.floor(value / 16777216)
	)
	return bytes:sub(1, offset) .. packed .. bytes:sub(offset + 5)
end
build.binary({ sources = first_specs, output = path })
assert(read(path) == first)
-- C serialization handles buffer-sized encodings and owns failed-write cleanup.
local long_code = string.rep("a", 20000)
local _, long_path = engine({ { data = { ["中"] = long_code } } })
local long_bytes = read(long_path)
assert(long_bytes:find(long_code, 1, true))
build.binary({ sources = { { data = { ["中"] = long_code } } }, output = long_path })
assert(read(long_path) == long_bytes)
local directory = vim.fn.tempname()
assert(vim.uv.fs_mkdir(directory, 448))
assert(not pcall(build.binary, { sources = {}, output = directory }))
assert(vim.fn.glob(directory .. ".*") == "")
assert(vim.uv.fs_rmdir(directory))
assert(not pcall(build.binary, { sources = {}, output = directory .. "/missing.bin" }))
assert(not pcall(require("flash-any.native").write, path, { "中" }, { { { 99, "a" } } }))
assert(read(path) == first)
for _, specs in ipairs({
	{ {
		matcher = function()
			return false
		end,
	} },

	{ {
		loader = function()
			return { "a" }
		end,
	} },
}) do
	assert(not pcall(build.binary, { sources = specs, output = path }))
	assert(read(path) == first)
end
local function scalar_slot(bytes, cp)
	local page = u32(bytes, 40 + math.floor(cp / 256) * 4)
	assert(page > 0)
	return 40 + 0x1100 * 4 + (page - 1) * 256 * 4 + cp % 256 * 4
end
local pages_start = 40
local trie_start = 40 + (u32(first, 24) > 0 and (0x1100 + u32(first, 24) * 256) * 4 or 0)
local pool_start = trie_start + u32(first, 20) * 8
local function node(bytes, start, state)
	local low, high = u32(bytes, start + state * 8), u32(bytes, start + state * 8 + 4)
	local base = low % 0x1000000
	if base >= 0x800000 then
		base = base - 0x1000000
	end
	return base,
		math.floor(high / 32) % 0x800000,
		math.floor(low / 0x1000000) + high % 32 * 256,
		math.floor(high / 0x10000000)
end
local function put_node(bytes, start, state, base, parent, quotient, kind)
	local low = base % 0x1000000 + quotient % 256 * 0x1000000
	local high = math.floor(quotient / 256) + parent * 32 + kind * 0x10000000
	return replace(replace(bytes, start + state * 8, low), start + state * 8 + 4, high)
end
local function parent_of(bytes, start, state, parent)
	local base, _, quotient, kind = node(bytes, start, state)
	return put_node(bytes, start, state, base, parent, quotient, kind)
end
local function step(bytes, start, state, cp)
	local base, _, _, kind = node(bytes, start, state)
	local modulus = 2 ^ (kind + 8)
	local next_state = base + cp % modulus
	assert(next_state >= 0 and next_state < u32(bytes, 20))
	local _, parent, quotient, child_kind = node(bytes, start, next_state)
	assert(parent == state + 1)
	assert(cp == 0 and child_kind == 15 or cp > 0 and child_kind ~= 15 and quotient == math.floor(cp / modulus))
	return next_state
end
-- Local moduli differ between siblings' subtrees; unknown congruent labels fail.
local modular_map = {
	["aက"] = "left",
	["aᄀ"] = "right",
	["bက"] = "down",
	["bခ"] = "up",
	ab = "stem",
	["abက"] = "deep",
}
local modular = engine({ { data = modular_map } })
for i, case in ipairs({ { "aሀ", "left" }, { "bᄀ", "down" } }) do
	assert(#modular:new_state():scan(0, 1, i, 1, 1, { case[1] }, case[2], {}) == 0)
end
local parents = engine({ { data = { aa = "left", ba = "down", bc = "right" } } })
assert(
	#parents:new_state():scan(0, 1, 1, 1, 1, { "c" }, "down", {}) == 0,
	"a matching quotient at another parent's slot must fail"
)
-- Terminal payloads retain a full u32 offset, beyond the normal 24-bit base.
do
	local wide_path = root .. "/wide-offset.bin"
	native.write(wide_path, { "中", "甲乙" }, { { { 1, string.rep("a", 0x1000000) } }, { { 1, "tail" } } })
	local wide = native.load(wide_path)
	assert(#wide:new_state():scan(0, 1, 1, 1, 1, { "甲乙" }, "tail", {}) == 1)
end
local accent = step(first, trie_start, step(first, trie_start, 0, 97), 0x301)
local terminal = step(first, trie_start, accent, 0)
local code_slot = scalar_slot(first, vim.fn.char2nr("中"))
local first_codes = pool_start + u32(first, code_slot) - 1
local terminator = pool_start + u32(first, 28) - 1
for _, bytes in ipairs({
	"",
	first:sub(1, 7),
	first:sub(1, -2),
	first .. "x",
	"B" .. first:sub(2),
	first:sub(1, 7) .. "\4" .. first:sub(9),
	replace(first, 8, 18),
	replace(first, 16, 0xFFFFFFFF),
	replace(first, 20, 3),
	replace(first, 24, 0xFFFFFFFF),
	replace(first, 32, 1),
	put_node(first, trie_start, 0, 0, 1, 0, 0), -- Root cannot have a parent.
	put_node(first, trie_start, 0, -0x800000, 0, 0, 0), -- Out-of-range root remainder.
	replace(first, trie_start + terminal * 8, 0), -- Missing terminal code list.
	replace(first, trie_start + terminal * 8, u32(first, 28)), -- Empty final pool byte.
	parent_of(first, trie_start, terminal, terminal + 1), -- Self parent.
	parent_of(first, trie_start, terminal, 0x7FFFFF), -- Invalid parent.
	put_node(first, trie_start, accent, 0, 1, 0, 14), -- Reserved exponent code.
	replace(first, code_slot, 0xFFFFFFFF),
	replace(first, 36, 0xFFFFFFFF),
	first:sub(1, terminator) .. "a" .. first:sub(terminator + 2), -- Missing final list terminator.
	replace(first, pages_start, 0xFFFFFFFF),
	replace(first, pages_start + 0x1100 * 4, 0xFFFFFFFF),
	first:sub(1, first_codes) .. "\132" .. first:sub(first_codes + 2),
}) do
	local file = root .. "/bad.bin"
	local handle = assert(io.open(file, "wb"))
	handle:write(bytes)
	handle:close()
	assert(not pcall(native.load, file), "corrupt package must fail")
end
-- A disconnected parent cycle must fail even when labels and terminal counts fit.
local cycle = string.rep("\0", 6 * 8)
cycle = put_node(cycle, 0, 3, u32(first, code_slot), 6, 0, 15)
cycle = put_node(cycle, 0, 4, 4, 6, 0, 0)
cycle = put_node(cycle, 0, 5, 3, 5, 0, 0)
local cyclic = first:sub(1, trie_start) .. cycle .. first:sub(pool_start + 1)
cyclic = replace(replace(replace(cyclic, 12, #cyclic), 16, 1), 20, 6)
local cyclic_file = root .. "/cycle.bin"
local handle = assert(io.open(cyclic_file, "wb"))
handle:write(cyclic)
handle:close()
local valid, reason = pcall(native.load, cyclic_file)
assert(not valid and tostring(reason):find("cyclic binary Trie", 1, true), tostring(reason))
-- NUL encodings and optional suffixes are rejected before replacing an existing package.
for _, code in ipairs({ "\0", "\0a", "a\0", "a\0b" }) do
	assert(not pcall(build.binary, { sources = { { data = { ["中"] = code } } }, output = path }))
	assert(not pcall(native.write, path, { "中" }, { { { native.modes.full_code, code } } }))
	assert(not pcall(native.write, path, { "中" }, { { { native.modes.suffix, "a", code } } }))
	assert(not pcall(build.selectors, {}, {}, { code }))
	assert(read(path) == first)
end
-- A state pins the immutable snapshot even after its book/file disappears.
local session
do
	local book, snapshot_path = engine({ { data = { ["中"] = "ab" } } })
	session = book:new_state()
	assert(vim.uv.fs_unlink(snapshot_path))
end
collectgarbage("collect")
local found = session:scan(0, 1, 0, 1, 1, { "中" }, "ab", nil)
assert(#found == 1 and found[1].pos[2] == 0)

do
	-- Exercise buffer chunk boundaries, arbitrary ASCII spellings and IDs above 255.
	local forms = {}
	for i = 1, 300 do
		forms[i] = { string.rep("x", 255), "a;", "\ta", "ab", "a" }
	end
	native.write(root .. "/large.bin", { "甲" }, { { { native.modes.initial + native.modes.group, { 299 } } } }, forms)
	local large = native.load(root .. "/large.bin")
	assert(#large:scan(0, 0, 1, 1, 1, { "甲" }, "a;", nil) == 1)
	assert(#large:scan(0, 0, 1, 1, 1, nil, "\ta", nil) == 1)
	-- A zero byte inside a fixed-width ID must not terminate the list.
	native.write(root .. "/zero-id.bin", { "甲", "乙" }, {
		{ { native.modes.full_code + native.modes.group, { 0 } }, { native.modes.full_code, "tail" } },
		{ { native.modes.full_code + native.modes.group, { 256 } }, { native.modes.full_code, "tail" } },
	}, forms)
	local zero_id = native.load(root .. "/zero-id.bin")
	assert(#zero_id:scan(0, 0, 1, 1, 1, { "甲乙" }, "a;tail", nil) == 1)
	assert(#zero_id:scan(0, 0, 1, 1, 1, nil, "taila;", nil) == 1)
	local bytes = read(root .. "/large.bin")
	for _, mode in ipairs({ 8, 12, 14, 31 }) do
		assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { mode, 0 } } }, forms))
		assert(read(root .. "/large.bin") == bytes)
	end
	for _, id in ipairs({ -1, 300, 0.5, math.huge, 0 / 0 }) do
		assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { 10, { id } } } }, forms))
	end
	local function change(value, offset, replacement)
		return value:sub(1, offset) .. replacement .. value:sub(offset + #replacement + 1)
	end
	local profile_at = #bytes - u32(bytes, 32)
	local pages_at = 40 + 0x1100 * 4
	local pool_at = #bytes - u32(bytes, 32) - u32(bytes, 28)
	local cp = vim.fn.char2nr("甲")
	local page = u32(bytes, 40 + math.floor(cp / 256) * 4)
	local group_slot = pages_at + (page - 1) * 256 * 4 + cp % 256 * 4
	local code_at = pool_at + u32(bytes, group_slot) - 1
	for _, invalid in ipairs({
		change(bytes, profile_at, "\0\0"), -- Count cannot hide trailing spelling records.
		change(bytes, profile_at + 4, "\0"), -- Empty spelling.
		change(bytes, profile_at + 5, "\255"), -- Non-ASCII spelling.
		change(bytes, code_at + 1, "\255\255"), -- Out-of-range reference.
		change(bytes, code_at, "\136"), -- Literal + syllable is invalid.
		change(bytes, group_slot, string.char(u32(bytes, 28), 0, 0, 0)), -- List starts at final NUL.
		change(bytes, code_at + 3, "x"), -- Missing list terminator after a binary ID.
		change(bytes, profile_at + 5, "\0"), -- NUL spelling.
	}) do
		local file = assert(io.open(root .. "/bad.bin", "wb"))
		file:write(invalid)
		file:close()
		assert(not pcall(native.load, root .. "/bad.bin"), "corrupt syllable profile must fail")
	end
	for _, invalid in ipairs({ { { "" } }, { { "中" } }, { { "a\0" } }, { { string.rep("a", 256) } }, { false } }) do
		assert(not pcall(native.write, root .. "/large.bin", { "甲" }, { { { 10, { 0 } } } }, invalid))
		assert(read(root .. "/large.bin") == bytes)
	end
	native.write(root .. "/empty.bin", { "甲" }, { { { 10, { 0 } } } }, { {} })
	assert(#native.load(root .. "/empty.bin"):scan(0, 0, 1, 1, 1, { "甲" }, "a", nil) == 0)
end

do
	-- Cross Lua buffer chunks, include low-byte FF, and exercise the final valid ID.
	local forms = {}
	for i = 1, 65280 do
		forms[i] = { "a" }
	end
	local ids = { 0, 255, 256, 0x8089, 65279 }
	for _ = 1, 5000 do
		ids[#ids + 1] = 255
	end
	local limits_path = root .. "/limits.bin"
	native.write(limits_path, { "甲" }, { { { native.modes.full_code + native.modes.group, ids } } }, forms)
	assert(#native.load(limits_path):scan(0, 0, 1, 1, 1, { "甲" }, string.rep("a", #ids), nil) == 1)
	forms[65281] = { "a" }
	assert(not pcall(native.write, limits_path, { "甲" }, { { { 9, { 0 } } } }, forms))
	for _, invalid in ipairs({ {}, { -1 }, { 65280 }, { 0.5 }, { math.huge }, { 0 / 0 }, { 0, "bad" } }) do
		assert(not pcall(native.write, limits_path, { "甲" }, { { { 9, invalid } } }, { { "a" } }))
	end
end
vim.fn.delete(root, "rf")
print("binary corruption, write failure, group limits and snapshot ownership passed")

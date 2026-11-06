#!/usr/bin/env -S nvim -l
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path

vim.opt.runtimepath:prepend(vim.uv.cwd())
local tsv = require("flash-any.tsv")
local function fixture(content)
	local path = vim.fn.tempname()
	local file = assert(io.open(path, "wb"))
	file:write(content)
	file:close()
	return path
end
local entries = { ["a"] = { "ab", "cd" }, ["中"] = { "zhong" }, ["😀"] = { "emoji" }, ["𠀀"] = { "rare" } }
local keys = vim.tbl_keys(entries)
table.sort(keys)
for _, newline in ipairs({ "\n", "\r\n" }) do
	local rows = {}
	for _, key in ipairs(keys) do
		rows[#rows + 1] = key .. "\t" .. table.concat(entries[key], ",")
	end
	local lookup = tsv.loader(fixture(table.concat(rows, newline) .. newline), {
		decode = function(value)
			return vim.split(value, ",", { plain = true })
		end,
	})
	for _, key in ipairs(keys) do
		assert(vim.deep_equal(lookup(key), entries[key]), key)
	end
	assert(lookup("missing") == nil)
end
assert(tsv.loader(fixture(""))("a") == nil)
assert(vim.deep_equal(tsv.loader(fixture("中||ab"), { separator = "||" })("中"), { "ab" }))
local rows = {}
for cp = 0x4E00, 0x4E00 + 511 do
	rows[#rows + 1] = vim.fn.nr2char(cp) .. "\t" .. tostring(cp)
end
local lookup = tsv.loader(fixture(table.concat(rows, "\n")))
for cp = 0x4E00, 0x4E00 + 511 do
	assert(vim.deep_equal(lookup(vim.fn.nr2char(cp)), { tostring(cp) }))
end
-- Alternate distant branches after warming the cached binary-search nodes.
for _ = 1, 2 do
	for i = 0, 511 do
		local cp = 0x4E00 + (i * 137) % 512
		local char = vim.fn.nr2char(cp)
		assert(vim.deep_equal(lookup(char), { tostring(cp) }))
		assert(lookup(char .. "!") == nil)
	end
end
-- The upper byte bound can lie inside a row; scanning starts at aligned low.
for _, length in ipairs({ 60, 61, 62, 63, 64, 65, 4096 }) do
	for _, newline in ipairs({ "\n", "\r\n" }) do
		local value = string.rep("x", length)
		local scan = tsv.loader(fixture("a\t" .. value .. newline .. "z\tlast"))
		for _ = 1, 2 do
			assert(vim.deep_equal(scan("a"), { value }))
			assert(scan("0") == nil)
			assert(scan("b") == nil)
			assert(vim.deep_equal(scan("z"), { "last" }))
			assert(scan("zz") == nil)
		end
	end
end
print("all TSV lookup tests passed")

-- Prefixes without their own codes still locate their first descendant. Exact
-- rows may repeat, and a saved offset must include all duplicate codes.
local prefix_entries = {
	a = { "a" },
	ab = { "ab" },
	abc = { "abc" },
	abd = { "abd" },
	["中国"] = { "country", "word" },
	["中国人"] = { "people" },
	["中华"] = { "china" },
	["きゃ"] = { "kya" },
	["👩‍💻"] = { "dev" },
}
local prefix_keys = vim.tbl_keys(prefix_entries)
table.sort(prefix_keys)
for _, newline in ipairs({ "\n", "\r\n" }) do
	local lines = {}
	for _, key in ipairs(prefix_keys) do
		for _, code in ipairs(prefix_entries[key]) do
			lines[#lines + 1] = key .. "\t" .. code
		end
	end
	local search = tsv.loader(fixture(table.concat(lines, newline)))
	for _, key in ipairs(prefix_keys) do
		local previous
		for after in require("reference.utf8").iter_offset(key) do
			local prefix = key:sub(1, after)
			local codes, offset = search(prefix, previous)
			local expected_longer = false
			for _, candidate in ipairs(prefix_keys) do
				if #candidate > #prefix and candidate:sub(1, #prefix) == prefix then
					expected_longer = true
				end
			end
			assert(vim.deep_equal(codes, prefix_entries[prefix]), prefix)
			assert((offset ~= false) == expected_longer, prefix .. " continuation")
			if offset ~= false then
				assert(offset >= (previous or 0), "offsets only move forward")
				previous = offset
			end
		end
	end
end
print("ok - TSV prefix queries share forward offsets across Unicode prefixes and duplicate rows")

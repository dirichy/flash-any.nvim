#!/usr/bin/env -S nvim -l

vim.opt.runtimepath:prepend(vim.uv.cwd())
local scopes = require("flash-any.scope")
local function accepts(spec, char)
	local scope = scopes.describe(spec)
	return scopes.contains(scope, char)
end

for byte = 0, 127 do
	assert(accepts("ascii", string.char(byte)))
end
for _, char in ipairs({ "", "中", "α", "🙂", string.char(0x80) }) do
	assert(not accepts("ascii", char))
end
for _, char in ipairs({ "中", "㐀", "，", "。", "𠀀" }) do
	assert(accepts("chinese", char))
end
for _, char in ipairs({ "a", "α", "🙂", "ぁ", "　" }) do
	assert(not accepts("chinese", char))
end
assert(accepts("unicode", vim.fn.nr2char(0xA0)))
assert(not accepts("unicode", "a") and not accepts("unicode", string.char(0x9F)))
for _, range in ipairs({ { 0xE000, 0xF8FF }, { 0xF0000, 0xFFFFD }, { 0x100000, 0x10FFFD } }) do
	assert(accepts("private_use", vim.fn.nr2char(range[1])))
	assert(accepts("private_use", vim.fn.nr2char(range[2])))
	assert(not accepts("private_use", vim.fn.nr2char(range[1] - 1)))
	assert(not accepts("private_use", vim.fn.nr2char(range[2] + 1)))
end
assert(scopes.describe("all") == nil and scopes.describe(nil) == nil)
assert(vim.deep_equal(scopes.describe("chinese"), scopes.describe("chinese")))
print("ok - predefined scope strategies preserve character coverage")

local numeric = { { 1, 10000 }, a = false, ["🙂"] = true }
assert(not accepts(numeric, "a") and accepts(numeric, "b"))
assert(accepts(numeric, "🙂") and not accepts(numeric, "字"))
local kana = { { "ぁ", "ヿ" }, ["あ"] = false, ["漢"] = true }
assert(accepts(kana, "ぁ") and accepts(kana, "ヿ") and accepts(kana, "カ"))
assert(not accepts(kana, "あ") and not accepts(kana, "🙂") and accepts(kana, "漢"))
assert(accepts({ { 0x3040, "ヿ" } }, "あ"))
assert(accepts({ ["あ"] = true }, "あ") and not accepts({ ["あ"] = true }, "い"))
assert(not accepts({}, "あ"))
local compiled = assert(scopes.describe(kana))
kana[1][1], kana["漢"] = "ん", false
assert(scopes.contains(compiled, "ぁ") and scopes.contains(compiled, "漢"))
print("ok - mixed scopes check character hashes first and copy numeric/string ranges")

local extra = { ["あ"] = { "a", "other" }, ["漢"] = "kan" }
assert(accepts(extra, "あ") and accepts(extra, "漢") and not accepts(extra, "い"))
local mixed_codes = { { "ぁ", "ヿ" }, ["あ"] = false, ["漢"] = { "kan" } }
assert(not accepts(mixed_codes, "あ") and accepts(mixed_codes, "い") and accepts(mixed_codes, "漢"))
assert(accepts({ a = 0, b = "", c = {} }, "a"))
assert(accepts({ a = 0, b = "", c = {} }, "b"))
assert(accepts({ a = 0, b = "", c = {} }, "c"))
local extra_scope = assert(scopes.describe(extra))
extra["あ"] = nil
assert(scopes.contains(extra_scope, "あ"), "compiled scopes retain their snapshot")
print("ok - character hashes accept code maps directly and preserve false-over-range priority")

-- Hashes and inclusive ranges compare complete graphemes, including endpoints.
assert(accepts({ ["á"] = true }, "á") and not accepts({ a = true }, "á"))
assert(not accepts({ { "a", "z" }, ["á"] = false }, "á"))
assert(accepts({ { "a", "z" }, a = false }, "á"))
assert(accepts({ { "á", "á" } }, "á") and not accepts({ { "á", "á" } }, "a"))
assert(not accepts({ { "a", "z" } }, "ź")) -- Strict UTF-8 string upper bound.
local clusters = { { "😀", "🧑‍💻" }, ["👩‍💻"] = true, ["👩🏽‍💻"] = false }
assert(accepts(clusters, "🧑‍💻") and accepts(clusters, "👩‍💻") and accepts(clusters, "😃"))
assert(not accepts(clusters, "👩🏽‍💻") and not accepts({ ["👩‍💻"] = true }, "👩"))
print("ok - scopes compare full grapheme hashes and inclusive UTF-8 string bounds")

for _, invalid in ipairs({
	false,
	42,
	"missing",
	{ { 0x110000, 0x110001 } },
	{ { -1, 1 } },
	{ { 0.5, 1 } },
	{ { "あ" } },
	{ { "あ", "a" } },
	{ { "ab", "z" } },
	{ { "", "z" } },
	{ ["ab"] = true },
	{ ["👩‍💻x"] = true },
	{ { "a", "👩‍💻x" } },
	{ [0] = { 1, 2 } },
}) do
	assert(not pcall(scopes.describe, invalid), vim.inspect(invalid))
end
print("ok - invalid declarations fail during build")

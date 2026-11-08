package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path
-- nvim --clean -l tests/cursor.lua [host-root]
vim.opt.runtimepath:prepend(vim.uv.cwd())
local grapheme = require("reference.grapheme")
local original_each, runs, decoded = grapheme.each, 0, 0
rawset(grapheme, "each", function(value, emit, emit_codepoint)
	runs = runs + 1
	original_each(value, function(first, after, count, last)
		decoded = decoded + count
		emit(first, after, count, last)
	end, emit_codepoint)
end)
local Cursor = require("reference.cursor")
rawset(grapheme, "each", original_each)
local utf8 = require("reference.utf8")
local function equal(a, b, context)
	assert(vim.deep_equal(a, b), context .. "\nactual=" .. vim.inspect(a) .. "\nexpected=" .. vim.inspect(b))
end

local view = Cursor.new("👩‍💻🇨🇳áx")
local before_runs, before_decoded = runs, decoded
equal({ view:get(1) }, { "👩‍💻", #"👩‍💻", #"👩‍" }, "whole cluster with final codepoint endpoint")
assert(view:get_codepoint() == 0x1F469 and view:get_codepoint(1) == 0x200D and view:get_codepoint(2) == 0x1F4BB)
equal({ view:get(2) }, { "👩‍💻🇨🇳", #"👩‍💻🇨🇳", #"👩‍💻🇨" }, "two clusters")
assert(view:shift(2) and view.offset == #"👩‍💻🇨🇳")
equal({ view:get(1) }, { "á", #"👩‍💻🇨🇳á", #"👩‍💻🇨🇳a" }, "combining accent")
assert(view:get_codepoint() == 0x61 and view:get_codepoint(1) == 0x301 and view:get_codepoint(-1) == 0x1F1F3)
assert(not pcall(view.set_offset, view, #"👩‍"), "cluster-internal boundary must be rejected")
view:set_offset(0)
assert(view:get(99) == view.value and not view:shift(99) and view.offset == 0)
assert(select("#", view:get()) == 1)
assert(view:shift(4) and view.offset == #view.value and not view:shift())
equal({ view:get(1) }, { "" }, "read at end")
assert(view:get_codepoint() == nil and view:get_codepoint(-1) == 0x78)
equal({ runs, decoded }, { before_runs, before_decoded }, "all revisits reuse a single segmentation")
for _, invalid in ipairs({ 0, -1, 0.5, false, "1", math.huge }) do
	assert(not pcall(view.get, view, invalid))
	assert(not pcall(view.shift, view, invalid))
end
for _, invalid in ipairs({ -1, 0.5, false, "1", #view.value + 1, math.huge }) do
	assert(not pcall(view.set_offset, view, invalid))
end
for _, invalid in ipairs({ 0.5, false, "1", math.huge, -math.huge }) do
	assert(not pcall(view.get_codepoint, view, invalid))
end

local cases = 0
local function check(value, expected, codepoints)
	equal(grapheme.split(value), expected, "split clusters")
	assert(grapheme.len(value) == #expected)
	local text, positions = Cursor.new(value), { 0 }
	for i, cluster in ipairs(expected) do
		positions[i + 1] = positions[i] + #cluster
	end
	local codepoint_index = 1
	for index = 0, #expected do
		text:set_offset(positions[index + 1])
		if codepoints then
			assert(text:get_codepoint() == codepoints[codepoint_index], "current codepoint")
			for pos = -#codepoints - 1, #codepoints + 1 do
				assert(text:get_codepoint(pos) == codepoints[codepoint_index + pos], "relative codepoint: " .. pos)
			end
			if index < #expected then
				codepoint_index = codepoint_index + utf8.len(expected[index + 1])
			end
		end
		assert(text:get() == value:sub(text.offset + 1))
		for count = 1, #expected + 1 do
			local actual = { text:get(count) }
			local want = table.concat(expected, "", index + 1, math.min(index + count, #expected))
			if index + count > #expected then
				equal(actual, { want }, "short cluster read")
			else
				local last = expected[index + count]
				local last_byte = positions[index + count] + utf8.byteidx(last, utf8.len(last) - 1)
				equal(actual, { want, positions[index + count + 1], last_byte }, "bounded cluster read")
			end
		end
	end
	for offset = 0, #value do
		local allowed = vim.tbl_contains(positions, offset)
		assert(pcall(text.set_offset, text, offset) == allowed, "offset validation: " .. offset)
	end
	cases = cases + 1
end
for line in io.lines("tests/data/GraphemeBreakTest-17.0.0.txt") do
	local body = line:match("^([^#]+)")
	if body and body:find("÷", 1, true) then
		local clusters, current, marker, codepoints = {}, "", nil, {}
		for token in body:gmatch("%S+") do
			if token == "÷" or token == "×" then
				marker = token
			else
				local cp = assert(tonumber(token, 16))
				codepoints[#codepoints + 1] = cp
				if marker == "÷" and current ~= "" then
					clusters[#clusters + 1], current = current, ""
				end
				current = current .. (cp == 0 and "\0" or vim.fn.nr2char(cp))
			end
		end
		if current ~= "" then
			clusters[#clusters + 1] = current
		end
		check(table.concat(clusters), clusters, codepoints)
	end
end
check("", {}, {})
check("\255x\240\159", { "\255", "x", "\240", "\159" })
local malformed = Cursor.new("\255x\240\159")
for pos, codepoint in ipairs({ -1, 0x78, -1, -1 }) do
	assert(malformed:get_codepoint(pos - 1) == codepoint)
end
local scalars = Cursor.new("\0" .. vim.fn.nr2char(0x10FFFF))
assert(scalars:get_codepoint() == 0 and scalars:get_codepoint(1) == 0x10FFFF)

check("👩🏽‍💻🇦🇧🇨1️⃣á", { "👩🏽‍💻", "🇦🇧", "🇨", "1️⃣", "á" })
check("a" .. ("́"):rep(100), { "a" .. ("́"):rep(100) })
for _, value in ipairs({ "\192\128", "\237\160\128", "\244\144\128\128", "\248\128\128\128\128", "\228\184" }) do
	local bytes = {}
	for i = 1, #value do
		bytes[i] = value:sub(i, i)
	end
	check(value, bytes)
end
print("all cursor tests passed (" .. cases .. " Unicode and edge cases)")

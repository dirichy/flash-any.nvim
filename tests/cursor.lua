-- nvim --clean -l tests/cursor.lua [host-root]
vim.opt.runtimepath:prepend(vim.uv.cwd())
local grapheme = require("flash-any.grapheme")
local original_each, runs, decoded = grapheme.each, 0, 0
rawset(grapheme, "each", function(value, emit)
	runs = runs + 1
	original_each(value, function(first, after, count, last)
		decoded = decoded + count
		emit(first, after, count, last)
	end)
end)
local Cursor = require("flash-any.cursor")
rawset(grapheme, "each", original_each)
local utf8 = require("flash-any.utf8")
local function equal(a, b, context)
	assert(vim.deep_equal(a, b), context .. "\nactual=" .. vim.inspect(a) .. "\nexpected=" .. vim.inspect(b))
end

local view = Cursor.new("👩‍💻🇨🇳áx")
local before_runs, before_decoded = runs, decoded
equal({ view:get(1) }, { "👩‍💻", #"👩‍💻", #"👩‍" }, "whole cluster with final codepoint endpoint")
equal({ view:get(2) }, { "👩‍💻🇨🇳", #"👩‍💻🇨🇳", #"👩‍💻🇨" }, "two clusters")
assert(view:shift(2) and view.offset == #"👩‍💻🇨🇳")
equal({ view:get(1) }, { "á", #"👩‍💻🇨🇳á", #"👩‍💻🇨🇳a" }, "combining accent")
assert(not pcall(view.set_offset, view, #"👩‍"), "cluster-internal boundary must be rejected")
view:set_offset(0)
assert(view:get(99) == view.value and not view:shift(99) and view.offset == 0)
assert(select("#", view:get()) == 1)
assert(view:shift(4) and view.offset == #view.value and not view:shift())
equal({ view:get(1) }, { "" }, "read at end")
equal({ runs, decoded }, { before_runs, before_decoded }, "all revisits reuse a single segmentation")
for _, invalid in ipairs({ 0, -1, 0.5, false, "1", math.huge }) do
	assert(not pcall(view.get, view, invalid))
	assert(not pcall(view.shift, view, invalid))
end
for _, invalid in ipairs({ -1, 0.5, false, "1", #view.value + 1, math.huge }) do
	assert(not pcall(view.set_offset, view, invalid))
end

local cases = 0
local function check(value, expected)
	equal(grapheme.split(value), expected, "split clusters")
	assert(grapheme.len(value) == #expected)
	local text, positions = Cursor.new(value), { 0 }
	for i, cluster in ipairs(expected) do
		positions[i + 1] = positions[i] + #cluster
	end
	for index = 0, #expected do
		text:set_offset(positions[index + 1])
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
		local clusters, current, marker = {}, "", nil
		for token in body:gmatch("%S+") do
			if token == "÷" or token == "×" then
				marker = token
			else
				local cp = assert(tonumber(token, 16))
				if marker == "÷" and current ~= "" then
					clusters[#clusters + 1], current = current, ""
				end
				current = current .. (cp == 0 and "\0" or vim.fn.nr2char(cp))
			end
		end
		if current ~= "" then
			clusters[#clusters + 1] = current
		end
		check(table.concat(clusters), clusters)
	end
end
check("", {})
check("\255x\240\159", { "\255", "x", "\240", "\159" })

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

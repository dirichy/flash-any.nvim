-- Native text segmentation against the official Unicode corpus; no public Cursor API.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local cases, codes = {}, {}
local grapheme = require("flash-any.grapheme")
for line in io.lines("tests/data/GraphemeBreakTest-17.0.0.txt") do
	local text, cluster, first, last, count = "", "", 0, 0, 0
	local expected = {}
	for token in line:gsub("#.*", ""):gmatch("%S+") do
		if token == "÷" then
			if cluster ~= "" then
				codes[cluster] = "g"
				expected[#expected + 1] = { first, last, count }
				first, cluster, count = #text, "", 0
			end
		elseif token ~= "×" then
			local cp = assert(tonumber(token, 16))
			local char = cp == 0 and "\0" or vim.fn.nr2char(cp)
			last = #text
			text, cluster = text .. char, cluster .. char
			count = count + 1
		end
	end
	if #expected > 0 then
		cases[#cases + 1] = { text = text, expected = expected }
	end
end
for _, text in ipairs({ "", "\255x\240\159", "\192\128", "\237\160\128", "\244\144\128\128", "\248\128\128\128\128" }) do
	local expected = {}
	for i = 1, #text do
		codes[text:sub(i, i)] = "g"
		expected[#expected + 1] = { i - 1, i - 1, 1 }
	end
	cases[#cases + 1] = { text = text, expected = expected }
end
local path = vim.fn.tempname() .. ".bin"
-- Exercise result growth and a single grapheme with many combining codepoints.
local repeated, boundaries = {}, {}
for i = 1, 2048 do
	local offset = (i - 1) * #"áx"
	repeated[i] = "áx"
	boundaries[#boundaries + 1] = { offset, offset + 1, 2 }
	boundaries[#boundaries + 1] = { offset + #"á", offset + #"á", 1 }
end
codes["á"], codes.x = "g", "g"
cases[#cases + 1] = { text = table.concat(repeated), expected = boundaries }
local long = "a" .. ("́"):rep(10000)
codes[long] = "g"
cases[#cases + 1] = { text = long, expected = { { 0, #long - #"́", 10001 } } }
require("flash-any.build").binary({ sources = { { data = codes } }, output = path })
local book = require("flash-any.native").load(path)
local session = book:new_state()
for i, case in ipairs(cases) do
	assert(grapheme.len(case.text) == #case.expected, "native count mismatch in case " .. i)
	local index = 0
	grapheme.each(case.text, function(first, after, count, last)
		index = index + 1
		local expected = case.expected[index]
		local next_cluster = case.expected[index + 1]
		assert(first == expected[1] and last == expected[2] and count == expected[3])
		assert(after == (next_cluster and next_cluster[1] or #case.text))
	end)
	assert(index == #case.expected)
	local parts = grapheme.split(case.text)
	assert(#parts == #case.expected and table.concat(parts) == case.text)
	local found = session:scan(0, 1, i, 1, 1, { case.text }, "g", nil)
	assert(#found == #case.expected, "cluster count mismatch in case " .. i)
	for j, expected in ipairs(case.expected) do
		assert(found[j].pos[2] == expected[1] and found[j].end_pos[2] == expected[2], "boundary mismatch in case " .. i)
	end
	for _, motion in ipairs({ "f", "F", "t", "T" }) do
		local chars = session:scan(0, 1, i, 1, 1, nil, "g", nil, motion)
		local first = motion == "t" and 2 or 1
		local last = #case.expected - (motion == "T" and 1 or 0)
		assert(#chars == math.max(0, last - first + 1), "char count mismatch " .. motion .. " case " .. i)
		for j = first, last do
			local target = j + (motion == "t" and -1 or motion == "T" and 1 or 0)
			local col = case.expected[target][1]
			assert(chars[j - first + 1].pos[2] == col, "char boundary mismatch " .. motion .. " case " .. i)
		end
	end
end
local points = {}
grapheme.each("a\0中😀\255", function() end, function(cp, after)
	points[#points + 1] = { cp, after }
end)
assert(vim.deep_equal(points, { { 97, 1 }, { 0, 2 }, { 0x4E2D, 5 }, { 0x1F600, 9 }, { -1, 10 } }))
assert(not pcall(grapheme.len, {}))
assert(not pcall(grapheme.each, "a", false))
assert(not pcall(grapheme.each, "a", function()
	error("callback failure")
end))
assert(not pcall(grapheme.each, "a", function() end, function()
	error("codepoint callback failure")
end))
assert(package.loaded["flash-any.grapheme_data"] == nil)
vim.uv.fs_unlink(path)
print("native text tests passed (" .. #cases .. " Unicode/edge cases)")

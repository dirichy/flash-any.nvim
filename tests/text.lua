-- Native text segmentation against the official Unicode corpus; no public Cursor API.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local cases, codes = {}, {}
for line in io.lines("tests/data/GraphemeBreakTest-17.0.0.txt") do
	local text, cluster, first, last = "", "", 0, 0
	local expected = {}
	for token in line:gsub("#.*", ""):gmatch("%S+") do
		if token == "÷" then
			if cluster ~= "" then
				codes[cluster] = "g"
				expected[#expected + 1] = { first, last }
				first, cluster = #text, ""
			end
		elseif token ~= "×" then
			local cp = assert(tonumber(token, 16))
			local char = cp == 0 and "\0" or vim.fn.nr2char(cp)
			last = #text
			text, cluster = text .. char, cluster .. char
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
		expected[#expected + 1] = { i - 1, i - 1 }
	end
	cases[#cases + 1] = { text = text, expected = expected }
end
local path = vim.fn.tempname() .. ".bin"
-- Exercise result growth and a single grapheme with many combining codepoints.
local repeated, boundaries = {}, {}
for i = 1, 2048 do
	local offset = (i - 1) * #"áx"
	repeated[i] = "áx"
	boundaries[#boundaries + 1] = { offset, offset + 1 }
	boundaries[#boundaries + 1] = { offset + #"á", offset + #"á" }
end
codes["á"], codes.x = "g", "g"
cases[#cases + 1] = { text = table.concat(repeated), expected = boundaries }
local long = "a" .. ("́"):rep(10000)
codes[long] = "g"
cases[#cases + 1] = { text = long, expected = { { 0, #long - #"́" } } }
require("flash-any.build").binary({ sources = { { data = codes } }, output = path })
local book = require("flash-any.native").load(path)
local session = book:new_state()
for i, case in ipairs(cases) do
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
vim.uv.fs_unlink(path)
print("native text tests passed (" .. #cases .. " Unicode/edge cases)")

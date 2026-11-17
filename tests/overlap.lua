-- Compare the scanner with exhaustive word segmentation, before any merging.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local grapheme = require("flash-any.grapheme")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial, comparisons = 0, 0
local function engine(data)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = { { data = data } }, output = path })
	return native.load(path)
end
local function ranges(found, text)
	local starts, ends, offset = {}, {}, 0
	for index, glyph in ipairs(grapheme.split(text)) do
		starts[offset] = index
		local last = vim.fn.strcharpart(glyph, vim.fn.strchars(glyph) - 1, 1)
		ends[offset + #glyph - #last] = index
		offset = offset + #glyph
	end
	local ret = {}
	for _, match in ipairs(found) do
		assert(starts[match.pos[2]] and ends[match.end_pos[2]], "ranges must cover complete graphemes")
		ret[#ret + 1] = { starts[match.pos[2]], ends[match.end_pos[2]] }
	end
	return ret
end
local function check(data, text, queries)
	local book, state = engine(data), nil
	state = book:new_state()
	for _, case in ipairs(queries) do
		local query, expected = case[1], case[2]
		local found = state:scan(0, 0, 1, 1, 1, { text }, query, { "a", "b", "y", "q" })
		assert(vim.deep_equal(ranges(found, text), expected), query .. ": " .. vim.inspect(found))
		assert(vim.deep_equal(found, state:scan(0, 0, 1, 1, 1, nil, query, { "a", "b", "y", "q" })))
		assert(vim.deep_equal(found, book:new_state():scan(0, 0, 1, 1, 1, { text }, query, { "a", "b", "y", "q" })))
	end
	return book
end
check({ ["甲"] = "x", ["乙"] = "x", ["甲乙"] = "x" }, "甲乙", {
	{ "x", { { 1, 1 }, { 2, 2 } } },
	{ "xx", { { 1, 2 } } },
})
check({ ["甲乙"] = "x", ["乙"] = "x", ["丙"] = "y", ["丁"] = "z" }, "甲乙丙丁", {
	{ "x", { { 2, 2 } } },
	{ "xy", { { 2, 3 } } },
	{ "xyz", { { 2, 4 } } },
})
check({ ["甲乙"] = "x", ["乙丙"] = "x", ["丙丁"] = "x" }, "甲乙丙丁", {
	{ "x", { { 1, 2 }, { 3, 4 } } },
})
check({ ["重"] = "x", ["重重"] = "x", ["重重重"] = "x" }, "重重重重", {
	{ "x", { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 } } },
	{ "xx", { { 1, 2 }, { 3, 4 } } },
	{ "xxx", { { 1, 3 } } },
})
check({ ["き"] = "ki", ["きゃ"] = "kya", ["ゃ"] = "ya", ["く"] = "ku" }, "きゃく", {
	{ "k", { { 1, 1 }, { 3, 3 } } },
	{ "ki", { { 1, 1 } } },
	{ "ky", { { 1, 2 } } },
	{ "kya", { { 1, 2 } } },
})
local book = check({ ["甲"] = "x", ["甲乙"] = "xy", ["乙"] = "a" }, "甲乙", {
	{ "x", { { 1, 1 } } },
	{ "xy", { { 1, 2 } } },
	{ "xa", { { 1, 2 } } },
})
local state = book:new_state()
local found = state:scan(0, 0, 1, 1, 2, { "甲乙", "甲乙" }, "x", { "y", "a", "q", "w" })
assert(#found == 2 and found[1].pos[1] == 1 and found[2].pos[1] == 2)
assert(found[1].label == "q" and found[2].label == "w", "hidden word continuations still reserve labels")
assert(not found[1].next.y and found[1].next.a, "hidden keys must not be attached to an unrelated range")
found = state:scan(0, 0, 1, 1, 2, nil, "x", { "a", "y", "w", "q" })
assert(found[1].label == "w" and found[2].label == "q", "cached results must retain hidden next keys")
book = check({ ["甲"] = "x", ["甲乙"] = "x" }, "甲乙👩‍💻", {
	{ "x", { { 1, 1 } } },
	{ "x👩‍💻", { { 1, 3 } } },
})
found = book:new_state():scan(0, 0, 1, 1, 1, { "甲乙👩‍💻" }, "x", { "👩", "👩‍", "👩‍💻", "q" })
assert(#found == 1 and found[1].label == "q", "hidden literal continuations reserve complete Unicode prefixes")

-- Small exhaustive searches retain every origin and segmentation, unlike the
-- production request ring. A separate interval DP checks the maximum count.
local function all_ranges(data, chars, query)
	local unique, ret = {}, {}
	local function visit(origin, at, input)
		for word, code in pairs(data) do
			local glyphs = grapheme.split(word)
			local fits = at + #glyphs - 1 <= #chars
			for index, glyph in ipairs(glyphs) do
				fits = fits and chars[at + index - 1] == glyph
			end
			if fits then
				local last, remaining = at + #glyphs - 1, query:sub(input)
				if #remaining <= #code and code:sub(1, #remaining) == remaining then
					local key = origin .. ":" .. last
					if not unique[key] then
						ret[#ret + 1] = { origin, last }
						unique[key] = true
					end
				elseif #remaining > #code and remaining:sub(1, #code) == code then
					visit(origin, last + 1, input + #code)
				end
			end
		end
	end
	for origin = 1, #chars do
		visit(origin, origin, 1)
	end
	return ret, unique
end
local random = 37
local function pick(count)
	random = random * 16807 % 2147483647
	return random % count + 1
end
local alphabet, codes = { "甲", "乙", "丙" }, { "a", "b", "aa", "ab", "ba", "bb" }
for _ = 1, 120 do
	local chars, data = {}, {}
	for index = 1, 6 do
		chars[index] = alphabet[pick(#alphabet)]
	end
	for first = 1, #chars do
		for last = first, math.min(first + 2, #chars) do
			if pick(3) > 1 then
				data[table.concat(chars, "", first, last)] = codes[pick(#codes)]
			end
		end
	end
	book = engine(data)
	state = book:new_state()
	local text = table.concat(chars)
	for _, query in ipairs({ "a", "b", "aa", "ab", "ba", "bb", "aaa", "aba" }) do
		local all, unique = all_ranges(data, chars, query)
		local best = { [#chars + 1] = 0 }
		for first = #chars, 1, -1 do
			best[first] = best[first + 1]
			for _, span in ipairs(all) do
				if span[1] == first then
					best[first] = math.max(best[first], 1 + best[span[2] + 1])
				end
			end
		end
		local labels = { "a", "b", "q", "w", "e", "r" }
		found = state:scan(0, 0, 1, 1, 1, { text }, query, labels)
		local spans, previous = ranges(found, text), 0
		assert(#spans == best[1], "must retain the maximum number of disjoint matches")
		for _, span in ipairs(spans) do
			assert(unique[span[1] .. ":" .. span[2]] and span[1] > previous)
			-- Each choice must end as early as possible; ties prefer the shorter span.
			for _, other in ipairs(all) do
				if other[1] > previous then
					assert(other[2] >= span[2])
					assert(other[2] ~= span[2] or other[1] <= span[1])
				end
			end
			previous = span[2]
		end
		local blocked = {}
		for _, key in ipairs({ "a", "b" }) do
			blocked[key] = #all_ranges(data, chars, query .. key) > 0
		end
		local label = 1
		for _, match in ipairs(found) do
			while labels[label] and blocked[labels[label]] do
				label = label + 1
			end
			assert(match.label == labels[label], "hidden ASCII branches must still exclude their next keys")
			label = label + 1
		end
		comparisons = comparisons + 1
	end
end
vim.fn.delete(root, "rf")
print(
	"non-overlapping ranges, hidden continuations and exhaustive segmentation tests passed ("
		.. comparisons
		.. " comparisons)"
)

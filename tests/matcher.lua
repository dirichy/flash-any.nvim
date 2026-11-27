-- Generated dictionaries exercise public matching rules, independent of source packages.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local grapheme = require("flash-any.grapheme")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial, comparisons = 0, 0
local function compile(sources)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = sources, output = path })
	return native.load(path)
end
local random = 20261127
local function pick(count)
	random = random * 16807 % 2147483647
	return random % count + 1
end
local glyphs = { "甲", "乙", "寿司", "é", "👩‍💻", "𠀀" }
for _ = 1, 3 do
	local data, groups = {}, {}
	for index, glyph in ipairs(glyphs) do
		local code = string.char(96 + index) .. string.char(65 + pick(26) - 1) .. string.char(96 + pick(26))
		data[glyph], groups["group" .. index] = { code, code .. "q" }, { code, code .. "q" }
	end
	for _, mode in ipairs({ "full_code", "initial", "prefix", "letter" }) do
		local inline = compile({ { data = data, matcher = mode } })
		local references = {}
		for index, glyph in ipairs(glyphs) do
			references[glyph] = "group" .. index
		end
		local grouped = compile({ { data = references, groups = groups, matcher = mode } })
		for _, glyph in ipairs(glyphs) do
			local code = data[glyph][1]
			local lines = { "|" .. glyph .. "! " .. glyph .. "!" }
			local a, b = inline:new_state(), grouped:new_state()
			-- Type a code, finish with literal text, mistype, then backspace. Group
			-- storage must give the same ranges, continuations and labels throughout.
			for _, query in ipairs({ code:sub(1, 1), code, code .. "!", code .. "!wrong", code .. "!" }) do
				local found = a:scan(0, 0, 1, 1, 1, lines, query, { "q", "!", "z" })
				local expected = query == code .. "!wrong" and 0 or 2
				assert(#found == expected, mode .. ": " .. query)
				assert(vim.deep_equal(found, b:scan(0, 0, 1, 1, 1, lines, query, { "q", "!", "z" })))
				assert(vim.deep_equal(found, inline:new_state():scan(0, 0, 1, 1, 1, lines, query, { "q", "!", "z" })))
				comparisons = comparisons + 1
			end
			-- Completing an abbreviation before the following glyph distinguishes modes.
			for length = 1, 2 do
				local found = a:scan(0, 0, 1, 1, 1, lines, code:sub(1, length) .. "!", nil)
				local accepts = mode == "prefix" or mode == "initial" and length == 1
				assert(#found == (accepts and 2 or 0), mode .. " abbreviation " .. length)
			end
			-- Case folding applies to letter rules and ASCII literals, never ordinary codes.
			local insensitive = a:scan(0, 0, 1, 1, 1, lines, code:lower(), nil, nil, true)
			assert(#insensitive == (mode == "letter" and 2 or 0))
			assert(vim.deep_equal(insensitive, b:scan(0, 0, 1, 1, 1, lines, code:lower(), nil, nil, true)))
			assert(#a:scan(0, 0, 1, 1, 1, lines, code:lower(), nil, nil, false) == 0)
			assert(#a:scan(0, 0, 2, 1, 1, { glyph .. "X" }, code .. "x", nil, nil, true) == 1)
			assert(#a:scan(0, 0, 2, 1, 1, nil, code .. "x", nil, nil, false) == 0)
			for _, query in ipairs({ glyph, glyph .. "!", code .. "!" }) do
				assert(#a:scan(0, 0, 3, 1, 1, { glyph .. "!" }, query, nil) == 1, "literal/code mixing")
			end
		end
	end
end

-- Group sequences compose per-group abbreviations, not prefixes of the final string.
local groups = { a = { "su", "suu" }, b = { "shi", "si" } }
for _, mode in ipairs({ "full_code", "initial", "prefix", "letter" }) do
	local expanded = { "" }
	for _, name in ipairs({ "a", "b" }) do
		local forms = {}
		for _, spelling in ipairs(groups[name]) do
			forms[spelling] = true
			if mode == "initial" then
				forms[spelling:sub(1, 1)] = true
			elseif mode == "prefix" then
				for n = 1, #spelling do
					forms[spelling:sub(1, n)] = true
				end
			end
		end
		local next_codes = {}
		for _, prefix in ipairs(expanded) do
			for form in pairs(forms) do
				next_codes[#next_codes + 1] = prefix .. form
			end
		end
		expanded = next_codes
	end
	local grouped = compile({ { data = { ["寿司"] = "a b" }, groups = groups, matcher = mode } })
	local inline = compile({ { data = { ["寿司"] = expanded }, matcher = mode == "letter" and mode or "full_code" } })
	for _, query in ipairs({ "s", "sushi", "ss!", "sush!", "SUSHI", "sushi!", "wrong" }) do
		for _, insensitive in ipairs({ false, true }) do
			local a = grouped:new_state():scan(0, 0, 1, 1, 1, { "寿司!" }, query, nil, nil, insensitive)
			local b = inline:new_state():scan(0, 0, 1, 1, 1, { "寿司!" }, query, nil, nil, insensitive)
			assert(vim.deep_equal(a, b), mode .. " sequence " .. query)
		end
	end
end
local padded = compile({ { data = { ["寿司"] = "a b" }, groups = groups, append_space_below = 4 } })
assert(#padded:scan(0, 0, 1, 1, 1, { "寿司" }, "su shi ", nil) == 1)
assert(#padded:scan(0, 0, 1, 1, 1, nil, "sushi", nil) == 0)
local empty = compile({ { data = { ["寿司"] = "a empty" }, groups = { a = { "su" }, empty = {} } } })
assert(#empty:scan(0, 0, 1, 1, 1, { "寿司" }, "s", nil) == 0)
-- Repeated ambiguous groups must not enumerate exponentially many spellings.
local repeated = {}
for _ = 1, 50 do
	repeated[#repeated + 1] = "a"
end
local dense = compile({ { data = { ["寿司"] = table.concat(repeated, " ") }, groups = { a = { "a", "aa" } } } })
assert(#dense:scan(0, 0, 1, 1, 1, { "寿司!" }, string.rep("a", 75) .. "!", nil) == 1)
assert(#dense:scan(0, 0, 1, 1, 1, nil, string.rep("a", 101) .. "!", nil) == 0)

-- Recognition, empty blockers and fallback compose across sources.
local fallback = compile({
	{ data = { ["甲"] = {}, ["乙"] = "x" } },
	{ data = { ["甲"] = "z", ["乙"] = "z", ["丙"] = "z" }, fallback = true },
})
assert(#fallback:scan(0, 0, 1, 1, 1, { "甲乙丙" }, "z", nil) == 1)
local fallback_matches = fallback:scan(0, 0, 1, 1, 1, nil, "z", nil)
assert(fallback_matches[1].pos[2] == #"甲乙")

do
	-- Public bridges read ignorecase/smartcase changes without changing the query.
	local book = compile({ { data = { ["甲"] = "AbC" }, matcher = "letter" } })
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "|甲 A a|" })
	local query = "a"
	local state = {
		pattern = function()
			return query
		end,
	}
	local range = { from = { 1, 0 }, to = { 1, 0 } }
	for _, motion in ipairs({ "search", "f", "F", "t", "T" }) do
		local function count()
			return #(
				motion == "search" and native.get(0, state, range, book) or native.char(0, state, range, book, motion)
			)
		end
		vim.go.ignorecase, vim.go.smartcase = false, true
		assert(count() == 1)
		vim.go.ignorecase, vim.go.smartcase = true, false
		assert(count() == 3)
		query, vim.go.smartcase = "A", true
		assert(count() == 2)
		query = "a"
	end
	vim.go.ignorecase, vim.go.smartcase = false, false
	-- Built-in Latin needs only a smoke test; matching rules above use synthetic maps.
	local latin = compile({ "latin" })
	assert(#latin:scan(0, 0, 1, 1, 1, { "café æx" }, "cafe aex", nil) == 1)
end
-- Literal input may arrive inside a compound glyph; previews must retain its whole range.
do
	local literal = compile({}):new_state()
	for _, glyph in ipairs({ "é", "👩‍💻", "🇨🇳", "\255", "\r\n" }) do
		local complete = literal:scan(0, 0, 1, 1, 1, { "|" .. glyph .. "x" }, glyph, nil)
		assert(#complete == 1 and complete[1].pos[2] == 1)
		for n = 1, #glyph do
			local preview = literal:scan(0, 0, 1, 1, 1, nil, glyph:sub(1, n), nil)
			assert(#preview == 1 and preview[1].end_pos[2] == complete[1].end_pos[2])
		end
		assert(#literal:scan(0, 0, 1, 1, 1, nil, glyph .. "x", nil) == 1)
	end
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
-- Small exhaustive searches retain every origin and segmentation, unlike the
-- production request ring. A separate interval DP checks the maximum count.
local function all_ranges(data, chars, query)
	local unique, ret = {}, {}
	local function visit(origin, at, input)
		for word, code in pairs(data) do
			local parts = grapheme.split(word)
			local fits = at + #parts - 1 <= #chars
			for index, glyph in ipairs(parts) do
				fits = fits and chars[at + index - 1] == glyph
			end
			if fits then
				local last, remaining = at + #parts - 1, query:sub(input)
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
local alphabet, codes = { "甲", "乙", "丙" }, { "a", "b", "aa", "ab", "ba", "bb" }
for _ = 1, 3 do
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
	local book = compile({ { data = data } })
	local state = book:new_state()
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
		local found = state:scan(0, 0, 1, 1, 1, { text }, query, labels)
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
print(("matcher modes, case/literal mixing, groups and overlapping words passed (%d checks)"):format(comparisons))

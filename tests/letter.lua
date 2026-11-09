vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local serial = 0
local function compile(sources)
	serial = serial + 1
	local path = root .. "/" .. serial .. ".bin"
	build.binary({ sources = sources, output = path })
	return native.load(path)
end

-- The same pattern and line snapshot must be rescanned when only case policy changes.
local book = compile({ { data = { ["甲"] = "AbC" }, matcher = "letter" } })
local engine = book:new_state()
local function scan(query, insensitive, text, motion)
	return engine:scan(0, 0, 1, 1, 1, text and { text } or nil, query, { "b", "B", "z" }, motion, insensitive)
end
assert(#scan("abc", false, "|甲|") == 0)
assert(#scan("abc", true) == 1)
assert(#scan("abc", false) == 0)
local found = scan("a", true)
assert(found[1].next.b and found[1].next.B and found[1].label == "z")
assert(scan("Ab", false)[1].next.C and not scan("Ab", false)[1].next.c)
for _, motion in ipairs({ "f", "F", "t", "T" }) do
	assert(#scan("a", false, nil, motion) == 0)
	assert(#scan("a", true, nil, motion) == 1)
	assert(#scan("a", false, nil, motion) == 0)
end

-- Inline and shared spellings obey the same policy in every matching mode.
for _, mode in ipairs({ "full_code", "initial", "prefix", "letter" }) do
	for _, grouped in ipairs({ false, true }) do
		local compiled = compile({
			{
				data = { ["甲"] = grouped and "alias" or { "AbC", "AbD" } },
				groups = grouped and { alias = { "AbC", "AbD" } } or nil,
				matcher = mode,
			},
		})
		local session = compiled:new_state()
		assert(#session:scan(0, 0, 1, 1, 1, { "甲x" }, "AbCX", nil, nil, true) == 1)
		for _, query in ipairs({ "a", "ab", "abc", "abd", "abcX" }) do
			local text = { "甲x" }
			local result = session:scan(0, 0, 1, 1, 1, text, query, nil, nil, true)
			assert(#result == (mode == "letter" and 1 or 0), mode .. " " .. query)
			assert(#session:scan(0, 0, 1, 1, 1, nil, query, nil, nil, false) == 0)
		end
	end
end

-- Exact code rules still mix with case-insensitive literal text.
engine = compile({ { data = { ["甲"] = "ab" } } }):new_state()
assert(#scan("abX", true, "甲x") == 1)
assert(#scan("ABx", true) == 0)
found = scan("a", true)
assert(found[1].next.b and not found[1].next.B and found[1].label == "B")

-- Following literal glyphs contribute both cases to label exclusions as well.
engine = compile({}):new_state()
assert(#scan("a", false, "A Á á") == 1)
assert(#scan("a", true) == 2, "compound literals keep their case and whole-glyph range")
-- A fresh engine owns a separate line snapshot.
engine = compile({}):new_state()
found = scan("a", true, "Ab;")
assert(found[1].next.b and found[1].next.B and found[1].label == "z")
assert(#scan("aB;", true) == 1)
assert(#scan("ab;", false) == 0)

-- Optional selectors can also contain letters in the generic builder API.
local suffix_path = root .. "/suffix.bin"
native.write(suffix_path, { "甲" }, { { { native.modes.suffix, "ab", "X" } } })
engine = native.load(suffix_path):new_state()
assert(#scan("ABx", true, "甲") == 0)
assert(#scan("abx", true) == 0)
assert(#scan("abX", true) == 1)
assert(#scan("ABx", false) == 0)
found = scan("ab", true)
assert(not found[1].next.x and found[1].next.X)

-- Public bridges read options on each call, without rebuilding or changing the query.
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
		return #(motion == "search" and native.get(0, state, range, book) or native.char(0, state, range, book, motion))
	end
	vim.go.ignorecase, vim.go.smartcase = false, true
	assert(count() == 1)
	vim.go.ignorecase, vim.go.smartcase = true, false
	assert(count() == 3)
	query = "A"
	assert(count() == 3)
	vim.go.smartcase = true
	assert(count() == 2)
	query = "a"
	assert(count() == 3)
	vim.go.ignorecase = false
	assert(count() == 1)
end
-- A compound glyph contributes exact rules plus only letter rules from its head scalar.
for _, grouped in ipairs({ false, true }) do
	local letters = compile({
		{
			data = { e = grouped and "vowel" or "e", E = "E", ["é"] = "e", ["æ"] = "ae" },
			groups = grouped and { vowel = { "e", "ee" } } or nil,
			matcher = "letter",
		},
		{ data = { e = "wrong", ["é"] = "bad", ["é"] = "accent", ["👩"] = "woman" } },
	})
	local session = letters:new_state()
	local tick = 0
	local function find(text, input, insensitive, motion)
		tick = tick + 1
		return session:scan(0, 0, tick, 1, 1, { text }, input, { "e", "E", "z" }, motion, insensitive)
	end
	for _, glyph in ipairs({ "é", "é̈", "e‍", "é́", "æ̈", "É" }) do
		local code = glyph:sub(1, 2) == "æ" and "ae" or (glyph:sub(1, 1) == "E" and "E" or "e")
		local matches = find(glyph, code, false)
		assert(#matches == 1, glyph)
		assert(matches[1].pos[2] == 0)
		assert(matches[1].end_pos[2] > 0, "consume the whole grapheme")
		assert(#find(glyph, code:upper(), true) == 1)
		assert(#find(glyph .. "x", code .. "X", true) == 1)
		assert(#find(glyph, "wrong", true) == 0)
		assert(#find(glyph, "bad", true) == 0)
	end
	assert(#find("é", "E", false) == 0)
	assert(#find("É", "e", false) == 0)
	assert(#find("é", "accent", false) == 1, "keep the exact full-grapheme entry")
	assert(#find("👩‍💻", "woman", true) == 0, "ordinary scalar aliases must not skip suffixes")
	assert(#find("\r\n", "\r", true) == 1, "literal prefixes preview the whole glyph")
	local next_keys = find("xæ̈", "x", true)[1].next
	assert(next_keys.a and next_keys.A, "lookahead must include letter head rules")
	next_keys = find("xæ̈", "x", false)[1].next
	assert(next_keys.a and not next_keys.A)
	for _, motion in ipairs({ "f", "F", "t", "T" }) do
		local matches = find("|é|", "E", true, motion)
		assert(#matches == 1)
		local col = motion == "t" and 0 or (motion == "T" and #"|é" or 1)
		assert(matches[1].pos[2] == col, motion)
	end
	if grouped then
		assert(#find("é", "ee", false) == 1)
	end
end
-- Without letter rules, even ASCII heads remain exact complete-grapheme matches.
local exact = compile({ { data = { e = "e", ["é"] = "e" } } }):new_state()
assert(#exact:scan(0, 0, 1, 1, 1, { "éx é́" }, "e", nil, nil, true) == 1)
assert(#exact:scan(0, 0, 1, 1, 1, nil, "ex", nil, nil, true) == 0)

vim.fn.delete(root, "rf")
print("letter head-codepoint and ignorecase/smartcase tests passed")

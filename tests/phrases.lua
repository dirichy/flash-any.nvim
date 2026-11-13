vim.opt.runtimepath:prepend(vim.uv.cwd())
local build, native = require("flash-any.build"), require("flash-any.native")
local path = vim.fn.tempname() .. ".bin"
build.binary({
	output = path,
	sources = {
		{
			data = {
				["甲乙"] = "x",
				["乙"] = "xy",
				["乙丙"] = "xyz",
				["丙丁"] = "w",
				["甲👩"] = "partial",
				["👩"] = "head",
				["👩‍💻甲"] = "emoji",
				["á甲"] = "accent",
				["きゃ"] = "kana",
				["中国"] = "word",
			},
		},
		{ data = { ["甲甲"] = "group" }, groups = { group = { "g", "gg" } } },
	},
})
local book = native.load(path)
local function scan(lines, query, motion)
	return book:new_state():scan(0, 1, 1, 1, #lines, lines, query, { "w", "x", "y", "z", "q" }, motion)
end
local found = scan({ "甲乙丙丁" }, "x")
assert(#found == 2)
assert(found[1].pos[2] == 0 and found[1].end_pos[2] == 3)
assert(found[1].next.y and found[1].next.w, "following words contribute next keys to earlier completions")
assert(#scan({ "甲乙丙丁" }, "xw") == 1)
assert(#scan({ "甲", "乙" }, "x") == 1, "only the separate scalar code may preview; words cannot cross lines")
assert(#scan({ "中国" }, "word") == 1 and #scan({ "中", "国" }, "word") == 0)
assert(#scan({ "甲👩‍💻" }, "partial") == 0 and #scan({ "👩‍💻" }, "head") == 0)
assert(#scan({ "👩‍💻甲" }, "emoji") == 1 and #scan({ "á甲" }, "accent") == 1)
for _, query in ipairs({ "a", "á", "á甲", "👩", "👩‍", "👩‍💻", "👩‍💻甲" }) do
	local text = query:sub(1, 1) == "a" and "á甲" or "👩‍💻甲"
	local end_col = text:sub(1, 1) == "a" and (#query <= 3 and 1 or 3) or (#query <= 11 and 7 or 11)
	local literal = false
	for _, match in ipairs(scan({ text }, query)) do
		literal = literal or (match.pos[2] == 0 and match.end_pos[2] == end_col)
	end
	assert(literal, "phrase dictionaries preserve literal previews: " .. query)
end
for _, query in ipairs({ "g", "gg", "ggg" }) do
	assert(#scan({ "甲甲甲甲" }, query) > 0, "shared groups work on word terminals")
end
for _, motion in ipairs({ "f", "F", "t", "T" }) do
	found = scan({ "|きゃ!" }, "kana", motion)
	local col = motion == "t" and 0 or motion == "T" and 4 or 1
	assert(#found == 1 and found[1].pos[2] == col, "motions use the word's first grapheme")
end
vim.fn.delete(path)
print("phrase boundaries, Unicode literals, shared groups, following keys and motions passed")

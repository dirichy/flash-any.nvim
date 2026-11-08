-- Prepare a recording without requiring demo files in the code-table project.
local root = assert(vim.uv.cwd())
vim.opt.runtimepath:prepend(root)
local config, directory = {}, root
if arg[1] then
	local path = vim.fn.fnamemodify(arg[1], ":p")
	config = assert(loadfile(path))()
	assert(type(config) == "table", "demo config must return a Lua table")
	directory = vim.fn.fnamemodify(path, ":h")
end
for _, key in ipairs({ "file", "format", "columns", "encoding", "converter", "matcher", "title" }) do
	local value = vim.env["TABLE_" .. key:upper()]
	if value and value ~= "" then
		config[key] = key == "columns" and vim.json.decode(value) or value
	end
end
assert(type(config.file) == "string" and config.file ~= "", "provide TABLE_FILE or a Lua config with file")
for _, key in ipairs({ "file", "converter", "sample" }) do
	if config[key] then
		local path = vim.fn.expand(config[key])
		config[key] = path:sub(1, 1) == "/" and path or directory .. "/" .. path
	end
end
local source = {
	file = config.file,
	format = config.format,
	columns = config.columns,
	encoding = config.encoding,
	header = config.header,
	converter = config.converter,
	matcher = config.matcher or "full_code",
}
local data = assert(require("flash-any.source").resolve({ source })[2].data)
local fonts = dofile(assert(vim.api.nvim_get_runtime_file("demos/fonts.lua", false)[1]))
local grapheme = require("flash-any.grapheme")
local function code_for(text)
	local codes = {}
	for _, code in ipairs(data[text] or {}) do
		if code ~= "" and code:find("%S") and not code:find("[%c\128-\255]") then
			codes[#codes + 1] = code
		end
	end
	table.sort(codes, function(a, b)
		local da, db = math.abs(#a - 3), math.abs(#b - 3)
		return da < db or (da == db and a < b)
	end)
	return codes[1]
end
local name = config.text_name or "any text"
assert(type(name) == "string" and name ~= "" and not name:find("[%c]"), "text_name must be a single-line name")
local seed = config.seed or 20261108
assert(
	type(seed) == "number" and seed >= 1 and seed < 2147483647 and seed % 1 == 0,
	"seed must be an integer in 1..2147483646"
)
local samples = {}
-- Explicit examples bypass random sampling entirely. The fallback remains reproducible for a table/font set.
if not config.text then
	local random = seed
	local keys = vim.fn.sort(vim.tbl_keys(data))
	while #keys > 0 and #samples < 1 do
		random = random * 16807 % 2147483647
		local index = random % #keys + 1
		local text = keys[index]
		keys[index] = keys[#keys]
		keys[#keys] = nil
		-- Cmap coverage does not prove that a ligature/ZWJ sequence can be shaped.
		if
			#vim.fn.str2list(text) == 1
			and not text:find("[%c]")
			and vim.fn.charclass(text) ~= 0
			and vim.fn.strdisplaywidth(text) > 0
			and grapheme.len(" " .. text) == 2
		then
			local code, font = code_for(text), fonts.find(text)
			if code and font then
				samples[#samples + 1] = { text = text, code = code, font = font }
			end
		end
	end
	assert(#samples > 0, "no printable table entries are covered by the installed demo fonts")
end
local text = config.text or samples[1].text
assert(type(text) == "string" and grapheme.len(text) == 1 and not text:find("[%c]"), "text must be one grapheme")
local query = assert(code_for(text), "demo text has no printable code")
local primary_font = assert(fonts.find(text), "the demo fonts do not cover the requested text")
local mixed = config.mixed_text or (text .. " with flash")
assert(type(mixed) == "string" and mixed ~= "" and not mixed:find("[%c]"), "mixed_text must be single-line text")
local parts, checkpoints, has_ascii, has_code = {}, {}, false, false
for _, char in ipairs(grapheme.split(mixed)) do
	if char:match("^[ -~]+$") then
		parts[#parts + 1] = char
		has_ascii = true
	else
		parts[#parts + 1] = assert(code_for(char), "mixed_text has no printable code for " .. char)
		assert(fonts.find(char), "the demo fonts do not cover " .. char)
		has_code = true
	end
	checkpoints[#checkpoints + 1] = table.concat(parts)
end
-- An ASCII-only dictionary can still demonstrate its code followed by literal ASCII.
if not has_code and mixed:sub(1, #text) == text then
	parts[1] = query
	for index = 1, #parts do
		checkpoints[index] = table.concat(parts, "", 1, index)
	end
	has_code = true
end
assert(has_code and has_ascii, "mixed_text must combine table text and literal ASCII")
local mixed_query = table.concat(parts)
-- Pause after the first grapheme's code, then at the complete mixed query.
checkpoints = { checkpoints[1], mixed_query }
if checkpoints[1] == checkpoints[2] then
	table.remove(checkpoints)
end
local comment = config.comment or ("Flash can match " .. name .. ": type a code, then choose a label.")
local mixed_comment = config.mixed_comment or ("Mix " .. name .. " codes with ASCII in the same search.")
local lines = {}
local function add_comment(value)
	assert(type(value) == "string", "demo comments must be strings")
	for _, line in ipairs(vim.split(value, "\n", { plain = true })) do
		lines[#lines + 1] = "-- " .. line
	end
end
add_comment(comment)
if config.sample then
	add_comment(mixed_comment)
	vim.list_extend(lines, vim.fn.readfile(config.sample))
else
	lines[#lines + 1] = "local target = " .. vim.json.encode(text)
	lines[#lines + 1] = ""
	add_comment(mixed_comment)
	lines[#lines + 1] = "print(" .. vim.json.encode(mixed) .. ")"
end
-- A small separate area guarantees several real labels without cluttering the main examples.
lines[#lines + 1] = ""
lines[#lines + 1] = "local alternatives = " .. vim.json.encode(text .. " " .. text)
lines[#lines + 1] = "print(alternatives)"
-- Validate custom sample glyphs too; an accepted target must not hide missing surrounding text.
local checked = {}
for _, line in ipairs(lines) do
	for _, char in ipairs(grapheme.split(line)) do
		if char:find("[\128-\255]") and not checked[char] then
			assert(fonts.find(char), "the demo fonts do not cover sample text: " .. char)
			checked[char] = true
		end
	end
end
local stages = {
	{
		title = "Match " .. name .. ": " .. query .. " -> " .. text,
		pattern = query,
		text = text,
		checkpoints = #query > 1 and { query:sub(1, 1), query } or { query },
		minimum = 2,
	},
	{
		title = "Mixed input",
		pattern = mixed_query,
		text = mixed,
		checkpoints = checkpoints,
		minimum = 1,
	},
}
vim.fn.mkdir(root .. "/demos/output", "p")
local extension = config.sample and vim.fn.fnamemodify(config.sample, ":e") or "lua"
local fixture = root .. "/demos/output/table-sample." .. (extension ~= "" and extension or "txt")
assert(vim.fn.writefile(lines, fixture) == 0)
local binary = root .. "/demos/output/table.bin"
require("flash-any.build").binary({ sources = { { data = data, matcher = source.matcher } }, output = binary })
local engine = require("flash-any.native").load(binary)
local labels = "asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM"
for _, stage in ipairs(stages) do
	local matches = engine:scan(0, 0, 1, 1, #lines, lines, stage.pattern, vim.split(labels, ""))
	assert(#matches >= stage.minimum, "not enough live candidates for " .. stage.title)
	stage.matches = #matches
	-- Choose the last matching occurrence so repeated text can demonstrate an actual jump.
	-- Labels still come directly from the matcher; result order and labels stay untouched.
	for _, match in ipairs(matches) do
		local row, col = unpack(match.pos)
		if lines[row]:sub(col + 1, col + #stage.text) == stage.text then
			stage.label = assert(match.label, "demo target has no label")
			stage.target = { row, col }
		end
	end
	assert(stage.label, "query does not match the demo target: " .. stage.text)
	local first = engine:scan(0, 0, 1, 1, #lines, nil, stage.checkpoints[1], nil)
	stage.narrow = #first > #matches
end
local output = {
	title = config.title or (name .. " + ASCII"),
	text_name = name,
	sources = { source },
	binary = binary,
	labels = labels,
	stages = stages,
	fixture = fixture,
	verification = "table-verification.json",
	seed = seed,
	samples = samples,
	font = { family = fonts.family, primary = primary_font },
}
assert(vim.fn.writefile({ vim.json.encode(output) }, "demos/output/table-config.json") == 0)
local tape = {
	"Output demos/output/table.mp4",
	"Require nvim",
	"Source demos/common/style.tape",
	"Hide",
	"Type@1ms "
		.. vim.json.encode(
			"env XDG_CONFIG_HOME=$PWD/demos/output/config XDG_STATE_HOME=$PWD/demos/output/state XDG_CACHE_HOME=$PWD/demos/output/cache NVIM_LOG_FILE=$PWD/demos/output/table-nvim.log FLASH_ANY_DEMO_CONFIG=$PWD/demos/output/table-config.json nvim -n -i NONE -u demos/init.lua "
				.. vim.fn.shellescape(fixture)
		),
	"Enter",
	"Sleep 2s",
	"Show",
	"Sleep 1.5s",
}
for _, stage in ipairs(stages) do
	vim.list_extend(tape, { 'Type "s"', "Sleep 300ms" })
	for index, checkpoint in ipairs(stage.checkpoints) do
		local previous = stage.checkpoints[index - 1] or ""
		tape[#tape + 1] = "Type " .. vim.json.encode(checkpoint:sub(#previous + 1))
		tape[#tape + 1] = "Sleep 800ms"
	end
	vim.list_extend(tape, { "Type " .. vim.json.encode(stage.label), "Sleep 1.8s" })
end
vim.list_extend(tape, {
	"Hide",
	'Type@1ms ":lua FlashAnyDemo.verify()"',
	"Enter",
	"Sleep 200ms",
	'Type@1ms ":qa!"',
	"Enter",
	"Sleep 300ms",
})
assert(vim.fn.writefile(tape, "demos/output/table.tape") == 0)
print("Prepared two jumps using " .. text .. " <- " .. query)

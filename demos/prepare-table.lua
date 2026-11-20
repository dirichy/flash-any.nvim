-- Prepare source examples or an external dictionary through the same C matcher.
local root = assert(vim.uv.cwd())
vim.opt.runtimepath:prepend(root)
dofile(assert(vim.api.nvim_get_runtime_file("scripts/source_path.lua", false)[1]))
local scene = arg[2] or "table"
assert(scene == "demo" or scene == "table", "scene must be demo or table")
local config, directory = {}, root
if arg[1] then
	local path = vim.fn.fnamemodify(arg[1], ":p")
	config = assert(loadfile(path))()
	assert(type(config) == "table", "demo config must return a Lua table")
	directory = vim.fn.fnamemodify(path, ":h")
end
if scene == "table" then
	for _, key in ipairs({ "file", "format", "columns", "encoding", "converter", "matcher", "title" }) do
		local value = vim.env["TABLE_" .. key:upper()]
		if value and value ~= "" then
			config[key] = key == "columns" and vim.json.decode(value) or value
		end
	end
end
local fonts = dofile(assert(vim.api.nvim_get_runtime_file("demos/fonts.lua", false)[1]))
local grapheme = require("flash-any.grapheme")
local sources, output_sources, lines, stages, name, seed, samples, primary_font
if config.examples then
	assert(type(config.sources) == "table" and vim.islist(config.sources), "examples require a sources list")
	assert(
		type(config.examples) == "table" and vim.islist(config.examples) and #config.examples > 0,
		"examples must be a nonempty list"
	)
	assert(not config.sample, "examples generate their own sample")
	sources, output_sources = config.sources, config.sources
	name, samples = config.text_name or "source examples", {}
	lines, stages = {}, {}
	for index, example in ipairs(config.examples) do
		assert(type(example) == "table", "examples must contain tables")
		for _, key in ipairs({ "title", "text", "pattern" }) do
			assert(
				type(example[key]) == "string" and example[key] ~= "" and not example[key]:find("%c"),
				"example " .. index .. " requires single-line " .. key
			)
		end
		local stage = vim.deepcopy(example)
		stage.mode = stage.mode or "jump"
		assert(vim.tbl_contains({ "jump", "char", "remote", "search" }, stage.mode), "unknown example mode")
		local first = grapheme.split(stage.pattern)[1]
		assert(stage.mode ~= "char" or first == stage.pattern, "char needs one query grapheme")
		stage.checkpoints = stage.checkpoints
			or (#first < #stage.pattern and { first, stage.pattern } or { stage.pattern })
		assert(
			type(stage.checkpoints) == "table" and vim.islist(stage.checkpoints) and #stage.checkpoints > 0,
			"example checkpoints must be a nonempty list"
		)
		local previous = ""
		for _, checkpoint in ipairs(stage.checkpoints) do
			assert(
				type(checkpoint) == "string"
					and #checkpoint > #previous
					and stage.pattern:sub(1, #checkpoint) == checkpoint,
				"checkpoints must be increasing prefixes of the example pattern"
			)
			previous = checkpoint
		end
		assert(previous == stage.pattern, "the final checkpoint must equal the example pattern")
		local comment = stage.comment or stage.title
		assert(type(comment) == "string" and not comment:find("%c"), "example comments must be single-line")
		if stage.decoys then
			assert(
				stage.mode == "search" and index == #config.examples and vim.islist(stage.decoys),
				"decoys require a final search example"
			)
			stage.previews = {}
			for decoy_index, text in ipairs(stage.decoys) do
				assert(type(text) == "string" and not text:find("%c"), "decoys must be single-line text")
				lines[#lines + 1] = "-- Keep typing: the next prefix skips this near match."
				local prefix = "local near_" .. decoy_index .. " = "
				lines[#lines + 1] = prefix .. vim.json.encode(text)
				stage.previews[#stage.previews + 1] = { #lines, #prefix + 1 }
				-- More than one recording viewport between each near match.
				vim.list_extend(lines, {
					"",
					"local notes_" .. decoy_index .. " = {",
					'  title = "Daily notes",',
					'  owner = "team",',
					'  status = "draft",',
					'  topic = "Release review",',
					"",
					"  tasks = {",
					'    "Read the guide",',
					'    "Review the examples",',
					'    "Try each motion",',
					"  },",
					"",
					'  tags = { "demo", "notes" },',
					"  published = false,",
					"}",
					"",
					"-- Review the notes before sharing.",
					"-- Each section has its own nearby search result.",
					"-- Continue typing to find a more specific phrase.",
					"",
					"",
				})
			end
		end
		local prefix = "local example_" .. index .. " = "
		local text = stage.text
		if stage.alternatives then
			assert(
				stage.mode == "char" and type(stage.alternatives) == "string" and not stage.alternatives:find("%c"),
				"alternatives require single-line char text"
			)
			text = text .. " " .. stage.alternatives
		end
		-- Native iW needs whitespace around a Japanese word inside a quoted string.
		local padding = stage.mode == "remote" and " " or ""
		local line = prefix .. vim.json.encode(padding .. text .. padding)
		local col = #prefix + 1 + #padding
		lines[#lines + 1] = "-- " .. comment
		lines[#lines + 1] = line
		assert(line:sub(col + 1, col + #stage.text) == stage.text, "example text cannot be escaped in the sample")
		stage.target = { #lines, col }
		if stage.previews then
			stage.previews[#stage.previews + 1] = stage.target
			assert(#stage.previews == #stage.checkpoints, "search needs one preview per checkpoint")
		end
		stage.minimum = 1
		stages[#stages + 1] = stage
		if index < #config.examples then
			lines[#lines + 1] = ""
		end
	end
	primary_font = assert(fonts.find(stages[1].text), "the demo fonts do not cover the requested text")
else
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
		groups = config.groups,
		matcher = config.matcher or "full_code",
	}
	local data = assert(require("flash-any.source").resolve({ source })[2].data)
	local tables = require("flash-any.table")
	local function printable(code)
		return code ~= "" and code:find("%S") and not code:find("[%c\128-\255]")
	end
	local function code_for(text)
		local codes = {}
		for _, code in ipairs(data[text] or {}) do
			local sequence = tables.group_sequence(code, source.groups)
			if sequence then
				local parts = {}
				for _, group_name in ipairs(sequence) do
					local spelling
					for _, variant in ipairs(source.groups[group_name]) do
						if printable(variant) then
							spelling = variant
							break
						end
					end
					if not spelling then
						parts = nil
						break
					end
					parts[#parts + 1] = spelling
				end
				code = parts and table.concat(parts) or ""
			end
			if printable(code) then
				codes[#codes + 1] = code
			end
		end
		table.sort(codes, function(a, b)
			local da, db = math.abs(#a - 3), math.abs(#b - 3)
			return da < db or (da == db and a < b)
		end)
		return codes[1]
	end
	name = config.text_name or "any text"
	assert(type(name) == "string" and name ~= "" and not name:find("[%c]"), "text_name must be a single-line name")
	seed = config.seed or 20261108
	assert(
		type(seed) == "number" and seed >= 1 and seed < 2147483647 and seed % 1 == 0,
		"seed must be an integer in 1..2147483646"
	)
	samples = {}
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
	primary_font = assert(fonts.find(text), "the demo fonts do not cover the requested text")
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
	lines = {}
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
	stages = {
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
	sources = { { data = data, groups = source.groups, matcher = source.matcher } }
	output_sources = { source }
end
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
vim.fn.mkdir(root .. "/demos/output", "p")
local extension = config.sample and vim.fn.fnamemodify(config.sample, ":e") or "lua"
local fixture = root .. "/demos/output/" .. scene .. "-sample." .. (extension ~= "" and extension or "txt")
assert(vim.fn.writefile(lines, fixture) == 0)
local binary = root .. "/demos/output/" .. scene .. ".bin"
require("flash-any.build").binary({
	sources = sources,
	output = binary,
})
local engine = require("flash-any.native").load(binary)
local labels = "asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM"
local jump_end = #lines
for _, stage in ipairs(stages) do
	if stage.previews then
		jump_end = stage.previews[1][1]
		break
	end
end
for _, stage in ipairs(stages) do
	stage.mode = stage.mode or "jump"
	local target = stage.target
	if stage.mode == "char" then
		stage.positions = vim.tbl_map(function(match)
			return match.pos
		end, engine:scan(0, 0, 1, target[1], target[1], { lines[target[1]] }, stage.pattern, nil, "f"))
		assert(
			#stage.positions > 1 and vim.deep_equal(stage.positions[1], target),
			"char needs multiple first-code matches"
		)
	else
		local last = stage.mode == "search" and #lines or jump_end
		local matches =
			engine:scan(0, 0, 1, 1, last, vim.list_slice(lines, 1, last), stage.pattern, vim.split(labels, ""))
		assert(#matches >= stage.minimum, "not enough live candidates for " .. stage.title)
		stage.matches = #matches
		-- Keep an example's dedicated row; table scenes choose the last real occurrence.
		-- Labels and result order come directly from the matcher.
		for _, match in ipairs(matches) do
			local row, col = unpack(match.pos)
			if
				lines[row]:sub(col + 1, col + #stage.text) == stage.text
				and (not target or vim.deep_equal(target, { row, col }))
			then
				stage.label = assert(match.label, "demo target has no label")
				stage.target = { row, col }
			end
		end
		assert(stage.label, "query does not match the demo target: " .. stage.text)
		local first = engine:scan(0, 0, 1, 1, last, nil, stage.checkpoints[1], nil)
		stage.narrow = stage.mode ~= "search" and #first > #matches
		if stage.previews then
			for index, pattern in ipairs(stage.checkpoints) do
				local candidates = engine:scan(0, 0, 1, 1, #lines, lines, pattern, nil)
				assert(vim.deep_equal(candidates[1].pos, stage.previews[index]), "unexpected nearest search preview")
			end
		end
	end
end
local output = {
	title = config.title or (name .. " + ASCII"),
	text_name = name,
	sources = output_sources,
	binary = binary,
	labels = labels,
	stages = stages,
	fixture = fixture,
	verification = scene == "demo" and "verification.json" or "table-verification.json",
	seed = seed,
	samples = samples,
	font = { family = fonts.family, primary = primary_font },
}
assert(vim.fn.writefile({ vim.json.encode(output) }, "demos/output/" .. scene .. "-config.json") == 0)
local tape = {
	"Output demos/output/" .. scene .. ".mp4",
	"Require nvim",
	"Source demos/common/style.tape",
	"Hide",
	"Type@1ms "
		.. vim.json.encode(
			"env XDG_CONFIG_HOME=$PWD/demos/output/config XDG_STATE_HOME=$PWD/demos/output/state XDG_CACHE_HOME=$PWD/demos/output/cache NVIM_LOG_FILE=$PWD/demos/output/"
				.. scene
				.. "-nvim.log FLASH_ANY_DEMO_CONFIG=$PWD/demos/output/"
				.. scene
				.. "-config.json nvim -n -i NONE -u demos/init.lua "
				.. vim.fn.shellescape(fixture)
		),
	"Enter",
	"Sleep 2s",
	"Show",
	"Sleep 1.5s",
}
for _, stage in ipairs(stages) do
	if stage.mode == "char" then
		-- Move to the example row with native motions before starting f.
		vim.list_extend(tape, { "Type " .. vim.json.encode(stage.target[1] .. "G0"), "Sleep 300ms" })
		vim.list_extend(tape, { 'Type "f"', "Sleep 300ms", "Type " .. vim.json.encode(stage.pattern), "Sleep 1.5s" })
		for _ = 2, #stage.positions do
			vim.list_extend(tape, { 'Type "f"', "Sleep 900ms" })
		end
		vim.list_extend(tape, { "Escape", "Sleep 300ms" })
	else
		local key = ({ jump = "s", remote = "dr", search = " /" })[stage.mode]
		vim.list_extend(tape, { "Type " .. vim.json.encode(key), "Sleep 300ms" })
		for index, checkpoint in ipairs(stage.checkpoints) do
			local previous = stage.checkpoints[index - 1] or ""
			tape[#tape + 1] = "Type " .. vim.json.encode(checkpoint:sub(#previous + 1))
			tape[#tape + 1] = "Sleep 800ms"
		end
		if stage.mode == "search" then
			vim.list_extend(tape, { "Enter", "Sleep 1.8s" })
		else
			vim.list_extend(tape, { "Type " .. vim.json.encode(stage.label), "Sleep 1s" })
			if stage.mode == "remote" then
				vim.list_extend(tape, { 'Type "iW"', "Sleep 1.8s" })
			end
		end
	end
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
assert(vim.fn.writefile(tape, "demos/output/" .. scene .. ".tape") == 0)
print("Prepared " .. #stages .. " jumps for " .. scene)

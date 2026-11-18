-- Exercise manifest generation in a separate working tree, without a browser.
local project = assert(vim.uv.cwd())
vim.opt.runtimepath:prepend(project)
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function write(name, lines)
	assert(vim.fn.writefile(lines, root .. "/" .. name) == 0)
end
write("table.tsv", { "国\tGUO", "中\tZHONG", "👩‍💻\tDEV" })
write("convert.lua", { "return function(codes) return vim.tbl_map(string.lower, codes) end" })
local function prepare(config, overrides, scene)
	scene = scene or "table"
	write("demo.lua", vim.split("return " .. vim.inspect(config), "\n", { plain = true }))
	local process = vim.system({
		vim.v.progpath,
		"--clean",
		"--cmd",
		"lua vim.opt.runtimepath:prepend(" .. vim.json.encode(project) .. ")",
		"-l",
		project .. "/demos/prepare-table.lua",
		root .. "/demo.lua",
		scene,
	}, {
		cwd = root,
		text = true,
		env = vim.tbl_extend("force", {
			TABLE_FILE = "",
			TABLE_FORMAT = "",
			TABLE_COLUMNS = "",
			TABLE_ENCODING = "",
			TABLE_CONVERTER = "",
			TABLE_MATCHER = "",
			TABLE_TITLE = "",
		}, overrides or {}),
	}):wait()
	if process.code ~= 0 then
		return nil, process.stderr
	end
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/demos/output/" .. scene .. "-config.json"), "\n"))
end
local function check(config)
	assert(#config.stages == 2)
	assert(config.stages[1].matches >= 2 and config.stages[2].matches >= 1)
	for _, stage in ipairs(config.stages) do
		assert(type(stage.label) == "string" and #stage.label == 1)
	end
	local lines = vim.fn.readfile(config.fixture)
	assert(lines[1]:sub(1, 3) == "-- ")
	assert(vim.uv.fs_stat(config.binary), "the renderer must use the same prebuilt dictionary as label planning")
	for _, sample in ipairs(config.samples) do
		assert(vim.fn.filereadable(sample.font.file) == 1 and #sample.font.scalars == 1)
	end
end
local config = assert(prepare({ file = "table.tsv", converter = "convert.lua" }))
check(config)
assert(config.sources[1].file == root .. "/table.tsv" and config.sources[1].converter == root .. "/convert.lua")
assert(config.stages[1].pattern == ({ ["中"] = "zhong", ["国"] = "guo" })[config.samples[1].text])
local repeated = assert(prepare({ file = "table.tsv", converter = "convert.lua" }))
assert(vim.deep_equal(repeated.samples, config.samples) and vim.deep_equal(repeated.stages, config.stages))
config = assert(prepare({ file = "table.tsv", converter = "convert.lua", matcher = "initial" }))
check(config)
-- Initial matching may use the complete spelling; the sequence is inferred from the table too.
assert(#config.stages[1].checkpoints >= 1)
config = assert(prepare({ file = "table.tsv", converter = "convert.lua", text = "👩‍💻", title = '100% "demo"' }))
check(config)
assert(config.title == '100% "demo"' and config.stages[1].pattern == "dev")
assert(table.concat(vim.fn.readfile(config.fixture), "\n"):find("👩‍💻", 1, true))
config =
	assert(prepare({ file = "missing.tsv" }, { TABLE_FILE = root .. "/table.tsv", TABLE_TITLE = "Override title" }))
check(config)
assert(config.title == "Override title")
assert(not prepare({ file = "table.tsv", matcher = "custom" }))
assert(not prepare({ file = "table.tsv", text_name = "\n" }))
assert(not prepare({ file = "table.tsv", text = "missing" }))
assert(not prepare({ file = "missing.tsv" }))
write("sample.lua", { "-- custom sample", 'local a = "中国"', 'local b = "中"', 'print("中国 with flash")' })
config = assert(prepare({
	file = "table.tsv",
	converter = "convert.lua",
	text_name = "Chinese",
	text = "中",
	mixed_text = "中国 with flash",
	sample = "sample.lua",
}))
check(config)
assert(config.text_name == "Chinese" and #config.samples == 0)
assert(config.stages[2].pattern == "zhongguo with flash")
assert(vim.fn.readfile(config.fixture)[3] == "-- custom sample")
write("kana.tsv", { "本\tほん", "ほ\tほ", "ん\tん" })
write("kana-converter.lua", {
	'return function(codes) for i, code in ipairs(codes) do if code == "ほん" then codes[i] = "ほ ん" end end return codes end',
})
local kana_demo = {
	file = "kana.tsv",
	converter = "kana-converter.lua",
	groups = { ["ほ"] = { "ho" }, ["ん"] = { "n", "nn" } },
	text = "本",
	mixed_text = "ほん with flash",
}
local grouped = assert(prepare(kana_demo))
check(grouped)
assert(grouped.stages[1].pattern == "hon" and grouped.stages[2].pattern == "hon with flash")
assert(vim.deep_equal(grouped.sources[1].groups, kana_demo.groups))
local empty_group = vim.deepcopy(kana_demo)
empty_group.groups["ん"] = {}
assert(not prepare(empty_group), "empty groups cannot supply demo spellings")
assert(not prepare({ file = "table.tsv", text = "中", mixed_text = "国" }))
assert(not prepare({ file = "table.tsv", text = "中", mixed_text = "国x with flash", sample = "sample.lua" }))
assert(not prepare({ file = "table.tsv", text = "中", mixed_text = "国 with flash", sample = "missing.lua" }))
write("one.lua", { 'print("中 with flash")' })
config = assert(prepare({ file = "table.tsv", text = "中", sample = "one.lua" }))
check(config)
write("duplicate.lua", { 'print("中 with flash")', 'print("中 with flash")' })
config = assert(prepare({ file = "table.tsv", text = "中", sample = "duplicate.lua" }))
check(config)
assert(config.stages[2].matches == 2, "mixed input may leave several real labels")
config = assert(prepare({
	file = "table.tsv",
	text = "中",
	comment = "First scene\nChoose a label",
	mixed_comment = "Now mix input",
}))
check(config)
local narrated = vim.fn.readfile(config.fixture)
assert(narrated[1] == "-- First scene" and narrated[2] == "-- Choose a label")
assert(table.concat(narrated, "\n"):find("-- Now mix input", 1, true))
assert(not prepare({ file = "table.tsv", text = "中", comment = 42 }))
assert(not prepare(42))
write("missing-glyph.lua", { 'local a = "中"', 'print("中 with flash")', "-- " .. vim.fn.nr2char(0x10FFFF) })
assert(not prepare({ file = "table.tsv", text = "中", sample = "missing-glyph.lua" }))
config = assert(prepare({
	file = project .. "/demos/templates/table.dict.yaml",
	text_name = "Chinese",
	text = "中",
	mixed_text = "中文 with flash",
	sample = project .. "/demos/templates/table-sample.lua",
}))
check(config)
assert(config.stages[2].pattern == "zhongwen with flash")
local template = assert(loadfile(project .. "/demos/templates/table-demo.lua"))()
template.file = project .. "/demos/templates/table.dict.yaml"
config = assert(prepare(template))
check(config)
assert(vim.fn.readfile(config.fixture)[1] == "-- " .. template.comment)
write("table.tsv", { "a\talpha" })
config = assert(prepare({ file = "table.tsv" }))
check(config)
assert(config.samples[1].text == "a" and config.stages[1].pattern == "alpha")
write("headers.csv", { "字,码", "文,wen" })
config = assert(prepare({ file = "headers.csv", header = true }))
check(config)
assert(config.sources[1].header == true and config.stages[1].pattern == "wen")
write("table.tsv", { "中\tzhong", vim.fn.nr2char(0x10FFFF) .. "\tmissing" })
config = assert(prepare({ file = "table.tsv" }))
assert(config.samples[1].text == "中", "uncovered codepoints cannot enter automatic samples")
-- Instantiate the package templates and exercise the named source through the actual C engine.
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
vim.fn.mkdir(root .. "/lua/flash-any/tables", "p")
local factory = table.concat(vim.fn.readfile(project .. "/demos/templates/source.lua"), "\n")
write("lua/flash-any/sources/example.lua", vim.split(factory:gsub("SOURCE", "example"), "\n", { plain = true }))
write("lua/flash-any/tables/example.tsv", vim.fn.readfile(project .. "/demos/templates/table.tsv"))
local demo_template = assert(loadfile(project .. "/demos/templates/table-demo.lua"))()
demo_template.file = demo_template.file:gsub("SOURCE", "example")
check(assert(prepare(demo_template)))
vim.opt.runtimepath:append(root)
local binary = root .. "/example.bin"
require("flash-any.build").binary({ sources = { "example" }, output = binary })
local engine = require("flash-any.native").load(binary)
local lines = { "中 中 中文 with flash" }
assert(#engine:scan(0, 0, 1, 1, 1, lines, "zhong", {}) == 3)
assert(#engine:scan(0, 0, 1, 1, 1, nil, "zhongwen with flash", nil) == 1)
local workflow = table.concat(vim.fn.readfile(project .. "/demos/templates/table-demo.yml"), "\n")
assert(workflow:find("config: demo.lua", 1, true) and not workflow:find("      file:", 1, true))
-- The main clip plans real f repeats, labelled jumps, remote yank and offscreen search.
-- Small dictionaries keep core tests independent of optional source downloads.
local main = assert(loadfile(project .. "/demos/demo.lua"))()
assert(vim.deep_equal(main.sources, { "latin", "pinyin", "japanese", "nerdfont" }))
main.sources = {
	"latin",
	{ data = { ["中"] = "zhong", ["文"] = "wen", ["字"] = "zi" }, matcher = "initial" },
	{
		data = { ["食べる"] = "た べ る", ["ず"] = "zu" },
		groups = { ["た"] = { "ta" }, ["べ"] = { "be" }, ["る"] = { "ru" } },
	},
	{ data = { [""] = "vim", [""] = "zip" }, matcher = "prefix" },
}
local prepared = assert(prepare(main, { TABLE_FILE = "must-not-override-main.tsv" }, "demo"))
assert(#prepared.stages == 5 and prepared.verification == "verification.json")
local fixture = vim.fn.readfile(prepared.fixture)
for index, stage in ipairs(prepared.stages) do
	assert(stage.pattern == main.examples[index].pattern)
	if index < 5 then
		assert(stage.target[1] == index * 3 - 1, "dedicated examples must not jump into the mixed example")
	end
	assert(fixture[stage.target[1]]:sub(stage.target[2] + 1, stage.target[2] + #stage.text) == stage.text)
	if stage.mode == "char" then
		assert(#stage.positions == 6 and vim.deep_equal(stage.positions[1], stage.target))
	else
		assert(stage.matches >= 1 and stage.label)
	end
end
assert(prepared.stages[3].mode == "remote")
assert(prepared.stages[5].mode == "search" and prepared.stages[5].matches == 1)
assert(#prepared.stages[5].previews == 4)
for index, pos in ipairs(prepared.stages[5].previews) do
	if index > 1 then
		assert(pos[1] - prepared.stages[5].previews[index - 1][1] > 20, "search previews must cross viewports")
	end
end
local generated = table.concat(vim.fn.readfile(root .. "/demos/output/demo.tape"), "\n")
assert(generated:find("demo-config.json", 1, true) and generated:find("demo.mp4", 1, true))
assert(generated:find('Type "f"', 1, true) and generated:find('Type "yr"', 1, true))
assert(generated:find('Type " /"', 1, true) and generated:find('Type "iW"', 1, true))
local invalid = vim.deepcopy(main)
invalid.examples[2].checkpoints = { "zh", "z" }
assert(not prepare(invalid, nil, "demo"))
invalid.examples[2].checkpoints = { "zh" }
assert(not prepare(invalid, nil, "demo"))
invalid.examples[2].checkpoints = { "wrong", "zhongwen" }
assert(not prepare(invalid, nil, "demo"))
invalid = vim.deepcopy(main)
invalid.examples[1].mode = "unknown"
assert(not prepare(invalid, nil, "demo"))
invalid = vim.deepcopy(main)
invalid.examples[5].decoys = { "café noir" }
assert(not prepare(invalid, nil, "demo"))
invalid = vim.deepcopy(main)
invalid.examples[1].pattern = "not-in-the-sample"
invalid.examples[1].checkpoints = nil
assert(not prepare(invalid, nil, "demo"))
assert(not prepare({ sources = {}, examples = main.examples }, nil, "demo"))
assert(not prepare({ sources = main.sources, examples = {} }, nil, "demo"))
local unicode = assert(prepare({
	sources = {},
	examples = { { title = "Literal", text = "本", pattern = "本" } },
}, nil, "demo"))
assert(vim.deep_equal(unicode.stages[1].checkpoints, { "本" }))
local ascii = assert(prepare({
	sources = { "latin" },
	examples = { { title = "Literal", text = "local", pattern = "local" } },
}, nil, "demo"))
assert(ascii.stages[1].target[2] == #'local example_1 = "', "target must refer to the value, not its declaration")
vim.fn.delete(root, "rf")
print("table and multi-source demo preparation, real targets and input validation tests passed")

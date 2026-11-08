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
local function prepare(config, overrides)
	write("demo.lua", vim.split("return " .. vim.inspect(config), "\n", { plain = true }))
	local process = vim.system({
		vim.v.progpath,
		"--clean",
		"--cmd",
		"lua vim.opt.runtimepath:prepend(" .. vim.json.encode(project) .. ")",
		"-l",
		project .. "/demos/prepare-table.lua",
		root .. "/demo.lua",
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
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/demos/output/table-config.json"), "\n"))
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
vim.fn.delete(root, "rf")
print("external-table demo configuration, converted examples and input validation tests passed")

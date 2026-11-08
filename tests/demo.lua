-- Exercise manifest generation in a separate working tree, without a browser.
local project = assert(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function write(name, lines)
	assert(vim.fn.writefile(lines, root .. "/" .. name) == 0)
end
write("table.tsv", { "国\tGUO", "中\tZHONG", "👩‍💻\tDEV" })
write("convert.lua", { "return function(codes) return vim.tbl_map(string.lower, codes) end" })
local function prepare(config, overrides)
	write("demo.json", { vim.json.encode(config) })
	local process = vim.system({
		vim.v.progpath,
		"--clean",
		"--cmd",
		"lua vim.opt.runtimepath:prepend(" .. vim.json.encode(project) .. ")",
		"-l",
		project .. "/demos/prepare-table.lua",
		root .. "/demo.json",
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
			TABLE_TEXT = "",
			TABLE_QUERY = "",
		}, overrides or {}),
	}):wait()
	if process.code ~= 0 then
		return nil, process.stderr
	end
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/demos/output/table-config.json"), "\n"))
end
local config = assert(prepare({ file = "table.tsv", converter = "convert.lua" }))
assert(config.sources[1].file == root .. "/table.tsv")
assert(config.sources[1].converter == root .. "/convert.lua")
assert(config.stages[1].text == "中" and config.stages[1].pattern == "zhong")
assert(vim.deep_equal(config.stages[1].checkpoints, { "z", "zhong" }))
config = assert(prepare({ file = "table.tsv", converter = "convert.lua", matcher = "initial" }))
assert(config.stages[1].pattern == "z" and #config.stages[1].checkpoints == 1)
config = assert(prepare({ file = "table.tsv", converter = "convert.lua", text = "👩‍💻", title = '100% "demo"' }))
assert(config.title == '100% "demo"' and config.stages[1].pattern == "dev")
assert(vim.fn.readfile(config.fixture)[4] == "    👩‍💻")
config = assert(
	prepare({ file = "missing.tsv" }, { TABLE_FILE = root .. "/table.tsv", TABLE_TEXT = "国", TABLE_QUERY = "GUO" })
)
assert(config.stages[1].text == "国" and config.stages[1].pattern == "GUO")
assert(not prepare({ file = "table.tsv", matcher = "custom" }))
assert(not prepare({ file = "table.tsv", query = "\n" }))
assert(not prepare({ file = "table.tsv", text = "missing" }))
assert(not prepare({ file = "missing.tsv" }))
write("table.tsv", { "a\talpha" })
config = assert(prepare({ file = "table.tsv" }))
assert(config.stages[1].text == "a" and config.stages[1].pattern == "alpha")
write("headers.csv", { "字,码", "文,wen" })
config = assert(prepare({ file = "headers.csv", header = true }))
assert(config.sources[1].header == true and config.stages[1].pattern == "wen")
vim.fn.delete(root, "rf")
print("external-table demo configuration, converted examples and input validation tests passed")

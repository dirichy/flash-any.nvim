-- Prepare a recording without requiring demo files in the code-table project.
local root = assert(vim.uv.cwd())
vim.opt.runtimepath:prepend(root)
local config, directory = {}, root
if arg[1] then
	local path = vim.fn.fnamemodify(arg[1], ":p")
	config = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	directory = vim.fn.fnamemodify(path, ":h")
end
for _, key in ipairs({ "file", "format", "columns", "encoding", "converter", "matcher", "title", "text", "query" }) do
	local value = vim.env["TABLE_" .. key:upper()]
	if value and value ~= "" then
		config[key] = key == "columns" and vim.json.decode(value) or value
	end
end
assert(type(config.file) == "string" and config.file ~= "", "provide TABLE_FILE or a JSON config with file")
for _, key in ipairs({ "file", "converter" }) do
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
if not config.text then
	for _, text in ipairs(vim.fn.sort(vim.tbl_keys(data))) do
		if #data[text] > 0 and require("flash-any.grapheme").len(text) == 1 then
			config.text = config.text or text
			if text:find("[\128-\255]") then
				config.text = text
				break
			end
		end
	end
end
assert(config.text and not config.text:find("[\r\n]"), "provide a single-line demo text")
if not config.query then
	local code = assert(data[config.text] and data[config.text][1], "provide query for text missing from the table")
	config.query = source.matcher == "initial" and code:sub(1, 1) or code
end
assert(
	type(config.query) == "string" and #config.query > 0 and not config.query:find("[%c\128-\255]"),
	"demo query must be printable ASCII"
)
local stages = {
	{
		title = config.title or "Third-party code table",
		pattern = config.query,
		text = config.text,
		checkpoints = #config.query > 1 and { config.query:sub(1, 1), config.query } or { config.query },
	},
}
vim.fn.mkdir(root .. "/demos/output", "p")
local fixture = root .. "/demos/output/table-sample.txt"
assert(vim.fn.writefile({ "", "", "", "    " .. config.text, "", "", "" }, fixture) == 0)
local output = {
	title = config.title or "Third-party code table",
	sources = { source },
	stages = stages,
	fixture = fixture,
	verification = "table-verification.json",
}
assert(vim.fn.writefile({ vim.json.encode(output) }, "demos/output/table-config.json") == 0)
local tape = {
	"Output demos/output/table.mp4",
	"Require nvim",
	"Source demos/common/style.tape",
	"Hide",
	'Type@1ms "env XDG_CONFIG_HOME=$PWD/demos/output/config XDG_STATE_HOME=$PWD/demos/output/state XDG_CACHE_HOME=$PWD/demos/output/cache NVIM_LOG_FILE=$PWD/demos/output/table-nvim.log FLASH_ANY_DEMO_CONFIG=$PWD/demos/output/table-config.json nvim -n -i NONE -u demos/init.lua demos/output/table-sample.txt"',
	"Enter",
	"Sleep 2s",
	"Show",
	"Sleep 1s",
	'Type "s"',
	"Sleep 300ms",
}
for index, checkpoint in ipairs(stages[1].checkpoints) do
	local previous = stages[1].checkpoints[index - 1] or ""
	tape[#tape + 1] = "Type " .. vim.json.encode(checkpoint:sub(#previous + 1))
	tape[#tape + 1] = "Sleep 1s"
end
vim.list_extend(tape, {
	'Type "a"',
	"Sleep 2s",
	"Hide",
	'Type@1ms ":lua FlashAnyDemo.verify()"',
	"Enter",
	"Sleep 200ms",
	'Type@1ms ":qa!"',
	"Enter",
	"Sleep 300ms",
})
assert(vim.fn.writefile(tape, "demos/output/table.tape") == 0)
print("Prepared " .. config.text .. " <- " .. config.query)

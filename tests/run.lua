-- Each test gets its own Neovim process. External source tests are opt-in.
local root = assert(vim.uv.cwd())
local source_path = vim.env.FLASH_ANY_SOURCE_PATH
if arg[1] == "child" then
	dofile("scripts/source_path.lua")
	local path = assert(arg[2])
	table.remove(arg, 1)
	table.remove(arg, 1)
	dofile(path)
	return
end
local tests = {
	"autobuild",
	"init",
	"runtime",
	"source",
	"source_cache",
	"third_party",
	"formats",
	"demo",
	"groups",
	"selection",
	"table",
	"build",
	"health",
	"text",
	"native",
	"phrases",
	"letter",
	"literal",
	"latin",
	"tsv",
	"utf8",
	"reference_cursor",
}
local paths = {}
for _, test in ipairs(tests) do
	paths[#paths + 1] = "tests/" .. test .. ".lua"
end
vim.list_extend(paths, vim.fn.glob("tests/reference_match/*.lua", false, true))
if source_path then
	assert(vim.fn.isdirectory(source_path) == 1, "FLASH_ANY_SOURCE_PATH must contain the optional plugin directories")
	vim.list_extend(paths, vim.fn.glob("tests/integration/*.lua", false, true))
end
for _, path in ipairs(paths) do
	local result = vim.system(
		{ vim.v.progpath, "--clean", "-l", "tests/run.lua", "child", path },
		{ cwd = root, text = true }
	)
		:wait()
	io.stdout:write(result.stdout or "")
	io.stderr:write(result.stderr or "")
	assert(result.code == 0, "failed: " .. path)
end
print("all requested tests passed")

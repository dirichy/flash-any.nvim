-- Isolate setup/module state. Matching uses generated tables, without optional source packages.
local root = assert(vim.uv.cwd())
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
	"build_async",
	"rebuild",
	"init",
	"setup",
	"source",
	"source_cache",
	"third_party",
	"formats",
	"selection",
	"table_files",
	"build",
	"health",
	"text",
	"binary",
	"matcher",
}
local paths = {}
for _, test in ipairs(tests) do
	paths[#paths + 1] = "tests/" .. test .. ".lua"
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

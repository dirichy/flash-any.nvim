vim.opt.runtimepath:prepend(vim.uv.cwd())
if arg[1] == "child" then
	vim.opt.runtimepath:append(assert(arg[2]))
	local options
	package.loaded.flash = {
		jump = function(opts)
			options = opts
		end,
	}
	local plugin = require("flash-any")
	plugin.setup({ sources = { "cached_source" } })
	plugin.jump()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	assert(#options.matcher(0, {
		pattern = function()
			return arg[3]
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
	if arg[4] == "cached" then
		for _, module in ipairs({ "source", "table", "build", "sources.cached_source", "cached_source.codes" }) do
			assert(package.loaded["flash-any." .. module] == nil, "cache hit loaded " .. module)
		end
	end
	return
end
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/plugin/lua/flash-any/sources", "p")
vim.fn.mkdir(root .. "/plugin/lua/flash-any/cached_source", "p")
vim.fn.writefile(
	{ 'return function() return { data = require("flash-any.cached_source.codes") } end' },
	root .. "/plugin/lua/flash-any/sources/cached_source.lua"
)
local codes = root .. "/plugin/lua/flash-any/cached_source/codes.lua"
vim.fn.writefile({ 'return { ["甲"] = { "a" } }' }, codes)
local function run(query, cached)
	local result = vim.system({
		vim.v.progpath,
		"--clean",
		"-l",
		"tests/source_cache.lua",
		"child",
		root .. "/plugin",
		query,
		cached and "cached" or "build",
	}, { env = { XDG_CACHE_HOME = root .. "/cache" }, text = true }):wait()
	assert(result.code == 0, result.stderr)
end
run("a")
run("a", true)
assert(#vim.fn.glob(root .. "/cache/**/flash-any/*.bin", false, true) == 1)
vim.fn.writefile({ 'return { ["甲"] = { "changed" } }' }, codes)
run("changed")
run("changed", true)
assert(
	#vim.fn.glob(root .. "/cache/**/flash-any/*.bin", false, true) == 2,
	"external source dependency changes must select a new cache"
)
vim.fn.delete(root, "rf")
print("external source dependency invalidation and cache-hit loading tests passed")

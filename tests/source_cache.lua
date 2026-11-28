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
	assert(vim.wait(10000, function()
		return #options.matcher(0, {
			pattern = function()
				return arg[3]
			end,
		}, { from = { 1, 0 }, to = { 1, 0 } }) == 1
	end))
	if arg[4] == "cached" then
		for _, module in ipairs({ "source", "table", "build", "cached_source.codes" }) do
			assert(package.loaded["flash-any." .. module] == nil, "cache hit loaded " .. module)
		end
	end
	return
end
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/plugin/lua/flash-any/sources", "p")
vim.fn.mkdir(root .. "/plugin/lua/flash-any/cached_source", "p")
local factory = root .. "/plugin/lua/flash-any/sources/cached_source.lua"
local codes = root .. "/plugin/lua/flash-any/cached_source/codes.lua"
local function write_factory(version)
	local suffix = version ~= nil and (", " .. vim.inspect(version)) or ""
	vim.fn.writefile(
		{ 'return function() return {data = require("flash-any.cached_source.codes")} end' .. suffix },
		factory
	)
	-- Keep metadata constant: only the returned version should select a new cache.
	assert(vim.uv.fs_utime(factory, 1000000000, 1000000000))
end
write_factory()
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
write_factory(0)
run("a", true) -- Omitted version and explicit zero select the same cache.
vim.fn.writefile({ 'return { ["甲"] = { "changed" } }' }, codes)
run("a", true) -- No broad file tracking; unchanged version keeps the existing cache.
write_factory(1)
run("changed")
run("changed", true)
vim.fn.writefile({ 'return { ["甲"] = { "next" } }' }, codes)
run("changed", true)
write_factory(2)
run("next")
run("next", true)
write_factory("release-3")
run("next")
run("next", true)
assert(#vim.fn.glob(root .. "/cache/**/flash-any/*.bin", false, true) == 4)
vim.fn.delete(root, "rf")
print("source versions, legacy default zero and cache-hit factory isolation tests passed")

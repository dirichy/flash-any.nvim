local root = assert(vim.uv.cwd())
if arg[1] then
	vim.opt.runtimepath:prepend(arg[2])
	local options
	package.loaded.flash = {
		jump = function(opts)
			options = opts
		end,
	}
	local plugin = require("flash-any")
	local specs = { { data = { ["中"] = "x", ["国"] = "y" } } }
	plugin.setup({ sources = specs, labels = "ab" })
	plugin.jump()
	assert(options.sources == nil and options.binary == nil and options.labels == "ab")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国" })
	assert(#options.matcher(0, {
		pattern = function()
			return "xy"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }) == 1)
	local paths = vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true)
	assert(#paths == (arg[1] == "first" and 1 or 2))
	if arg[1] == "cached" then
		for _, module in ipairs({ "build", "source", "table", "grapheme", "tsv", "scope" }) do
			assert(package.loaded["flash-any." .. module] == nil, "cached setup loaded " .. module)
		end
		return
	end
	local build = require("flash-any.build")
	local binary, calls = build.binary, 0
	rawset(build, "binary", function(opts)
		calls = calls + 1
		return binary(opts)
	end)
	plugin.setup({ sources = specs })
	assert(calls == 0, "same configuration rebuilt")
	plugin.setup({ sources = { { data = { ["中"] = "z", ["国"] = "y" } } } })
	assert(calls == 1, "changed configuration did not build its own package")
	assert(#vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true) == 2)
	local path = vim.fn.stdpath("cache") .. "/nested/custom.bin"
	plugin.setup({ sources = specs, binary = path })
	assert(calls == 2 and vim.uv.fs_stat(path))
	plugin.setup({ binary = path })
	assert(calls == 2)
	assert(not pcall(plugin.setup, { sources = { { data = { ["中国"] = "word" } } } }))
	assert(#vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true) == 2)
	return
end

-- A fresh plugin directory and cache exercise both missing native.so and a
-- second Neovim process that must reuse the on-disk dictionary without builders.
local temporary = vim.fn.tempname()
local plugin_root = temporary .. "/plugin"
vim.fn.mkdir(plugin_root, "p")
for _, pattern in ipairs({ "lua/**/*", "src/*", "scripts/build_native.py", "Makefile" }) do
	for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
		local target = plugin_root .. path:sub(#root + 1)
		if vim.fn.isdirectory(path) == 1 then
			vim.fn.mkdir(target, "p")
		elseif not path:match("%.so$") then
			vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")
			assert(vim.uv.fs_copyfile(path, target))
		end
	end
end
assert(not vim.uv.fs_stat(plugin_root .. "/lua/flash-any/native.so"))
local native_mtime
for _, phase in ipairs({ "first", "cached" }) do
	local process = vim.system(
		{ vim.v.progpath, "--clean", "-l", root .. "/tests/autobuild.lua", phase, plugin_root },
		{
			env = { XDG_CACHE_HOME = temporary .. "/cache", NVIM_LOG_FILE = temporary .. "/nvim.log" },
			text = true,
		}
	)
		:wait()
	assert(process.code == 0, (process.stderr or "") .. (process.stdout or ""))
	local library = assert(vim.uv.fs_stat(plugin_root .. "/lua/flash-any/native.so"))
	assert(not native_mtime or vim.deep_equal(native_mtime, library.mtime), "cached native core was rebuilt")
	native_mtime = library.mtime
end
vim.fn.delete(temporary, "rf")
print("automatic native/dictionary build and persistent-cache reuse tests passed")

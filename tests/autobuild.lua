local root = assert(vim.uv.cwd())
if arg[1] then
	vim.opt.runtimepath:prepend(arg[2])
	rawset(vim, "system", function()
		error("loading and setup must not spawn a compiler or any external process")
	end)
	if arg[1] == "missing" or arg[1] == "invalid" then
		local ok, err = pcall(require, "flash-any.native")
		assert(not ok and tostring(err):find("run make in " .. arg[2], 1, true), tostring(err))
		return
	end
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
	assert(#paths == (arg[1] == "first" and 1 or arg[1] == "updated" and 3 or 2))
	if arg[1] == "updated" then
		return
	end
	if arg[1] == "cached" then
		for _, module in ipairs({ "build", "source", "table", "grapheme", "tsv" }) do
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

-- A fresh installation must report missing/broken native modules without building.
-- After an external make, setup owns only dictionary construction and cache reuse.
local temporary = vim.fn.tempname()
local plugin_root = temporary .. "/plugin"
vim.fn.mkdir(plugin_root, "p")
for _, pattern in ipairs({ "Makefile", "lua/**/*", "src/*", "vendor/**/*" }) do
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
for _, phase in ipairs({ "missing", "invalid", "first", "cached", "updated" }) do
	if phase == "invalid" then
		assert(vim.fn.writefile({ "invalid shared library" }, plugin_root .. "/lua/flash-any/native.so") == 0)
	elseif phase == "first" then
		local result = vim.system({ "make", "-B" }, { cwd = plugin_root, text = true }):wait()
		assert(result.code == 0, result.stderr)
	end
	if phase == "updated" then
		-- A package update must invalidate dictionaries even if the wire version is unchanged.
		local path = plugin_root .. "/lua/flash-any/build.lua"
		local content = vim.fn.readfile(path)
		table.insert(content, 1, "-- Updated package fixture.")
		assert(vim.fn.writefile(content, path) == 0)
	end
	local process = vim.system(
		{ vim.v.progpath, "--clean", "-l", root .. "/tests/autobuild.lua", phase, plugin_root },
		{
			env = { XDG_CACHE_HOME = temporary .. "/cache", NVIM_LOG_FILE = temporary .. "/nvim.log" },
			text = true,
		}
	)
		:wait()
	assert(process.code == 0, (process.stderr or "") .. (process.stdout or ""))
	if phase == "missing" then
		assert(not vim.uv.fs_stat(plugin_root .. "/lua/flash-any/native.so"))
	elseif phase ~= "invalid" then
		local library = assert(vim.uv.fs_stat(plugin_root .. "/lua/flash-any/native.so"))
		assert(not native_mtime or vim.deep_equal(native_mtime, library.mtime), "setup rebuilt the native core")
		native_mtime = library.mtime
	end
end
vim.fn.delete(temporary, "rf")
print("external native build, automatic dictionary build and persistent-cache reuse tests passed")

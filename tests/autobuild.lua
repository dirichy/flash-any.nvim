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
	assert(
		vim.wait(10000, function()
			plugin.jump()
			if not options.matcher then
				return false
			end
			return #options.matcher(0, {
				pattern = function()
					return "xy"
				end,
			}, { from = { 1, 0 }, to = { 1, 0 } }) == 1
		end),
		"async dictionary did not become ready"
	)
	local paths = vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true)
	assert(
		#paths == (arg[1] == "first" and 1 or arg[1] == "updated" and 3 or 2),
		vim.inspect({
			phase = arg[1],
			cache = vim.fn.stdpath("cache"),
			paths = paths,
		})
	)
	if arg[1] == "updated" then
		return
	end
	if arg[1] == "cached" then
		for _, module in ipairs({ "build", "source", "table", "grapheme" }) do
			assert(package.loaded["flash-any." .. module] == nil, "cached setup loaded " .. module)
		end
		return
	end
	local build = require("flash-any.build")
	local binary, calls = build.binary, 0
	rawset(build, "binary", function(...)
		calls = calls + 1
		return binary(...)
	end)
	require("flash-any.native").load(nil, specs)
	assert(calls == 0, "same configuration rebuilt")
	require("flash-any.native").load(nil, { { data = { ["中"] = "z", ["国"] = "y" } } })
	assert(calls == 1, "changed configuration did not build its own package")
	assert(vim.wait(10000, function()
		return #vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true) == 2
	end))
	local path = vim.fn.stdpath("cache") .. "/nested/custom.bin"
	require("flash-any.native").load(path, specs)
	assert(calls == 2)
	assert(vim.wait(10000, function()
		return vim.uv.fs_stat(path) ~= nil
	end))
	require("flash-any.native").load(path)
	assert(calls == 2)
	assert(not pcall(require("flash-any.native").load, nil, { { data = { ["中国"] = "\0" } } }))
	assert(#vim.fn.glob(vim.fn.stdpath("cache") .. "/flash-any/*.bin", false, true) == 2)
	return
end

-- A fresh installation compiles automatically; later starts reuse the native core and dictionaries.
local temporary = vim.fn.tempname()
local plugin_root = temporary .. "/plugin"
vim.fn.mkdir(plugin_root, "p")
for _, pattern in ipairs({ "lua/**/*", "src/*", "vendor/**/*" }) do
	for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
		local target = plugin_root .. path:sub(#root + 1)
		if vim.fn.isdirectory(path) == 1 then
			vim.fn.mkdir(target, "p")
		elseif not path:match("%.so$") and not path:match("%.dll$") then
			vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")
			assert(vim.uv.fs_copyfile(path, target))
		end
	end
end
local library_path = plugin_root .. "/lua/flash-any/native." .. (vim.fn.has("win32") == 1 and "dll" or "so")
local native_mtime
for _, phase in ipairs({ "first", "cached", "updated" }) do
	if phase == "updated" then
		-- Lua compilation changes bump the core cache revision without changing the wire format.
		local path = plugin_root .. "/lua/flash-any/native.lua"
		local content = vim.fn.readfile(path)
		for i, line in ipairs(content) do
			content[i] = line:gsub("local CACHE_VERSION = 2", "local CACHE_VERSION = 3")
		end
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
	local library = assert(vim.uv.fs_stat(library_path))
	assert(not native_mtime or vim.deep_equal(native_mtime, library.mtime), "setup rebuilt the native core")
	native_mtime = library.mtime
end
vim.fn.delete(temporary, "rf")
print("automatic native build, dictionary build and persistent-cache reuse tests passed")

local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local windows = vim.fn.has("win32") == 1
M.library = root .. "/lua/flash-any/native." .. (windows and "dll" or "so")
local sources = { "src/native.c", "src/binary.c", "src/scan.c", "src/trie.c" }
local inputs = vim.list_extend(vim.deepcopy(sources), {
	"src/native.h",
	"src/text.h",
	"src/grapheme_data.h",
	"vendor/luajit/lua.h",
	"vendor/luajit/lauxlib.h",
	"vendor/luajit/luaconf.h",
	"lua/flash-any/compiler.lua",
})
local callbacks
local native

local function current()
	local output = vim.uv.fs_stat(M.library)
	if not output then
		return false
	end
	for _, path in ipairs(inputs) do
		local input = vim.uv.fs_stat(root .. "/" .. path)
		if
			not input
			or input.mtime.sec > output.mtime.sec
			or input.mtime.sec == output.mtime.sec and input.mtime.nsec > output.mtime.nsec
		then
			return false
		end
	end
	return true
end

---Compile directly in a compiler process; concurrent callers share one build.
---@param done? fun(err?: string)
function M.build(done)
	if not done then
		local finished, failure = false, nil
		M.build(function(err)
			finished, failure = true, err
		end)
		assert(
			vim.wait(120000, function()
				return finished
			end),
			"C compilation timed out"
		)
		assert(not failure, failure)
		return
	end
	if callbacks then
		callbacks[#callbacks + 1] = done
		return
	end
	local temporary = M.library .. "." .. vim.fn.getpid() .. "." .. tostring(vim.uv.hrtime()) .. ".tmp"
	local command = { vim.env.CC or (windows and "gcc" or "cc") }
	-- Environment flags are whitespace-separated arguments, never shell commands.
	vim.list_extend(command, vim.split(vim.env.CPPFLAGS or "", "%s+", { trimempty = true }))
	vim.list_extend(command, vim.split(vim.env.CFLAGS or "-O3", "%s+", { trimempty = true }))
	vim.list_extend(command, { "-std=c99", "-Wall", "-Wextra", "-Werror", "-Ivendor/luajit" })
	if windows then
		local nvim = vim.uv.fs_realpath(vim.v.progpath) or vim.v.progpath
		local dll = vim.fs.joinpath(vim.fs.dirname(nvim), "lua51.dll")
		assert(vim.uv.fs_stat(dll), "Neovim's lua51.dll was not found next to " .. nvim)
		vim.list_extend(command, { "-shared", "-DLUA_BUILD_AS_DLL" })
		vim.list_extend(command, sources)
		command[#command + 1] = dll
	else
		vim.list_extend(command, { "-fPIC" })
		vim.list_extend(command, sources)
		vim.list_extend(
			command,
			vim.fn.has("mac") == 1 and { "-bundle", "-undefined", "dynamic_lookup" } or { "-shared" }
		)
	end
	vim.list_extend(command, vim.split(vim.env.LDFLAGS or "", "%s+", { trimempty = true }))
	vim.list_extend(command, { "-o", temporary })
	callbacks = { done }
	local function finish(err)
		vim.uv.fs_unlink(temporary)
		local waiting = callbacks
		callbacks = nil
		for _, callback in ipairs(waiting) do
			callback(err)
		end
	end
	local ok, err = pcall(vim.system, command, { cwd = root, text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				finish("C compilation failed: " .. (result.stderr or "") .. (result.stdout or ""))
				return
			end
			local renamed, reason = vim.uv.fs_rename(temporary, M.library)
			finish(
				not renamed
						and ("cannot replace C module: " .. tostring(reason) .. (windows and "; close Neovim instances using the DLL and retry" or ""))
					or nil
			)
		end)
	end)
	if not ok then
		vim.schedule(function()
			finish(
				"cannot start C compiler (install "
					.. (windows and "native MinGW-w64 GCC" or "GCC or Clang")
					.. "; CC selects its executable): "
					.. tostring(err)
			)
		end)
	end
end

---Return a loaded core, or build asynchronously when a callback is supplied.
---@param done? fun(core: FlashAnyNativeModule?, err?: string)
---@return FlashAnyNativeModule?
function M.load(done)
	if native then
		return native
	end
	if current() then
		local loader = package.loadlib(M.library, "luaopen_flash_any_native")
		if loader then
			native = loader()
			return native
		end
	end
	if not done then
		M.build()
		local loader, err = package.loadlib(M.library, "luaopen_flash_any_native")
		assert(loader, err)
		native = loader()
		return native
	end
	if not callbacks then
		vim.notify("flash-any: compiling C core in background", vim.log.levels.INFO)
	end
	M.build(function(err)
		if err then
			done(nil, err)
			return
		end
		local ok, core = pcall(M.load)
		done(ok and core or nil, not ok and tostring(core) or nil)
	end)
end

if ... == nil then
	M.build()
end

return M

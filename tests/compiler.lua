-- Exercise native build ownership in an isolated plugin tree, never the working library.
local root = assert(vim.uv.cwd())
if arg[1] then
	vim.opt.runtimepath:prepend(arg[1])
	local compiler = require("flash-any.compiler")
	local system, calls = vim.system, 0
	rawset(vim, "system", function(command, opts, done)
		if command[1] ~= vim.v.progpath then
			calls = calls + 1
		end
		return system(command, opts, done)
	end)
	local complete, responsive = 0, false
	local function ready(core, err)
		assert(core, err)
		complete = complete + 1
	end
	assert(not compiler.load(ready))
	assert(not compiler.load(ready))
	vim.opt.runtimepath:append(root .. "/.dev/flash.nvim")
	local flash = require("flash")
	rawset(flash, "jump", function(opts)
		return require("flash.state").new(opts)
	end)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo foo" })
	local plugin = require("flash-any")
	plugin.setup({ sources = {}, binary = arg[1] .. "/literal.bin", char = true })
	local fallback = plugin.jump({ pattern = "foo", search = { multi_window = false } })
	assert(fallback.opts.matcher == nil and fallback.opts.labeler == nil)
	assert(#fallback.results == 2, "first compile must retain Flash's native matching")
	fallback:hide()
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.api.nvim_feedkeys("fo", "xt", false)
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 }), "native char fallback failed")
	vim.api.nvim_feedkeys(";", "xt", false)
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 2 }), "native char repeat failed")
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.api.nvim_feedkeys(vim.keycode("foo<CR>"), "t", false)
	plugin.search({ search = { multi_window = false } })
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 4 }), "native search fallback failed")
	vim.defer_fn(function()
		responsive = complete == 0
	end, 10)
	assert(vim.wait(10000, function()
		return complete == 2
	end))
	assert(responsive and calls == 1, "build must stay responsive and share concurrent requests")
	assert(compiler.load())
	assert(calls == 1)
	assert(
		vim.wait(10000, function()
			local state = plugin.jump({ pattern = "foo", search = { multi_window = false } })
			local matched = state.opts.matcher ~= nil and #state.results == 2
			state:hide()
			return matched
		end),
		"matching did not switch to the C core"
	)
	assert(vim.wait(10000, function()
		return vim.uv.fs_stat(arg[1] .. "/literal.bin") ~= nil
	end))
	local previous = assert(vim.uv.fs_stat(compiler.library))
	local bytes = vim.fn.readfile(compiler.library, "b")
	local cc, flags = vim.env.CC, vim.env.CFLAGS
	for _, missing in ipairs({ false, true }) do
		vim.env.CC = missing and "flash-any-missing-compiler" or cc
		vim.env.CFLAGS = missing and flags or "-flash-any-invalid-compiler-flag"
		local failure
		compiler.build(function(err)
			failure = err
		end)
		assert(vim.wait(1000, function()
			return failure ~= nil
		end))
		assert(failure:find(missing and "cannot start C compiler" or "C compilation failed", 1, true), failure)
		local after = assert(vim.uv.fs_stat(compiler.library))
		assert(vim.deep_equal(previous.mtime, after.mtime), "failed build changed the module's modification time")
		assert(vim.deep_equal(bytes, vim.fn.readfile(compiler.library, "b")), "failed build changed the old module")
		assert(#vim.fn.glob(compiler.library .. ".*.tmp", false, true) == 0)
	end
	return
end
local temporary = vim.fn.tempname() .. "/中文 plugin"
vim.fn.mkdir(temporary, "p")
for _, pattern in ipairs({ "lua/**/*", "src/*", "vendor/**/*" }) do
	for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
		local target = temporary .. path:sub(#root + 1)
		if vim.fn.isdirectory(path) == 1 then
			vim.fn.mkdir(target, "p")
		elseif not path:match("%.so$") and not path:match("%.dll$") then
			vim.fn.mkdir(vim.fs.dirname(target), "p")
			assert(vim.uv.fs_copyfile(path, target))
		end
	end
end
local library = temporary .. "/lua/flash-any/native." .. (vim.fn.has("win32") == 1 and "dll" or "so")
-- A corrupt pre-existing library must be repaired automatically as well.
assert(vim.fn.writefile({ "invalid shared library" }, library) == 0)

for _, stale in ipairs({ false, true }) do
	if stale then
		assert(vim.uv.fs_utime(library, 1, 1))
	end
	local result = vim.system(
		{ vim.v.progpath, "--clean", "-l", root .. "/tests/compiler.lua", temporary },
		{ text = true }
	)
		:wait()
	assert(result.code == 0, result.stderr)
end
vim.fn.delete(vim.fs.dirname(temporary), "rf")
print(
	"background native compilation, Unicode paths, shared requests, corrupt-library repair and failure preservation passed"
)

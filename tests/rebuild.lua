-- Setup variants run in fresh processes; the public API has no reset hook.
if not arg[1] then
	for _, phase in ipairs({ "automatic", "binary-only", "explicit", "serial" }) do
		local result = vim.system({ vim.v.progpath, "--clean", "-l", "tests/rebuild.lua", phase }, { text = true })
			:wait()
		assert(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
	end
	print("manual asynchronous rebuild, deduplication, snapshots, explicit output and retry tests passed")
	return
end
vim.opt.runtimepath:prepend(vim.uv.cwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/flash-any/sources", "p")
local input = root .. "/dictionary.tsv"
vim.fn.writefile({
	("return function() vim.uv.sleep(150); return {file = %q, format = 'tsv'} end, 1"):format(input),
}, root .. "/lua/flash-any/sources/rebuild.lua")
vim.opt.runtimepath:append(root)
vim.env.XDG_CACHE_HOME = root .. "/cache"
local notices = {}
rawset(vim, "notify", function(message, level)
	notices[#notices + 1] = { message, level }
end)
---@type table?
local options
package.loaded.flash = {
	jump = function(opts)
		options = opts
	end,
}
local plugin = require("flash-any")
assert(not pcall(plugin.rebuild), "rebuild requires setup")
local builder = require("flash-any.build")
local async = builder.async
local builds, active = 0, 0
rawset(builder, "async", function(kind, opts, done)
	builds, active = builds + 1, active + 1
	return async(kind, opts, function(...)
		active = active - 1
		done(...)
	end)
end)
local function wait()
	assert(vim.wait(10000, function()
		return active == 0
	end))
end
local query = "a"
local state = {
	pattern = function()
		return query
	end,
}
local range = { from = { 1, 0 }, to = { 1, 0 } }
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" })
if arg[1] == "automatic" then
	vim.fn.writefile({ "中\ta" }, input)
	plugin.setup({ sources = { "rebuild" }, labels = "xy" })
	wait()
	vim.fn.writefile({ "中\tb" }, input)
	assert(require("flash-any.native").load(nil, { "rebuild" }))
	assert(builds == 1, "unchanged source version should reuse automatic cache")
	plugin.jump()
	local matcher = assert(options).matcher
	assert(#matcher(0, state, range) == 1)
	plugin.rebuild()
	plugin.rebuild()
	assert(builds == 2 and active == 1, "concurrent rebuild calls must share a worker")
	assert(#matcher(0, state, range) == 1, "pending rebuild must retain old dictionary")
	wait()
	assert(#matcher(0, state, range) == 1, "current query must retain its snapshot")
	query = "b"
	assert(#matcher(0, state, range) == 1, "changed query must use the rebuilt dictionary")
	plugin.jump()
	assert(assert(options).labels == "xy", "rebuild must retain Flash configuration")
	local cached = require("flash-any.native").load(nil, { "rebuild" })
	assert(#cached:scan(0, 0, 1, 1, 1, { "中" }, "b", nil) == 1)
	assert(builds == 2, "successful rebuild must replace the automatic cache")
elseif arg[1] == "binary-only" then
	local explicit = root .. "/export.bin"
	vim.fn.writefile({ "中\ta" }, input)
	builder.binary({ sources = { "rebuild" }, output = explicit })
	plugin.setup({ binary = explicit })
	assert(not pcall(plugin.rebuild), "binary-only setup cannot reconstruct sources")
elseif arg[1] == "explicit" then
	local explicit = root .. "/export.bin"
	vim.fn.writefile({ "中\ta" }, input)
	builder.binary({ sources = { "rebuild" }, output = explicit })
	plugin.setup({ binary = explicit, sources = { "rebuild" } })
	vim.fn.writefile({ "中\tc" }, input)
	plugin.rebuild()
	wait()
	plugin.jump()
	local matcher = assert(options).matcher
	query = "c"
	assert(#matcher(0, { pattern = state.pattern }, range) == 1)
	local previous = vim.fn.readblob(explicit)
	vim.fn.writefile({ "invalid dictionary row" }, input)
	plugin.rebuild()
	wait()
	assert(notices[#notices][2] == vim.log.levels.ERROR)
	assert(vim.deep_equal(previous, vim.fn.readblob(explicit)), "failed rebuild must preserve the binary")
	assert(#matcher(0, { pattern = state.pattern }, range) == 1, "failure must preserve the loaded dictionary")
	vim.fn.writefile({ "中\td" }, input)
	plugin.rebuild()
	wait()
	query = "d"
	assert(#matcher(0, state, range) == 1, "rebuild must allow retrying after failure")
elseif arg[1] == "serial" then
	-- One configuration keeps one task, even when file changes select another cache path.
	local queued = {}
	rawset(builder, "async", function(_, opts, done)
		local snapshot = builder.read(input, { format = "tsv" })
		queued[#queued + 1] = function()
			builder.binary({ sources = { { data = snapshot } }, output = opts.output })
			done(nil)
		end
	end)
	vim.fn.writefile({ "中\tbase" }, input)
	plugin.setup({ sources = { { file = input, format = "tsv" } } })
	plugin.rebuild()
	assert(#queued == 1, "rebuild during initial construction must reuse the active task")
	queued[1]()
	vim.fn.writefile({ "中\tfirst" }, input)
	plugin.rebuild()
	vim.fn.writefile({ "中\tsecond-long" }, input)
	plugin.rebuild()
	assert(#queued == 2, "a file change must not launch a concurrent rebuild")
	queued[2]()
	query = "first"
	plugin.jump()
	assert(#assert(options).matcher(0, state, range) == 1)
	assert(#queued == 2, "repeated requests must not enqueue another rebuild")
	plugin.rebuild()
	assert(#queued == 3, "a completed task must allow a subsequent rebuild")
	queued[3]()
	query = "second-long"
	assert(#assert(options).matcher(0, state, range) == 1, "subsequent rebuild must read the latest data")
end
vim.fn.delete(root, "rf")

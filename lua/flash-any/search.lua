local Matcher = require("flash-any.matcher")
local Pos = require("flash.search.pos")
local M = {}

---@type {opts: Flash.State.Config, scan: FlashAnyScan}?
local last

---@param state Flash.State
---@param scan FlashAnyScan
---@param wrap? boolean Explicit override; otherwise follow the live wrapscan option.
function M.remember(state, scan, wrap)
	local opts = vim.deepcopy(state.opts)
	opts.pattern = state.pattern()
	opts.matcher = scan
	opts.search.incremental = false
	opts.search.wrap = wrap
	last = { opts = opts, scan = scan }
end

---@param key "n"|"N"|"gn"|"gN"
---@param opts? {forward?: boolean}
---@return Flash.Match?
function M.repeat_search(key, opts)
	assert(key == "n" or key == "N" or key == "gn" or key == "gN", "expected n, N, gn or gN")
	assert(opts == nil or type(opts) == "table", "repeat options must be a table")
	assert(not opts or opts.forward == nil or type(opts.forward) == "boolean", "forward must be a boolean")
	-- Dot replays the <Cmd> from an operator mapping without its expr callback.
	-- Recheck here too, so a newer native query still takes precedence on redo.
	if vim.fn.getreg("/") ~= "" or not last then
		local native_key = key
		if opts and opts.forward ~= nil then
			if key == "gn" or key == "gN" then
				native_key = opts.forward and "gn" or "gN"
			else
				native_key = (vim.v.searchforward == 1) == opts.forward and "n" or "N"
			end
		end
		vim.cmd.normal({ args = { tostring(vim.v.count1) .. native_key }, bang = true })
		return
	end
	local forward = key == "gn" or (key ~= "gN" and last.opts.search.forward)
	if key == "N" then
		forward = not forward
	end
	if opts and opts.forward ~= nil then
		forward = opts.forward
	end
	local config = vim.deepcopy(last.opts)
	if config.search.wrap == nil then
		config.search.wrap = vim.o.wrapscan
	end
	config.jump.pos, config.jump.inclusive = "start", false
	local state = require("flash.state").new(config)
	state:hide()
	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	local matcher = Matcher.new(win, state, last.scan)
	local count = vim.v.count1
	local select = key == "gn" or key == "gN"
	local target
	if select then
		local visual = vim.fn.mode():match("^[vV\22]") ~= nil
		for _, match in ipairs(matcher:get({ from = Pos({ pos[1], 0 }), to = Pos({ pos[1], math.huge }) })) do
			if match.pos[2] <= pos[2] and pos[2] <= match.end_pos[2] then
				-- Visual gn/gN extends past an already selected boundary.
				local boundary = forward and match.end_pos or match.pos
				if not visual or pos[2] ~= boundary[2] then
					target = match
					count = count - 1
					pos = match.pos
				end
				break
			end
		end
	end
	if count > 0 then
		target = matcher:find({ pos = pos, count = count, forward = forward, wrap = config.search.wrap })
	end
	if not target then
		-- An unsuccessful motion must also cancel a pending operator.
		vim.cmd.normal({ args = { vim.keycode("<Esc>") }, bang = true })
		vim.notify("flash-any: pattern not found: " .. state.pattern(), vim.log.levels.WARN)
		return
	end
	if select then
		local pattern, direction, highlight = vim.fn.getreg("/"), vim.v.searchforward, vim.v.hlsearch
		local wrapscan = vim.o.wrapscan
		-- Delegate selection/operator semantics to native gn with one bounded range,
		-- not a regex expansion of the dictionary. Restore the register synchronously.
		vim.fn.setreg(
			"/",
			("\\m\\%%%dl\\%%%dc.\\{-}\\%%>%dc"):format(target.pos[1], target.pos[2] + 1, target.end_pos[2] + 1)
		)
		vim.o.wrapscan = config.search.wrap
		local ok, err = pcall(vim.cmd.normal, { args = { forward and "gn" or "gN" }, bang = true })
		vim.o.wrapscan = wrapscan
		vim.fn.setreg("/", pattern)
		vim.v.searchforward, vim.v.hlsearch = direction, highlight
		if not ok then
			error(err)
		end
	else
		state:jump(target)
	end
	return target
end

---@param scan FlashAnyScan
---@return fun(win: integer, state: Flash.State, range: table): Flash.Match[]
---@return fun(state: Flash.State): Flash.Match?
function M.new(scan)
	local job
	local matches = {}
	local synchronous = false

	local function valid(current)
		return current == job
			and current.state.visible
			and vim.api.nvim_win_is_valid(current.win)
			and vim.api.nvim_win_get_buf(current.win) == current.buf
			and vim.api.nvim_buf_get_changedtick(current.buf) == current.tick
			and current.state.pattern() == current.pattern
			and vim.go.ignorecase == current.ignorecase
			and vim.go.smartcase == current.smartcase
	end

	local function resume(current)
		if not valid(current) or current.done then
			return
		end
		local ok, err = coroutine.resume(current.thread)
		if not ok then
			current.done = true
			error(err)
		end
		if coroutine.status(current.thread) == "dead" then
			current.done = true
			matches = current.matches
			if not synchronous then
				current.state:update({ force = true })
			end
		elseif not synchronous then
			vim.defer_fn(function()
				resume(current)
			end, 1)
		end
	end

	local function get(win, state, range)
		local buf = vim.api.nvim_win_get_buf(win)
		local key = {
			win = win,
			buf = buf,
			tick = vim.api.nvim_buf_get_changedtick(buf),
			pattern = state.pattern(),
			ignorecase = vim.go.ignorecase,
			smartcase = vim.go.smartcase,
			count = vim.v.count1,
			from = range.from,
			to = range.to,
		}
		if job and (job.buf ~= buf or job.tick ~= key.tick) then
			matches = {}
		end
		if not job or not vim.deep_equal(job.key, key) then
			local current = vim.tbl_extend("force", key, { key = key, state = state })
			job = current
			current.thread = coroutine.create(function()
				local deadline = vim.uv.hrtime() + 2000000
				local matcher = Matcher.new(win, state, function(...)
					if not synchronous and vim.uv.hrtime() >= deadline then
						coroutine.yield()
						deadline = vim.uv.hrtime() + 2000000
					end
					return scan(...)
				end)
				current.matches = matcher:get(range)
				current.target = matcher:find({
					pos = state.pos,
					count = current.count,
					forward = state.opts.search.forward,
					wrap = state.opts.search.wrap,
				})
			end)
			vim.defer_fn(function()
				resume(current)
			end, 1)
		end
		-- Flash's callback adapter otherwise only finds in its visible result list.
		state:get_matcher(win).find = function()
			return job and job.done and valid(job) and job.target or nil
		end
		return matches
	end

	local function finish(state)
		-- Refresh input/buffer state before committing; retain the query's dictionary.
		state:update({ force = true })
		synchronous = true
		while job and not job.done and valid(job) do
			resume(job)
		end
		synchronous = false
		return job and valid(job) and job.target or nil
	end
	return get, finish
end

return M

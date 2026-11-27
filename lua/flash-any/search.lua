local Matcher = require("flash-any.matcher")
local M = {}

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

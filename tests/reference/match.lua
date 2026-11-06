-- Frozen Lua reference for differential tests; never loaded by the plugin.
local M = {}
local Cursor = require("reference.cursor")

-- 跨 source 和扫描器共用的 matcher 协议；具体实现只引用这些类型。
---@alias ReferenceNext table<string, boolean>

-- Emit a consumed input byte count, or a string of possible next ASCII keys.
-- chars is the matched buffer span in graphemes, defaulting to 1.
---@alias ReferenceEmit fun(value: integer|string, chars?: integer)

-- Return true for a known position, even when no branch matched; false means unknown.
-- Matchers emit synchronously and are prefix-closed: appends cannot revive failures.
---@alias ReferenceMatcher fun(text: ReferenceCursor, stream: ReferenceCursor, source: ReferenceSource, emit: ReferenceEmit): boolean

-- 初始化后的运行时 source；scheme、fuzzy 等配置已用于构建 data 和 matcher。
---@class ReferenceSource
---@field data? ReferenceTable
---@field max_chars? integer Maximum text graphemes per entry.
---@field mode? string Built-in mode retained for binary compilation.
---@field scope_spec? ReferenceScope Declarative scope retained for binary compilation.
---@field matcher ReferenceMatcher
---@field scope? ReferenceScopeFn Run before the matcher; false means unknown here.
---@field fallback? boolean Only run if every earlier configured source returned false.
---@field name? string

---One input cursor per state/pattern; all source calls share its read cache.
---@param state table
---@param pattern string
---@return ReferenceCursor
local function stream_for(state, pattern)
	local stream = state._flash_any_stream
	if not stream or stream.value ~= pattern then
		stream = Cursor.new(pattern)
		state._flash_any_stream = stream
	end
	return stream
end

---@param text ReferenceCursor
---@param stream ReferenceCursor
---@param sources ReferenceSource[]
---@param emit ReferenceEmit
local function match_text(text, stream, sources, emit)
	local known = false
	for _, source in ipairs(sources) do
		if (not known or not source.fallback) and (not source.scope or source.scope(text)) then
			if source.matcher(text, stream, source, emit) then
				known = true
			end
		end
	end
end

-- Buffer byte column -> input byte offset -> earliest match start column.
---@alias ReferenceRequests table<integer, table<integer, integer>>

---@param requests ReferenceRequests
---@param col integer
---@param offset integer
---@param start integer
local function add_request(requests, col, offset, start)
	local at = requests[col]
	if not at then
		at = {}
		requests[col] = at
	end
	at[offset] = math.min(at[offset] or start, start)
end

---@class ReferenceInternalMatch
---@field line integer
---@field start_col integer
---@field end_col integer Last character's starting byte column
---@field next ReferenceNext

---@param text ReferenceCursor
---@param line integer
---@param pattern string
---@param sources ReferenceSource[]
---@param stream ReferenceCursor Shared across starts, lines and windows.
---@param resume? ReferenceRequests Only these states can survive appended input.
---@return ReferenceInternalMatch[], ReferenceRequests
local function scan_line(text, line, pattern, sources, stream, resume)
	if resume and next(resume) == nil then
		return {}, {}
	end
	local matches = {}
	local requests, frontier = {}, {}
	local first = 0
	if resume then
		first = #text.value
		for col, offsets in pairs(resume) do
			first = math.min(first, col)
			for offset, start in pairs(offsets) do
				add_request(requests, col, offset, start)
			end
		end
	end
	-- A multi-grapheme branch may finish ahead of the current scan position.
	---@type table<integer, ReferenceInternalMatch>
	local ends, waiting = {}, {}
	local offset, start = 0, 0
	local col = first
	---@type integer?, integer?
	local next_col, last_col
	---@type ReferenceInternalMatch?
	local completed

	-- One emitter per line scan, reused across positions, input offsets and sources.
	---@type ReferenceEmit
	local function emit(value, chars)
		---@type integer?, integer?
		local after, last = next_col, last_col
		if chars and chars ~= 1 then
			local _
			_, after, last = text:get(chars)
		end
		if not after or not last then
			return
		end
		local is_next = type(value) == "string"
		if completed then
			-- Query only next keys at a completed span's successor, without extending it.
			if is_next then
				for i = 1, #value do
					completed.next[value:sub(i, i)] = true
				end
			end
			return
		end
		local complete = not is_next and value == #stream.value - stream.offset
		if is_next then
			add_request(frontier, col, offset, start)
		end
		if is_next or complete then
			local at_end = ends[last]
			if not at_end then
				at_end = { line = line, start_col = start, end_col = last, next = {} }
				ends[last] = at_end
				matches[#matches + 1] = at_end
			else
				at_end.start_col = math.min(at_end.start_col, start)
			end
			if is_next then
				for i = 1, #value do
					at_end.next[value:sub(i, i)] = true
				end
			end
			if complete and after < #text.value then
				add_request(frontier, after, #pattern, start)
				waiting[after] = at_end
			end
		elseif after < #text.value then
			---@cast value integer
			add_request(requests, after, offset + value, start)
		end
	end

	text:set_offset(first)
	while true do
		local char
		char, next_col, last_col = text:get(1)
		if not char or not next_col then
			break
		end
		col = text.offset
		completed = waiting[col]
		if completed then
			stream:set_offset(#pattern)
			match_text(text, stream, sources, emit)
			waiting[col] = nil
			completed = nil
		end
		if not resume then
			add_request(requests, col, 0, col)
		end
		local pending = requests[col]
		if pending then
			for input_offset, match_start in pairs(pending) do
				offset, start = input_offset, match_start
				stream:set_offset(offset)
				match_text(text, stream, sources, emit)
			end
			requests[col] = nil
		end
		if resume and next(waiting) == nil and next(requests) == nil then
			break
		end
		text:set_offset(next_col)
	end
	-- Branch enumeration must not change label order.
	table.sort(matches, function(a, b)
		if a.start_col == b.start_col then
			return a.end_col < b.end_col
		end
		return a.start_col < b.start_col
	end)
	return matches, frontier
end

---@class ReferenceDisplayMatch
---@field win integer
---@field pos integer[]
---@field end_pos integer[]
---@field next ReferenceNext
---@field label? string

---@param win integer
---@param state table
---@param opts table
---@param sources ReferenceSource[]
---@return ReferenceDisplayMatch[]
function M.get(win, state, opts, sources)
	local pattern = state.pattern()
	if pattern == "" then
		return {}
	end
	state._flash_any_cache = state._flash_any_cache or {}
	local stream = stream_for(state, pattern)
	local buf = vim.api.nvim_win_get_buf(win)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local from, to = opts.from[1], opts.to[1]
	local cache = state._flash_any_cache[win]
	if not cache or cache.buf ~= buf or cache.from ~= from or cache.to ~= to or cache.tick ~= tick then
		---@type ReferenceCursor[]
		local lines = {}
		for i, text in ipairs(vim.api.nvim_buf_get_lines(buf, from - 1, to, false)) do
			lines[i] = Cursor.new(text)
		end
		cache = { buf = buf, from = from, to = to, tick = tick, lines = lines }
		state._flash_any_cache[win] = cache
	end
	if cache.pattern ~= pattern or cache.sources ~= sources then
		local previous = cache.pattern
		local incremental = cache.sources == sources
			and previous
			and previous ~= ""
			and #pattern > #previous
			and pattern:sub(1, #previous) == previous
		if incremental then
			-- Appends can merge the old final cluster (accents, ZWJ, RI), or
			-- repair truncated UTF-8. Resume only when the old end is still a boundary.
			incremental = pcall(stream.set_offset, stream, #previous)
		end
		local matches, frontiers = {}, {}
		for i, text in ipairs(cache.lines) do
			local found, frontier =
				scan_line(text, from + i - 1, pattern, sources, stream, incremental and cache.frontiers[i] or nil)
			vim.list_extend(matches, found)
			frontiers[i] = frontier
		end
		cache.matches, cache.frontiers = matches, frontiers
		cache.pattern, cache.sources = pattern, sources
	end
	local ret = {}
	for _, match in ipairs(cache.matches) do
		ret[#ret + 1] = {
			win = win,
			pos = { match.line, match.start_col },
			end_pos = { match.line, match.end_col },
			next = match.next,
		}
	end
	if state.labels then
		local labels = state:labels()
		local blocked = {}
		for _, item in ipairs(ret) do
			for value in pairs(item.next) do
				blocked[value] = true
			end
		end
		local label_index = 1
		for _, item in ipairs(ret) do
			while label_index <= #labels and blocked[labels[label_index]] do
				label_index = label_index + 1
			end
			if label_index <= #labels then
				item.label = labels[label_index]
				label_index = label_index + 1
			end
		end
	end
	return ret
end

---Single-character search; lines are loaded and cached only when requested.
---@param win integer
---@param state table
---@param opts table
---@param sources ReferenceSource[]
---@param motion? string t/T return the adjacent grapheme start.
---@return ReferenceDisplayMatch[]
function M.char(win, state, opts, sources, motion)
	local pattern = state.pattern()
	if pattern == "" then
		return {}
	end
	local stream = stream_for(state, pattern)
	local buf = vim.api.nvim_win_get_buf(win)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	state._flash_any_char_cache = state._flash_any_char_cache or {}
	local cache = state._flash_any_char_cache[win]
	if not cache or cache.buf ~= buf or cache.tick ~= tick then
		cache = { buf = buf, tick = tick, lines = {}, matches = {} }
		state._flash_any_char_cache[win] = cache
	end
	if cache.pattern ~= pattern or cache.sources ~= sources then
		cache.matches = {}
		cache.pattern, cache.sources = pattern, sources
	end
	local ret = {}
	---@type ReferenceCursor
	local text
	local found = false
	---@type ReferenceEmit
	local function emit(_, chars)
		local _, after = text:get(chars or 1)
		if after then
			found = true
		end
	end
	local last = math.min(opts.to[1], vim.api.nvim_buf_line_count(buf))
	for row = math.max(1, opts.from[1]), last do
		---@type {col: integer, before?: integer, after?: integer}[]?
		local matches = cache.matches[row]
		if not matches then
			matches = {}
			text = cache.lines[row]
			if not text then
				text = Cursor.new(vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1])
				cache.lines[row] = text
			end
			text:set_offset(0)
			---@type integer?
			local before
			while true do
				local char, after = text:get(1)
				if not char or not after then
					break
				end
				found = false
				stream:set_offset(0)
				match_text(text, stream, sources, emit)
				if found then
					matches[#matches + 1] =
						{ col = text.offset, before = before, after = after < #text.value and after or nil }
				end
				before = text.offset
				text:set_offset(after)
			end
			cache.matches[row] = matches
		end
		for _, item in ipairs(matches) do
			local col = item.col
			if motion == "t" then
				col = item.before
			elseif motion == "T" then
				col = item.after
			end
			if col then
				ret[#ret + 1] = { win = win, pos = { row, col }, end_pos = { row, col }, next = {} }
			end
		end
	end
	return ret
end

return M

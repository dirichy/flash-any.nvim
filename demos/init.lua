-- Isolated recording configuration; run from the repository root.
local root = vim.fn.getcwd()
dofile(root .. "/scripts/source_path.lua")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.FLASH_NVIM_PATH or (root .. "/.dev/flash.nvim"))
vim.opt.runtimepath:prepend(vim.env.TOKYONIGHT_PATH or (root .. "/.dev/tokyonight.nvim"))
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.cursorline = true
vim.opt.scrolloff = 2
vim.opt.laststatus = 3
vim.opt.showmode = false
vim.opt.showcmd = false
vim.opt.ruler = false
vim.opt.shortmess:append("I")
vim.cmd.colorscheme("tokyonight-night")
vim.cmd("filetype on")
vim.cmd("syntax enable")

local config = vim.json.decode(table.concat(vim.fn.readfile(assert(vim.env.FLASH_ANY_DEMO_CONFIG)), "\n"))
vim.opt.winbar = "  flash-any.nvim   /   " .. config.title:gsub("%%", "%%%%")
local plugin = require("flash-any")
plugin.setup({
	sources = config.sources,
	binary = config.binary,
	labels = config.labels,
	label = { style = "inline", uppercase = config.labels == nil },
})
vim.g.mapleader = " "
require("flash").setup({ modes = { char = { matcher = plugin.char, multi_line = false } } })
local demo = { seen = {}, jumps = {}, active = 0, char_cursors = {} }
local stages = config.stages
-- Resolve expected byte positions from the original fixture, before any interaction.
local lines = vim.fn.readfile(config.fixture)
for _, stage in ipairs(stages) do
	if stage.target then
		local row, col = unpack(stage.target)
		assert(lines[row] and lines[row]:sub(col + 1, col + #stage.text) == stage.text, "invalid planned target")
	else
		for row, line in ipairs(lines) do
			local col = line:find(stage.text, 1, true)
			if col then
				assert(
					not stage.target and not line:find(stage.text, col + 1, true),
					"duplicate target: " .. stage.text
				)
				stage.target = { row, col - 1 }
			end
		end
	end
	assert(stage.target, "missing target: " .. stage.text)
end
local keys = ""
vim.on_key(function(_, typed)
	if typed and typed ~= "" then
		keys = (keys .. vim.fn.keytrans(typed)):sub(-32)
		vim.g.flash_any_demo_keys = keys
		vim.schedule(function()
			vim.cmd.redrawstatus()
		end)
	end
end, vim.api.nvim_create_namespace("flash-any-demo-keys"))

local function begin(index)
	local stage = assert(stages[index], "unexpected extra search")
	demo.active = index
	demo.seen[index] = {}
	demo.origin = vim.api.nvim_win_get_cursor(0)
	demo.viewport = { vim.fn.line("w0"), vim.fn.line("w$") }
	vim.opt.statusline = "  " .. stage.title:gsub("%%", "%%%%") .. "%=%{get(g:, 'flash_any_demo_keys', '')}  %l:%c  "
	return stage
end

for key, mode in pairs({ s = "jump", r = "remote", ["<leader>/"] = "search" }) do
	vim.keymap.set(mode == "remote" and "o" or "n", key, function()
		local stage = begin(#demo.jumps + 1)
		assert(stage.mode == mode, "unexpected demo mode")
		local origin, viewport = demo.origin, demo.viewport
		local state = plugin[mode]()
		demo.jumps[#demo.jumps + 1] = {
			pattern = state.pattern(),
			cursor = vim.api.nvim_win_get_cursor(0),
			origin = origin,
			viewport = viewport,
		}
	end)
end

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		if stages[1].mode == "char" then
			vim.api.nvim_win_set_cursor(0, { stages[1].target[1], 0 })
			begin(1)
		end
	end,
})
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		local index = demo.active
		local jump = demo.jumps[index]
		if jump and stages[index].mode == "remote" then
			vim.hl.on_yank({ timeout = 1000 })
			local contents = vim.v.event.regcontents
			assert(type(contents) == "table", "yank contents must be lines")
			jump.yanked = table.concat(contents, "\n")
			jump.landing = vim.api.nvim_win_get_cursor(0)
			vim.defer_fn(function()
				jump.restored = vim.api.nvim_win_get_cursor(0)
			end, 100)
		end
	end,
})

-- Observe actual live search results without changing them or their labels.
local timer = assert(vim.uv.new_timer())
timer:start(
	0,
	40,
	vim.schedule_wrap(function()
		if demo.active == 0 then
			return
		end
		local stage = stages[demo.active]
		local state
		if stage.mode == "char" then
			state = require("flash.plugins.char").state
		else
			-- Recording-only dependency on Flash's live states, including search().
			for current in pairs(require("flash.state")._states) do
				if current.visible and current ~= require("flash.plugins.char").state then
					state = current
				end
			end
		end
		if state and state.visible and state.pattern() ~= "" then
			local pattern = state.pattern()
			local cursor = vim.api.nvim_win_get_cursor(0)
			demo.seen[demo.active][pattern] = {
				matches = vim.tbl_map(function(match)
					return { pos = { unpack(match.pos) }, label = match.label }
				end, state.results),
				cursor = cursor,
				target = state.target and { unpack(state.target.pos) } or nil,
				viewport = { vim.fn.line("w0"), vim.fn.line("w$") },
			}
			if stage.mode == "char" then
				local previous = demo.char_cursors[#demo.char_cursors]
				if not previous or not vim.deep_equal(previous, cursor) then
					demo.char_cursors[#demo.char_cursors + 1] = cursor
				end
				if vim.deep_equal(cursor, stage.positions[#stage.positions]) then
					demo.jumps[demo.active] = { pattern = pattern, cursor = cursor }
				end
			end
		end
	end)
)

function demo.verify()
	timer:stop()
	timer:close()
	local ok, err = pcall(function()
		assert(#demo.jumps == #stages, "all demo jumps must finish")
		for i, stage in ipairs(stages) do
			for _, pattern in ipairs(stage.checkpoints) do
				assert(
					demo.seen[i][pattern]
						and (
							stage.mode == "search" and demo.seen[i][pattern].target ~= nil
							or #demo.seen[i][pattern].matches > 0
						),
					"missing live candidates: " .. pattern
				)
			end
			assert(demo.jumps[i].pattern == stage.pattern, "unexpected jump pattern")
			assert(
				vim.deep_equal(
					demo.jumps[i].landing or demo.jumps[i].cursor,
					stage.mode == "char" and stage.positions[#stage.positions] or stage.target
				),
				stage.title
					.. ": expected cursor "
					.. vim.inspect(stage.target)
					.. ", got "
					.. vim.inspect(demo.jumps[i].cursor)
			)
			local matches = demo.seen[i][stage.pattern].matches
			if stage.mode == "char" then
				assert(vim.deep_equal(demo.char_cursors, stage.positions), "f must visit every first-code candidate")
				assert(#matches == #stage.positions, "f must highlight all sources together")
			else
				if stage.mode ~= "search" then
					assert(#matches == (stage.matches or 1), "unexpected final candidate count")
				end
				local selected
				for _, match in ipairs(matches) do
					if vim.deep_equal(match.pos, stage.target) then
						assert(not selected, "duplicate target candidates")
						selected = match
					end
				end
				assert(stage.mode == "search" or selected, "missing selected target")
				if stage.mode == "search" then
					assert(stage.target[1] > demo.jumps[i].viewport[2], "search target must start below the screen")
					local previous = 0
					for index, pattern in ipairs(stage.checkpoints) do
						local preview = demo.seen[i][pattern]
						-- Search finds in the entire buffer; results only describe a viewport.
						assert(
							vim.deep_equal(preview.target, stage.previews[index]),
							"unexpected full-buffer target: " .. pattern
						)
						assert(
							vim.deep_equal(preview.cursor, stage.previews[index]),
							"unexpected incremental preview: " .. pattern
						)
						assert(preview.cursor[1] > previous, "search must advance past each near match")
						assert(
							preview.viewport[1] <= preview.cursor[1] and preview.cursor[1] <= preview.viewport[2],
							"preview must scroll into view"
						)
						for _, match in ipairs(preview.matches) do
							assert(not match.label or match.label == "", "search has no labels")
						end
						previous = preview.cursor[1]
					end
				else
					assert(selected.label == (stage.label or "a"), "the displayed label must select the target")
				end
				if stage.mode == "remote" then
					assert(demo.jumps[i].yanked == stage.text, "remote must yank the Japanese word")
					assert(
						vim.deep_equal(demo.jumps[i].restored, demo.jumps[i].origin),
						"remote must restore the origin"
					)
				end
				if stage.narrow then
					assert(
						#demo.seen[i][stage.checkpoints[1]].matches > #matches,
						"the query must narrow the candidates"
					)
				end
			end
		end
		assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines), "fixture changed")
		assert(not vim.bo.modified, "demo must leave the fixture unchanged")
		assert(vim.v.errmsg == "", vim.v.errmsg)
	end)
	vim.fn.writefile({
		vim.json.encode({
			verified = ok,
			error = not ok and tostring(err) or nil,
			seen = demo.seen,
			jumps = demo.jumps,
			char_cursors = demo.char_cursors,
			expected = stages,
			seed = config.seed,
			samples = config.samples,
			font = config.font,
		}),
	}, root .. "/demos/output/" .. config.verification)
	if not ok then
		error(err)
	end
end

_G.FlashAnyDemo = demo

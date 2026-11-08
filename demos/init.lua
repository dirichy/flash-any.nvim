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

local config
if vim.env.FLASH_ANY_DEMO_CONFIG then
	config = vim.json.decode(table.concat(vim.fn.readfile(vim.env.FLASH_ANY_DEMO_CONFIG), "\n"))
else
	config = {
		sources = { "pinyin", "unicode" },
		fixture = root .. "/demos/sample.lua",
		verification = "verification.json",
		title = "Full pinyin + initials + ascii + Unicode",
		stages = {
			{ title = "Full pinyin", pattern = "quanpin", text = "全拼", checkpoints = { "quan", "quanpin" } },
			{ title = "Initials", pattern = "jp", text = "简拼", checkpoints = { "j", "jp" } },
			{
				title = "Mixed input",
				pattern = "hunsasciigrin",
				text = "混输ascii😀",
				checkpoints = { "hun", "huns", "hunsascii", "hunsasciigrin" },
			},
		},
	}
end
vim.opt.winbar = "  flash-any.nvim   /   " .. config.title:gsub("%%", "%%%%")
local plugin = require("flash-any")
plugin.setup({
	sources = config.sources,
	binary = config.binary,
	labels = config.labels,
	label = { style = "inline", uppercase = config.labels == nil },
})
local demo = { seen = {}, jumps = {}, active = 0 }
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
vim.opt.statusline = "  " .. config.title:gsub("%%", "%%%%") .. "%=%l:%c  "

vim.keymap.set("n", "s", function()
	local index = #demo.jumps + 1
	local stage = assert(stages[index], "unexpected extra search")
	demo.active = index
	demo.seen[index] = {}
	vim.opt.statusline = "  "
		.. stage.title:gsub("%%", "%%%%")
		.. "   |   s > "
		.. stage.pattern:gsub("%%", "%%%%")
		.. " > "
		.. (stage.label or "a")
		.. "%=%l:%c  "
	local state = plugin.jump()
	demo.jumps[#demo.jumps + 1] = {
		pattern = state.pattern(),
		cursor = vim.api.nvim_win_get_cursor(0),
	}
end)

-- Observe actual live search results without changing them or their labels.
local timer = assert(vim.uv.new_timer())
timer:start(
	0,
	40,
	vim.schedule_wrap(function()
		local state = require("flash.repeat")._states.jump
		if state and state.visible and demo.active > 0 then
			local pattern = state.pattern()
			if pattern ~= "" then
				demo.seen[demo.active][pattern] = vim.tbl_map(function(match)
					return { pos = { unpack(match.pos) }, label = match.label }
				end, state.results)
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
				assert(demo.seen[i][pattern] and #demo.seen[i][pattern] > 0, "missing live candidates: " .. pattern)
			end
			assert(demo.jumps[i].pattern == stage.pattern, "unexpected jump pattern")
			assert(
				vim.deep_equal(demo.jumps[i].cursor, stage.target),
				stage.title
					.. ": expected cursor "
					.. vim.inspect(stage.target)
					.. ", got "
					.. vim.inspect(demo.jumps[i].cursor)
			)
			local matches = demo.seen[i][stage.pattern]
			assert(#matches == (stage.matches or 1), "unexpected final candidate count")
			local selected
			for _, match in ipairs(matches) do
				if vim.deep_equal(match.pos, stage.target) then
					assert(not selected, "duplicate target candidates")
					selected = match
				end
			end
			assert(selected and selected.label == (stage.label or "a"), "the displayed label must select the target")
			if stage.narrow then
				assert(#demo.seen[i][stage.checkpoints[1]] > #matches, "the query must narrow the candidates")
			end
		end
		assert(not vim.bo.modified, "demo must leave the fixture unchanged")
		assert(vim.v.errmsg == "", vim.v.errmsg)
	end)
	vim.fn.writefile({
		vim.json.encode({
			verified = ok,
			error = not ok and tostring(err) or nil,
			seen = demo.seen,
			jumps = demo.jumps,
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

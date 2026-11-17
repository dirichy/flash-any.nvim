-- Run the actual commands in both tutorials against fresh source directories.
local project = assert(vim.uv.cwd())
vim.opt.runtimepath:prepend(project)
local function block(guide, language, prefix)
	for lang, code in guide:gmatch("```([%w]+)\n(.-)\n```") do
		if lang == language and code:sub(1, #prefix) == prefix then
			return code
		end
	end
	error("missing tutorial block: " .. prefix)
end
for _, document in ipairs({ "docs/writing-sources.md", "docs/writing-sources.zh-CN.md" }) do
	local root = vim.fn.tempname()
	local source = root .. "/source package"
	vim.fn.mkdir(root, "p")
	local env = {
		FLASH_ANY_SOURCE_ROOT = source,
		FLASH_NVIM_PATH = vim.env.FLASH_NVIM_PATH or project .. "/.dev/flash.nvim",
		XDG_CACHE_HOME = root .. "/cache",
		XDG_STATE_HOME = root .. "/state",
		NVIM_LOG_FILE = root .. "/nvim.log",
		PATH = vim.fn.fnamemodify(vim.v.progpath, ":h") .. ":" .. vim.env.PATH,
	}
	local function run(args, cwd)
		local result = vim.system(args, { cwd = cwd or project, env = env, text = true }):wait()
		assert(result.code == 0, document .. ":\n" .. (result.stdout or "") .. (result.stderr or ""))
	end
	local function write(path, content)
		assert(vim.fn.writefile(vim.split(content, "\n", { plain = true }), path) == 0)
	end
	local guide = table.concat(vim.fn.readfile(document), "\n")
	run({ "sh", "-eu", "-c", block(guide, "sh", "# Create the minimal source package.") })
	assert(vim.fn.filereadable(source .. "/lua/flash-any/sources/mycodes.lua") == 1)
	assert(vim.fn.readfile(source .. "/lua/flash-any/tables/mycodes.tsv")[1] == "中\tzhong")
	assert(table.concat(vim.fn.readfile(source .. "/.gitignore"), "\n"):find("nvim.log", 1, true))
	local check = root .. "/check.lua"
	write(
		check,
		[[
dofile(assert(vim.env.FLASH_ANY_SOURCE_ROOT) .. "/minimal.lua")
assert(vim.fn.maparg("s", "n") ~= "", "minimal configuration did not install the real keymap")
local book = require("flash-any.native").load(nil, { "mycodes" })
assert(#book:new_state():scan(0,0,1,1,1,{"中 重"},"zhong",nil) == 2)
assert(#book:new_state():scan(0,0,1,1,1,{"中文 with flash"},"zhongwen with flash",nil) == 1)
]]
	)
	-- The smoke test is deliberately launched outside the core and source roots.
	local minimal = vim.tbl_extend("force", env, { FLASH_ANY_ROOT = project })
	local result = vim.system({ vim.v.progpath, "--clean", "-l", check }, { cwd = root, env = minimal, text = true })
		:wait()
	assert(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
	run({ "sh", "-eu", "-c", block(guide, "sh", 'mkdir -p "$FLASH_ANY_SOURCE_ROOT/docs"') })
	local function prepare()
		run({
			vim.v.progpath,
			"--clean",
			"--cmd",
			"lua vim.opt.runtimepath:prepend(" .. vim.json.encode(project) .. ")",
			"-l",
			project .. "/demos/prepare-table.lua",
			source .. "/demo.lua",
		}, root)
		local config = vim.json.decode(table.concat(vim.fn.readfile(root .. "/demos/output/table-config.json"), "\n"))
		assert(config.stages[1].pattern == "zhong" and config.stages[2].pattern == "zhongwen with flash")
		assert(config.stages[1].matches >= 2 and config.stages[2].matches >= 1)
		return config
	end
	prepare()
	-- Test the exact factory-reuse example with a codetable factory first.
	write(source .. "/demo.lua", block(guide, "lua", "-- demo.lua: reuse the source factory"))
	prepare()
	-- Then test a file factory whose converter returns Unicode group names.
	write(
		source .. "/lua/flash-any/sources/mycodes.lua",
		[[
return function()
  return {
    file=assert(vim.api.nvim_get_runtime_file("lua/flash-any/tables/mycodes.tsv", false)[1]),
    converter=assert(vim.api.nvim_get_runtime_file("lua/flash-any/converter.lua", false)[1]),
    groups={["中"]={"zhong","zong"},["文"]={"wen"},["重"]={"chong"}},
    matcher="full_code",
  }
end
]]
	)
	write(
		source .. "/lua/flash-any/converter.lua",
		[[
return function(codes)
  local names={zhong="中",wen="文",chong="重"}
  local result={}
  for i, code in ipairs(codes) do result[i]=assert(names[code]) end
  return result
end
]]
	)
	local configured = prepare()
	assert(configured.sources[1].converter and configured.sources[1].groups["中"][2] == "zong")
	local book = require("flash-any.native").load(configured.binary)
	assert(#book:new_state():scan(0, 0, 1, 1, 1, { "中文" }, "zongwen", nil) == 1)
	local workflow = table.concat(vim.fn.readfile(source .. "/.github/workflows/demo.yml"), "\n")
	assert(workflow:find("table-demo.yml@main", 1, true) and workflow:find("flash-any-ref: main", 1, true))
	assert(workflow:find("table-ref: ${{ github.sha }}", 1, true))
	for _, name in ipairs({ "README.md", "README.en.md" }) do
		local readme = table.concat(vim.fn.readfile(source .. "/" .. name), "\n")
		assert(readme:find("releases/download/demos/table.gif", 1, true))
		assert(readme:find("releases/download/demos/table.mp4", 1, true))
		assert(readme:find("releases/download/demos/table-verification.json", 1, true))
		assert(not readme:find("](demos/output/", 1, true), "public README must not embed ignored local media")
		assert(not readme:find('dir = "/', 1, true), "public README must not install from the author's checkout")
	end
	vim.fn.delete(root, "rf")
	print("source tutorial commands passed: " .. document)
end

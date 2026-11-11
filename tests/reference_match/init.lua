#!/usr/bin/env -S nvim -l
package.path = vim.uv.cwd() .. "/tests/?.lua;" .. package.path

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:prepend(vim.uv.cwd() .. "/.dev/flash.nvim")

local matcher = require("reference.match")
local tables = require("reference.table")
local registry = require("reference.source")
local function load(name, opts)
	local source = registry.load(name, opts)
	-- File-only factories declare build inputs rather than eagerly loaded data.
	return rawget(source, "file")
			and require("flash-any.source").resolve({ vim.tbl_extend("force", { name = name }, opts or {}) })[2].data
		or source.data
end
local codetable = require("reference.codetable")
local literal = require("reference.literal")()
local literal_source =
	{ name = "literal", matcher = literal.matcher, scope = require("reference.scope").resolve(literal.scope) }

local function check(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		error(name .. ": " .. err)
	end
	print("ok - " .. name)
end

local function run(text, pattern, map, state)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
	state = state or {
		pattern = function()
			return pattern
		end,
	}
	return matcher.get(
		0,
		state,
		{ from = { 1, 0 }, to = { 2, 0 } },
		{ literal_source, { data = map, matcher = codetable.full_code } }
	)
end

check("literal source matches ASCII", function()
	local matches = run("abc", "ab", {})
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 1)
end)

check("empty source list matches nothing", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
	assert(#matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {}) == 0)
end)

check("utf8 positions", function()
	local matches = run("a中b", "z", { ["中"] = { "z" } })
	assert(#matches == 1 and matches[1].pos[2] == 1 and matches[1].end_pos[2] == 1)
end)

check("punctuation and emoji use configured encodings", function()
	local map = { ["，"] = { "p" }, ["😀"] = { "e" } }
	local matches = run("，😀", "e", map)
	assert(#matches == 1 and matches[1].pos[2] == 3 and matches[1].end_pos[2] == 3)
	matches = run("，😀", "p", map)
	assert(#matches == 1 and matches[1].pos[2] == 0)
end)

check("invalid utf8 preserves following characters", function()
	for _, bytes in ipairs({ { 0x80 }, { 0xC2 }, { 0xE4, 0xB8 }, { 0xF0, 0x9F, 0x98 }, { 0xFE }, { 0xFF } }) do
		local invalid = string.char(unpack(bytes))
		local matches = run("a" .. invalid .. "b中😀", "bze", { ["中"] = { "z" }, ["😀"] = { "e" } })
		local col = 1 + #invalid
		assert(#matches == 1 and matches[1].pos[2] == col and matches[1].end_pos[2] == col + 4)
	end
end)

check("literal rejects non-ASCII characters and input", function()
	for _, char in ipairs({ "中", "😀", string.char(0xE4) }) do
		assert(#run(char, char, {}) == 0)
	end
end)

check("literal and code-table sources can both recognize ASCII", function()
	assert(#run("a", "x", { a = { "x" } }) == 1)
	assert(#run("a", "a", { a = { "x" } }) == 1)
end)

check("literal success does not skip later ordinary sources", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
	local calls = 0
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		literal_source,
		{
			matcher = function(_, _, _, emit)
				calls = calls + 1
				emit("z")
				return true
			end,
		},
	})
	assert(#matches == 1 and matches[1].next.z and calls == 1)
end)

check("literal recognizes ASCII mismatch and blocks later fallback", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
	local matches = matcher.get(0, {
		pattern = function()
			return "x"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		literal_source,
		{
			matcher = function()
				error("literal recognizes ASCII")
			end,
			fallback = true,
		},
	})
	assert(#matches == 0)
end)

check("non-ASCII characters remain available to later fallback sources", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "α" })
	local matches = matcher.get(0, {
		pattern = function()
			return "alpha"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		literal_source,
		{ data = { ["α"] = { "alpha" } }, matcher = codetable.prefix, fallback = true },
	})
	assert(#matches == 1 and matches[1].pos[2] == 0)
end)

check("literal and code-table input can mix", function()
	local matches = run("a国", "ag", { ["国"] = { "guo" } })
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 1 and matches[1].next.u)
end)

check("mixed literal and code-table input remains incremental", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a国" })
	local value, calls = "a", {}
	local state = {
		pattern = function()
			return value
		end,
	}
	local sources = {
		literal_source,
		{
			data = { ["国"] = { "guo" } },
			matcher = function(text, stream, args, emit)
				local char = text:get(1)
				calls[#calls + 1] = char
				return codetable.full_code(text, stream, args, emit)
			end,
		},
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	assert(#matcher.get(0, state, opts, sources) == 1)
	calls = {}
	value = "ag"
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == 1 and matches[1].end_pos[2] == 1 and matches[1].next.u)
	assert(vim.deep_equal(calls, { "国" }))
end)

check("starting keys combine eligible sources", function()
	local matches = run("甲a", "x", { ["甲"] = { "x" }, a = { "z" } })
	assert(#matches == 1 and matches[1].next.a and matches[1].next.z)
end)

check("multiple codes", function()
	local matches = run("行", "xk", { ["行"] = { "xk", "h" } })
	assert(#matches == 1)
end)

check("initial matcher", function()
	local matches = run("中国", "v", { ["中"] = { "vs" }, ["国"] = { "go" } })
	-- default source matcher is full_code; configure the source directly below
	matches = matcher.get(0, {
		pattern = function()
			return "v"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = { ["中"] = { "vs" } }, matcher = codetable.initial },
	})
	assert(#matches == 1)
end)

check("prefix matcher advances", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国" })
	local matches = matcher.get(0, {
		pattern = function()
			return "vsg"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = { ["中"] = { "vscode" }, ["国"] = { "go" } }, matcher = codetable.prefix },
	})
	assert(#matches >= 1)
end)

check("variable code continues and advances", function()
	local matches = run("甲乙", "ab", { ["甲"] = { "a" }, ["乙"] = { "b" } })
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 3)
end)

check("same end keeps longest start", function()
	local matches = run("甲甲", "aa", { ["甲"] = { "a", "aa" } })
	assert(#matches == 2)
	local seen = {}
	for _, match in ipairs(matches) do
		local key = match.end_pos[2]
		assert(not seen[key])
		seen[key] = true
		assert(match.pos[2] == 0)
	end
end)

check("equal streams merge before invoking the following matcher", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
	local calls = 0
	local sources = {
		{
			data = { ["甲"] = { "a" }, ["乙"] = { "a", "aa" }, ["丙"] = { "a" } },
			matcher = function(text, stream, args, emit)
				local char = text:get(1)
				if char == "丙" and stream:get() == "a" then
					calls = calls + 1
				end
				return codetable.full_code(text, stream, args, emit)
			end,
		},
	}
	local matches = matcher.get(0, {
		pattern = function()
			return "aaa"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, sources)
	assert(calls == 1)
	assert(#matches == 2 and matches[1].pos[2] == 0 and matches[2].pos[2] == 0)
end)

check("same endpoint merges next but preserves different continuation streams", function()
	for _, case in ipairs({
		{ codes = { "b", "abx" }, x_start = 3, c_start = 0 },
		{ codes = { "bx", "ab" }, x_start = 0, c_start = 3 },
	}) do
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
		local sources =
			{ { data = { ["甲"] = { "a" }, ["乙"] = case.codes, ["丙"] = { "c" } }, matcher = codetable.full_code } }
		local value = "ab"
		local state = {
			pattern = function()
				return value
			end,
		}
		local opts = { from = { 1, 0 }, to = { 1, 0 } }
		local matches = matcher.get(0, state, opts, sources)
		assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 3)
		assert(matches[1].next.c and matches[1].next.x)
		value = "abx"
		matches = matcher.get(0, state, opts, sources)
		assert(#matches == 1 and matches[1].pos[2] == case.x_start and matches[1].end_pos[2] == 3)
		value = "ab"
		matcher.get(0, state, opts, sources)
		value = "abc"
		matches = matcher.get(0, state, opts, sources)
		assert(#matches == 1 and matches[1].pos[2] == case.c_start and matches[1].end_pos[2] == 6)
	end
end)

check("input append reuses cached line text", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
	local value = "a"
	local state = {
		pattern = function()
			return value
		end,
	}
	local opts, sources = { from = { 1, 0 }, to = { 1, 0 } }, { literal_source }
	local first = matcher.get(0, state, opts, sources)
	local lines = state._flash_any_cache[0].lines
	assert(lines[1].value == "abc")
	value = "ab"
	local second = matcher.get(0, state, opts, sources)
	assert(#first == 1 and #second == 1 and second[1].end_pos[2] == 1)
	assert(state._flash_any_cache[0].lines == lines)
end)

if #vim.api.nvim_get_runtime_file("lua/flash-any/sources/pinyin.lua", false) > 0 then
	check("lazy schemes", function()
		local flypy = load("pinyin", { scheme = "flypy" })
		local pinyin = load("pinyin")
		local pyjj = load("pinyin", { scheme = "pyjj" })
		local natural = load("pinyin", { scheme = "natural" })
		local abc = load("pinyin", { scheme = "abc" })
		local mspy = load("pinyin", { scheme = "mspy" })
		local st = load("pinyin", { scheme = "st" })
		local tiger = load("tiger")
		assert(flypy["中"] and pinyin["中"] and pyjj["中"] and tiger["的"])
		assert(pinyin["㐀"] and pinyin["㐀"][1] == "qiu")
		assert(flypy["㐀"] and flypy["㐀"][1] == "qq")
		local schemes = require("flash-any.pinyin.schemes")
		assert(schemes.flypy.initials and schemes.flypy.finals)
		assert(schemes.pyjj.initials and schemes.pyjj.finals)
		assert(vim.deep_equal(flypy["中"], { "vs" }))
		assert(vim.deep_equal(pyjj["中"], { "vs" }))
		assert(vim.deep_equal(natural["中"], { "vs" }))
		assert(vim.deep_equal(abc["中"], { "as" }))
		assert(vim.deep_equal(mspy["中"], { "vs" }))
		assert(vim.deep_equal(st["中"], { "ay" }))
		assert(vim.deep_equal(flypy["爱"], { "ai" }))
		assert(vim.deep_equal(pyjj["爱"], { "as" }))
		assert(vim.deep_equal(pyjj["学"], { "xt" }))
		assert(vim.deep_equal(pyjj["光"], { "gl" }))
		local fuzzy = load("pinyin", { scheme = "flypy", fuzzy = { initials = { { "zh", "z" } } } })
		assert(vim.deep_equal(fuzzy["中"], { "vs", "zs" }))
	end)
end

check("cjk lazy source", function()
	local calls = 0
	local lazy = require("reference.table").lazy({}, function(char)
		if char == "甲" then
			calls = calls + 1
			return { "a" }
		end
	end)
	local source = { { data = lazy, matcher = codetable.full_code } }
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, source)
	assert(calls == 0)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, source)
	assert(#matches == 1 and calls == 1)
	assert(lazy["甲"] and lazy["甲"][1] == "a")
end)

check("matcher scope avoids lazy lookup", function()
	local calls = 0
	local data = tables.lazy({}, function()
		calls = calls + 1
		return { "a" }
	end)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
	matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, {
		{
			data = data,
			matcher = function(text, stream, args, emit)
				local char = text:get(1)
				if char ~= "甲" then
					return false
				end
				return codetable.full_code(text, stream, args, emit)
			end,
		},
	})
	assert(calls == 0)
end)

check("source priority can stop later tables", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local state = {
		pattern = function()
			return "x"
		end,
	}
	local matches = matcher.get(0, state, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = { ["甲"] = { "x" } }, matcher = codetable.full_code },
		{ data = { ["甲"] = { "x" } }, matcher = codetable.full_code, fallback = true },
	})
	assert(#matches == 1)
	matches = matcher.get(0, {
		pattern = function()
			return "y"
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = {}, matcher = codetable.full_code },
		{ data = { ["甲"] = { "y" } }, matcher = codetable.full_code, fallback = true },
	})
	assert(#matches == 1)
end)

check("matcher owns next", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local custom = function(_, stream, _, emit)
		if stream:get() == "" then
			emit("z")
			return true
		end
		if stream:get() == "x" then
			emit("z")
			return true
		end
		return true
	end
	local state = {
		pattern = function()
			return "x"
		end,
		labels = function()
			return { "z", "a" }
		end,
	}
	local matches = matcher.get(0, state, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = { ["甲"] = { "x" } }, matcher = custom },
	})
	assert(#matches == 1 and matches[1].next.z and matches[1].label == "a")
end)

check("custom matcher owns consumption without a code table", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中国" })
	local received
	local source = {
		matcher = function(text, stream, _, emit)
			local char = text:get(1)
			if char == "中" and stream:get() == "zhongg" then
				emit(5)
				return true
			end
			if char == "国" and stream:get() == "g" then
				received = stream:get()
				emit("u")
				return true
			end
			return true
		end,
	}
	local matches = matcher.get(0, {
		pattern = function()
			return "zhongg"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, { source })
	assert(received == "g" and #matches == 1)
	assert(matches[1].pos[2] == 0 and matches[1].end_pos[2] == 3 and matches[1].next.u)
end)

check("custom consumption branches keep distinct ranges", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
	local sources = {
		{
			matcher = function(text, stream, _, emit)
				local char = text:get(1)
				if char == "甲" and stream:get() == "abc" then
					emit(1)
					emit(2)
					return true
				end
				if char == "乙" and stream:get() == "bc" then
					emit(1)
					return true
				end
				if (char == "乙" or char == "丙") and stream:get() == "c" then
					emit("")
					return true
				end
				return true
			end,
		},
	}
	local matches = matcher.get(0, {
		pattern = function()
			return "abc"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, sources)
	assert(#matches == 2 and matches[1].pos[2] == 0 and matches[2].pos[2] == 0)
	assert(matches[1].end_pos[2] == 3 and matches[2].end_pos[2] == 6)
end)

check("outer matcher never reads source data", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local source = {
		data = setmetatable({}, {
			__index = function()
				error("outer matcher read codes")
			end,
		}),
		matcher = function(_, stream, _, emit)
			if stream:get() == "a" then
				emit("")
				return true
			end
			return true
		end,
	}
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, { source })
	assert(#matches == 1 and next(matches[1].next) == nil)
	source.matcher = function()
		return true
	end
	matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, { source })
	assert(#matches == 0)
end)

check("append retries only the unfinished character", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
	local value = "a"
	local state = {
		pattern = function()
			return value
		end,
	}
	local calls = {}
	local sources = {
		{
			matcher = function(text, stream, _, emit)
				local char = text:get(1)
				calls[#calls + 1] = { char, (stream:get()) }
				if char == "甲" and stream:get() == "a" then
					emit("b")
					return true
				end
				if char == "甲" and stream:get() == "ab" then
					emit("")
					return true
				end
				return true
			end,
		},
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	assert(#matcher.get(0, state, opts, sources) == 1)
	calls = {}
	value = "ab"
	assert(#matcher.get(0, state, opts, sources) == 1)
	assert(vim.deep_equal(calls, { { "甲", "ab" } }))
end)

check("append starts after the completed character", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
	local value = "a"
	local calls = {}
	local state = {
		pattern = function()
			return value
		end,
	}
	local sources = {
		{
			matcher = function(text, stream, _, emit)
				local char = text:get(1)
				calls[#calls + 1] = { char, (stream:get()) }
				if char == "甲" and stream:get():sub(1, 1) == "a" then
					emit(1)
					return true
				end
				if char == "乙" and stream:get() == "" then
					emit("b")
					return true
				end
				if char == "乙" and stream:get() == "b" then
					emit("")
					return true
				end
				return true
			end,
		},
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	assert(#matcher.get(0, state, opts, sources) == 1)
	calls = {}
	value = "ab"
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 3)
	assert(vim.deep_equal(calls, { { "乙", "b" } }))
end)

check("append keeps unfinished and completed alternatives", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙" })
	local value = "a"
	local state = {
		pattern = function()
			return value
		end,
	}
	local sources = { { data = { ["甲"] = { "a", "ab" }, ["乙"] = { "b" } }, matcher = codetable.full_code } }
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	assert(#matcher.get(0, state, opts, sources) == 1)
	value = "ab"
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == 2 and matches[1].end_pos[2] == 0 and matches[2].end_pos[2] == 3)
end)

check("append can consume several following characters", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙丁" })
	local value = "a"
	local state = {
		pattern = function()
			return value
		end,
	}
	local sources = {
		{
			data = { ["甲"] = { "a" }, ["乙"] = { "b" }, ["丙"] = { "c" }, ["丁"] = { "d" } },
			matcher = codetable.full_code,
		},
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	assert(#matcher.get(0, state, opts, sources) == 1)
	value = "abcd"
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == 9)
end)

check("ambiguous incremental paths agree with fresh scans", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { ("甲"):rep(12) })
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	for _, mode in ipairs({ "full_code", "initial", "prefix" }) do
		local value = ""
		local state = {
			pattern = function()
				return value
			end,
		}
		local sources = { { data = { ["甲"] = { "a", "aa", "aaa" } }, matcher = codetable[mode] } }
		for length = 1, 8 do
			value = ("a"):rep(length)
			local incremental = matcher.get(0, state, opts, sources)
			local fresh = matcher.get(0, {
				pattern = function()
					return value
				end,
			}, opts, sources)
			assert(vim.deep_equal(incremental, fresh), mode .. " " .. length)
		end
	end
end)

check("repairing invalid input bytes rebuilds custom UTF-8 matches", function()
	local invalid = string.char(0xE4)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "中" .. invalid })
	local value = invalid
	local state = {
		pattern = function()
			return value
		end,
	}
	local opts, sources =
		{ from = { 1, 0 }, to = { 1, 0 } }, { {
			matcher = function(text, stream, _, emit)
				local char = text:get(1)
				if stream:get() == "" then
					emit("")
					return true
				end
				if stream:get():sub(1, #char) == char then
					emit(#char)
					return true
				end
				return true
			end,
		} }
	local first = matcher.get(0, state, opts, sources)
	assert(#first == 1 and first[1].pos[2] == 3)
	value = "中"
	local second = matcher.get(0, state, opts, sources)
	assert(#second == 1 and second[1].pos[2] == 0)
end)

check("known character blocks fallback even when its input fails", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local matches = matcher.get(0, {
		pattern = function()
			return "b"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		{ data = { ["甲"] = { "a" } }, matcher = codetable.full_code },
		{
			matcher = function()
				error("known character reached fallback")
			end,
			fallback = true,
		},
	})
	assert(#matches == 0)
end)

check("coverage survives unknown sources and permits unconditional sources", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local matches = matcher.get(0, {
		pattern = function()
			return "b"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		{
			matcher = function()
				return true
			end,
		},
		{
			matcher = function()
				return false
			end,
		},
		{
			matcher = function()
				error("coverage was reset")
			end,
			fallback = true,
		},
		{ data = { ["甲"] = { "b" } }, matcher = codetable.full_code },
	})
	assert(#matches == 1)
end)

check("unfinished full code does not reserve following character keys", function()
	local matches = run("甲乙", "a", { ["甲"] = { "ab" }, ["乙"] = { "x" } })
	assert(#matches == 1 and matches[1].next.b and not matches[1].next.x)
end)

check("starting keys respect source coverage", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙" })
	local sources = {
		{ data = { ["甲"] = { "a" }, ["乙"] = { "b" } }, matcher = codetable.full_code },
		{ data = { ["乙"] = { "x" } }, matcher = codetable.full_code, fallback = true },
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	local first = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, opts, sources)
	assert(#first == 1 and first[1].next.b and not first[1].next.x)
	local continued = matcher.get(0, {
		pattern = function()
			return "ax"
		end,
	}, opts, sources)
	assert(#continued == 0)
	sources[1].data["乙"] = nil
	local fallback = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, opts, sources)
	assert(#fallback == 1 and fallback[1].next.x)
end)

check("one input cursor shares read caches across lines and windows", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙甲乙", "甲乙" })
	local value, slices = "ab", 0
	local state = {
		pattern = function()
			return value
		end,
	}
	local sources = {
		{
			matcher = function(text, stream, _, emit)
				local char = text:get(1)
				if char == "甲" and stream:get() == "ab" then
					emit(1)
					return true
				end
				if char == "乙" and stream:get() == "b" then
					emit("")
					return true
				end
				return true
			end,
		},
	}
	local opts = { from = { 1, 0 }, to = { 2, 0 } }
	local sub = string.sub
	rawset(string, "sub", function(str, first, last)
		if str == "ab" and first == 2 and last == nil then
			slices = slices + 1
		end
		return sub(str, first, last)
	end)
	local ok, err = pcall(function()
		assert(#matcher.get(0, state, opts, sources) == 3)
		assert(#matcher.get(vim.api.nvim_get_current_win(), state, opts, sources) == 3)
	end)
	rawset(string, "sub", sub)
	assert(ok, err)
	local cursor = state._flash_any_stream
	assert(slices == 1 and cursor.value == "ab")
	cursor:set_offset(1)
	assert(cursor:get() == "b" and slices == 1)
	value = "ac"
	matcher.get(0, state, opts, sources)
	assert(state._flash_any_stream ~= cursor and state._flash_any_stream.value == "ac")
end)

check("merge next for same extmark", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
		labels = function()
			return { "x", "y", "z" }
		end,
	}, { from = { 1, 0 }, to = { 2, 0 } }, {
		{ data = { ["甲"] = { "ax", "ay" } }, matcher = codetable.full_code },
	})
	assert(#matches == 1 and matches[1].next.x and matches[1].next.y and matches[1].label == "z")
end)

check("same code keeps next from each source", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲" })
	local sources = {}
	for _, label in ipairs({ "x", "y" }) do
		sources[#sources + 1] = {
			data = { ["甲"] = { "a" } },
			matcher = function(_, _, _, emit)
				emit(label)
				return true
			end,
		}
	end
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, sources)
	assert(#matches == 1 and matches[1].next.x and matches[1].next.y)
end)

check("empty-stream lookahead runs once per source", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙" })
	local calls = 0
	local matches = matcher.get(0, {
		pattern = function()
			return "a"
		end,
	}, { from = { 1, 0 }, to = { 1, 0 } }, {
		{ data = { ["甲"] = { "a" } }, matcher = codetable.full_code },
		{
			data = { ["乙"] = { "bx", "by", "bz" } },
			matcher = function(_, stream, _, emit)
				if stream:get() == "" then
					calls = calls + 1
					emit("b")
					return true
				end
				return true
			end,
		},
	})
	assert(#matches == 1 and matches[1].next.b and calls == 1)
end)

check("same pattern reuses scan and refreshes labels", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙" })
	local calls = 0
	local sources = {
		{
			data = { ["甲"] = { "a" }, ["乙"] = { "b" } },
			matcher = function(text, stream, args, emit)
				calls = calls + 1
				return codetable.full_code(text, stream, args, emit)
			end,
		},
	}
	local labels = { "b", "c" }
	local state = {
		pattern = function()
			return "a"
		end,
		labels = function()
			return labels
		end,
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	local first = matcher.get(0, state, opts, sources)
	assert(#first == 1 and first[1].label == "c" and calls > 0)
	local first_calls = calls
	labels = { "b", "d" }
	local second = matcher.get(0, state, opts, sources)
	assert(#second == 1 and second[1].label == "d" and calls == first_calls)
	local changed = matcher.get(0, state, opts, { { data = { ["甲"] = { "x" } }, matcher = codetable.full_code } })
	assert(#changed == 0)
end)

check("buffer identity invalidates incremental matches", function()
	local original = vim.api.nvim_get_current_buf()
	local first = vim.api.nvim_create_buf(false, true)
	local second = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(first, 0, -1, false, { "ab" })
	vim.api.nvim_buf_set_lines(second, 0, -1, false, { "ax" })
	assert(vim.api.nvim_buf_get_changedtick(first) == vim.api.nvim_buf_get_changedtick(second))
	local value = "a"
	local state = {
		pattern = function()
			return value
		end,
	}
	local opts, sources = { from = { 1, 0 }, to = { 1, 0 } }, { literal_source }
	vim.api.nvim_win_set_buf(0, first)
	assert(#matcher.get(0, state, opts, sources) == 1)
	vim.api.nvim_win_set_buf(0, second)
	value = "ab"
	assert(#matcher.get(0, state, opts, sources) == 0)
	vim.api.nvim_win_set_buf(0, original)
	vim.api.nvim_buf_delete(first, { force = true })
	vim.api.nvim_buf_delete(second, { force = true })
end)

check("exclude next labels globally", function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abacadaf" })
	local labels = { "a", "b", "c", "d", "e", "f", "g" }
	local state = {
		pattern = function()
			return "a"
		end,
		labels = function()
			return labels
		end,
	}
	local matches = matcher.get(0, state, { from = { 1, 0 }, to = { 2, 0 } }, {
		literal_source,
		{ data = {}, matcher = codetable.full_code },
	})
	assert(#matches == 4)
	local used = {}
	for _, item in ipairs(matches) do
		if item.label then
			assert(not item.next[item.label])
			assert(not used[item.label])
			used[item.label] = true
		end
	end
	assert(not used.b and not used.c and not used.d and not used.f)
end)

check("grapheme spans cover final codepoints and never visit internal positions", function()
	local Cursor = require("reference.cursor")
	local value = "á👩🏽‍💻🇨🇳1️⃣💻"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { value })
	local starts, expected =
		{}, { 0, #"á", #"á👩🏽‍💻", #"á👩🏽‍💻🇨🇳", #"á👩🏽‍💻🇨🇳1️⃣" }
	local sources = {
		{
			matcher = function(text, _, _, emit)
				starts[text.offset] = true
				emit(1)
				return true
			end,
		},
	}
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	local state = {
		pattern = function()
			return "x"
		end,
	}
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == #expected and vim.tbl_count(starts) == #expected)
	local text = Cursor.new(value)
	for i, col in ipairs(expected) do
		assert(starts[col] and matches[i].pos[2] == col)
		text:set_offset(col)
		local _, _, last = text:get(1)
		assert(matches[i].end_pos[2] == last)
	end
	starts = {}
	local chars = matcher.char(0, state, opts, sources)
	assert(#chars == #expected and vim.tbl_count(starts) == #expected)
	for i, col in ipairs(expected) do
		assert(chars[i].pos[2] == col and chars[i].end_pos[2] == col)
	end
end)

check("grapheme words agree across fresh, incremental, deleted and replaced input", function()
	local value = "👩‍💻á👩‍💻💻1️⃣"
	local data = tables.normalize({
		codes = {
			["👩‍💻"] = "dev",
			["👩‍💻á"] = "word",
			["á"] = "accent",
			["💻"] = "pc",
			["1️⃣"] = "one",
		},
		prefixes = { ["👩‍💻"] = true },
		max_chars = 2,
	})
	local sources = {
		literal_source,
		{
			data = data,
			matcher = codetable.full_code,
			scope = require("reference.scope").resolve({
				["👩‍💻"] = true,
				["á"] = true,
				["💻"] = true,
				["1️⃣"] = true,
			}),
		},
	}
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { value })
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	local query = "d"
	local state = {
		pattern = function()
			return query
		end,
	}
	for _, input in ipairs({ "d", "de", "dev", "deva", "devaccent", "word", "wordd", "worddev", "pc", "one", "1", "d" }) do
		query = input
		assert(
			vim.deep_equal(
				matcher.get(0, state, opts, sources),
				matcher.get(0, {
					pattern = function()
						return input
					end,
				}, opts, sources)
			),
			input
		)
	end
	query = "word"
	local matches = matcher.get(0, state, opts, sources)
	assert(#matches == 1 and matches[1].pos[2] == 0 and matches[1].end_pos[2] == #"👩‍💻a")
	query = "pc"
	matches = matcher.get(0, state, opts, sources)
	assert(#matches == 1 and matches[1].pos[2] == #"👩‍💻á👩‍💻")
	query = "1"
	assert(#matcher.get(0, state, opts, sources) == 0)
	local cached = state._flash_any_cache[0].lines[1]
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "💻" })
	query = "pc"
	assert(#matcher.get(0, state, opts, sources) == 1 and state._flash_any_cache[0].lines[1] ~= cached)
end)

check("input appends that merge graphemes rebuild continuation states", function()
	local opts = { from = { 1, 0 }, to = { 1, 0 } }
	local sources = {
		{
			matcher = function(_, stream, _, emit)
				local input, after = stream:get(1)
				if after then
					emit(#input)
				else
					emit("")
				end
				return true
			end,
		},
	}
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "甲乙丙" })
	for _, inputs in ipairs({
		{ "a", "á", "áb" },
		{ "👩", "👩‍", "👩‍💻", "👩‍💻x" },
		{ "🇨", "🇨🇳", "🇨🇳🇺", "🇨🇳🇺🇸" },
	}) do
		local query
		local state = {
			pattern = function()
				return query
			end,
		}
		for _, input in ipairs(inputs) do
			query = input
			assert(
				vim.deep_equal(
					matcher.get(0, state, opts, sources),
					matcher.get(0, {
						pattern = function()
							return input
						end,
					}, opts, sources)
				),
				input
			)
		end
	end
end)

print("all matcher tests passed")

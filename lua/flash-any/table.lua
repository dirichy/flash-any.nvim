local M = {}
local utf8 = require("flash-any.utf8")

-- 码表统一为 UTF-8 字符 → ASCII 编码数组；同一字符可有多个编码。
---@alias FlashAnyTable table<string, string[]>

---在 data 原表上添加按字符懒加载；查询结果和未命中（false）都缓存在原表。
---@param data FlashAnyTable
---@param loader fun(char: string): string[]?
---@return FlashAnyTable
function M.lazy(data, loader)
	return setmetatable(data, {
		__index = function(self, char)
			local value = loader(char)
			rawset(self, char, value or false)
			return value
		end,
	})
end

---为短于 max_length 的编码追加空格，实现短码按空格顶出；返回新数组。
---@param codes string[]?
---@param max_length integer
---@return string[]?
local function pad_codes(codes, max_length)
	if not codes then
		return nil
	end
	local ret = {}
	for _, code in ipairs(codes) do
		ret[#ret + 1] = #code < max_length and code .. " " or code
	end
	return ret
end

---应用顶功策略；未启用时返回原表，启用时创建独立码表并保留懒加载。
---@param data FlashAnyTable
---@param opts table?
---@return FlashAnyTable
function M.apply_strategy(data, opts)
	if not opts or opts.strategy == nil then
		return data
	end
	-- data may be a shared default cache; keep transformed arrays separate.
	assert(opts.strategy == "top_force", "unknown code-table strategy: " .. tostring(opts.strategy))
	local max_length = opts.max_length
	assert(type(max_length) == "number" and max_length > 0 and max_length % 1 == 0,
		"top_force requires a positive integer max_length")
	local ret = {}
	for char, codes in pairs(data) do
		ret[char] = pad_codes(codes, max_length)
	end
	return M.lazy(ret, function(char)
		return pad_codes(data[char], max_length)
	end)
end

---把单编码字符串转为数组，并复制 map 和数组，避免修改调用方或 require 缓存。
---@param map table<string, string|string[]>
---@return FlashAnyTable
function M.normalize(map)
	local ret = {}
	for char, codes in pairs(map) do
		assert(type(char) == "string", "code-table keys must be UTF-8 characters")
		local iter, str, offset = utf8.iter_offset(char)
		assert(iter(str, offset) == #char, "code-table key must be one character: " .. char)
		if type(codes) == "string" then
			ret[char] = { codes }
		else
			assert(type(codes) == "table" and vim.islist(codes), "codes must be a string or array: " .. char)
			ret[char] = vim.deepcopy(codes)
		end
		for _, code in ipairs(ret[char]) do
			assert(type(code) == "string" and #code > 0 and not code:find("[\128-\255]"),
				"codes must be nonempty ASCII strings: " .. char)
		end
	end
	return ret
end

local pinyin_parts = require("flash-any.table.pinyin_parts")

---拆分 TSV 值列中用逗号分隔的 ASCII 编码；这里不处理 CSV 引号语法。
---@param value string
---@return string[]
local function csv(value)
	local ret = {}
	for item in value:gmatch("[^,]+") do
		ret[#ret + 1] = item
	end
	return ret
end

---加载内置常用字 Lua 表，附加全字集 TSV 懒加载；两者共用 convert，缓存转换后的编码。
---@param name string 码表文件名，不含扩展名
---@param convert? fun(codes: string[]?): string[]?
---@return FlashAnyTable
local function file_source(name, convert)
	-- require() is shared; this private copy can be transformed in place.
	local common = M.normalize(require("flash-any.table." .. name))
	if convert then
		for char, codes in pairs(common) do
			common[char] = convert(codes)
		end
	end
	local files = vim.api.nvim_get_runtime_file("lua/flash-any/table/" .. name .. ".tsv", false)
	local full_path = files[1]
	if not full_path then
		return common
	end
	local decode = csv
	if convert then
		decode = function(value)
			return convert(csv(value)) or {}
		end
	end
	local lookup = require("flash-any.tsv").loader(full_path, { decode = decode })
	return M.lazy(common, lookup)
end

---加载用户指定的 Lua 码表，复制后按需挂接 TSV；不复用内置方案缓存。
---@param lua_path string
---@param tsv_path string?
---@return FlashAnyTable
function M.from_files(lua_path, tsv_path)
	local common = M.normalize(dofile(vim.fn.expand(lua_path)))
	if not tsv_path then
		return common
	end
	local lookup = require("flash-any.tsv").loader(tsv_path, { decode = csv })
	return M.lazy(common, lookup)
end

local default_fuzzy = {
	initials = { { "zh", "z" }, { "ch", "c" }, { "sh", "s" } },
	finals = { { "ang", "an" }, { "eng", "en" }, { "ing", "in" } },
}

---把分组索引为“声母/韵母 → 候选数组”；重叠时保留第一个分组，未分组仅保留自身。
---@param groups? string[][]
---@param parts table<string, string> 音节到声母或韵母的映射
---@return table<string, string[]>
local function fuzzy_index(groups, parts)
	assert(groups == nil or (type(groups) == "table" and vim.islist(groups)), "fuzzy groups must be arrays")
	local ret = {}
	for _, group in ipairs(groups or {}) do
		assert(type(group) == "table" and vim.islist(group), "each fuzzy group must be an array")
		for _, value in ipairs(group) do
			assert(type(value) == "string" and not value:find("[\128-\255]"), "fuzzy components must be ASCII strings")
			if not ret[value] then
				ret[value] = group
			end
		end
	end
	for _, value in pairs(parts) do
		if not ret[value] then
			ret[value] = { value }
		end
	end
	return ret
end

---从统一拼音表生成全拼或双拼码表；模糊音先展开，再按方案转换键位。
---opts.scheme 省略时使用全拼；不启用模糊音的全拼直接加载原表。
---@param opts? table scheme 选择双拼方案，fuzzy 控制声母、韵母的模糊音分组。
---@return FlashAnyTable
local function from_pinyin(opts)
	local scheme = opts and opts.scheme
	local fuzzy = opts and opts.fuzzy
	assert(fuzzy == nil or type(fuzzy) == "boolean" or type(fuzzy) == "table", "fuzzy must be a boolean or table")
	if not scheme and not fuzzy then
		return file_source("pinyin")
	end
	local rules = scheme
		and assert(require("flash-any.table.schemes")[scheme], "unknown pinyin scheme: " .. tostring(scheme))
	local groups
	if fuzzy == true then
		groups = default_fuzzy
	elseif type(fuzzy) == "table" then
		groups = fuzzy
	end
	-- 分组只读；本次加载构建反向索引，常用字和懒加载生僻字共用。
	local initial_index = fuzzy_index(groups and groups.initials, pinyin_parts.initial)
	local final_index = fuzzy_index(groups and groups.finals, pinyin_parts.final)
	---把一个字符的所有读音转为最终编码，供常用字和 TSV 解码共用。
	---@param syllables? string[]
	---@return string[]? 无可用编码时返回 nil。
	local function convert(syllables)
		if not syllables then
			return nil
		end
		local ret = {}
		for _, syllable in ipairs(syllables) do
			local direct = rules and rules.syllables and rules.syllables[syllable]
			if direct then
				-- Zero-initial and scheme-specific exceptions take precedence.
				vim.list_extend(ret, direct)
			else
				-- 拆音表覆盖内置拼音的全部音节，直接查询 ASCII 声母、韵母。
				local initial, final = pinyin_parts.initial[syllable], pinyin_parts.final[syllable]
				for _, initial_variant in ipairs(initial_index[initial]) do
					if not rules then
						for _, final_variant in ipairs(final_index[final]) do
							ret[#ret + 1] = initial_variant .. final_variant
						end
					else
						for _, first in ipairs(rules.initials[initial_variant] or {}) do
							for _, final_variant in ipairs(final_index[final]) do
								for _, last in ipairs(rules.finals[final_variant] or {}) do
									ret[#ret + 1] = first .. last
								end
							end
						end
					end
				end
			end
		end
		return #ret > 0 and ret or nil
	end
	return file_source("pinyin", convert)
end

-- 注册时只创建函数，调用 load 时才加载所选码表。
local loaders = {
	pinyin = from_pinyin,
	tiger = function()
		return file_source("tiger")
	end,
	wubi86 = function()
		return file_source("wubi86")
	end,
	unicode = function()
		return file_source("unicode")
	end,
	nerdfont = function()
		return file_source("nerdfont")
	end,
}
-- 只缓存不带 opts 的默认码表；自定义选项每次创建独立实例。
local cache = {}

---按 source 名称加载码表，默认 pinyin；无 opts 时复用缓存，有 opts 时独立构建并应用策略。
---@param name? string
---@param opts? table scheme、fuzzy、strategy、max_length 等加载选项。
---@return FlashAnyTable
function M.load(name, opts)
	name = name or "pinyin"
	if not loaders[name] then
		error("unknown flash-any table: " .. tostring(name))
	end
	if opts then
		assert(not opts.scheme or name == "pinyin", "scheme is only supported by the pinyin source")
		return M.apply_strategy(loaders[name](opts), opts)
	end
	cache[name] = cache[name] or loaders[name]()
	return cache[name]
end

---返回已注册的 source 名称，不触发任何码表加载；结果不保证排序。
---@return string[]
function M.available()
	return vim.tbl_keys(loaders)
end

return M

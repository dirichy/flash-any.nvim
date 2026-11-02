local tables = require("flash-any.table")
local pinyin_parts = require("flash-any.tables.pinyin_parts")
local punctuation = require("flash-any.tables.punctuation")

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
---@return FlashAnySourceDefinition
return function(opts)
  local scheme = opts and opts.scheme
  local fuzzy = opts and opts.fuzzy
  assert(fuzzy == nil or type(fuzzy) == "boolean" or type(fuzzy) == "table", "fuzzy must be a boolean or table")
  if not scheme and not fuzzy then
    return { data = tables.load("pinyin", { extra = punctuation }), matcher = "initial", scope = "chinese" }
  end
  local rules = scheme
    and assert(require("flash-any.tables.schemes")[scheme], "unknown pinyin scheme: " .. tostring(scheme))
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
  return {
    data = tables.load("pinyin", { convert = convert, extra = punctuation }),
    matcher = scheme and "full_code" or "initial",
    scope = "chinese",
  }
end

-- Copy to lua/flash-any/sources/SOURCE.lua and replace SOURCE with the source name.
-- 复制到 lua/flash-any/sources/SOURCE.lua，将 SOURCE 换成 source 名称。
-- Complete data belongs in lua/flash-any/tables/SOURCE.tsv (text<Tab>code).
-- 完整码表放在同名 TSV 中，每行一个字素和一个编码，多编码重复写行。
return function()
	return {
		codetable = "SOURCE",
		matcher = "full_code", -- Keep demo.lua's matcher consistent / 与 demo.lua 的模式一致。
	}
end

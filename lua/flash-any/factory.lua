local M = {}

---@type table<string, {factory: fun(opts: table): FlashAnySourceDefinition, version: string|number}>
local cache = {}

---Load the module declaration once, preserving the optional second return value.
---Do not call the factory here: cache checks must not construct dictionaries.
---@param name string
---@return fun(opts: table): FlashAnySourceDefinition
---@return string|number
function M.load(name)
	if not cache[name] then
		local module = "flash-any.sources." .. name
		local path = vim.api.nvim_get_runtime_file("lua/flash-any/sources/" .. name .. ".lua", false)[1]
		local loader = package.preload[module] or (path and assert(loadfile(path)))
		assert(loader, "source '" .. name .. "' is not installed; load its source plugin before setup")
		local factory, version = loader(module)
		assert(type(factory) == "function", "source module must return a factory: " .. name)
		version = version == nil and 0 or version
		assert(
			(type(version) == "string" and version ~= "")
				or (type(version) == "number" and version == version and math.abs(version) ~= math.huge),
			"source version must be a nonempty string or a finite number: " .. name
		)
		cache[name] = { factory = factory, version = version }
		package.loaded[module] = factory
	end
	return cache[name].factory, cache[name].version
end

return M

---File identity for automatic dictionary caches; no file contents are read.
---@param path string
---@return string
return function(path)
	assert(type(path) == "string", "dependency must be a file path")
	path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local stat = assert(vim.uv.fs_stat(path), "missing dependency: " .. path)
	assert(stat.type == "file", "dependency must be a file: " .. path)
	return table.concat({ path, stat.size, stat.mtime.sec, stat.mtime.nsec }, "\n")
end

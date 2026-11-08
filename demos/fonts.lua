-- Fontconfig exposes the character maps of the fonts in the renderer's fallback chain.
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local family
for _, line in ipairs(vim.fn.readfile(directory .. "/common/style.tape")) do
	family = family or line:match('^Set FontFamily "(.-)"$')
end
assert(family, "missing FontFamily in demos/common/style.tape")
assert(vim.fn.executable("fc-match") == 1, "install fontconfig (fc-match) to prepare demos")
local result = vim.system(
	{ "fc-match", "-s", "-f", "%{file}\t%{index}\t%{family}\t%{charset}\n", family },
	{ text = true }
)
	:wait()
assert(result.code == 0, result.stderr)
local function ranges_for(charset)
	local ranges = {}
	for item in charset:gmatch("%S+") do
		local first_hex, last_hex = item:match("^(%x+)%-(%x+)$")
		local first, last = tonumber(first_hex or item, 16), tonumber(last_hex or item, 16)
		assert(first and last and first <= last, "invalid Fontconfig charset range")
		ranges[#ranges + 1] = { first, last }
	end
	table.sort(ranges, function(a, b)
		return a[1] < b[1]
	end)
	return ranges
end
local fonts = {}
for line in result.stdout:gmatch("[^\n]+") do
	local file, index, name, charset = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
	if file and vim.fn.filereadable(file) == 1 then
		fonts[#fonts + 1] = { file = file, index = tonumber(index), family = name, ranges = ranges_for(charset) }
	end
end
assert(#fonts > 0, "no readable fonts in the Fontconfig fallback chain")
local function contains(ranges, scalar)
	local low, high = 1, #ranges
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local range = ranges[middle]
		if scalar < range[1] then
			high = middle - 1
		elseif scalar > range[2] then
			low = middle + 1
		else
			return true
		end
	end
	return false
end
local function covers(font, scalars)
	for _, scalar in ipairs(scalars) do
		if not contains(font.ranges, scalar) then
			return false
		end
	end
	return #scalars > 0
end
assert(vim.fn.executable("fc-query") == 1, "install fontconfig (fc-query) to verify font files")
local M = { family = family }
function M.find(text)
	local scalars = vim.fn.str2list(text)
	for _, font in ipairs(fonts) do
		if covers(font, scalars) then
			-- Confirm the actual font face, rather than trusting a possibly stale Fontconfig cache.
			if not font.queried then
				local query = vim.system(
					{ "fc-query", "--index", tostring(font.index or 0), "-f", "%{charset}", font.file },
					{ text = true }
				):wait()
				assert(query.code == 0, query.stderr)
				font.ranges, font.queried = ranges_for(query.stdout), true
			end
			if covers(font, scalars) then
				return {
					file = font.file,
					index = font.index,
					family = font.family,
					scalars = scalars,
					checked_with = "fc-query",
				}
			end
		end
	end
end
return M

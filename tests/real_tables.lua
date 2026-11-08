-- Optional real-data suite; scripts/check_dictionaries.py prepares independent models.
vim.opt.runtimepath:prepend(vim.uv.cwd())
local function json(path)
	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end
local path = assert(arg[1], "run python scripts/check_dictionaries.py [--download]")
local root = vim.fn.fnamemodify(path, ":h")
local converter = root .. "/unicode-code.lua"
vim.fn.writefile({
	"return function(codes)",
	"  local result = {}",
	"  for _, code in ipairs(codes) do",
	"    if code:find('[\\128-\\255]') then",
	"      code = 'u:' .. table.concat(vim.tbl_map(function(cp) return ('%x'):format(cp) end, vim.fn.str2list(code)), '.')",
	"    end",
	"    result[#result + 1] = code",
	"  end",
	"  return result",
	"end",
}, converter)
local convert = dofile(converter)
local build = require("flash-any.build")
local reports, failures = {}, 0
for _, case in ipairs(json(path)) do
	local report = { name = case.name, entries = case.entries, pairs = case.pairs, unicode_codes = case.unicode_codes }
	local ok, err = pcall(function()
		local expected = json(case.expected)
		local formats = { "auto", case.format }
		if case.format == "tsv" then
			formats[#formats + 1] = "tab"
		end
		for _, format in ipairs(formats) do
			local opts = vim.tbl_extend("force", case.options, { format = format })
			local actual = build.read(case.file, opts)
			for key, codes in pairs(expected) do
				assert(vim.deep_equal(actual[key], codes), format .. ": mismatch at " .. key)
			end
			assert(vim.tbl_count(actual) == vim.tbl_count(expected), format .. ": unexpected extra entries")
		end
		local opts = vim.tbl_extend("force", case.options, {
			file = case.file,
			format = case.format,
			converter = converter,
			matcher = "full_code",
		})
		local output = root .. "/" .. case.name .. ".bin"
		local _, entries = build.binary({ sources = { opts }, output = output })
		if #case.samples == 0 then
			assert(entries == 128, "word-only table must retain only ASCII literals")
		end
		local book = require("flash-any.native").load(output)
		for index, sample in ipairs(case.samples) do
			local query = convert({ sample[2] })[1]
			local matches = book:scan(0, 0, index, 1, 1, { sample[1] }, query, nil)
			local found = false
			for _, match in ipairs(matches) do
				found = found or (match.pos[1] == 1 and match.pos[2] == 0 and match.end_pos[2] == 0)
			end
			assert(found, "native mismatch: " .. sample[1] .. " / " .. sample[2])
		end
		report.native_samples = #case.samples
	end)
	report.verified, report.error = ok, not ok and tostring(err) or nil
	reports[#reports + 1] = report
	if not ok then
		failures = failures + 1
	end
	print(case.name .. ": " .. (ok and ("PASS, " .. case.entries .. " entries") or tostring(err)))
	collectgarbage("collect")
end
vim.fn.writefile({ vim.json.encode(reports) }, root .. "/results.json")
assert(failures == 0, tostring(failures) .. " real dictionary cases failed; see " .. root .. "/results.json")

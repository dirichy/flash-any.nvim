# Provide a source for flash-any

[简体中文](writing-sources.zh-CN.md)

This tutorial targets the core's `main` branch and takes a source through local
use, recording and publication. An ordinary table needs a factory and data, without
core changes, C code or a runtime matcher. Run the minimal example first, then
replace its dictionary and names with yours.

## 1. Run a minimal package first

You need Neovim 0.11+, a C compiler, and local checkouts of flash-any.nvim and
flash.nvim. The commands below target Linux/macOS. Enter your existing core checkout,
or download the dependencies first:

```sh
git clone --branch main https://github.com/dirichy/flash-any.nvim.git "$HOME/flash-any.nvim"
git clone https://github.com/folke/flash.nvim.git "$HOME/flash.nvim"
cd "$HOME/flash-any.nvim"
```

The source package itself needs no make, Python, VHS or dictionary-download install hook.

Run the block below from the **flash-any.nvim checkout root**. Set FLASH_NVIM_PATH
to your existing flash.nvim checkout and choose an empty FLASH_ANY_SOURCE_ROOT.
Neither dependency nor source needs to live inside the core checkout.

```sh
# Create the minimal source package.
export FLASH_ANY_ROOT="$PWD"
export FLASH_NVIM_PATH="${FLASH_NVIM_PATH:-$HOME/flash.nvim}"
export FLASH_ANY_SOURCE_ROOT="${FLASH_ANY_SOURCE_ROOT:-$HOME/flash-any-mycodes.nvim}"

mkdir -p "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/sources" "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/tables"
sed 's/SOURCE/mycodes/g' demos/templates/source.lua > "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/sources/mycodes.lua"
sed 's/"SOURCE"/"mycodes"/g' demos/templates/minimal.lua > "$FLASH_ANY_SOURCE_ROOT/minimal.lua"
cp demos/templates/source.gitignore "$FLASH_ANY_SOURCE_ROOT/.gitignore"
printf '中\tzhong\n文\twen\n重\tzhong\n重\tchong\n' > "$FLASH_ANY_SOURCE_ROOT/lua/flash-any/tables/mycodes.tsv"
printf '中 文 重\n中文 with flash\n' > "$FLASH_ANY_SOURCE_ROOT/sample.txt"

nvim --clean -l "$FLASH_ANY_ROOT/lua/flash-any/compiler.lua"
NVIM_LOG_FILE="$FLASH_ANY_SOURCE_ROOT/nvim.log" nvim --clean -l "$FLASH_ANY_SOURCE_ROOT/minimal.lua"
```

A successful exit verifies **named factory discovery, dictionary loading and setup's
binary build**, rather than just parsing a Lua file. The isolated development entry
comes from [minimal.lua](../demos/templates/minimal.lua). Keep the exported variables
and run in the same terminal:

```sh
nvim --clean -u "$FLASH_ANY_SOURCE_ROOT/minimal.lua" "$FLASH_ANY_SOURCE_ROOT/sample.txt"
```

Press `s`, type `zhong`, and select a label on 中 or 重. Confirm the cursor position.
Press `s` again and enter `zhongwen with flash` to match the second line. Ordinary
ASCII needs no dictionary entries. Reproduce problems here before adding personal
configuration or trying to diagnose them through the recorder.

The package now contains:

```text
flash-any-mycodes.nvim/
├── .gitignore
├── minimal.lua
├── sample.txt
└── lua/flash-any/
    ├── sources/mycodes.lua
    └── tables/mycodes.tsv
```

## 2. Replace the dictionary and names

`mycodes` is the name in `sources = { "mycodes" }`, not the repository name. The
repository can be named flash-any-mycodes.nvim. Keep the factory path, codetable
value and configured source name consistent:

```lua
-- lua/flash-any/sources/mycodes.lua
return function()
  return {
    codetable = "mycodes",
    matcher = "full_code",
  }
end, 1
```

Place the complete UTF-8 table in lua/flash-any/tables/mycodes.tsv. Each row contains
text, a **real Tab**, and one code. The printf above writes real Tabs, not literal
backslash-t pairs. Repeat rows for multiple codes; commas are literal characters.
No sorting, common-character subset or registration function is needed.

Text keys can be graphemes, combining sequences or phrases, such as 中, `á`, 👩‍💻
and 中文. Inline codes must be nonempty ASCII without Tabs, newlines or NUL; group
references may use Unicode names. Character and phrase entries participate together
at complete grapheme boundaries, without crossing lines. Word entries do not infer
readings for their individual characters or unlisted contextual pronunciations.

| matcher | Accepted input |
| --- | --- |
| `full_code` | Complete codes, e.g. zhong; the tutorial default |
| `initial` | First letter or complete code, e.g. z or zhong |
| `prefix` | Any nonempty prefix, e.g. z, zh or zhong |
| `letter` | Complete codes, ignorecase/smartcase, optional grapheme-head lookup |

When renaming, update the factory filename, codetable, minimal.lua source name,
READMEs and demo. **Restart Neovim** after factory/table changes; setup succeeds only once per session. Use rebuild() for data changes; a restart
also reloads Lua modules. Use `:checkhealth flash-any` for environment
checks and the [reference](sources.md) for caches and explicit binary rebuilding.

Modules may return `factory, version`, as in `end, 1` above. Versions are finite numbers
or nonempty strings; omission means `0`, preserving old factory-only modules. Bump the
version whenever dictionaries, conversions or other build dependencies change. Package
files are no longer scanned for updates. Keep module-level code limited to declarations;
perform data loading and conversion inside the factory. After manual edits, bump the
version and restart, or call `require("flash-any").rebuild()` to rebuild
setup's sources asynchronously.

## 3. Existing files, converters and groups

A factory can return file for an existing supported dictionary instead of exporting
another format during installation:

```lua
return function()
  return {
    file = assert(vim.api.nvim_get_runtime_file("lua/flash-any/tables/mycodes.tsv", false)[1]),
    format = "tsv",
    matcher = "full_code",
  }
end
```

Locate factory-owned files through nvim_get_runtime_file, independently of the
shell's working directory and the author's absolute paths. Headerless files default
to text/code order; reversed columns require `columns = { "code", "text" }`.
See [file integration](sources.md#直接读取码表--dictionary-files) for Rime, CSV,
Fcitx, IBus, encodings and weights.

- **ASCII codes are already correct:** read the table directly, without a converter.
- **Readings need conversion or segmentation:** use file with converter; the factory
  supplies the converter's absolute path. It receives one text entry's deduplicated
  code array and returns ASCII codes or valid group-reference/sequence strings.
  Returning nil or an empty array omits that entry. Conversion runs only at build
  time, without buffer context or XML parsing. Maintainers must first extract
  unsupported source formats into supported tables; installation should not download
  the original dictionaries.
- **Syllables have alternative spellings:** supply groups. A table code `す し` for
  寿司 with `groups = { ["す"] = { "su" }, ["し"] = { "shi", "si" } }` accepts
  sushi and susi. Full_code/initial/prefix/letter apply independently to each group.
  A converter can segment すし into す し; arbitrary unknown names are not segmented
  automatically.

Distinguish raw readings, group names and actual input spellings. Metadata and symbol
definitions are not necessarily pronunciations. Report unsupported readings and
filtered counts, preserving the text's other valid readings. Ordinary tables still
need only the factory in step 2; the [build reference](sources.md) covers the full API.

## 4. Separate local and public installation instructions

During development, lazy.nvim can load a local source:

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    { dir = "/absolute/path/to/flash-any-mycodes.nvim" },
  },
  opts = { sources = { "mycodes" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
  },
}
```

Load the source before core setup. When testing unpublished core features, also use
the corresponding local core checkout; remote main does not contain unpushed edits.
Public installation examples use the real `"OWNER/flash-any-mycodes.nvim"` dependency.
**Do not leave the author's dir, HOME or .dev paths in public READMEs.** The core compiles its C module automatically; neither package needs an installation build hook.

## 5. Complete READMEs, licenses and ignore rules

Copy the templates from the core checkout root:

```sh
mkdir -p "$FLASH_ANY_SOURCE_ROOT/docs" "$FLASH_ANY_SOURCE_ROOT/.github/workflows"
cp demos/templates/README.zh-CN.md "$FLASH_ANY_SOURCE_ROOT/README.md"
cp demos/templates/README.md "$FLASH_ANY_SOURCE_ROOT/README.en.md"
cp demos/templates/maintenance.md "$FLASH_ANY_SOURCE_ROOT/docs/maintenance.md"
sed 's/SOURCE/mycodes/g' demos/templates/table-demo.lua > "$FLASH_ANY_SOURCE_ROOT/demo.lua"
cp demos/templates/table-demo.yml "$FLASH_ANY_SOURCE_ROOT/.github/workflows/demo.yml"
```

Replace OWNER/TABLE in the READMEs with the actual repository, e.g.
OWNER/flash-any-mycodes.nvim, and SOURCE with mycodes. Language-specific packages use
that language for README.md and link an English translation. The commands above
set up a Chinese homepage; write a homepage in the relevant language for other
languages. Language-neutral packages can retain English as the homepage. Document
all user options, defaults, enums, examples and combination constraints, keeping
internal build data in maintenance documentation.

Add a code license and THIRD_PARTY.md with upstream versions, data terms, input
hashes and transformations. The code license does not license the data. The copied
.gitignore excludes generated media, Neovim logs and Python caches. Review
`git status --short` before committing; exclude local dependencies, downloaded
original dictionaries and recording outputs.

## 6. Prepare scenes before recording

For an ordinary table, edit the copied demo.lua's language name, text and narration:

```lua
return {
  file = "lua/flash-any/tables/mycodes.tsv",
  matcher = "full_code",
  text_name = "Chinese",
  text = "中",
  mixed_text = "中文 with flash",
  comment = "Flash can match Chinese: type a code, then choose a label.",
  mixed_comment = "Mix Chinese codes with ASCII in the same search.",
}
```

**For a converter, groups or a custom default matcher**, use this complete alternative
to reuse the real factory, rather than maintaining demo-only conversion rules:

```lua
-- demo.lua: reuse the source factory
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.runtimepath:append(root)
local source = require("flash-any.sources.mycodes")()
return vim.tbl_extend("force", source, {
  file = source.file or "lua/flash-any/tables/mycodes.tsv",
  text_name = "Chinese",
  text = "中",
  mixed_text = "中文 with flash",
  comment = "Type a code, then choose a label to jump.",
  mixed_comment = "Mix codes and ASCII in the same search.",
})
```

File factories retain their actual file; codetable factories use the same-name TSV
as recording input. Demo-relative paths resolve from demo.lua's directory. Requiring
the factory also needs the runtimepath initialization above. Queries and labels are
inferred from real table/group data, without manually duplicating them.

The current template's first target must be **one complete grapheme** with a code;
two copies are added for multiple labels. Mixed_text must include table text and
ASCII, and every non-ASCII grapheme in it must have an individual encoding. Phrase
support does not infer character readings; phrase-only tables do not currently fit
this single-grapheme recording template. Optional sample must contain the complete
mixed_text and use covered fonts. Omitted text triggers font-covered single-scalar
sampling. Text_name names the language/category, not the target character's meaning.

Local scene preparation also needs fontconfig (fc-match/fc-query) and the recording
fonts: JetBrainsMono Nerd Font Mono, Noto CJK and Noto Color Emoji. Full recording
additionally requires VHS, ttyd, Chromium/Chrome, FFmpeg/ffprobe, Python 3 and Tokyo
Night; see [dependencies](../demos/README.md#录制--record). Without local recording
tools, verify the source first and use CI in step 7; CI installs recording dependencies.

With fonts available, prepare scenes without launching a browser from the core checkout:

```sh
nvim --clean -l demos/prepare-table.lua "$FLASH_ANY_SOURCE_ROOT/demo.lua"
```

Expect Prepared 2 jumps for table. This already reads the table, executes the converter,
compiles real group data and checks both targets and available labels. Fix targets,
paths, missing fonts or the core version here first. Recording retains FLASH_NVIM_PATH
from step 1; set TOKYONIGHT_PATH to an existing theme checkout. If needed, first run
`git clone https://github.com/folke/tokyonight.nvim.git "$HOME/tokyonight.nvim"`. Then record:

```sh
export TOKYONIGHT_PATH="${TOKYONIGHT_PATH:-$HOME/tokyonight.nvim}"
sh demos/record.sh table "$FLASH_ANY_SOURCE_ROOT/demo.lua"
```

If sandboxing blocks
local ports or Chromium, run the recorder with appropriate permissions instead of
changing the tape to conceal the failure.

Outputs belong to the **core checkout's** demos/output: table.gif, table.mp4,
table.png, table-verification.json, table-media.json and README.local.md. Check
verified: true, both actual cursor positions and the unchanged fixture; inspect the
GIF/MP4 fonts and cropping. Use that directory's README.local.md for local previews.
Copying media into a source package does not publish it.

## 7. Configure remote recording against a suitable core

The template defaults to uses ...table-demo.yml@main and flash-any-ref: main, so each
new run follows the published core. Table-ref: ${{ github.sha }} selects the source
commit; the workflow passes only config: demo.lua.

| Setting | Controls |
| --- | --- |
| @ref in uses | The reusable recording workflow definition |
| flash-any-ref | The checked-out core and recording implementation |
| table-ref | The checked-out source and dictionary revision |

For reproducibility, pin the first two to the same **published core SHA tested with
this source**. Matching SHAs alone do not imply feature compatibility: an accessible
old commit may lack converters, groups or group sequences. Run the local source and
scene preparation against the chosen version. Uncommitted or unpushed local changes
are not included in a remote ref.

Publish the source repository on main. Main pushes or Actions' Run workflow start
recording. Core pushes alone do not trigger the source workflow; start a **new run**
on the source's main after a core update. Also start a new run after changing workflow
refs, rather than only retrying an old failed job: it may retain the reusable
workflow SHA from the first attempt. See
[GitHub's rerun rules](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations).
The publishing job runs only on main; change both push and publish conditions for a
different default branch.

The template grants read access to recording and contents: write only to publication.
It uses this repository's GITHUB_TOKEN to replace the demos prerelease assets; no
separate uploader is needed. If recording succeeds but publication lacks permissions,
inspect the table-demo artifact first. An artifact does not establish that the
README's Release URLs exist.

## 8. Verify publication as a new user

Before the first media release, READMEs may link to
https://github.com/OWNER/TABLE/actions/workflows/demo.yml. After successful publication,
update **every language README** to the template's stable GIF, MP4 and verification
report URLs. Do not stop at an Actions link or reference ignored local output:

```markdown
![Search and jump](https://github.com/OWNER/TABLE/releases/download/demos/table.gif)

[MP4](https://github.com/OWNER/TABLE/releases/download/demos/table.mp4) · [Verification report](https://github.com/OWNER/TABLE/releases/download/demos/table-verification.json)
```

Subsequent successful recordings replace the same filenames without README edits.
Open all three URLs after the first publication, check verified and the actual
frames, then install with the README's remote dependencies from a fresh checkout
and test character and mixed input. This must use only the published core/source,
without the author's local paths or unpublished changes.

Completion means **named installation can jump, playback verifies, release assets
are accessible, and every README displays the demo**. Local success, Actions artifact
success and Release publication are distinct outcomes.

## Troubleshooting

| Symptom | First check |
| --- | --- |
| source is not installed | Factory path, name, runtimepath before setup; retry minimal.lua |
| Tabs, columns or Unicode code errors | Real Tabs, text/code order, format, missing converter/groups |
| Factory/converter cannot find files | Runtime file lookup in factories; demo-relative configuration paths |
| Updates appear stale | Make and restart; restart for source Lua/TSV too; rebuild explicit binaries as documented |
| Local success but CI lacks groups etc. | Actual features in both core refs; publish the new core and start a new run |
| Demo target has no code/font | Single-grapheme text, per-grapheme mixed coverage, converter output and real fonts |
| Local GIF exists but GitHub shows no image | Publish job, demos release assets, README's remote URLs |

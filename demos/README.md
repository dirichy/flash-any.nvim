# Demo

使用真实 Flash 输入循环演示小鹤双拼和 Unicode 名称搜索：

1. `s` → `vs` 显示“中”及“重”的候选，继续 `go` 缩小到“中国”，按标签 `a` 跳转。
2. `s` → `alpha` → `a` 跳转到 `α`。
3. `s` → `grin` → `a` 跳转到 `😀`。

从仓库根目录重新录制：

```sh
sh demos/record.sh
```

需要 Neovim、VHS、ttyd、Chromium/Chrome、FFmpeg（含 ffprobe）、Python 3、fontconfig，
以及 `JetBrainsMono Nerd Font Mono` 字体；中文和 emoji 分别通过 Noto CJK、Noto Color Emoji
字体补全。终端与 Neovim 均使用 Tokyo Night 主题。`flash.nvim` 默认位于 `.dev/flash.nvim`，
`tokyonight.nvim` 默认位于 `.dev/tokyonight.nvim`，也可通过 `FLASH_NVIM_PATH`、
`TOKYONIGHT_PATH` 指向本地安装目录。

录制使用 `init.lua` 和 `sample.lua`，不加载个人配置。本地产物、config/state/cache、日志和
验证报告全部位于已忽略的 `demos/output/`；仓库只保存录制脚本和样例。同一次 TUI 回放中
会记录候选、实际标签和跳转落点，验证样例未被修改且没有 Neovim 错误。`record.sh` 检查
`verification.json` 和 GIF/MP4 的编码信息，并生成 `media.json`；生成后仍需目视检查画面。

`.github/workflows/demos.yml` 在 `master` 的插件、录制脚本或工作流变化时自动运行，也可在
Actions 页面手动运行。CI 固定 Neovim 0.12.6、VHS 0.12.1、ttyd 1.7.7、Nerd Fonts 3.4.0，
以及 Flash、Tokyo Night 的提交。验证成功后更新独立的 `demos` prerelease 附件，并检查附件
链接；不提交媒体文件，不将演示 Release 标为 latest。README 引用固定的
`releases/download/demos/demo.gif` 和 `demo.mp4`，首次成功运行工作流后链接才可用。

The isolated demo uses Tokyo Night and JetBrainsMono Nerd Font Mono. Run
`sh demos/record.sh` from the repository root; `FLASH_NVIM_PATH` and
`TOKYONIGHT_PATH` can override local dependency paths. Generated media and evidence
stay in the ignored `demos/output/` directory. The local script does not publish.
The Demos workflow records on relevant `master` pushes or manual dispatch, verifies
playback and media, then updates assets on the `demos` prerelease. README links
become available after its first successful run; no media files enter Git history.

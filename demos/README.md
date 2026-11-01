# Demo recordings / 演示录制

一段连续演示使用同一套 `sources = { "pinyin", "unicode" }` 配置，真实输入查询并按 Flash 标签跳转：

| 场景 / Scene | 输入 / Input | 目标 / Target |
| --- | --- | --- |
| 全拼 / Full pinyin | `s` → `quan` → `pin` → `a` | 全拼 |
| 简拼 / Initials | `s` → `j` → `p` → `a` | 简拼 |
| 连续混输 / Mixed input | `s` → `hun` → `s` → `ascii` → `grin` → `a` | 混输ascii😀 |

混输只开启一次搜索：`hun` 是“混”的全拼，`s` 是“输”的简拼首字母，`ascii` 按字面匹配，
`grin` 是 😀 的 Unicode 名称前缀。分段停顿仅用于阅读，不切换输入模式。

## 录制 / Record

从仓库根目录运行：

```sh
sh demos/record.sh
```

需要 Neovim、VHS、ttyd、Chromium/Chrome、FFmpeg（含 ffprobe）、Python 3、fontconfig，
以及 JetBrainsMono Nerd Font Mono、Noto CJK 和 Noto Color Emoji 字体。
Flash 默认位于 `.dev/flash.nvim`，Tokyo Night 默认位于 `.dev/tokyonight.nvim`，可指定已有安装：

```sh
FLASH_NVIM_PATH=/path/to/flash.nvim \
TOKYONIGHT_PATH=/path/to/tokyonight.nvim \
sh demos/record.sh
```

录制通过 `init.lua` 和 `sample.lua` 隔离个人配置。样式、启动命令和三次搜索统一放在
[demo.tape](demo.tape)，全程只启动一次 Neovim。
本地产物、config/state/cache、日志、调色板及验证报告都保存在已忽略的 `demos/output/`，
脚本不上传文件。

Requires Neovim, VHS, ttyd, Chromium/Chrome, FFmpeg/ffprobe, Python 3, fontconfig,
JetBrainsMono Nerd Font Mono, Noto CJK, and Noto Color Emoji. Run from the repository
root. Set `FLASH_NVIM_PATH` and `TOKYONIGHT_PATH` to override local plugin paths.
The isolated configuration never loads personal dotfiles. Local recording does not publish.

## 画质与验证 / Quality and verification

原始 MP4 为 1920×1080、36 号字，单窗口采用 56px 渐变外边框、圆角和 Colorful 窗口栏。
背景与样式参考 vimoi.nvim 录制脚本；背景原样来自
[chezmoi-template.nvim](https://github.com/dpezto/chezmoi-template.nvim/blob/670ba83095ba6571f3125a5e5fd4118505a2c3c6/assets/tapes/style.tape)，
保留 [MIT 许可](common/backdrop.LICENSE)。

VHS 设置抓帧 30fps，本机 H.264 输出实测 25fps，以 ffprobe 报告为准。
GIF 从 MP4 两遍转换，保留 1920×1080、20fps，变化区域调色板与固定 Bayer 抖动可减少渐变闪烁。
输入速度为 120ms/键，语义分段后停留 0.8 秒，跳转后停留 1.8 秒。

同一次 TUI 回放记录中间查询候选、实际标签和最终落点，确认样例未修改且没有 Neovim 错误。
每轮清空旧验证文件，异常写入本轮 JSON；验证成功才转换 GIF、检查 codec/尺寸/实际帧率并提取封面。
生成后仍须目视检查关键帧的字体、emoji、裁切和标签。

The recording produces `demo.mp4`, `demo.gif`, `demo.png`, `verification.json`,
and `media.json`. Live TUI assertions check intermediate matches, the selected label,
all three final queries and cursor positions, and the unchanged fixture. Media checks verify
1920×1080 output and actual codecs/frame rates. The MP4 retains full color; the
20fps GIF uses a separate palette pass and stable Bayer dithering.

## CI 与发布 / CI and publishing

[工作流](../.github/workflows/demos.yml) 在 `master` 的插件、录制素材、README 和相关测试变化时
自动运行，也可手动运行。工具与插件版本固定在工作流中，字体包括 CJK 和 emoji fallback。
验证成功后保存 GIF、MP4、PNG 和 JSON artifact，再更新独立 `demos` prerelease 的同名媒体附件，
最后检查附件 URL。不提交生成媒体，不将 demo Release 标为 latest。

README 引用 `releases/download/demos/demo.gif` 和 `demo.mp4`；
本地录制不更新远端附件，提交后 CI 才会发布新版演示。

The workflow records the continuous demo, verifies playback and media, saves artifacts,
and updates the `demos` prerelease on the default branch. README media URLs become
available after the updated workflow publishes them. Local files and release assets
are separate; no generated media enters Git history.

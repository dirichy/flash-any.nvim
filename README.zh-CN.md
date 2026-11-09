# ⚡ flash-any.nvim

为了支持更大的码表和词库，旧的二分查找性能不够。同时，为了使项目体积不会随source变多而无限增大，我外置了几乎所有的码表。
因此，新版本会和旧版本不兼容。

新版本在 [`main` 分支](https://github.com/dirichy/flash-any.nvim/tree/main) 开发，
使用 C 匹配核心和新版配置 API。

安装和使用方式请查看 [main 分支 README](https://github.com/dirichy/flash-any.nvim/blob/main/README.zh-CN.md)。

当前 source 插件：

- [`dirichy/flash-any-pinyin.nvim`](https://github.com/dirichy/flash-any-pinyin.nvim) —— 中文拼音和双拼
- [`dirichy/flash-any-tiger.nvim`](https://github.com/dirichy/flash-any-tiger.nvim) —— 中文虎码

旧版 README 保存在 [README.zh-CN.old.md](README.zh-CN.old.md)。

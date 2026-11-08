# Public Lua/C headers

Unmodified public headers from LuaJIT 2.1.1793383622:
`lua.h`, `lauxlib.h`, `lualib.h`, and `luaconf.h`.

Upstream: https://github.com/LuaJIT/LuaJIT/tree/v2.1/src

These provide Lua 5.1-compatible API declarations and configuration only, not
another LuaJIT runtime. The native module resolves API symbols from the host
Neovim process. See https://luajit.org/extensions.html for ABI compatibility.

Lua-originated headers retain the Lua.org MIT notice in `lua.h`. LuaJIT's MIT
notice is retained in `COPYRIGHT` (copied from `luajit.h`). Do not format or edit
the vendored headers when formatting this project's C sources.

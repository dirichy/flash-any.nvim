/* Lua API, per-state window caches, labels and motion position conversion. */
#include <stdlib.h>
#include "native.h"
#include "text.h"

static Engine *check_engine(lua_State *L) {
  return (Engine *)luaL_checkudata(L, 1, ENGINE_MT);
}

/* Dictionary bytes are shared; query caches follow the Flash state lifetime. */
static int new_state(lua_State *L) {
  Engine *owner = check_engine(L);
  Engine *state = (Engine *)lua_newuserdata(L, sizeof(Engine));
  *state = *owner;
  luaL_getmetatable(L, ENGINE_MT);
  lua_setmetatable(L, -2);
  lua_createtable(L, 0, 2);
  lua_pushvalue(L, 1);
  lua_setfield(L, -2, "owner");
  lua_newtable(L);
  lua_setfield(L, -2, "windows");
  lua_setfenv(L, -2);
  return 1;
}

/* Push one engine-owned window table. has() is read-only; invalidation happens
 * when scan() receives the replacement buffer snapshot. */
static int window_cache(lua_State *L, int create_new) {
  lua_getfenv(L, 1);
  lua_getfield(L, -1, "windows");
  int windows = lua_gettop(L);
  int win = (int)luaL_checkinteger(L, 2);
  lua_rawgeti(L, windows, win);
  int valid = lua_istable(L, -1);
  if (valid) {
    lua_getfield(L, -1, "buf");
    valid = lua_tonumber(L, -1) == luaL_checknumber(L, 3);
    lua_pop(L, 1);
    lua_getfield(L, -1, "tick");
    valid = valid && lua_tonumber(L, -1) == luaL_checknumber(L, 4);
    lua_pop(L, 1);
  }
  if (valid) {
    return lua_gettop(L);
  }
  lua_pop(L, 1);
  if (!create_new) {
    lua_pushnil(L);
    return lua_gettop(L);
  }
  lua_createtable(L, 0, 4);
  lua_pushvalue(L, 3);
  lua_setfield(L, -2, "buf");
  lua_pushvalue(L, 4);
  lua_setfield(L, -2, "tick");
  lua_newtable(L);
  lua_setfield(L, -2, "lines");
  lua_newtable(L);
  lua_setfield(L, -2, "chars");
  lua_pushvalue(L, -1);
  lua_rawseti(L, windows, win);
  return lua_gettop(L);
}

static int has_lines(lua_State *L) {
  check_engine(L);
  int window_index = window_cache(L, 0);
  if (!lua_istable(L, window_index)) {
    lua_pushboolean(L, 0);
    return 1;
  }
  lua_getfield(L, window_index, "lines");
  int lines = lua_gettop(L);
  int from = (int)luaL_checkinteger(L, 5);
  int to = (int)luaL_checkinteger(L, 6);
  int valid = 1;
  for (int row = from; row <= to; ++row) {
    lua_rawgeti(L, lines, row);
    if (lua_type(L, -1) != LUA_TSTRING) {
      valid = 0;
    }
    lua_pop(L, 1);
    if (!valid) {
      break;
    }
  }
  lua_pushboolean(L, valid);
  return 1;
}

static int sort_matches(const void *left, const void *right) {
  const Match *a = (const Match *)left, *b = (const Match *)right;
  if (a->row != b->row) {
    return (a->row > b->row) - (a->row < b->row);
  }
  if (a->start != b->start) {
    return (a->start > b->start) - (a->start < b->start);
  }
  return (a->end > b->end) - (a->end < b->end);
}

static void integer_field(lua_State *L, const char *key, uint32_t value) {
  lua_pushinteger(L, value);
  lua_setfield(L, -2, key);
}

static void position_field(lua_State *L, const char *key, uint32_t row, uint32_t col) {
  lua_createtable(L, 2, 0);
  lua_pushinteger(L, row);
  lua_rawseti(L, -2, 1);
  lua_pushinteger(L, col);
  lua_rawseti(L, -2, 2);
  lua_setfield(L, -2, key);
}

/* A completed literal can continue with any prefix of the following whole glyph. */
static void literal_keys(lua_State *L, const Match *match, int lines, int output) {
  if (!match->literal_size) {
    return;
  }
  lua_rawgeti(L, lines, (int)match->row);
  const unsigned char *suffix = (const unsigned char *)lua_tostring(L, -1) + match->literal_start;
  uint32_t at = 0;
  while (at < match->literal_size) {
    decode(suffix, match->literal_size, &at);
    lua_pushlstring(L, (const char *)suffix, at);
    lua_pushboolean(L, 1);
    lua_rawset(L, output);
  }
  lua_pop(L, 1);
}

static int push_results(lua_State *L, Result *result, int character, char motion, int lines) {
  Match *matches = (Match *)(result + 1);
  uint64_t blocked[2] = {0, 0};
  int has_literals = 0;
  if (!character) {
    for (uint32_t i = 0; i < result->count; ++i) {
      blocked[0] |= matches[i].next[0];
      blocked[1] |= matches[i].next[1];
      has_literals |= matches[i].literal_size != 0;
    }
  }
  int blocked_literals = 0;
  if (has_literals) {
    lua_newtable(L);
    blocked_literals = lua_gettop(L);
    for (uint32_t i = 0; i < result->count; ++i) {
      literal_keys(L, matches + i, lines, blocked_literals);
    }
  }
  uint32_t label = 1;
  uint32_t label_count = lua_istable(L, 9) ? (uint32_t)lua_objlen(L, 9) : 0;
  lua_createtable(L, (int)result->count, 0);
  int output = lua_gettop(L);
  int written = 0;
  for (uint32_t i = 0; i < result->count; ++i) {
    Match *match = matches + i;
    uint32_t col = character && motion == 't'   ? match->before
                   : character && motion == 'T' ? match->after
                                                : match->start;
    if (col == NONE) {
      continue;
    }
    lua_createtable(L, 0, 6);
    lua_pushvalue(L, 2);
    lua_setfield(L, -2, "win");
    position_field(L, "pos", match->row, col);
    position_field(L, "end_pos", match->row, character ? col : match->end);
    lua_newtable(L);
    if (!character) {
      for (unsigned key = 0; key < 128; ++key) {
        if (match->next[key >> 6] & ((uint64_t)1 << (key & 63))) {
          char byte = (char)key;
          lua_pushlstring(L, &byte, 1);
          lua_pushboolean(L, 1);
          lua_rawset(L, -3);
        }
      }
    }
    if (!character) {
      literal_keys(L, match, lines, lua_gettop(L));
    }
    lua_setfield(L, -2, "next");
    if (!character) {
      while (label <= label_count) {
        lua_rawgeti(L, 9, (int)label++);
        size_t n;
        const char *key = lua_tolstring(L, -1, &n);
        if (!key) {
          return luaL_error(L, "labels must be strings");
        }
        int reserved =
            n == 1 && (unsigned char)key[0] < 128 &&
            (blocked[(unsigned char)key[0] >> 6] & ((uint64_t)1 << ((unsigned char)key[0] & 63)));
        if (!reserved && blocked_literals) {
          lua_pushvalue(L, -1);
          lua_rawget(L, blocked_literals);
          reserved = lua_toboolean(L, -1);
          lua_pop(L, 1);
        }
        if (!reserved) {
          lua_setfield(L, -2, "label");
          break;
        }
        lua_pop(L, 1);
      }
    }
    lua_rawseti(L, output, ++written);
  }
  return 1;
}

/* Lua: state:scan(win, buf, tick, from, to, lines?, pattern, labels?, motion?, ignorecase?). */
static int scan(lua_State *L) {
  Engine *instance = check_engine(L);
  int from = (int)luaL_checkinteger(L, 5), to = (int)luaL_checkinteger(L, 6);
  if (from < 1 || to < from) {
    return luaL_error(L, "invalid native scan row range");
  }
  luaL_checktype(L, 8, LUA_TSTRING);
  size_t length;
  const char *input = lua_tolstring(L, 8, &length);
  if (length >= INT_MAX) {
    return luaL_error(L, "native input too long");
  }
  const char *mode = lua_isnoneornil(L, 10) ? NULL : luaL_checkstring(L, 10);
  int character = mode != NULL;
  int ignorecase = lua_toboolean(L, 11);
  int window_index = window_cache(L, 1);
  lua_getfield(L, window_index, "lines");
  int lines = lua_gettop(L);
  if (!lua_isnoneornil(L, 7)) {
    luaL_checktype(L, 7, LUA_TTABLE);
    if (lua_objlen(L, 7) != (size_t)(to - from + 1)) {
      return luaL_error(L, "invalid native line snapshot");
    }
    int base = lua_gettop(L);
    for (int row = from; row <= to; ++row) {
      lua_rawgeti(L, 7, row - from + 1);
      luaL_checktype(L, -1, LUA_TSTRING);
      lua_rawseti(L, lines, row);
      lua_settop(L, base);
    }
  }
  /* Full search caches one range. Character recognition caches each requested row. */
  lua_getfield(L, window_index, character ? "chars" : "search");
  int cache;
  if (character) {
    if (from != to) {
      return luaL_error(L, "native character adapter requests one row at a time");
    }
    lua_rawgeti(L, -1, from);
  }
  if (lua_istable(L, -1)) {
    cache = lua_gettop(L);
    lua_getfield(L, cache, "pattern");
    int same = lua_rawequal(L, -1, 8);
    lua_pop(L, 1);
    lua_getfield(L, cache, "from");
    same = same && lua_tointeger(L, -1) == from;
    lua_pop(L, 1);
    lua_getfield(L, cache, "to");
    same = same && lua_tointeger(L, -1) == to;
    lua_pop(L, 1);
    lua_getfield(L, cache, "ignorecase");
    same = same && lua_toboolean(L, -1) == ignorecase;
    lua_pop(L, 1);
    /* Labels and f/F/t/T positions are reapplied when materializing results. */
    if (same) {
      lua_getfield(L, cache, "result");
      return push_results(L, (Result *)lua_touserdata(L, -1), character, mode ? mode[0] : 0, lines);
    }
  }
  Result *result = (Result *)lua_newuserdata(L, sizeof(Result));
  result->count = result->capacity = 0;
  int result_index = lua_gettop(L);
  Requests requests = {0};
  requests.slots = instance->depth + 1;
  if (!character && length) {
    requests.width = (uint32_t)length + 1;
    if (requests.slots > INT_MAX / 8 ||
        requests.width > (INT_MAX / 8 - requests.slots) / requests.slots) {
      return luaL_error(L, "native scan workspace too large");
    }
    size_t cells = (size_t)requests.slots * requests.width;
    uint32_t *memory =
        (uint32_t *)lua_newuserdata(L, (cells * 2 + requests.slots * 2) * sizeof(uint32_t));
    requests.starts = memory;
    requests.offsets = memory + cells;
    requests.counts = memory + cells * 2;
    requests.lookahead = requests.counts + requests.slots;
  }
  /* Keep result and request userdata on the Lua stack across row scans. */
  int base = lua_gettop(L);
  if (length) {
    for (int row = from; row <= to; ++row) {
      lua_rawgeti(L, lines, row);
      luaL_checktype(L, -1, LUA_TSTRING);
      size_t text_size;
      const char *value = lua_tolstring(L, -1, &text_size);
      if (text_size >= INT_MAX) {
        return luaL_error(L, "native line too long");
      }
      Slice text = {value, (uint32_t)text_size};
      result = scan_line(L, result_index, result, instance, text, input, (uint32_t)length, row,
                         &requests, character, ignorecase);
      lua_settop(L, base);
    }
  }
  qsort(result + 1, result->count, sizeof(Match), sort_matches);
  lua_createtable(L, 0, 5);
  cache = lua_gettop(L);
  lua_pushvalue(L, 8);
  lua_setfield(L, cache, "pattern");
  integer_field(L, "from", from);
  integer_field(L, "to", to);
  lua_pushboolean(L, ignorecase);
  lua_setfield(L, cache, "ignorecase");
  lua_pushvalue(L, result_index);
  lua_setfield(L, cache, "result");
  if (character) {
    lua_getfield(L, window_index, "chars");
    lua_pushvalue(L, cache);
    lua_rawseti(L, -2, from);
    lua_pop(L, 1);
  } else {
    lua_pushvalue(L, cache);
    lua_setfield(L, window_index, "search");
  }
  return push_results(L, result, character, mode ? mode[0] : 0, lines);
}

int luaopen_flash_any_native(lua_State *L) {
  static const luaL_Reg methods[] = {
      {"new_state", new_state}, {"has", has_lines}, {"scan", scan}, {NULL, NULL}};
  luaL_newmetatable(L, ENGINE_MT);
  luaL_register(L, NULL, methods);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  lua_newtable(L);
  lua_pushcfunction(L, load_binary);
  lua_setfield(L, -2, "load");
  lua_pushcfunction(L, open_binary);
  lua_setfield(L, -2, "open");
  lua_pushcfunction(L, write_binary);
  lua_setfield(L, -2, "write");
  lua_newtable(L);
  lua_pushboolean(L, 0);
  lua_pushcclosure(L, graphemes, 1);
  lua_setfield(L, -2, "len");
  lua_pushboolean(L, 1);
  lua_pushcclosure(L, graphemes, 1);
  lua_setfield(L, -2, "each");
  lua_setfield(L, -2, "grapheme");
  lua_pushfstring(L, "%s/%d", BINARY_MAGIC, UNICODE_VERSION);
  lua_setfield(L, -2, "version");
  lua_createtable(L, 0, 7);
  integer_field(L, "group", GROUP_FLAG);
  integer_field(L, "literal", MATCH_LITERAL);
  integer_field(L, "full_code", MATCH_FULL);
  integer_field(L, "initial", MATCH_INITIAL);
  integer_field(L, "prefix", MATCH_PREFIX);
  integer_field(L, "suffix", MATCH_SUFFIX);
  integer_field(L, "letter", MATCH_LETTER);
  lua_setfield(L, -2, "modes");
  return 1;
}

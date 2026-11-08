#ifndef FLASH_ANY_GROUPS_H
#define FLASH_ANY_GROUPS_H

#include <lauxlib.h>
#include <lua.h>
#include <stdint.h>

/* Shared code groups are independent of source names. Views borrow the binary's bytes. */
typedef struct {
  const unsigned char *begin, *end;
  unsigned first; /* 128 means no common first byte. */
} CodeGroup;

typedef struct {
  unsigned count;
  CodeGroup groups[];
} CodeGroups;

static unsigned short_word(const unsigned char *p) { return p[0] | (unsigned)p[1] << 8; }

static void add_short(luaL_Buffer *buffer, unsigned value) {
  luaL_addchar(buffer, (char)(value & 255));
  luaL_addchar(buffer, (char)(value >> 8));
}

/* u16 group count; each has u16 spelling count, then u8 length + ASCII bytes. */
static void write_groups(lua_State *L, int index) {
  luaL_Buffer buffer;
  luaL_buffinit(L, &buffer);
  if (lua_isnil(L, index)) {
    luaL_pushresult(&buffer);
    return;
  }
  luaL_checktype(L, index, LUA_TTABLE);
  size_t count = lua_objlen(L, index);
  if (count > 65535) {
    luaL_error(L, "too many code groups");
  }
  add_short(&buffer, (unsigned)count);
  for (unsigned i = 0; i < count; ++i) {
    lua_rawgeti(L, index, (int)i + 1);
    luaL_checktype(L, -1, LUA_TTABLE);
    size_t n = lua_objlen(L, -1);
    lua_pop(L, 1);
    if (n > 65535) {
      luaL_error(L, "too many group spellings");
    }
    add_short(&buffer, (unsigned)n);
    for (unsigned j = 0; j < n; ++j) {
      lua_rawgeti(L, index, (int)i + 1);
      lua_rawgeti(L, -1, (int)j + 1);
      luaL_checktype(L, -1, LUA_TSTRING);
      size_t length;
      const char *code = lua_tolstring(L, -1, &length);
      if (!length || length > 255) {
        luaL_error(L, "invalid group spelling length");
      }
      for (size_t k = 0; k < length; ++k) {
        if ((unsigned char)code[k] >= 128) {
          luaL_error(L, "group spellings must be ASCII");
        }
      }
      /* The forms table pins the string while the buffer allocates chunks. */
      lua_pop(L, 2);
      luaL_addchar(&buffer, (char)length);
      luaL_addlstring(&buffer, code, length);
    }
  }
  luaL_pushresult(&buffer);
}

static CodeGroups *load_groups(lua_State *L, const unsigned char *data, uint32_t size) {
  if (size < 2) {
    luaL_error(L, "invalid binary group header");
  }
  unsigned count = short_word(data);
  CodeGroups *groups = (CodeGroups *)lua_newuserdata(L, sizeof(CodeGroups) + count * sizeof(CodeGroup));
  groups->count = count;
  const unsigned char *p = data + 2, *end = data + size;
  for (unsigned i = 0; i < count; ++i) {
    if (end - p < 2) {
      luaL_error(L, "invalid binary group spellings");
    }
    unsigned n = short_word(p);
    p += 2;
    CodeGroup *group = &groups->groups[i];
    group->begin = p;
    group->first = 128;
    for (unsigned j = 0; j < n; ++j) {
      if (p == end || !*p || (size_t)(end - p - 1) < *p) {
        luaL_error(L, "invalid binary group spelling length");
      }
      unsigned length = *p++;
      if (!j) {
        group->first = *p;
      } else if (group->first != *p) {
        group->first = 128;
      }
      for (unsigned k = 0; k < length; ++k) {
        if (*p++ >= 128) {
          luaL_error(L, "binary group spellings must be ASCII");
        }
      }
    }
    group->end = p;
  }
  if (p != end) {
    luaL_error(L, "invalid binary group trailing data");
  }
  return groups;
}

#endif

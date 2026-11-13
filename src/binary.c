#define _POSIX_C_SOURCE 200809L
/* Immutable dictionary packages: encoding, validation, indexes and atomic writes. */
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include "native.h"
#include "text.h"

static int is_group_mode(unsigned mode) {
  return (mode >= GROUP_FLAG + MATCH_FULL && mode <= GROUP_FLAG + MATCH_PREFIX) ||
         mode == GROUP_FLAG + MATCH_LETTER;
}

static void write_u16(luaL_Buffer *buffer, unsigned value) {
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
  write_u16(&buffer, (unsigned)count);
  for (unsigned i = 0; i < count; ++i) {
    lua_rawgeti(L, index, (int)i + 1);
    luaL_checktype(L, -1, LUA_TTABLE);
    size_t n = lua_objlen(L, -1);
    lua_pop(L, 1);
    if (n > 65535) {
      luaL_error(L, "too many group spellings");
    }
    write_u16(&buffer, (unsigned)n);
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
        if (!code[k] || (unsigned char)code[k] >= 128) {
          luaL_error(L, "group spellings must be non-NUL ASCII");
        }
      }
      /* The groups table pins the string while the buffer allocates chunks. */
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
  unsigned count = read_u16(data);
  CodeGroups *groups =
      (CodeGroups *)lua_newuserdata(L, sizeof(CodeGroups) + count * sizeof(CodeGroup));
  groups->count = count;
  const unsigned char *p = data + 2, *end = data + size;
  for (unsigned i = 0; i < count; ++i) {
    if (end - p < 2) {
      luaL_error(L, "invalid binary group spellings");
    }
    unsigned n = read_u16(p);
    p += 2;
    CodeGroup *group = &groups->groups[i];
    group->begin = p;
    group->first_byte = 128;
    for (unsigned j = 0; j < n; ++j) {
      if (p == end || !*p || (size_t)(end - p - 1) < *p) {
        luaL_error(L, "invalid binary group spelling length");
      }
      unsigned length = *p++;
      if (!j) {
        group->first_byte = *p;
      } else if (group->first_byte != *p) {
        group->first_byte = 128;
      }
      for (unsigned k = 0; k < length; ++k) {
        unsigned byte = *p++;
        if (!byte || byte >= 128) {
          luaL_error(L, "binary group spellings must be non-NUL ASCII");
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

static const unsigned char *read_section(lua_State *L, const unsigned char **at,
                                         const unsigned char *end, uint32_t count, size_t width) {
  if (count > (size_t)(end - *at) / width) {
    luaL_error(L, "invalid flash-any binary: truncated section");
  }
  const unsigned char *start = *at;
  *at += (size_t)count * width;
  return start;
}

static int32_t single_scalar(Slice key) {
  uint32_t at = 0;
  int32_t cp = decode((const unsigned char *)key.data, key.size, &at);
  return at == key.size ? cp : -1;
}

static void pack_u32(uint32_t *values, uint32_t count) {
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t value = values[i];
    unsigned char *bytes = (unsigned char *)(values + i);
    bytes[0] = value & 255;
    bytes[1] = (value >> 8) & 255;
    bytes[2] = (value >> 16) & 255;
    bytes[3] = value >> 24;
  }
}

/* Validate a terminated list using its grammar: zero bytes inside a u16 group
 * ID are payload, not terminators. literal_scalar is -1 for the text-key table. */
static int validate_codes(lua_State *L, const Dictionary *dictionary, uint32_t offset,
                          uint32_t pool_size, const CodeGroups *groups, int32_t literal_scalar) {
  if (offset >= pool_size) {
    return luaL_error(L, "invalid binary code offset");
  }
  const unsigned char *p = dictionary->pool + offset, *begin = p;
  const unsigned char *end = dictionary->pool + pool_size;
  int letters = 0;
  while (p < end && *p) {
    unsigned tag = *p++;
    if (tag >= MATCHER_TAG && is_group_mode(tag - MATCHER_TAG)) {
      if (end - p < 2 || !groups || read_u16(p) >= groups->count) {
        return luaL_error(L, "invalid binary group reference");
      }
      letters |= tag == MATCHER_TAG + GROUP_FLAG + MATCH_LETTER;
      p += 2;
      continue;
    }
    if (tag < MATCHER_TAG || tag > MATCHER_TAG + MATCH_LETTER) {
      return luaL_error(L, "invalid binary matcher ID");
    }
    letters |= tag == MATCHER_TAG + MATCH_LETTER;
    if (tag == MATCHER_TAG + MATCH_SUFFIX) {
      if (p == end || !*p || *p >= 128 || (size_t)(end - p - 1) < *p) {
        return luaL_error(L, "invalid binary input-key metadata");
      }
      unsigned count = *p++;
      for (unsigned j = 0; j < count; ++j) {
        unsigned byte = *p++;
        if (!byte || byte >= 128) {
          return luaL_error(L, "binary input-key metadata must be non-NUL ASCII");
        }
      }
    }
    const unsigned char *code = p;
    while (p < end && *p && *p < 128) {
      ++p;
    }
    if (p == code) {
      return luaL_error(L, "invalid binary empty encoding");
    }
    if (tag == MATCHER_TAG + MATCH_LITERAL &&
        (p - code != 1 || literal_scalar < 1 || literal_scalar >= 128 || *code != literal_scalar)) {
      return luaL_error(L, "invalid binary literal encoding");
    }
  }
  if (p == begin || p == end) {
    return luaL_error(L, "invalid binary code-list terminator");
  }
  return letters;
}

/* owner is the positive Lua stack index of the string/userdata backing data. */
static int load_data(lua_State *L, const unsigned char *data, size_t size, int owner) {
  if (size < BINARY_HEADER || memcmp(data, BINARY_MAGIC, 8)) {
    return luaL_error(L, "invalid flash-any binary: magic/version");
  }
  if (read_u32(data + 8) != UNICODE_VERSION) {
    return luaL_error(L, "unsupported binary Unicode version");
  }
  if (read_u32(data + 12) != size) {
    return luaL_error(L, "invalid flash-any binary: size");
  }
  uint32_t text_count = read_u32(data + 16), units = read_u32(data + 20);
  uint32_t npages = read_u32(data + 24), pool_size = read_u32(data + 28);
  uint32_t groups_size = read_u32(data + 32), scalar_count = read_u32(data + 36);
  if (units > TRIE_MAX_UNITS || npages > UNICODE_PAGES || scalar_count > 0x110000u ||
      (!text_count != !units)) {
    return luaL_error(L, "invalid binary index size");
  }
  const unsigned char *at = data + BINARY_HEADER, *end = data + size;
  const unsigned char *directory = read_section(L, &at, end, npages ? UNICODE_PAGES : 0, 4);
  const unsigned char *pages = read_section(L, &at, end, npages * 256, 4);
  const unsigned char *trie = read_section(L, &at, end, units, 8);
  const unsigned char *pool = read_section(L, &at, end, pool_size, 1);
  const unsigned char *groups_data = read_section(L, &at, end, groups_size, 1);
  if (at != end) {
    return luaL_error(L, "invalid flash-any binary: trailing data");
  }
  CodeGroups *groups = groups_size ? load_groups(L, groups_data, groups_size) : NULL;
  int groups_owner = groups ? lua_gettop(L) : 0;
  unsigned char *seen_pages = (unsigned char *)lua_newuserdata(L, npages);
  memset(seen_pages, 0, npages);
  Engine *instance = (Engine *)lua_newuserdata(L, sizeof(Engine));
  instance->groups = groups;
  instance->letters = 0;
  instance->depth = 1;
  Dictionary *dictionary = &instance->table;
  dictionary->scalars = (ScalarTable){scalar_count, npages, directory, pages};
  dictionary->trie = (Trie){units, trie};
  dictionary->pool = pool;

  /* Scalar identity comes entirely from the directory and slot position. Every
   * physical page must have one owner and at least one populated scalar slot. */
  uint32_t occupied = 0, used_pages = 0;
  for (uint32_t high = 0; npages && high < UNICODE_PAGES; ++high) {
    uint32_t page = read_u32(directory + (size_t)high * 4);
    if (!page) {
      continue;
    }
    if (page > npages || seen_pages[page - 1]) {
      return luaL_error(L, "invalid binary page ID");
    }
    seen_pages[page - 1] = 1;
    ++used_pages;
    uint32_t page_count = 0;
    for (uint32_t low = 0; low < 256; ++low) {
      uint32_t offset = read_u32(pages + ((size_t)(page - 1) * 256 + low) * 4);
      if (!offset) {
        continue;
      }
      uint32_t cp = high * 256 + low;
      if (cp >= 0xD800 && cp <= 0xDFFF) {
        return luaL_error(L, "invalid binary surrogate scalar");
      }
      instance->letters |=
          validate_codes(L, dictionary, offset - 1, pool_size, groups, (int32_t)cp);
      ++page_count;
    }
    if (!page_count) {
      return luaL_error(L, "invalid binary empty scalar page");
    }
    occupied += page_count;
  }
  if (used_pages != npages || occupied != scalar_count) {
    return luaL_error(L, "invalid binary scalar occupancy");
  }

  /* Parent checks validate every occupied unit, including disconnected cycles.
   * Depths are memoized so each parent chain is traversed at most twice. */
  uint32_t *depths = lua_newuserdata(L, (size_t)units * sizeof(uint32_t));
  memset(depths, 255, (size_t)units * sizeof(uint32_t));
  occupied = 0;
  if (units) {
    uint64_t root = trie_unit(&dictionary->trie, 0);
    if (trie_parent(root) || ((root >> 24) & TRIE_QUOTIENT_MASK) ||
        trie_kind(root) > TRIE_MAX_BITS - TRIE_MIN_BITS) {
      return luaL_error(L, "invalid binary Trie root");
    }
    depths[0] = 0;
  }
  for (uint32_t i = 1; i < units; ++i) {
    uint64_t unit = trie_unit(&dictionary->trie, i);
    uint32_t parent = trie_parent(unit);
    if (!parent) {
      if (unit) {
        return luaL_error(L, "invalid binary Trie empty slot");
      }
      continue;
    }
    if (parent > units || parent - 1 == i) {
      return luaL_error(L, "invalid binary Trie parent");
    }
    uint64_t owner = trie_unit(&dictionary->trie, parent - 1);
    unsigned kind = trie_kind(unit), owner_kind = trie_kind(owner);
    if ((parent > 1 && !trie_parent(owner)) || owner_kind > TRIE_MAX_BITS - TRIE_MIN_BITS ||
        (kind > TRIE_MAX_BITS - TRIE_MIN_BITS && kind != TRIE_TERMINAL)) {
      return luaL_error(L, "invalid binary Trie node kind");
    }
    unsigned bits = owner_kind + TRIE_MIN_BITS;
    int64_t remainder = (int64_t)i - trie_base(owner);
    if (remainder < 0 || remainder >= (1u << bits)) {
      return luaL_error(L, "invalid binary Trie remainder");
    }
    if (kind == TRIE_TERMINAL) {
      uint32_t codes = (uint32_t)unit;
      if (remainder || ((unit >> 32) & 31) || !codes || parent == 1) {
        return luaL_error(L, "invalid binary Trie terminal");
      }
      instance->letters |= validate_codes(L, dictionary, codes - 1, pool_size, groups, -1);
      ++occupied;
    } else {
      uint64_t cp = (((unit >> 24) & TRIE_QUOTIENT_MASK) << bits) | (uint64_t)remainder;
      if (!cp || cp > 0x1100FF || (cp >= 0xD800 && cp <= 0xDFFF) ||
          (cp > 0x10FFFF && cp < 0x110080)) {
        return luaL_error(L, "invalid binary Trie label");
      }
    }
  }
  if (occupied != text_count) {
    return luaL_error(L, "invalid binary Trie terminal count");
  }
  for (uint32_t i = 1; i < units; ++i) {
    uint64_t unit = trie_unit(&dictionary->trie, i);
    uint32_t check = trie_parent(unit);
    if (!check) {
      continue;
    }
    uint32_t cursor = i, hops = 0;
    while (depths[cursor] == NONE) {
      if (++hops >= units) {
        return luaL_error(L, "cyclic binary Trie");
      }
      cursor = trie_parent(trie_unit(&dictionary->trie, cursor)) - 1;
    }
    uint32_t depth = depths[cursor] + hops;
    cursor = i;
    while (hops--) {
      depths[cursor] = depth--;
      cursor = trie_parent(trie_unit(&dictionary->trie, cursor)) - 1;
    }
    uint32_t key_depth = depths[i] - (trie_kind(unit) == TRIE_TERMINAL);
    if (key_depth > instance->depth) {
      instance->depth = key_depth;
    }
  }
  lua_pop(L, 1);
  /* The dictionary contains borrowed pointers: keep their storage alive with the engine. */
  luaL_getmetatable(L, ENGINE_MT);
  lua_setmetatable(L, -2);
  lua_createtable(L, 0, 2);
  lua_pushvalue(L, owner);
  lua_setfield(L, -2, "bytes");
  if (groups_owner) {
    lua_pushvalue(L, groups_owner);
    lua_setfield(L, -2, "groups");
  }
  lua_newtable(L);
  lua_setfield(L, -2, "windows");
  lua_setfenv(L, -2);
  return 1;
}

int load_binary(lua_State *L) {
  luaL_checktype(L, 1, LUA_TSTRING);
  size_t size;
  const unsigned char *data = (const unsigned char *)lua_tolstring(L, 1, &size);
  return load_data(L, data, size, 1);
}

/* pool[string] is its byte offset; pool[1..n] preserves first-use write order.
 * Entire code lists share this pool. */
static uint32_t intern_string(lua_State *L, int pool, int value, uint32_t *size) {
  lua_pushvalue(L, value);
  lua_rawget(L, pool);
  if (!lua_isnil(L, -1)) {
    uint32_t offset = (uint32_t)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return offset;
  }
  lua_pop(L, 1);
  size_t length;
  lua_tolstring(L, value, &length);
  if (length > UINT32_MAX - *size) {
    luaL_error(L, "binary string pool too large");
  }
  uint32_t offset = *size;
  *size += (uint32_t)length;
  lua_pushvalue(L, value);
  lua_pushinteger(L, offset);
  lua_rawset(L, pool);
  lua_pushvalue(L, value);
  lua_rawseti(L, pool, (int)lua_objlen(L, pool) + 1);
  return offset;
}

/* write(keys, codes, path, groups?): rows contain mode, ASCII code or group ID, optional suffix. */
int write_binary(lua_State *L) {
  lua_settop(L, 4);
  write_groups(L, 4);
  size_t groups_size;
  const char *groups_data = lua_tolstring(L, -1, &groups_size);
  unsigned group_count = groups_size ? read_u16((const unsigned char *)groups_data) : 0;
  luaL_checktype(L, 1, LUA_TTABLE);
  luaL_checktype(L, 2, LUA_TTABLE);
  size_t path_size;
  const char *path = luaL_checklstring(L, 3, &path_size);
  if (!path_size || memchr(path, 0, path_size)) {
    return luaL_error(L, "invalid binary path");
  }
  size_t count = lua_objlen(L, 1);
  if (count > INT_MAX / sizeof(TrieKey) || lua_objlen(L, 2) != count) {
    return luaL_error(L, "invalid binary entry count");
  }
  uint32_t directory[UNICODE_PAGES] = {0};
  uint32_t npages = 0, text_count = 0;
  int32_t *points = (int32_t *)lua_newuserdata(L, count * sizeof(int32_t));
  for (uint32_t i = 0; i < count; ++i) {
    lua_rawgeti(L, 1, (int)i + 1);
    luaL_checktype(L, -1, LUA_TSTRING);
    size_t length;
    const char *key = lua_tolstring(L, -1, &length);
    if (!length || length >= UINT32_MAX) {
      return luaL_error(L, "invalid binary key length");
    }
    int32_t cp = points[i] = single_scalar((Slice){key, (uint32_t)length});
    if (cp < 0) {
      ++text_count;
    } else if (!directory[(uint32_t)cp >> 8]) {
      directory[(uint32_t)cp >> 8] = ++npages;
    }
    lua_pop(L, 1);
  }
  uint32_t page_words = npages ? UNICODE_PAGES + npages * 256 : 0;
  uint32_t *pages = (uint32_t *)lua_newuserdata(L, (size_t)page_words * 4);
  memset(pages, 0, (size_t)page_words * 4);
  if (npages) {
    memcpy(pages, directory, sizeof(directory));
  }
  TrieKey *keys = lua_newuserdata(L, (size_t)text_count * sizeof(TrieKey));
  lua_newtable(L);
  int pool = lua_gettop(L);
  uint32_t pool_size = 0, text_index = 0;
  for (uint32_t i = 0; i < count; ++i) {
    lua_rawgeti(L, 1, (int)i + 1);
    luaL_checktype(L, -1, LUA_TSTRING);
    if (points[i] < 0) {
      size_t key_size;
      const char *key = lua_tolstring(L, -1, &key_size);
      keys[text_index].key = (Slice){key, (uint32_t)key_size};
    }
    lua_pop(L, 1);
    lua_rawgeti(L, 2, (int)i + 1);
    luaL_checktype(L, -1, LUA_TTABLE);
    int codes = lua_gettop(L);
    size_t ncode = lua_objlen(L, codes);
    if (!ncode) {
      return luaL_error(L, "invalid binary empty code list");
    }
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    for (size_t j = 0; j < ncode; ++j) {
      lua_rawgeti(L, codes, (int)j + 1);
      luaL_checktype(L, -1, LUA_TTABLE);
      lua_rawgeti(L, -1, 1);
      int mode = luaL_checkint(L, -1);
      lua_pop(L, 1);
      if (mode >= 0 && is_group_mode((unsigned)mode)) {
        lua_rawgeti(L, -1, 2);
        lua_Number value = luaL_checknumber(L, -1);
        if (!(value >= 0 && value < group_count) || value != (unsigned)value) {
          return luaL_error(L, "invalid group reference");
        }
        unsigned id = (unsigned)value;
        lua_pop(L, 2);
        luaL_addchar(&buffer, (char)(MATCHER_TAG + mode));
        write_u16(&buffer, id);
        continue;
      }
      if (mode < MATCH_LITERAL || mode > MATCH_LETTER) {
        return luaL_error(L, "invalid binary matcher mode");
      }
      lua_rawgeti(L, -1, 2);
      luaL_checktype(L, -1, LUA_TSTRING);
      size_t length;
      const char *code = lua_tolstring(L, -1, &length);
      if (!length) {
        return luaL_error(L, "invalid binary empty encoding");
      }
      for (size_t k = 0; k < length; ++k) {
        if (!code[k] || (unsigned char)code[k] >= MATCHER_TAG) {
          return luaL_error(L, "binary codes must be non-NUL ASCII");
        }
      }
      const char *parameters = NULL;
      size_t parameter_size = 0;
      if (mode == MATCH_SUFFIX) {
        lua_rawgeti(L, -2, 3);
        parameters = luaL_checklstring(L, -1, &parameter_size);
        if (!parameter_size || parameter_size >= 128) {
          return luaL_error(L, "invalid input-key metadata");
        }
        for (size_t k = 0; k < parameter_size; ++k) {
          if (!parameters[k] || (unsigned char)parameters[k] >= 128) {
            return luaL_error(L, "input-key metadata must be non-NUL ASCII");
          }
        }
        lua_pop(L, 1);
      }
      /* codes pins both strings; pop our pair before the buffer pushes chunks. */
      lua_pop(L, 2);
      luaL_addchar(&buffer, (char)(MATCHER_TAG + mode));
      if (mode == MATCH_SUFFIX) {
        luaL_addchar(&buffer, (char)parameter_size);
        luaL_addlstring(&buffer, parameters, parameter_size);
      }
      luaL_addlstring(&buffer, code, length);
    }
    luaL_addchar(&buffer, 0);
    luaL_pushresult(&buffer);
    uint32_t offset = intern_string(L, pool, lua_gettop(L), &pool_size);
    if (points[i] >= 0) {
      uint32_t cp = (uint32_t)points[i];
      uint32_t slot = UNICODE_PAGES + (directory[cp >> 8] - 1) * 256 + (cp & 255);
      if (pages[slot]) {
        return luaL_error(L, "duplicate binary scalar key");
      }
      pages[slot] = offset + 1;
    } else {
      keys[text_index++].codes = offset;
    }
    lua_pop(L, 2);
  }
  uint32_t trie_size;
  uint32_t *trie = build_trie(L, keys, text_count, &trie_size);
  uint64_t total =
      BINARY_HEADER + (uint64_t)page_words * 4 + (uint64_t)trie_size * 8 + pool_size + groups_size;
  if (total > UINT32_MAX || total > SIZE_MAX) {
    return luaL_error(L, "binary table exceeds format limits");
  }
  unsigned char *data = (unsigned char *)lua_newuserdata(L, (size_t)total);
  int owner = lua_gettop(L);
  uint32_t header[] = {UNICODE_VERSION,
                       (uint32_t)total,
                       text_count,
                       trie_size,
                       npages,
                       pool_size,
                       (uint32_t)groups_size,
                       (uint32_t)count - text_count};
  pack_u32(header, 8);
  pack_u32(pages, page_words);
  pack_u32(trie, trie_size * 2);
  memcpy(data, BINARY_MAGIC, 8);
  memcpy(data + 8, header, sizeof(header));
  unsigned char *at = data + BINARY_HEADER;
  memcpy(at, pages, (size_t)page_words * 4);
  at += (size_t)page_words * 4;
  memcpy(at, trie, (size_t)trie_size * 8);
  at += (size_t)trie_size * 8;
  for (size_t i = 0, n = lua_objlen(L, pool); i < n; ++i) {
    lua_rawgeti(L, pool, (int)i + 1);
    size_t length;
    const char *value = lua_tolstring(L, -1, &length);
    memcpy(at, value, length);
    at += length;
    lua_pop(L, 1);
  }
  memcpy(at, groups_data, groups_size);
  /* All Lua allocations and format checks precede opening the temporary file. */
  load_data(L, data, (size_t)total, owner);
  lua_pop(L, 1);
  char *temporary = (char *)lua_newuserdata(L, path_size + sizeof(".XXXXXX"));
  memcpy(temporary, path, path_size);
  memcpy(temporary + path_size, ".XXXXXX", sizeof(".XXXXXX"));
  int fd = mkstemp(temporary);
  if (fd < 0) {
    return luaL_error(L, "cannot create binary file: %s", strerror(errno));
  }
  FILE *file = fdopen(fd, "wb");
  if (!file) {
    int failed = errno;
    close(fd);
    unlink(temporary);
    return luaL_error(L, "cannot open binary output: %s", strerror(failed));
  }
  int failed = fwrite(data, 1, (size_t)total, file) != (size_t)total ? (errno ? errno : EIO) : 0;
  if (fclose(file) && !failed) {
    failed = errno;
  }
  if (!failed && rename(temporary, path)) {
    failed = errno;
  }
  if (failed) {
    unlink(temporary);
    return luaL_error(L, "cannot write binary file: %s", strerror(failed));
  }
  return 0;
}

int open_binary(lua_State *L) {
  luaL_checktype(L, 1, LUA_TSTRING);
  size_t path_size;
  const char *path = lua_tolstring(L, 1, &path_size);
  if (memchr(path, 0, path_size)) {
    return luaL_error(L, "invalid binary path");
  }
  struct stat info;
  if (stat(path, &info) || !S_ISREG(info.st_mode)) {
    return luaL_error(L, "cannot stat binary file: %s", path);
  }
  if (info.st_size < BINARY_HEADER || (uint64_t)info.st_size > UINT32_MAX) {
    return luaL_error(L, "invalid binary file size");
  }
  size_t size = (size_t)info.st_size;
  /* Allocate before opening: a Lua allocation error cannot leak a file handle.
   * This frozen snapshot needs no mmap lifetime or Lua IO scratch buffer.
   */
  unsigned char *data = (unsigned char *)lua_newuserdata(L, size);
  int owner = lua_gettop(L);
  FILE *file = fopen(path, "rb");
  if (!file) {
    return luaL_error(L, "cannot open binary file: %s", strerror(errno));
  }
  size_t got = fread(data, 1, size, file);
  int extra = fgetc(file), failed = ferror(file);
  int close_failed = fclose(file);
  if (got != size || extra != EOF || failed || close_failed) {
    return luaL_error(L, "cannot read complete binary snapshot");
  }
  return load_data(L, data, size, owner);
}

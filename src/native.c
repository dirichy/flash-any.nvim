#define _POSIX_C_SOURCE 200809L
/* Unified grapheme dictionary and callback-free scanning. Unicode/indexing has one C owner. */
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include "text.h"
/* Header: magic[8], Unicode version, file bytes, entry count, hash slots,
 * scalar pages, pool bytes, reserved[2]. All numeric fields are little-endian u32. */
#define BINARY_MAGIC "FANYBIN\5"
#define BINARY_HEADER 40u
#define BINARY_ENTRY 16u
#define UNICODE_VERSION 17u
#define ENGINE_MT "flash-any.native-engine"
#define NONE UINT32_MAX
/* High-bit tags delimit ASCII codes, so no separator or terminator is needed. */
#define MATCHER_TAG 0x80u
#define REQUEST_SLOTS 2u

enum { MATCH_LITERAL, MATCH_FULL, MATCH_INITIAL, MATCH_PREFIX };

enum { EMIT_CONSUMED, EMIT_NEXT };

typedef struct {
  const char *data;
  uint32_t size;
} Slice;

typedef struct {
  Slice key, codes;
} Entry;

/* Views into one immutable binary snapshot; the engine environment pins its bytes. */
typedef struct {
  uint32_t nentry, capacity, npages;
  const unsigned char *entries, *hashes, *pages, *pool;
} Dictionary;

typedef struct {
  Dictionary table;
} Engine;

typedef struct {
  uint32_t row; /* 1-based; all columns below are 0-based byte offsets. */
  uint32_t start, end; /* end points to the last scalar, as Flash expects. */
  uint32_t before, after; /* Adjacent grapheme starts for t/T; NONE at line edges. */
  uint32_t valid;
  uint64_t next[2]; /* 128 ASCII next-input bits: these keys cannot become labels. */
} Match;

/* Match[capacity] follows this header; only the first count entries are live. */
typedef struct {
  uint32_t count, capacity;
} Result;

/* A single-grapheme table entry can advance only to the next grapheme, so
 * current/next positions share two slots, selected by glyph_index % 2. */
typedef struct {
  uint32_t width; /* Input byte length + 1. */
  uint32_t *starts; /* [slot][input offset]: earliest text start, or NONE. */
  uint32_t *offsets; /* [slot][active index]: sparse list of input offsets. */
  uint32_t *counts;
  uint32_t *lookahead; /* Previous match needs this glyph's next-input bits. */
} Requests;

typedef struct {
  Slice codes;
  const char *input;
  uint32_t input_size, input_offset; /* Byte length and current input position. */
  uint32_t glyph_index;
  uint32_t glyph_after, glyph_end; /* Exclusive byte end and final scalar's start. */
  uint32_t text_size;
  uint32_t match_start;
  Match current; /* Independent of result storage, which may move when it grows. */
  Match *completed; /* Existing result receiving next-input bits, not a new match. */
  Requests *requests;
  int character, found;
} MatchContext;

static int compare(Slice a, Slice b) {
  uint32_t n = a.size < b.size ? a.size : b.size;
  int value = memcmp(a.data, b.data, n);
  return value ? value : (a.size > b.size) - (a.size < b.size);
}

/* Fixed little-endian records permit zero-copy lookup from the immutable blob.
 * Explicit byte loads also work on unaligned strings and big-endian hosts.
 */
static uint32_t word(const unsigned char *p) {
  return p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static Slice stored(Dictionary *dictionary, const unsigned char *record) {
  Slice value = {(const char *)dictionary->pool + word(record), word(record + 4)};
  return value;
}

static Entry entry_at(Dictionary *dictionary, uint32_t index) {
  const unsigned char *record = dictionary->entries + (size_t)index * BINARY_ENTRY;
  Entry entry = {stored(dictionary, record), stored(dictionary, record + 8)};
  return entry;
}

static const unsigned char *section(lua_State *L, const unsigned char **at,
                                    const unsigned char *end, uint32_t count, size_t width) {
  if (count > (size_t)(end - *at) / width) {
    luaL_error(L, "invalid flash-any binary: truncated section");
  }
  const unsigned char *start = *at;
  *at += (size_t)count * width;
  return start;
}

static int span_valid(uint32_t first, uint32_t count, uint32_t size) {
  return first <= size && count <= size - first;
}

static void valid_string(lua_State *L, const unsigned char *record, uint32_t size) {
  uint32_t offset = word(record), length = word(record + 4);
  if (!length || !span_valid(offset, length, size)) {
    luaL_error(L, "invalid flash-any binary: string offset");
  }
}

/* Codepoint FNV-style mixing. Malformed bytes get distinct out-of-range
 * tokens; they remain isolated graphemes and must not all hash as scalar -1. */
static uint32_t hash_key(Slice key) {
  uint32_t hash = UINT32_C(2166136261), at = 0;
  while (at < key.size) {
    uint32_t before = at;
    int32_t cp = decode((const unsigned char *)key.data, key.size, &at);
    uint32_t value = cp >= 0 ? (uint32_t)cp : 0x110000u + (unsigned char)key.data[before];
    hash = (hash ^ value) * UINT32_C(16777619);
  }
  return hash;
}

/* Single scalars use a sparse directory of 256-codepoint pages. Zero means
 * absent; page slots and hash slots store entry ordinal + 1. */
#define UNICODE_PAGES 0x1100u

static int32_t single_scalar(Slice key) {
  uint32_t at = 0;
  int32_t cp = decode((const unsigned char *)key.data, key.size, &at);
  return at == key.size ? cp : -1;
}

static void pack_words(uint32_t *values, uint32_t count) {
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t value = values[i];
    unsigned char *bytes = (unsigned char *)(values + i);
    bytes[0] = value & 255;
    bytes[1] = (value >> 8) & 255;
    bytes[2] = (value >> 16) & 255;
    bytes[3] = value >> 24;
  }
}

/* keys[] in; packed hash/pages, hash capacity and scalar-page count out. */
static int build_index(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t count = lua_objlen(L, 1);
  if (count > INT_MAX / 4) {
    return luaL_error(L, "binary index too large");
  }
  uint32_t directory[UNICODE_PAGES] = {0};
  uint32_t npages = 0, complex = 0;
  int32_t *points = (int32_t *)lua_newuserdata(L, count * sizeof(int32_t));
  for (uint32_t i = 0; i < count; ++i) {
    lua_rawgeti(L, 1, (int)i + 1);
    luaL_checktype(L, -1, LUA_TSTRING);
    size_t length;
    const char *key = lua_tolstring(L, -1, &length);
    if (!length || length >= UINT32_MAX) {
      return luaL_error(L, "invalid binary key length");
    }
    Slice value = {key, (uint32_t)length};
    int32_t cp = points[i] = single_scalar(value);
    if (cp < 0) {
      ++complex;
    } else if (!directory[(uint32_t)cp >> 8]) {
      directory[(uint32_t)cp >> 8] = ++npages;
    }
    lua_pop(L, 1);
  }
  uint32_t capacity = complex ? 1 : 0;
  /* Keep load <= 3/4 so linear probes have an empty stopping slot. */
  while ((uint64_t)capacity * 3 < (uint64_t)complex * 4) {
    if (capacity > INT_MAX / 8) {
      return luaL_error(L, "binary hash index too large");
    }
    capacity *= 2;
  }
  uint32_t page_words = npages ? UNICODE_PAGES + npages * 256 : 0;
  uint32_t total = capacity + page_words;
  if (total > INT_MAX / 4) {
    return luaL_error(L, "binary index too large");
  }
  uint32_t *slots = (uint32_t *)lua_newuserdata(L, (size_t)total * 4);
  memset(slots, 0, (size_t)total * 4);
  if (npages) {
    memcpy(slots + capacity, directory, sizeof(directory));
  }
  for (uint32_t i = 0; i < count; ++i) {
    if (points[i] >= 0) {
      uint32_t cp = (uint32_t)points[i];
      slots[capacity + UNICODE_PAGES + (directory[cp >> 8] - 1) * 256 + (cp & 255)] = i + 1;
    } else {
      lua_rawgeti(L, 1, (int)i + 1);
      size_t length;
      const char *key = lua_tolstring(L, -1, &length);
      Slice value = {key, (uint32_t)length};
      uint32_t slot = hash_key(value) & (capacity - 1);
      while (slots[slot]) {
        slot = (slot + 1) & (capacity - 1);
      }
      slots[slot] = i + 1;
      lua_pop(L, 1);
    }
  }
  pack_words(slots, total);
  lua_pushlstring(L, (const char *)slots, (size_t)total * 4);
  lua_pushinteger(L, capacity);
  lua_pushinteger(L, npages);
  return 3;
}

static uint32_t lookup(Dictionary *dictionary, Slice key);

/* owner is the positive Lua stack index of the string/userdata backing data. */
static int load_data(lua_State *L, const unsigned char *data, size_t size, int owner) {
  if (size < BINARY_HEADER || memcmp(data, BINARY_MAGIC, 8)) {
    return luaL_error(L, "invalid flash-any binary: magic/version");
  }
  if (word(data + 8) != UNICODE_VERSION) {
    return luaL_error(L, "unsupported binary Unicode version");
  }
  if (word(data + 12) != size || word(data + 32) || word(data + 36)) {
    return luaL_error(L, "invalid flash-any binary: size/flags");
  }
  uint32_t entry_count = word(data + 16);
  uint32_t capacity = word(data + 20);
  uint32_t npages = word(data + 24);
  uint32_t pool_size = word(data + 28);
  if ((capacity & (capacity - 1)) || npages > UNICODE_PAGES) {
    return luaL_error(L, "invalid binary index size");
  }
  const unsigned char *at = data + BINARY_HEADER, *end = data + size;
  const unsigned char *entries = section(L, &at, end, entry_count, BINARY_ENTRY);
  const unsigned char *hashes = section(L, &at, end, capacity, 4);
  const unsigned char *pages = section(L, &at, end, npages ? UNICODE_PAGES + npages * 256 : 0, 4);
  const unsigned char *pool = section(L, &at, end, pool_size, 1);
  if (at != end) {
    return luaL_error(L, "invalid flash-any binary: trailing data");
  }
  Engine *instance = (Engine *)lua_newuserdata(L, sizeof(Engine));
  Dictionary *dictionary = &instance->table;
  dictionary->nentry = entry_count;
  dictionary->capacity = capacity;
  dictionary->npages = npages;
  dictionary->entries = entries;
  dictionary->hashes = hashes;
  dictionary->pages = pages;
  dictionary->pool = pool;
  for (uint32_t i = 0; i < entry_count; ++i) {
    const unsigned char *record = entries + (size_t)i * BINARY_ENTRY;
    valid_string(L, record, pool_size);
    valid_string(L, record + 8, pool_size);
    Entry entry = entry_at(dictionary, i);
    if (i && compare(entry_at(dictionary, i - 1).key, entry.key) >= 0) {
      return luaL_error(L, "invalid binary unsorted keys");
    }
    const unsigned char *p = (const unsigned char *)entry.codes.data, *limit = p + entry.codes.size;
    while (p < limit) {
      unsigned mode = *p++;
      if (mode < MATCHER_TAG || mode > MATCHER_TAG + MATCH_PREFIX) {
        return luaL_error(L, "invalid binary matcher ID");
      }
      const unsigned char *code = p;
      while (p < limit && *p < 128) {
        ++p;
      }
      if (p == code) {
        return luaL_error(L, "invalid binary empty encoding");
      }
      if (mode == MATCHER_TAG + MATCH_LITERAL &&
          (p - code != 1 || entry.key.size != 1 || (unsigned char)entry.key.data[0] != *code)) {
        return luaL_error(L, "invalid binary literal encoding");
      }
    }
  }
  uint32_t occupied = 0;
  for (uint32_t i = 0; i < capacity; ++i) {
    uint32_t id = word(hashes + (size_t)i * 4);
    if (id > entry_count) {
      return luaL_error(L, "invalid binary hash entry");
    }
    if (id) {
      ++occupied;
    }
  }
  if (npages) {
    for (uint32_t i = 0; i < UNICODE_PAGES; ++i) {
      if (word(pages + (size_t)i * 4) > npages) {
        return luaL_error(L, "invalid binary page ID");
      }
    }
    for (uint32_t i = 0; i < npages * 256; ++i) {
      uint32_t id = word(pages + ((size_t)UNICODE_PAGES + i) * 4);
      if (id > entry_count) {
        return luaL_error(L, "invalid binary scalar entry");
      }
      if (id) {
        ++occupied;
      }
    }
  }
  /* Occupancy alone is insufficient: every key must reach its own entry. */
  if (occupied != entry_count) {
    return luaL_error(L, "invalid binary index occupancy");
  }
  for (uint32_t i = 0; i < entry_count; ++i) {
    if (lookup(dictionary, entry_at(dictionary, i).key) != i) {
      return luaL_error(L, "invalid binary index");
    }
  }
  /* The dictionary contains borrowed pointers: keep their storage alive with the engine. */
  luaL_getmetatable(L, ENGINE_MT);
  lua_setmetatable(L, -2);
  lua_createtable(L, 0, 2);
  lua_pushvalue(L, owner);
  lua_setfield(L, -2, "bytes");
  lua_newtable(L);
  lua_setfield(L, -2, "windows");
  lua_setfenv(L, -2);
  return 1;
}

static int load_binary(lua_State *L) {
  luaL_checktype(L, 1, LUA_TSTRING);
  size_t size;
  const unsigned char *data = (const unsigned char *)lua_tolstring(L, 1, &size);
  return load_data(L, data, size, 1);
}

/* pool[string] is its byte offset; pool[1..n] preserves first-use write order.
 * Keys and entire code lists share this pool. */
static uint32_t intern(lua_State *L, int pool, int value, uint32_t *size) {
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

/* Lua: write(keys, codes, path), with byte-sorted keys and codes[i] = {{mode, code}, ...}. */
static int write_binary(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  luaL_checktype(L, 2, LUA_TTABLE);
  size_t path_size;
  const char *path = luaL_checklstring(L, 3, &path_size);
  if (!path_size || memchr(path, 0, path_size)) {
    return luaL_error(L, "invalid binary path");
  }
  size_t count = lua_objlen(L, 1);
  if (count > INT_MAX / BINARY_ENTRY || lua_objlen(L, 2) != count) {
    return luaL_error(L, "invalid binary entry count");
  }
  /* Keep the returned index string on the stack while assembling the package. */
  lua_pushcfunction(L, build_index);
  lua_pushvalue(L, 1);
  lua_call(L, 1, 3);
  size_t index_size;
  const char *index = lua_tolstring(L, -3, &index_size);
  uint32_t capacity = (uint32_t)lua_tointeger(L, -2), pages = (uint32_t)lua_tointeger(L, -1);
  uint32_t *entries = (uint32_t *)lua_newuserdata(L, count * BINARY_ENTRY);
  lua_newtable(L);
  int pool = lua_gettop(L);
  uint32_t pool_size = 0;
  for (uint32_t i = 0; i < count; ++i) {
    lua_rawgeti(L, 1, (int)i + 1);
    luaL_checktype(L, -1, LUA_TSTRING);
    size_t key_size;
    lua_tolstring(L, -1, &key_size);
    entries[i * 4] = intern(L, pool, lua_gettop(L), &pool_size);
    entries[i * 4 + 1] = (uint32_t)key_size;
    lua_pop(L, 1);
    lua_rawgeti(L, 2, (int)i + 1);
    luaL_checktype(L, -1, LUA_TTABLE);
    int codes = lua_gettop(L);
    size_t ncode = lua_objlen(L, codes);
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    for (size_t j = 0; j < ncode; ++j) {
      lua_rawgeti(L, codes, (int)j + 1);
      luaL_checktype(L, -1, LUA_TTABLE);
      lua_rawgeti(L, -1, 1);
      int mode = luaL_checkint(L, -1);
      lua_pop(L, 1);
      if (mode < MATCH_LITERAL || mode > MATCH_PREFIX) {
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
        if ((unsigned char)code[k] >= MATCHER_TAG) {
          return luaL_error(L, "binary codes must be ASCII");
        }
      }
      /* codes pins the string; pop our pair before the buffer pushes chunks. */
      lua_pop(L, 2);
      luaL_addchar(&buffer, (char)(MATCHER_TAG + mode));
      luaL_addlstring(&buffer, code, length);
    }
    luaL_pushresult(&buffer);
    size_t code_size;
    lua_tolstring(L, -1, &code_size);
    entries[i * 4 + 2] = intern(L, pool, lua_gettop(L), &pool_size);
    entries[i * 4 + 3] = (uint32_t)code_size;
    lua_pop(L, 2);
  }
  uint64_t total = BINARY_HEADER + count * BINARY_ENTRY + index_size + pool_size;
  if (total > UINT32_MAX || total > SIZE_MAX) {
    return luaL_error(L, "binary table exceeds format limits");
  }
  unsigned char *data = (unsigned char *)lua_newuserdata(L, (size_t)total);
  int owner = lua_gettop(L);
  uint32_t header[] = {
      UNICODE_VERSION, (uint32_t)total, (uint32_t)count, capacity, pages, pool_size, 0, 0};
  pack_words(header, 8);
  pack_words(entries, (uint32_t)count * 4);
  memcpy(data, BINARY_MAGIC, 8);
  memcpy(data + 8, header, sizeof(header));
  unsigned char *at = data + BINARY_HEADER;
  memcpy(at, entries, count * BINARY_ENTRY);
  at += count * BINARY_ENTRY;
  memcpy(at, index, index_size);
  at += index_size;
  for (size_t i = 0, n = lua_objlen(L, pool); i < n; ++i) {
    lua_rawgeti(L, pool, (int)i + 1);
    size_t length;
    const char *value = lua_tolstring(L, -1, &length);
    memcpy(at, value, length);
    at += length;
    lua_pop(L, 1);
  }
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

static int open_binary(lua_State *L) {
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

static Engine *engine(lua_State *L) {
  return (Engine *)luaL_checkudata(L, 1, ENGINE_MT);
}

/* Dictionary bytes are shared; query caches follow the Flash state lifetime. */
static int new_state(lua_State *L) {
  Engine *owner = engine(L);
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
static int window(lua_State *L, int create_new) {
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
  engine(L);
  int window_index = window(L, 0);
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

static uint32_t text_lookup(Dictionary *dictionary, Slice key, uint32_t hash) {
  if (!dictionary->capacity) {
    return NONE;
  }
  uint32_t slot = hash & (dictionary->capacity - 1);
  for (uint32_t probes = 0; probes < dictionary->capacity; ++probes) {
    uint32_t id = word(dictionary->hashes + (size_t)slot * 4);
    if (!id) {
      return NONE;
    }
    if (!compare(entry_at(dictionary, id - 1).key, key)) {
      return id - 1;
    }
    slot = (slot + 1) & (dictionary->capacity - 1);
  }
  return NONE;
}

static uint32_t scalar_lookup(Dictionary *dictionary, uint32_t cp) {
  if (!dictionary->npages || cp > 0x10FFFF) {
    return NONE;
  }
  uint32_t page = word(dictionary->pages + (size_t)(cp >> 8) * 4);
  if (!page) {
    return NONE;
  }
  uint32_t id =
      word(dictionary->pages + ((size_t)UNICODE_PAGES + (page - 1) * 256 + (cp & 255)) * 4);
  return id ? id - 1 : NONE;
}

/* Cold validation / benchmark convenience. The scanner already has the scalar. */
static uint32_t lookup(Dictionary *dictionary, Slice key) {
  int32_t cp = single_scalar(key);
  return cp >= 0 ? scalar_lookup(dictionary, (uint32_t)cp)
                 : text_lookup(dictionary, key, hash_key(key));
}

static void request(Requests *requests, uint32_t glyph, uint32_t offset, uint32_t start) {
  uint32_t slot = glyph % REQUEST_SLOTS;
  uint32_t *starts = requests->starts + (size_t)slot * requests->width;
  /* Equal glyph/input positions have identical futures; retain the earliest start. */
  if (starts[offset] == NONE) {
    requests->offsets[(size_t)slot * requests->width + requests->counts[slot]++] = offset;
    starts[offset] = start;
  } else if (start < starts[offset]) {
    starts[offset] = start;
  }
}

static void emit(MatchContext *context, int is_next, uint32_t value) {
  if (context->character) {
    context->found = 1;
    return;
  }
  /* A completed input still examines the next glyph to reserve label keys. */
  if (context->completed) {
    if (is_next) {
      context->completed->next[value >> 6] |= (uint64_t)1 << (value & 63);
    }
    return;
  }
  uint32_t end_glyph = context->glyph_index;
  uint32_t after = context->glyph_after;
  /* EMIT_NEXT passes a possible next input byte; EMIT_CONSUMED passes a length. */
  int complete = !is_next && value == context->input_size - context->input_offset;
  if (is_next || complete) {
    Match *m = &context->current;
    if (!m->valid) {
      m->valid = 1;
      m->start = context->match_start;
      m->end = context->glyph_end;
    } else if (context->match_start < m->start) {
      m->start = context->match_start;
    }
    if (is_next) {
      m->next[value >> 6] |= (uint64_t)1 << (value & 63);
    }
    /* Defer next-glyph label exclusions until that glyph is decoded. */
    if (complete && after < context->text_size) {
      context->requests->lookahead[(end_glyph + 1) % REQUEST_SLOTS] = 1;
    }
  } else if (after < context->text_size) {
    request(context->requests, end_glyph + 1, context->input_offset + value, context->match_start);
  }
}

/* Literal consumes only a whole one-byte input grapheme.
 * ASCII controls break before combining marks; CR+LF is the exception.
 */
static int one_byte_input(MatchContext *context) {
  uint32_t at = context->input_offset;
  unsigned char ch = (unsigned char)context->input[at];
  if (ch >= 128) {
    return 0;
  }
  if (at + 1 == context->input_size) {
    return 1;
  }
  if (ch == 13 && context->input[at + 1] == 10) {
    return 0;
  }
  if (ch < 32 || ch == 127) {
    return 1;
  }
  ++at;
  int32_t next = decode((const unsigned char *)context->input, context->input_size, &at);
  unsigned g = property(next) & GCB_MASK;
  return g != GCB_EXTEND && g != GCB_ZWJ && g != GCB_SPACING_MARK;
}

static void match_codes(MatchContext *context) {
  if (!context->codes.size) {
    return;
  }
  const unsigned char *p = (const unsigned char *)context->codes.data,
                      *end = p + context->codes.size;
  uint32_t size = context->input_size - context->input_offset, maximum = 0;
  int initial = 0;
  while (p < end) {
    unsigned mode = *p++ - MATCHER_TAG;
    const unsigned char *code = p;
    while (p < end && *p < 128) {
      ++p;
    }
    uint32_t length = (uint32_t)(p - code);
    if (mode == MATCH_LITERAL) {
      if (!size) {
        emit(context, EMIT_NEXT, code[0]);
      } else if ((unsigned char)context->input[context->input_offset] == code[0] &&
                 one_byte_input(context)) {
        emit(context, EMIT_CONSUMED, 1);
      }
      continue;
    }
    uint32_t common = 0;
    while (common < size && common < length &&
           code[common] == (unsigned char)context->input[context->input_offset + common]) {
      ++common;
    }
    if (length > size && common == size) {
      emit(context, EMIT_NEXT, code[size]);
    }
    if (common == length && (mode == MATCH_FULL || (mode == MATCH_INITIAL && length > 1))) {
      emit(context, EMIT_CONSUMED, length);
    }
    if (mode == MATCH_INITIAL && common) {
      initial = 1;
    }
    if (mode == MATCH_PREFIX && common > maximum) {
      maximum = common;
    }
  }
  /* Emit shared initial/prefix lengths once, even when several codes agree. */
  if (initial) {
    emit(context, EMIT_CONSUMED, 1);
  }
  for (uint32_t bytes = 1; bytes <= maximum; ++bytes) {
    emit(context, EMIT_CONSUMED, bytes);
  }
}

/* Grow only when a grapheme actually matches. Pointers are refreshed after
 * growth; the userdata at result_index owns the full result throughout scan(). */
static Result *append_match(lua_State *L, int result_index, Result *r, Match *match) {
  if (r->count == r->capacity) {
    uint32_t maximum = (INT_MAX - sizeof(Result)) / sizeof(Match);
    if (r->count == maximum) {
      luaL_error(L, "native result too large");
    }
    uint32_t capacity = r->capacity ? (r->capacity > maximum / 2 ? maximum : r->capacity * 2) : 64;
    Result *next = (Result *)lua_newuserdata(L, sizeof(Result) + (size_t)capacity * sizeof(Match));
    next->count = r->count;
    next->capacity = capacity;
    memcpy(next + 1, r + 1, (size_t)r->count * sizeof(Match));
    lua_replace(L, result_index);
    r = next;
  }
  ((Match *)(r + 1))[r->count++] = *match;
  return r;
}

static Result *scan_grapheme(lua_State *L, int result_index, Result *result, MatchContext *context,
                             uint32_t row, uint32_t col, uint32_t before) {
  Match *match = &context->current;
  memset(match, 0, sizeof(*match));
  context->match_start = col;
  context->input_offset = 0;
  context->completed = NULL;
  context->found = 0;
  if (context->character) {
    /* T needs the following glyph, which is known only on the next visit. */
    if (result->count) {
      Match *last = (Match *)(result + 1) + result->count - 1;
      if (last->row == row && last->start == before) {
        last->after = col;
      }
    }
    match_codes(context);
    if (context->found) {
      match->valid = 1;
      match->start = match->end = col;
      match->before = before;
      match->after = NONE;
    }
  } else {
    Requests *requests = context->requests;
    uint32_t slot = context->glyph_index % REQUEST_SLOTS;
    /* A completion on the previous glyph refers to the last appended result. */
    if (requests->lookahead[slot]) {
      context->completed = (Match *)(result + 1) + result->count - 1;
      context->input_offset = context->input_size;
      match_codes(context);
      /* Drop the borrowed result pointer before append_match can relocate it. */
      context->completed = NULL;
      requests->lookahead[slot] = 0;
    }
    /* Start a match here as well as advancing matches from earlier glyphs. */
    request(requests, context->glyph_index, 0, col);
    uint32_t *starts = requests->starts + (size_t)slot * requests->width;
    uint32_t *offsets = requests->offsets + (size_t)slot * requests->width;
    uint32_t count = requests->counts[slot];
    for (uint32_t i = 0; i < count; ++i) {
      context->input_offset = offsets[i];
      context->match_start = starts[context->input_offset];
      match_codes(context);
      /* Only consumed offsets are cleared; the other slot holds next-glyph work. */
      starts[context->input_offset] = NONE;
    }
    requests->counts[slot] = 0;
  }
  if (match->valid) {
    match->row = row;
    result = append_match(L, result_index, result, match);
  }
  ++context->glyph_index;
  return result;
}

static Result *scan_line(lua_State *L, int result_index, Result *result, Engine *instance,
                         Slice text, const char *input, uint32_t size, uint32_t row,
                         Requests *requests, int character) {
  if (!character) {
    memset(requests->starts, 255, (size_t)REQUEST_SLOTS * requests->width * sizeof(uint32_t));
    memset(requests->counts, 0, (size_t)REQUEST_SLOTS * sizeof(uint32_t));
    memset(requests->lookahead, 0, (size_t)REQUEST_SLOTS * sizeof(uint32_t));
  }
  MatchContext context = {0};
  context.input = input;
  context.input_size = size;
  context.text_size = text.size;
  context.requests = requests;
  context.character = character;
  GraphemeState state = {.previous = -1};
  uint32_t at = 0, start = 0, before = NONE, last = 0;
  uint32_t count = 0, hash = UINT32_C(2166136261);
  int32_t first = -1;
  /* Decode one scalar ahead to close the previous glyph. That scalar is then
   * reused as the next glyph's first; EOF closes the final glyph the same way. */
  while (1) {
    uint32_t col = at;
    int32_t scalar =
        col < text.size ? decode((const unsigned char *)text.data, text.size, &at) : -1;
    int boundary = col == text.size || grapheme_break(&state, scalar);
    if (boundary && count) {
      Slice key = {text.data + start, col - start};
      uint32_t entry = count == 1 && first >= 0 ? scalar_lookup(&instance->table, (uint32_t)first)
                                                : text_lookup(&instance->table, key, hash);
      context.codes = entry == NONE ? (Slice){NULL, 0} : entry_at(&instance->table, entry).codes;
      /* Flash end positions include the final scalar, not its trailing bytes. */
      context.glyph_after = col;
      context.glyph_end = last;
      result = scan_grapheme(L, result_index, result, &context, row, start, before);
      before = start;
      count = 0;
      hash = UINT32_C(2166136261);
    }
    if (col == text.size) {
      break;
    }
    if (!count) {
      start = col;
      first = scalar;
    }
    uint32_t token = scalar >= 0 ? (uint32_t)scalar : 0x110000u + (unsigned char)text.data[col];
    hash = (hash ^ token) * UINT32_C(16777619);
    last = col;
    ++count;
  }
  return result;
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

static int results(lua_State *L, Result *r, int character, char motion) {
  Match *matches = (Match *)(r + 1);
  uint64_t blocked[2] = {0, 0};
  if (!character) {
    for (uint32_t i = 0; i < r->count; ++i) {
      blocked[0] |= matches[i].next[0];
      blocked[1] |= matches[i].next[1];
    }
  }
  uint32_t label = 1;
  uint32_t label_count = lua_istable(L, 9) ? (uint32_t)lua_objlen(L, 9) : 0;
  lua_createtable(L, (int)r->count, 0);
  int output = lua_gettop(L);
  int written = 0;
  for (uint32_t i = 0; i < r->count; ++i) {
    Match *m = matches + i;
    uint32_t col = character && motion == 't'   ? m->before
                   : character && motion == 'T' ? m->after
                                                : m->start;
    if (col == NONE) {
      continue;
    }
    lua_createtable(L, 0, 5);
    lua_pushvalue(L, 2);
    lua_setfield(L, -2, "win");
    position_field(L, "pos", m->row, col);
    position_field(L, "end_pos", m->row, character ? col : m->end);
    lua_newtable(L);
    if (!character) {
      for (unsigned key = 0; key < 128; ++key) {
        if (m->next[key >> 6] & ((uint64_t)1 << (key & 63))) {
          char byte = (char)key;
          lua_pushlstring(L, &byte, 1);
          lua_pushboolean(L, 1);
          lua_rawset(L, -3);
        }
      }
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
        if (n != 1 || (unsigned char)key[0] >= 128 ||
            !(blocked[(unsigned char)key[0] >> 6] &
              ((uint64_t)1 << ((unsigned char)key[0] & 63)))) {
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

/* Lua: state:scan(win, buf, tick, from, to, lines?, pattern, labels?, motion?). */
static int scan(lua_State *L) {
  Engine *instance = engine(L);
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
  int window_index = window(L, 1);
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
    /* Labels and f/F/t/T positions are reapplied when materializing results. */
    if (same) {
      lua_getfield(L, cache, "result");
      return results(L, (Result *)lua_touserdata(L, -1), character, mode ? mode[0] : 0);
    }
  }
  Result *result = (Result *)lua_newuserdata(L, sizeof(Result));
  result->count = result->capacity = 0;
  int result_index = lua_gettop(L);
  Requests requests = {0};
  if (!character && length) {
    requests.width = (uint32_t)length + 1;
    if (requests.width > (INT_MAX / 8 - REQUEST_SLOTS) / REQUEST_SLOTS) {
      return luaL_error(L, "native scan workspace too large");
    }
    size_t cells = (size_t)REQUEST_SLOTS * requests.width;
    uint32_t *memory =
        (uint32_t *)lua_newuserdata(L, (cells * 2 + REQUEST_SLOTS * 2) * sizeof(uint32_t));
    requests.starts = memory;
    requests.offsets = memory + cells;
    requests.counts = memory + cells * 2;
    requests.lookahead = requests.counts + REQUEST_SLOTS;
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
                         &requests, character);
      lua_settop(L, base);
    }
  }
  qsort(result + 1, result->count, sizeof(Match), sort_matches);
  lua_createtable(L, 0, 4);
  cache = lua_gettop(L);
  lua_pushvalue(L, 8);
  lua_setfield(L, cache, "pattern");
  integer_field(L, "from", from);
  integer_field(L, "to", to);
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
  return results(L, result, character, mode ? mode[0] : 0);
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
  lua_pushfstring(L, "%s/%d", BINARY_MAGIC, UNICODE_VERSION);
  lua_setfield(L, -2, "version");
  lua_createtable(L, 0, 4);
  integer_field(L, "literal", MATCH_LITERAL);
  integer_field(L, "full_code", MATCH_FULL);
  integer_field(L, "initial", MATCH_INITIAL);
  integer_field(L, "prefix", MATCH_PREFIX);
  lua_setfield(L, -2, "modes");
  return 1;
}

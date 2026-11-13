#ifndef FLASH_ANY_NATIVE_H
#define FLASH_ANY_NATIVE_H

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>

/* Internal contracts only; the public API is registered in native.c. */
/* Header: magic[8], Unicode version, file bytes, text keys, Trie units,
 * scalar pages, pool bytes, code-group bytes, scalar count. Header fields are LE u32; Trie units
 * are LE u64. Layout: scalar directory/pages, Trie units, shared byte pool, code groups. */
#define BINARY_MAGIC "FANYBIN\x0D"
#define BINARY_HEADER 40u
#define UNICODE_VERSION 17u
#define ENGINE_MT "flash-any.native-engine"
#define NONE UINT32_MAX
/* High-bit tags delimit inline ASCII codes; group references use fixed-width IDs. */
#define MATCHER_TAG 0x80u
#define GROUP_FLAG 0x08u

/* 0x80..0x9F identify matchers. 0xA0..0xBF are reserved for future pattern operators.
 * Optional-suffix metadata: suffix byte count and ASCII suffix, before the base code.
 * Both the base and base+suffix consumption branches remain valid. */
enum { MATCH_LITERAL, MATCH_FULL, MATCH_INITIAL, MATCH_PREFIX, MATCH_SUFFIX, MATCH_LETTER };

/* Shared code groups are independent of source names. Views borrow the binary's bytes. */
typedef struct {
  const unsigned char *begin, *end;
  unsigned first_byte; /* 128 means no common first byte. */
} CodeGroup;

typedef struct {
  unsigned count;
  CodeGroup groups[];
} CodeGroups;

typedef struct {
  const char *data;
  uint32_t size; /* Byte length; data need not be terminated. */
} Slice;

/* Scalar slots store code-list offset + 1 directly; zero means absent.
 * A directory entry is page ordinal + 1. No scalar key or entry record is stored. */
#define UNICODE_PAGES 0x1100u

typedef struct {
  uint32_t count, npages;
  const unsigned char *directory, *pages;
} ScalarTable;

/* Packed DAT unit (low to high): signed base24, incoming quotient13,
 * parent+1 in 23 bits, outgoing exponent-8 in 4 bits. Exponents cover 8..21;
 * code 15 marks a terminal, whose low 32 bits hold code-list offset+1 instead.
 * Empty units are zero; the root at state 0 has no parent or incoming label. */
#define TRIE_BASE_MASK 0xFFFFFFu
#define TRIE_PARENT_MASK 0x7FFFFFu
#define TRIE_QUOTIENT_MASK 0x1FFFu
#define TRIE_MIN_BITS 8u
#define TRIE_MAX_BITS 21u
#define TRIE_TERMINAL 15u
#define TRIE_MAX_UNITS TRIE_PARENT_MASK

typedef struct {
  uint32_t count;
  const unsigned char *units;
} Trie;

typedef struct {
  Slice key;
  uint32_t codes;
} TrieKey;

uint32_t *build_trie(lua_State *L, TrieKey *keys, uint32_t count, uint32_t *size);

/* Both indexes borrow one immutable binary snapshot and may share pool contents. */
typedef struct {
  ScalarTable scalars;
  Trie trie;
  const unsigned char *pool;
} Dictionary;

typedef struct {
  Dictionary table;
  const CodeGroups *groups;
  int letters; /* A scalar lookup can contribute letter rules to compound graphemes. */
  uint32_t depth; /* Maximum key length in codepoints; at least one for scalar matching. */
} Engine;

typedef struct {
  uint32_t row; /* 1-based; all columns below are 0-based byte offsets. */
  uint32_t start, end; /* end points to the last scalar, as Flash expects. */
  uint32_t before, after; /* Adjacent grapheme starts for t/T; NONE at line edges. */
  uint32_t valid;
  uint64_t next[2]; /* 128 ASCII next-input bits: these keys cannot become labels. */
  uint32_t literal_start, literal_size; /* Next non-ASCII/compound glyph, in the saved row. */
} Match;

/* Match[capacity] follows this header; only the first count entries are live. */
typedef struct {
  uint32_t count, capacity;
} Result;

/* Retain starting positions until their longest possible word has finished. */
typedef struct {
  uint32_t width, slots; /* Input byte length + 1; retained text-start positions. */
  uint32_t *starts; /* [slot][input offset]: earliest text start, or NONE. */
  uint32_t *offsets; /* [slot][active index]: sparse list of input offsets. */
  uint32_t *counts; /* [slot]: number of active offsets. */
  uint32_t *lookahead; /* [slot]: completed result index+1. */
} Requests;

/* Fixed little-endian records permit zero-copy lookup from the immutable blob.
 * Explicit byte loads also work on unaligned strings and big-endian hosts.
 */
static inline uint32_t read_u32(const unsigned char *p) {
  return p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static inline uint64_t trie_unit(const Trie *trie, uint32_t state) {
  const unsigned char *p = trie->units + (size_t)state * 8;
  return read_u32(p) | (uint64_t)read_u32(p + 4) << 32;
}

static inline uint32_t trie_parent(uint64_t unit) {
  return (uint32_t)(unit >> 37) & TRIE_PARENT_MASK;
}

static inline int32_t trie_base(uint64_t unit) {
  int32_t base = (int32_t)(unit & TRIE_BASE_MASK);
  return base & 0x800000 ? base - 0x1000000 : base;
}

static inline unsigned trie_kind(uint64_t unit) {
  return (unsigned)(unit >> 60);
}

static inline uint32_t trie_step(const Dictionary *dictionary, uint32_t state, uint32_t cp) {
  const Trie *trie = &dictionary->trie;
  if (!trie->count) {
    return NONE;
  }
  uint64_t parent = trie_unit(trie, state);
  if (trie_kind(parent) == TRIE_TERMINAL) {
    return NONE;
  }
  unsigned bits = trie_kind(parent) + TRIE_MIN_BITS;
  uint64_t next = (uint64_t)((int64_t)trie_base(parent) + (cp & ((1u << bits) - 1)));
  if (next >= trie->count) {
    return NONE;
  }
  uint64_t child = trie_unit(trie, (uint32_t)next);
  if (trie_parent(child) != state + 1) {
    return NONE;
  }
  return cp ? (trie_kind(child) != TRIE_TERMINAL &&
                       ((child >> 24) & TRIE_QUOTIENT_MASK) == (cp >> bits)
                   ? (uint32_t)next
                   : NONE)
            : (trie_kind(child) == TRIE_TERMINAL ? (uint32_t)next : NONE);
}

static inline const unsigned char *trie_codes(const Dictionary *dictionary, uint32_t state) {
  uint32_t end = trie_step(dictionary, state, 0);
  return end == NONE ? NULL : dictionary->pool + (uint32_t)trie_unit(&dictionary->trie, end) - 1;
}

static inline const unsigned char *scalar_codes(const Dictionary *dictionary, uint32_t cp) {
  const ScalarTable *scalars = &dictionary->scalars;
  if (!scalars->npages || cp > 0x10FFFF) {
    return NULL;
  }
  uint32_t page = read_u32(scalars->directory + (size_t)(cp >> 8) * 4);
  if (!page) {
    return NULL;
  }
  uint32_t offset = read_u32(scalars->pages + ((size_t)(page - 1) * 256 + (cp & 255)) * 4);
  return offset ? dictionary->pool + offset - 1 : NULL;
}

static inline unsigned read_u16(const unsigned char *p) {
  return p[0] | (unsigned)p[1] << 8;
}

/* Lua entry points: loading pins binary bytes/groups in the returned engine. */
int load_binary(lua_State *L);
int open_binary(lua_State *L);
int write_binary(lua_State *L);
/* The boolean upvalue selects enumeration (true) or counting (false). */
int graphemes(lua_State *L);

/* result_index pins the result userdata. A growing result replaces that stack
 * slot and returns its new address; requests are scratch storage reused per row. */
Result *scan_line(lua_State *L, int result_index, Result *result, Engine *instance, Slice text,
                  const char *input, uint32_t size, uint32_t row, Requests *requests, int character,
                  int ignorecase);

#endif

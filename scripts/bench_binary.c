#define _POSIX_C_SOURCE 200809L
/* CPU-local lookup comparison. Reconstruct scalar UTF-8 keys only for the
 * all-text hash/sorted/MARISA baselines, outside every timed region. */
#include <time.h>
#include <stdio.h>
#include <stdint.h>
#include <lualib.h>
#include "../src/binary.c"
#include "../src/scan.c"
#include "../src/native.c"
#include "../src/trie.c"

static volatile uint64_t sink;
static uint32_t hash_key(Slice key);

typedef struct {
  Slice key;
  const unsigned char *codes;
} BenchEntry;

static int compare_slices(Slice a, Slice b) {
  uint32_t n = a.size < b.size ? a.size : b.size;
  int value = memcmp(a.data, b.data, n);
  return value ? value : (a.size > b.size) - (a.size < b.size);
}

typedef struct {
  Dictionary *dictionary;
  BenchEntry *entries;
  uint32_t count, capacity;
  uint32_t *hashes;
} BenchIndex;

#ifdef BENCH_MARISA
extern size_t bench_marisa_build(const char **keys, const size_t *sizes, uint32_t count);
extern uint32_t bench_marisa_lookup(const char *key, size_t size);
extern uint32_t bench_marisa_reuse(const char *key, size_t size);

static const unsigned char *marisa_lookup(BenchIndex *index, Slice key, int32_t cp) {
  (void)cp;
  uint32_t id = bench_marisa_lookup(key.data, key.size);
  return id == NONE ? NULL : index->entries[id].codes;
}

static const unsigned char *marisa_reuse(BenchIndex *index, Slice key, int32_t cp) {
  (void)cp;
  uint32_t id = bench_marisa_reuse(key.data, key.size);
  return id == NONE ? NULL : index->entries[id].codes;
}
#endif

static const unsigned char *sorted_lookup(BenchIndex *index, Slice key, int32_t cp) {
  (void)cp;
  uint32_t lo = 0, hi = index->count;
  while (lo < hi) {
    uint32_t mid = lo + (hi - lo) / 2;
    if (compare_slices(index->entries[mid].key, key) < 0) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < index->count && !compare_slices(index->entries[lo].key, key)
             ? index->entries[lo].codes
             : NULL;
}

static const unsigned char *hash_lookup(BenchIndex *index, Slice key, int32_t cp) {
  (void)cp;
  uint32_t slot = hash_key(key) & (index->capacity - 1);
  while (index->hashes[slot]) {
    BenchEntry *entry = &index->entries[index->hashes[slot] - 1];
    if (!compare_slices(entry->key, key)) {
      return entry->codes;
    }
    slot = (slot + 1) & (index->capacity - 1);
  }
  return NULL;
}

static uint32_t hash_key(Slice key) {
  uint32_t hash = 2166136261u, at = 0;
  while (at < key.size) {
    uint32_t before = at;
    int32_t cp = decode((const unsigned char *)key.data, key.size, &at);
    hash =
        (hash ^ (cp >= 0 ? (uint32_t)cp : 0x110000u + (unsigned char)key.data[before])) * 16777619u;
  }
  return hash;
}

static const unsigned char *page_lookup(BenchIndex *index, Slice key, int32_t cp) {
  if (cp >= 0) {
    return scalar_codes(index->dictionary, (uint32_t)cp);
  }
  uint32_t at = 0, state = 0;
  while (at < key.size) {
    uint32_t before = at;
    int32_t point = decode((const unsigned char *)key.data, key.size, &at);
    state = trie_step(index->dictionary, state,
                      point >= 0 ? (uint32_t)point : 0x110000u + (unsigned char)key.data[before]);
    if (state == NONE) {
      return NULL;
    }
  }
  return trie_codes(index->dictionary, state);
}

static const unsigned char *decoded_lookup(BenchIndex *index, Slice key, int32_t cp) {
  (void)cp;
  return page_lookup(index, key, single_scalar(key));
}

typedef const unsigned char *(*Find)(BenchIndex *, Slice, int32_t);

static double measure(BenchIndex *index, Slice *queries, int32_t *points, uint32_t n,
                      uint32_t rounds, Find find) {
  uint64_t sum = 0;
  clock_t start = clock();
  for (uint64_t i = 0, count = (uint64_t)rounds * n; i < count; ++i) {
    const unsigned char *codes = find(index, queries[i % n], points[i % n]);
    if (codes) {
      sum += (uint64_t)(codes - index->dictionary->pool) + 1;
    }
  }
  double seconds = (double)(clock() - start) / CLOCKS_PER_SEC;
  sink = sum;
  return seconds;
}

static int number_order(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

static int entry_order(const void *a, const void *b) {
  return compare_slices(((const BenchEntry *)a)->key, ((const BenchEntry *)b)->key);
}

/* Benchmark-only UTF-8 reconstruction; production scalar lookups never need keys. */
static uint32_t encode_scalar(unsigned char *bytes, uint32_t cp) {
  if (cp < 0x80) {
    bytes[0] = cp;
    return 1;
  }
  if (cp < 0x800) {
    bytes[0] = 0xC0 | (cp >> 6);
    bytes[1] = 0x80 | (cp & 63);
    return 2;
  }
  if (cp < 0x10000) {
    bytes[0] = 0xE0 | (cp >> 12);
    bytes[1] = 0x80 | ((cp >> 6) & 63);
    bytes[2] = 0x80 | (cp & 63);
    return 3;
  }
  bytes[0] = 0xF0 | (cp >> 18);
  bytes[1] = 0x80 | ((cp >> 12) & 63);
  bytes[2] = 0x80 | ((cp >> 6) & 63);
  bytes[3] = 0x80 | (cp & 63);
  return 4;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: bench PACKAGE hash|scalar|pages|sorted|marisa|marisa_reuse hit|miss\n");
    return 2;
  }
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  luaopen_flash_any_native(L);
  lua_pop(L, 1);
  double start = (double)clock();
  lua_pushcfunction(L, open_binary);
  lua_pushstring(L, argv[1]);
  if (lua_pcall(L, 1, 1, 0)) {
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    return 3;
  }
  double load_ms = ((double)clock() - start) / CLOCKS_PER_SEC * 1000;
  Engine *engine = lua_touserdata(L, -1);
  Dictionary *dictionary = &engine->table;
  lua_getfenv(L, -1);
  lua_getfield(L, -1, "bytes");
  uint32_t text_count = read_u32((const unsigned char *)lua_touserdata(L, -1) + 16);
  lua_pop(L, 2);
  BenchIndex index = {
      .dictionary = dictionary, .count = dictionary->scalars.count + text_count, .capacity = 1};
  if (!index.count) {
    return 4;
  }
  index.entries = malloc((size_t)index.count * sizeof(BenchEntry));
  unsigned char *scalar_keys = malloc((size_t)dictionary->scalars.count * 4 + 1);
  if (!index.entries || !scalar_keys) {
    return 5;
  }
  uint32_t written = 0;
  size_t key_bytes = 0;
  for (uint32_t high = 0; dictionary->scalars.npages && high < UNICODE_PAGES; ++high) {
    if (!read_u32(dictionary->scalars.directory + (size_t)high * 4)) {
      continue;
    }
    for (uint32_t low = 0; low < 256; ++low) {
      uint32_t cp = high * 256 + low;
      const unsigned char *codes = scalar_codes(dictionary, cp);
      if (!codes) {
        continue;
      }
      unsigned char *key = scalar_keys + (size_t)written * 4;
      uint32_t size = encode_scalar(key, cp);
      index.entries[written++] = (BenchEntry){{(const char *)key, size}, codes};
      key_bytes += size;
    }
  }
  unsigned char *text_keys = malloc((size_t)text_count * engine->depth * 4 + 1);
  uint32_t *path = malloc((size_t)engine->depth * 4 + 4);
  if (!text_keys || !path) {
    return 5;
  }
  size_t text_bytes = 0;
  const unsigned char *units = dictionary->trie.units;
  for (uint32_t i = 1; i < dictionary->trie.count; ++i) {
    uint64_t unit = trie_unit(&dictionary->trie, i);
    uint32_t check = trie_parent(unit);
    if (!check || trie_kind(unit) != TRIE_TERMINAL) {
      continue;
    }
    uint32_t state = check - 1, depth = 0;
    while (state) {
      uint64_t node = trie_unit(&dictionary->trie, state);
      uint32_t parent = trie_parent(node) - 1;
      uint64_t owner = trie_unit(&dictionary->trie, parent);
      unsigned bits = trie_kind(owner) + TRIE_MIN_BITS;
      path[depth++] = (uint32_t)(((node >> 24) & TRIE_QUOTIENT_MASK) << bits) |
                      (uint32_t)((int64_t)state - trie_base(owner));
      state = parent;
    }
    unsigned char *key = text_keys + text_bytes;
    uint32_t size = 0;
    while (depth) {
      uint32_t cp = path[--depth];
      if (cp > 0x10FFFF) {
        key[size++] = (unsigned char)cp;
      } else {
        size += encode_scalar(key + size, cp);
      }
    }
    index.entries[written++] = (BenchEntry){{(const char *)key, size},
                                            dictionary->pool + read_u32(units + (size_t)i * 8) - 1};
    text_bytes += size;
    key_bytes += size;
  }
  if (written != index.count) {
    return 6;
  }
  qsort(index.entries, index.count, sizeof(BenchEntry), entry_order);
  while ((uint64_t)index.capacity * 3 < (uint64_t)index.count * 4) {
    index.capacity *= 2;
  }
  index.hashes = calloc(index.capacity, sizeof(uint32_t));
  if (!index.hashes) {
    return 5;
  }
  for (uint32_t i = 0; i < index.count; ++i) {
    uint32_t slot = hash_key(index.entries[i].key) & (index.capacity - 1);
    while (index.hashes[slot]) {
      slot = (slot + 1) & (index.capacity - 1);
    }
    index.hashes[slot] = i + 1;
  }
  /* Serialized-equivalent bytes, including code offsets; not the C benchmark heap. */
  size_t index_bytes = (size_t)index.capacity * 4 + (size_t)index.count * 12 + key_bytes;
  Find find = hash_lookup;
  if (!strcmp(argv[2], "sorted")) {
    find = sorted_lookup;
    index_bytes -= (size_t)index.capacity * 4;
  }
  if (!strcmp(argv[2], "scalar") || !strcmp(argv[2], "pages")) {
    find = !strcmp(argv[2], "scalar") ? page_lookup : decoded_lookup;
    index_bytes = dictionary->scalars.npages
                      ? (UNICODE_PAGES + (size_t)dictionary->scalars.npages * 256) * 4
                      : 0;
    index_bytes += (size_t)dictionary->trie.count * 8;
  }
#ifdef BENCH_MARISA
  if (!strncmp(argv[2], "marisa", 6)) {
    const char **keys = malloc((size_t)index.count * sizeof(*keys));
    size_t *sizes = malloc((size_t)index.count * sizeof(*sizes));
    if (!keys || !sizes) {
      return 5;
    }
    for (uint32_t i = 0; i < index.count; ++i) {
      keys[i] = index.entries[i].key.data;
      sizes[i] = index.entries[i].key.size;
    }
    index_bytes = bench_marisa_build(keys, sizes, index.count) + (size_t)index.count * 4;
    find = !strcmp(argv[2], "marisa") ? marisa_lookup : marisa_reuse;
    free(keys);
    free(sizes);
  }
#endif
  Slice queries[256];
  int32_t points[256];
  uint32_t count = 0;
  unsigned char *owned[256] = {NULL};
  uint32_t step = index.count / 256 + 1;
  for (uint32_t i = 0; i < index.count && count < 256; i += step) {
    Slice key = index.entries[i].key;
    if (!strcmp(argv[3], "miss")) {
      owned[count] = malloc((size_t)key.size + 1);
      if (!owned[count]) {
        return 5;
      }
      memcpy(owned[count], key.data, key.size);
      owned[count][key.size] = 255;
      key.data = (const char *)owned[count];
      ++key.size;
      if (decoded_lookup(&index, key, -1)) {
        return 6;
      }
    }
    points[count] = single_scalar(key);
    queries[count++] = key;
  }
  for (uint32_t i = 0; i < count; ++i) {
    if (find(&index, queries[i], points[i]) != decoded_lookup(&index, queries[i], points[i])) {
      return 7;
    }
  }
  uint32_t rounds = 1;
  while (measure(&index, queries, points, count, rounds, find) < 0.03 && rounds < 1048576) {
    rounds *= 2;
  }
  double samples[7];
  for (unsigned i = 0; i < 7; ++i) {
    samples[i] = measure(&index, queries, points, count, rounds, find) * 1e9 / rounds / count;
  }
  qsort(samples, 7, sizeof(double), number_order);
  printf("{\"queries\":%u,\"median_ns\":%.4f,\"min_ns\":%.4f,\"max_ns\":%.4f,\"load_ms\":%.4f,"
         "\"index_bytes\":%zu,\"checksum\":%llu}\n",
         count, samples[3], samples[0], samples[6], load_ms, index_bytes, (unsigned long long)sink);
  for (unsigned i = 0; i < count; ++i) {
    free(owned[i]);
  }
  free(path);
  free(text_keys);
  free(index.hashes);
  free(index.entries);
  free(scalar_keys);
  lua_close(L);
  return 0;
}

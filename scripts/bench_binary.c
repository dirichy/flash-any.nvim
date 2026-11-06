#define _POSIX_C_SOURCE 200809L
/* CPU-local queries against the same immutable package, with no Lua calls in
 * the timed loop. Hash and sorted search use identical key/code records.
 */
#include <time.h>
#include <stdio.h>
#include <stdint.h>
#include <lualib.h>
static volatile uint64_t sink;
/* Keep implementation bodies out of clangd's header-only preamble. */
#include "../src/native.c"
#ifdef BENCH_MARISA
extern size_t bench_marisa_build(const char **keys, const size_t *sizes, uint32_t count);
extern uint32_t bench_marisa_lookup(const char *key, size_t size);
extern uint32_t bench_marisa_reuse(const char *key, size_t size);
static uint32_t marisa_lookup(Dictionary *s, Slice key, int32_t cp) {
  (void)s; (void)cp;
  return bench_marisa_lookup(key.data, key.size);
}
static uint32_t marisa_reuse(Dictionary *s, Slice key, int32_t cp) {
  (void)s; (void)cp;
  return bench_marisa_reuse(key.data, key.size);
}
#endif
static uint32_t sorted_lookup(Dictionary *s, Slice key, int32_t cp) {
  (void)cp;
  uint32_t lo = 0, hi = s->nentry;
  while (lo < hi) {
    uint32_t mid = lo + (hi - lo) / 2;
    if (compare(entry_at(s, mid).key, key) < 0) lo = mid + 1; else hi = mid;
  }
  return lo < s->nentry && !compare(entry_at(s, lo).key, key) ? lo : NONE;
}
static uint32_t hash_lookup(Dictionary *s, Slice key, int32_t cp) {
  (void)cp; return text_lookup(s, key, hash_key(key));
}
static uint32_t page_lookup(Dictionary *s, Slice key, int32_t cp) {
  return cp >= 0 ? scalar_lookup(s, (uint32_t)cp) : text_lookup(s, key, hash_key(key));
}
static uint32_t decoded_lookup(Dictionary *s, Slice key, int32_t cp) {
  (void)cp; return lookup(s, key);
}
static double measure(Dictionary *s, Slice *queries, int32_t *points, uint32_t n, uint32_t rounds,
                      uint32_t (*find)(Dictionary *, Slice, int32_t)) {
  uint64_t sum = 0;
  clock_t start = clock();
  for (uint64_t i = 0, count = (uint64_t)rounds * n; i < count; ++i) {
    uint32_t at = find(s, queries[i % n], points[i % n]);
    sum += at;
    if (at != NONE) sum += entry_at(s, at).codes.size;
  }
  double seconds = (double)(clock() - start) / CLOCKS_PER_SEC;
  sink = sum;
  return seconds;
}
static int number_order(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}
int main(int argc, char **argv) {
  if (argc != 4) { fprintf(stderr, "usage: bench PACKAGE hash|sorted|marisa|marisa_reuse hit|miss\n"); return 2; }
  lua_State *L = luaL_newstate(); luaL_openlibs(L);
  luaopen_flash_any_native(L); lua_pop(L, 1);
  if (luaL_loadstring(L, "local f=assert(io.open(...,'rb')); local s=f:read('*a'); f:close(); return s")) return 3;
  lua_pushstring(L, argv[1]);
  if (lua_pcall(L, 1, 1, 0)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 3; }
  clock_t load_start = clock();
  lua_pushcfunction(L, load_binary); lua_insert(L, 1);
  if (lua_pcall(L, 1, 1, 0)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 3; }
  double load_ms = (double)(clock() - load_start) / CLOCKS_PER_SEC * 1000;
  Engine *e = (Engine *)lua_touserdata(L, -1);
  Dictionary *s = &e->table;
  if (!s->nentry) return 4;
  /* Rebuild the all-text codepoint hash outside timing, using the same entries. */
  Dictionary baseline = *s;
  baseline.capacity = 1;
  while ((uint64_t)baseline.capacity * 3 < (uint64_t)s->nentry * 4) baseline.capacity *= 2;
  uint32_t *baseline_slots = calloc(baseline.capacity, 4);
  if (!baseline_slots) return 5;
  for (uint32_t i = 0; i < s->nentry; ++i) {
    uint32_t slot = hash_key(entry_at(s, i).key) & (baseline.capacity - 1);
    while (baseline_slots[slot]) slot = (slot + 1) & (baseline.capacity - 1);
    baseline_slots[slot] = i + 1;
  }
  pack_words(baseline_slots, baseline.capacity);
  baseline.hashes = (const unsigned char *)baseline_slots;
  if (!strcmp(argv[2], "hash")) s = &baseline;
  size_t index_bytes = (size_t)s->capacity * 4 + (size_t)s->nentry * 8;
  for (uint32_t i = 0; i < s->nentry; ++i) index_bytes += entry_at(s, i).key.size;
  if (!strcmp(argv[2], "scalar") || !strcmp(argv[2], "pages")) index_bytes += s->npages ? (UNICODE_PAGES + (size_t)s->npages * 256) * 4 : 0;
  if (!strcmp(argv[2], "sorted")) index_bytes -= (size_t)s->capacity * 4;
#ifdef BENCH_MARISA
  if (!strncmp(argv[2], "marisa", 6)) {
    const char **keys = malloc((size_t)s->nentry * sizeof(*keys));
    size_t *sizes = malloc((size_t)s->nentry * sizeof(*sizes));
    if (!keys || !sizes) return 5;
    for (uint32_t i = 0; i < s->nentry; ++i) { Slice key = entry_at(s, i).key; keys[i] = key.data; sizes[i] = key.size; }
    index_bytes = bench_marisa_build(keys, sizes, s->nentry);
    free(keys); free(sizes);
  }
#endif
  Slice queries[256]; int32_t points[256]; uint32_t count = 0;
  unsigned char *owned[256] = { NULL };
  uint32_t step = s->nentry / 256 + 1;
  for (uint32_t i = 0; i < s->nentry && count < 256; i += step) {
    Entry entry = entry_at(s, i);
    Slice key = entry.key;
    if (!strcmp(argv[3], "miss")) {
      owned[count] = (unsigned char *)malloc((size_t)key.size + 1);
      if (!owned[count]) return 5;
      memcpy(owned[count], key.data, key.size);
      owned[count][key.size] = 255;
      key.data = (const char *)owned[count]; ++key.size;
      if (lookup(s, key) != NONE) return 6;
    }
    points[count] = single_scalar(key);
    queries[count++] = key;
  }
  if (!count) { printf("{\"queries\":0}\n"); lua_close(L); return 0; }
  uint32_t (*find)(Dictionary *, Slice, int32_t) = !strcmp(argv[2], "hash") ? hash_lookup : sorted_lookup;
#ifdef BENCH_MARISA
  if (!strcmp(argv[2], "marisa")) find = marisa_lookup;
  if (!strcmp(argv[2], "marisa_reuse")) find = marisa_reuse;
#endif
  if (!strcmp(argv[2], "scalar")) find = page_lookup;
  if (!strcmp(argv[2], "pages")) find = decoded_lookup;
  for (uint32_t i = 0; i < count; ++i) if (find(s, queries[i], points[i]) != lookup(s, queries[i])) return 7;
  uint32_t rounds = 1;
  while (measure(s, queries, points, count, rounds, find) < 0.03 && rounds < 1048576) rounds *= 2;
  double samples[7];
  for (unsigned i = 0; i < 7; ++i) samples[i] = measure(s, queries, points, count, rounds, find) * 1e9 / rounds / count;
  qsort(samples, 7, sizeof(double), number_order);
  printf("{\"queries\":%u,\"median_ns\":%.4f,\"min_ns\":%.4f,\"max_ns\":%.4f,\"load_ms\":%.4f,\"index_bytes\":%zu,\"checksum\":%llu}\n",
         count, samples[3], samples[0], samples[6], load_ms, index_bytes, (unsigned long long)sink);
  for (unsigned i = 0; i < count; ++i) free(owned[i]);
  free(baseline_slots); lua_close(L); return 0;
}

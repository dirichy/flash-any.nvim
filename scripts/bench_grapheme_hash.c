/* Experimental hashes only. Inputs are already segmented and decoded. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { uint32_t count, size; uint32_t *cp; unsigned char *bytes; } Key;
static uint32_t sum(const Key *k) {
  uint32_t h = k->count;
  for (uint32_t i = 0; i < k->count; ++i) h += k->cp[i];
  return h;
}
#define POLY(name, multiplier) \
static uint32_t name(const Key *k) { \
  uint32_t h = k->count; \
  for (uint32_t i = 0; i < k->count; ++i) h = h * (multiplier) + k->cp[i]; \
  return h; \
}
POLY(poly31, 31u)
POLY(poly33, 33u)
POLY(poly65599, 65599u)
POLY(poly_golden, UINT32_C(0x9E3779B1))
static uint32_t fnv_cp(const Key *k) {
  uint32_t h = UINT32_C(2166136261);
  for (uint32_t i = 0; i < k->count; ++i) h = (h ^ k->cp[i]) * UINT32_C(16777619);
  return h;
}
static uint32_t fnv_bytes(const Key *k) {
  uint32_t h = UINT32_C(2166136261);
  for (uint32_t i = 0; i < k->size; ++i) h = (h ^ k->bytes[i]) * UINT32_C(16777619);
  return h;
}
#define ROTATE(name, shift) \
static uint32_t name(const Key *k) { \
  uint32_t h = k->count; \
  for (uint32_t i = 0; i < k->count; ++i) h = ((h << (shift)) | (h >> (32 - (shift)))) ^ k->cp[i]; \
  return h; \
}
ROTATE(rot5, 5)
ROTATE(rot13, 13)
static uint32_t mix(uint32_t h) {
  /* Public-domain MurmurHash3 fmix32 (aappleby/smhasher, src/MurmurHash3.cpp).
   * The bijective 32-bit finalizer redistributes bits; it cannot
   * separate two keys that already have the same polynomial hash. */
  h ^= h >> 16; h *= UINT32_C(0x85EBCA6B);
  h ^= h >> 13; h *= UINT32_C(0xC2B2AE35);
  h ^= h >> 16; return h;
}
static uint32_t poly33_mix(const Key *k) { return mix(poly33(k)); }
static uint32_t poly_golden_mix(const Key *k) { return mix(poly_golden(k)); }
static uint32_t structured(const Key *k) {
  if (k->count == 2) {
    uint32_t a = k->cp[0], b = k->cp[1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF)
      return UINT32_C(0x20000000) | ((a - 0x1F1E6) * 26 + b - 0x1F1E6);
    if (b >= 0x300 && b <= 0x36F) return UINT32_C(0x40000000) | (a << 7) | (b - 0x300);
    if (b >= 0xFE00 && b <= 0xFE0F) return UINT32_C(0x60000000) | (a << 4) | (b - 0xFE00);
    if (b >= 0x1F3FB && b <= 0x1F3FF) return UINT32_C(0x80000000) | (a << 3) | (b - 0x1F3FB);
  }
  return UINT32_C(0xA0000000) | (fnv_cp(k) & UINT32_C(0x1FFFFFFF));
}
static uint32_t structured_mix(const Key *k) { return mix(structured(k)); }
static volatile uint64_t sink;
static double measure(Key *keys, uint32_t count, uint32_t rounds, uint32_t (*hash)(const Key *)) {
  uint64_t total = 0;
  clock_t start = clock();
  for (uint32_t r = 0; r < rounds; ++r)
    for (uint32_t i = 0; i < count; ++i) total += hash(keys + i);
  double elapsed = (double)(clock() - start) / CLOCKS_PER_SEC;
  sink = total; return elapsed;
}
static int order(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  static const struct { const char *name; uint32_t (*hash)(const Key *); } methods[] = {
    {"sum", sum}, {"poly31", poly31}, {"poly33", poly33}, {"poly65599", poly65599},
    {"poly_golden", poly_golden}, {"fnv_cp", fnv_cp}, {"fnv_bytes", fnv_bytes},
    {"rot5", rot5}, {"rot13", rot13}, {"poly33_mix", poly33_mix},
    {"poly_golden_mix", poly_golden_mix}, {"structured", structured}, {"structured_mix", structured_mix}
  };
  uint32_t (*hash)(const Key *) = NULL;
  for (unsigned i = 0; i < sizeof(methods) / sizeof(methods[0]); ++i)
    if (!strcmp(argv[2], methods[i].name)) hash = methods[i].hash;
  if (!hash) return 2;
  FILE *file = fopen(argv[1], "rb");
  uint32_t count;
  if (!file || fread(&count, 4, 1, file) != 1 || !count) return 3;
  Key *keys = calloc(count, sizeof(Key));
  if (!keys) return 4;
  for (uint32_t i = 0; i < count; ++i) {
    Key *k = keys + i;
    if (fread(&k->count, 4, 1, file) != 1 || fread(&k->size, 4, 1, file) != 1) return 3;
    k->cp = malloc((size_t)k->count * 4); k->bytes = malloc(k->size);
    if (!k->cp || !k->bytes) return 4;
    if (fread(k->cp, 4, k->count, file) != k->count || fread(k->bytes, 1, k->size, file) != k->size) return 3;
  }
  fclose(file);
  if (!strcmp(argv[3], "hashes")) {
    for (uint32_t i = 0; i < count; ++i) { uint32_t h = hash(keys + i); fwrite(&h, 4, 1, stdout); }
  } else {
    uint32_t rounds = 1;
    while (measure(keys, count, rounds, hash) < 0.015 && rounds < 1048576) rounds *= 2;
    double samples[5];
    for (unsigned i = 0; i < 5; ++i) samples[i] = measure(keys, count, rounds, hash) * 1e9 / count / rounds;
    qsort(samples, 5, sizeof(double), order);
    printf("{\"median_ns\":%.4f,\"min_ns\":%.4f,\"max_ns\":%.4f}\n", samples[2], samples[0], samples[4]);
  }
  for (uint32_t i = 0; i < count; ++i) { free(keys[i].cp); free(keys[i].bytes); }
  free(keys); return 0;
}

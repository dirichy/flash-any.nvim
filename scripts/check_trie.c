/* Check every key/code list in a trusted v11 fixture against the current DAT.
 * Fixtures must have no binary code-group IDs. No Neovim or Lua library needed.
 * cc -O3 -std=c99 -Wall -Wextra -Werror -Ivendor/luajit scripts/check_trie.c -o /tmp/check-trie
 * /tmp/check-trie original-v11.bin current.bin
 */
#include <stdio.h>
#include <stdlib.h>
#include "../src/native.h"
#include "../src/text.h"

static unsigned char *read_file(const char *path) {
  FILE *file = fopen(path, "rb");
  if (!file) {
    return NULL;
  }
  fseek(file, 0, SEEK_END);
  long size = ftell(file);
  rewind(file);
  unsigned char *bytes = size >= BINARY_HEADER ? malloc((size_t)size) : NULL;
  if (!bytes || fread(bytes, 1, (size_t)size, file) != (size_t)size) {
    free(bytes);
    bytes = NULL;
  }
  fclose(file);
  return bytes;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    return 2;
  }
  unsigned char *source = read_file(argv[1]), *target = read_file(argv[2]);
  if (!source || !target || memcmp(source, "FANYBIN\x0B", 8) || memcmp(target, BINARY_MAGIC, 8) ||
      read_u32(source + 32)) {
    return 2;
  }
  if (read_u32(source + 16) != read_u32(target + 16) ||
      read_u32(source + 36) != read_u32(target + 36)) {
    return 1;
  }
  uint32_t pages = read_u32(source + 24), count = read_u32(source + 16);
  const unsigned char *entries = source + 40 + (pages ? (UNICODE_PAGES + pages * 256) * 4 : 0);
  const unsigned char *pool = entries + (size_t)count * 8 + (size_t)read_u32(source + 20) * 4;
  uint32_t new_pages = read_u32(target + 24), units = read_u32(target + 20);
  const unsigned char *dat = target + 40 + (new_pages ? (UNICODE_PAGES + new_pages * 256) * 4 : 0);
  Dictionary dictionary = {.scalars = {read_u32(target + 36), new_pages, target + 40,
                                       new_pages ? target + 40 + UNICODE_PAGES * 4 : NULL},
                           .trie = {units, dat},
                           .pool = dat + (size_t)units * 8};
  uint32_t checked = 0;
  for (uint32_t high = 0; pages && high < UNICODE_PAGES; ++high) {
    uint32_t page = read_u32(source + 40 + (size_t)high * 4);
    if (!page) {
      continue;
    }
    for (uint32_t low = 0; low < 256; ++low) {
      uint32_t offset =
          read_u32(source + 40 + UNICODE_PAGES * 4 + ((size_t)(page - 1) * 256 + low) * 4);
      if (!offset) {
        continue;
      }
      const unsigned char *codes = scalar_codes(&dictionary, high * 256 + low);
      const unsigned char *expected = pool + offset - 1;
      if (!codes || memcmp(codes, expected, strlen((const char *)expected) + 1)) {
        return 1;
      }
      ++checked;
    }
  }
  for (uint32_t i = 0; i < count; ++i) {
    const unsigned char *key = pool + read_u32(entries + (size_t)i * 8);
    uint32_t length = (uint32_t)strlen((const char *)key), at = 0, state = 0;
    while (at < length && state != NONE) {
      uint32_t before = at;
      int32_t cp = decode(key, length, &at);
      state = trie_step(&dictionary, state, cp >= 0 ? (uint32_t)cp : 0x110000u + key[before]);
    }
    const unsigned char *codes = state == NONE ? NULL : trie_codes(&dictionary, state);
    const unsigned char *expected = pool + read_u32(entries + (size_t)i * 8 + 4);
    if (!codes || memcmp(codes, expected, strlen((const char *)expected) + 1)) {
      fprintf(stderr, "different key/code list at entry %u\n", i);
      return 1;
    }
    ++checked;
  }
  /* Independent minimality oracle: every modulus above the lower bound must
   * have two children whose remainders collide if the modulus is halved. */
  unsigned char *witness = calloc(units, 1);
  if (units && !witness) {
    return 2;
  }
  for (uint32_t i = 1; i < units; ++i) {
    uint32_t parent = trie_parent(trie_unit(&dictionary.trie, i));
    if (!parent) {
      continue;
    }
    uint64_t owner = trie_unit(&dictionary.trie, parent - 1);
    unsigned bits = trie_kind(owner) + TRIE_MIN_BITS;
    if (bits == TRIE_MIN_BITS) {
      continue;
    }
    int32_t base = trie_base(owner);
    uint32_t remainder = (uint32_t)((int64_t)i - base);
    int64_t sibling = (int64_t)base + (remainder ^ (1u << (bits - 1)));
    if (sibling >= 0 && (uint64_t)sibling < units &&
        trie_parent(trie_unit(&dictionary.trie, (uint32_t)sibling)) == parent) {
      witness[parent - 1] = 1;
    }
  }
  uint32_t minimal = 0;
  for (uint32_t i = 0; i < units; ++i) {
    uint64_t unit = trie_unit(&dictionary.trie, i);
    if ((i && !trie_parent(unit)) || trie_kind(unit) == TRIE_TERMINAL) {
      continue;
    }
    if (trie_kind(unit) && !witness[i]) {
      fprintf(stderr, "nonminimal modulus at state %u\n", i);
      return 1;
    }
    ++minimal;
  }
  printf("{\"verified_keys\":%u,\"text_keys\":%u,\"units\":%u,\"minimal_moduli\":%u}\n", checked,
         count, units, minimal);
  free(witness);
  free(source);
  free(target);
  return 0;
}

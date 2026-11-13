/* Alternate incremental indexes for complete native phrase-scan experiments.
 * INDEX_KIND=0: fingerprinted prefix hash; 1: DAT; 2: paged-root DAT.
 * The paged variant also obtains scalar codes while starting a prefix.
 * Matching, requests and results stay shared.
 * One immutable dictionary per isolated benchmark process. */
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <vector>
extern "C" {
#include "native.h"
#include "text.h"
}

#if INDEX_KIND >= 1
extern "C" size_t trie_build(const char **keys, const size_t *sizes, uint32_t count);
extern "C" uint32_t trie_transition(uint32_t state, uint32_t token);
extern "C" uint32_t trie_value(uint32_t state);
extern "C" size_t trie_image(FILE *file, int load);
extern "C" uint32_t trie_base(uint32_t state);
extern "C" uint32_t trie_from_base(uint32_t base, uint32_t token);
#if INDEX_KIND == 2
extern "C" void trie_root_code(uint32_t cp, uint32_t offset);
extern "C" uint32_t trie_root(uint32_t cp, uint32_t *base);
extern "C" const unsigned char *bench_root_start(const Dictionary *dictionary, uint32_t cp,
                                                 uint32_t bytes, TextPrefix *prefix) {
  uint32_t codes = trie_root(cp, &prefix->begin);
  prefix->end = 0;
  prefix->bytes = bytes;
  return codes ? dictionary->pool + codes - 1 : NULL;
}
#endif
#else
struct PrefixRecord {
  uint32_t offset, bytes, terminal;
};

static std::vector<PrefixRecord> prefixes;
static std::vector<uint32_t> slots;
static uint32_t mask;
#endif

extern "C" void bench_prepare_index(const Dictionary *dictionary) {
  uint32_t count = dictionary->text.count;
  size_t bytes;
  const char *cache = std::getenv("FLASH_ANY_BENCH_INDEX");
  FILE *file = cache ? std::fopen(cache, "rb") : NULL;
#if INDEX_KIND == 0
  if (file) {
    uint32_t magic = 0;
    if (std::fread(&magic, 4, 1, file) != 1 || magic != 0x31504846u) {
      std::fclose(file);
      file = NULL;
    }
  }
#endif
  if (file) {
#if INDEX_KIND >= 1
    bytes = trie_image(file, 1);
#else
    uint32_t counts[2];
    if (std::fread(counts, 4, 2, file) != 2) {
      throw std::runtime_error("bad index cache");
    }
    prefixes.resize(counts[0]);
    slots.resize(counts[1]);
    mask = counts[1] - 1;
    if (std::fread(prefixes.data(), sizeof(PrefixRecord), prefixes.size(), file) !=
            prefixes.size() ||
        std::fread(slots.data(), 4, slots.size(), file) != slots.size()) {
      throw std::runtime_error("truncated index cache");
    }
    bytes = prefixes.size() * sizeof(PrefixRecord) + slots.size() * 4;
#endif
    std::fclose(file);
    std::fprintf(stderr, "index_bytes=%zu\n", bytes);
    return;
  }
#if INDEX_KIND >= 1
#if INDEX_KIND == 2
  for (uint32_t high = 0; high < UNICODE_PAGES; ++high) {
    uint32_t page = dictionary->scalars.npages
                        ? read_u32(dictionary->scalars.directory + size_t(high) * 4)
                        : 0;
    if (!page) continue;
    for (uint32_t low = 0; low < 256; ++low) {
      uint32_t offset = read_u32(dictionary->scalars.pages + ((size_t(page) - 1) * 256 + low) * 4);
      if (offset) trie_root_code((high << 8) | low, offset);
    }
  }
#endif
  std::vector<const char *> keys(count);
  std::vector<size_t> sizes(count);
  for (uint32_t i = 0; i < count; ++i) {
    keys[i] = text_entry_at(dictionary, i).key;
    sizes[i] = strlen(keys[i]);
  }
  bytes = trie_build(keys.data(), sizes.data(), count);
#else
  std::vector<uint32_t> path;
  std::vector<uint32_t> hashes;
  for (uint32_t i = 0; i < count; ++i) {
    const char *key = text_entry_at(dictionary, i).key;
    uint32_t size = (uint32_t)strlen(key), at = 0, hash = 2166136261u, common = 0;
    const char *previous = i ? text_entry_at(dictionary, i - 1).key : "";
    while (common < size && previous[common] && previous[common] == key[common]) {
      ++common;
    }
    size_t depth = 0;
    while (at < size) {
      uint32_t before = at;
      int32_t cp = decode((const unsigned char *)key, size, &at);
      uint32_t token = cp >= 0 ? (uint32_t)cp : 0x110000u + (unsigned char)key[before];
      hash = (hash ^ token) * 16777619u;
      if (at > common) {
        path.resize(depth);
        path.push_back((uint32_t)prefixes.size());
        prefixes.push_back({(uint32_t)(key - (const char *)dictionary->pool), at, NONE});
        hashes.push_back(hash);
      }
      ++depth;
    }
    prefixes[path[depth - 1]].terminal = i;
  }
  uint32_t capacity = 2;
  while ((uint64_t)capacity * 3 < prefixes.size() * 4) {
    capacity *= 2;
  }
  mask = capacity - 1;
  slots.resize(capacity);
  for (uint32_t i = 0; i < prefixes.size(); ++i) {
    uint32_t slot = hashes[i] & mask;
    while (slots[slot]) {
      slot = (slot + 1) & mask;
    }
    slots[slot] = (hashes[i] & ~mask) | (i + 1);
  }
  prefixes.shrink_to_fit();
  bytes = prefixes.size() * sizeof(PrefixRecord) + slots.size() * 4;
#endif
  if (cache) {
    file = std::fopen(cache, "wb");
    if (!file) {
      throw std::runtime_error("cannot write index cache");
    }
#if INDEX_KIND >= 1
    trie_image(file, 0);
#else
    uint32_t counts[] = {0x31504846u, (uint32_t)prefixes.size(), (uint32_t)slots.size()};
    std::fwrite(counts, 4, 3, file);
    std::fwrite(prefixes.data(), sizeof(PrefixRecord), prefixes.size(), file);
    std::fwrite(slots.data(), 4, slots.size(), file);
#endif
    if (std::fclose(file)) {
      throw std::runtime_error("cannot close index cache");
    }
  }
  std::fprintf(stderr, "index_bytes=%zu\n", bytes);
}

extern "C" int text_advance(const Dictionary *dictionary, TextPrefix *prefix, Slice token,
                            uint32_t value) {
#if INDEX_KIND >= 1
  (void)dictionary;
#if INDEX_KIND == 2
  uint32_t state = trie_from_base(prefix->begin, value);
#else
  uint32_t state = trie_from_base(prefix->bytes ? prefix->begin : trie_base(0), value);
#endif
  if (state == NONE) {
    return 0;
  }
  prefix->begin = trie_base(state);
  prefix->end = trie_value(state) + 1;
#else
  uint32_t hash = ((prefix->bytes ? prefix->begin : 2166136261u) ^ value) * 16777619u;
  uint32_t bytes = prefix->bytes + token.size, slot = hash & mask;
  const char *key = token.data - prefix->bytes;
  for (;;) {
    uint32_t word = slots[slot];
    if (!word) {
      return 0;
    }
    if (((word ^ hash) & ~mask) == 0) {
      uint32_t id = (word & mask) - 1;
      const PrefixRecord &record = prefixes[id];
      if (record.bytes == bytes && !memcmp(dictionary->pool + record.offset, key, bytes)) {
        prefix->begin = hash;
        prefix->end = id;
        break;
      }
    }
    slot = (slot + 1) & mask;
  }
#endif
  prefix->bytes += token.size;
  return 1;
}

extern "C" const unsigned char *prefix_codes(const Dictionary *dictionary,
                                             const TextPrefix *prefix) {
#if INDEX_KIND >= 1
  uint32_t terminal = prefix->end - 1;
#else
  uint32_t terminal = prefixes[prefix->end].terminal;
#endif
  return terminal == NONE ? NULL : text_entry_at(dictionary, terminal).codes;
}

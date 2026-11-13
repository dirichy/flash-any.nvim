/* Full-scanner adapter for trusted FANYPAK1 space-experiment images.
 * POOL_RELOCATED=0 is the parallel-array control without region selection.
 * One immutable image per isolated benchmark process; no production ABI change. */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <vector>
extern "C" {
#include "native.h"
}

static constexpr uint32_t CHILD = 0x80000000u, IN_BASE = 0x40000000u;
static constexpr uint32_t MASK = IN_BASE - 1;
static std::vector<unsigned char> image;
static const unsigned char *directory, *codes, *bases, *dat, *entries, *pool;
static uint32_t directory_count, units;

static inline const unsigned char *resolve(uint32_t ref) {
  uint32_t offset = ref & MASK;
  if (!offset) {
    return NULL;
  }
#if POOL_RELOCATED
  return ((ref & IN_BASE) ? bases : pool) + offset - 1;
#else
  return pool + offset - 1;
#endif
}

extern "C" void bench_prepare_index(const Dictionary *dictionary) {
  const char *path = std::getenv("FLASH_ANY_BENCH_INDEX");
  FILE *file = path ? std::fopen(path, "rb") : NULL;
  if (!file) {
    throw std::runtime_error("packed image required");
  }
  std::fseek(file, 0, SEEK_END);
  long size = std::ftell(file);
  std::rewind(file);
  if (size < 32) {
    throw std::runtime_error("truncated packed image");
  }
  image.resize(size);
  bool complete = std::fread(image.data(), 1, image.size(), file) == image.size();
  std::fclose(file);
  if (!complete || std::memcmp(image.data(), "FANYPAK1", 8)) {
    throw std::runtime_error("invalid packed image");
  }
  directory_count = read_u32(image.data() + 8);
  uint32_t slots = read_u32(image.data() + 12);
  units = read_u32(image.data() + 16);
  uint32_t count = read_u32(image.data() + 20), bytes = read_u32(image.data() + 24);
  uint32_t groups = read_u32(image.data() + 28);
  if (count != dictionary->text.count || directory_count != 0x1101 ||
      32 + size_t(directory_count) * 4 + size_t(slots) * 8 + size_t(units) * 8 + size_t(count) * 8 +
              bytes + groups !=
          image.size()) {
    throw std::runtime_error("packed image sections differ");
  }
  directory = image.data() + 32;
  codes = directory + size_t(directory_count) * 4;
  bases = codes + size_t(slots) * 4;
  dat = bases + size_t(slots) * 4;
  entries = dat + size_t(units) * 8;
  pool = entries + size_t(count) * 8;
}

extern "C" const unsigned char *bench_root_start(const Dictionary *, uint32_t cp, uint32_t bytes,
                                                 TextPrefix *prefix) {
  uint32_t page = (cp >> 8) < directory_count ? read_u32(directory + size_t(cp >> 8) * 4) : 0;
  prefix->begin = NONE;
  prefix->end = 0;
  prefix->bytes = bytes;
  if (!page) {
    return NULL;
  }
  uint32_t slot = (page - 1) * 256 + (cp & 255);
  uint32_t ref = read_u32(codes + size_t(slot) * 4);
  if (ref & CHILD) {
    prefix->begin = read_u32(bases + size_t(slot) * 4);
  }
  return resolve(ref);
}

static inline uint32_t step(uint32_t base, uint32_t cp) {
  int32_t offset;
  std::memcpy(&offset, &base, 4);
  uint64_t at = uint64_t(int64_t(offset) + (cp & ((1u << 18) - 1)));
  return at < units && read_u32(dat + size_t(at) * 8 + 4) == cp + 1 ? uint32_t(at) : NONE;
}

extern "C" int text_advance(const Dictionary *, TextPrefix *prefix, Slice token, uint32_t cp) {
  uint32_t state = step(prefix->begin, cp);
  if (state == NONE) {
    return 0;
  }
  prefix->begin = read_u32(dat + size_t(state) * 8);
  uint32_t terminal = step(prefix->begin, 0);
  prefix->end = terminal == NONE ? 0 : read_u32(dat + size_t(terminal) * 8) + 1;
  prefix->bytes += token.size;
  return 1;
}

extern "C" const unsigned char *prefix_codes(const Dictionary *, const TextPrefix *prefix) {
  return prefix->end ? resolve(read_u32(entries + size_t(prefix->end - 1) * 8 + 4)) : NULL;
}

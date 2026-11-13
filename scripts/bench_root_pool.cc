/* Reuse non-branch root base slots for shared-pool blocks. Experimental images
 * only: plain/codes/all layouts, rebuilt offsets, full reference and DAT checks.
 * c++ -O3 -std=c++17 -Wall -Wextra -Werror scripts/bench_root_pool.cc -o /tmp/bench-root-pool
 * /tmp/bench-root-pool DICTIONARY.bin PAGED.index OUTPUT_PREFIX
 */
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

using Bytes = std::vector<unsigned char>;
static constexpr uint32_t CHILD = 0x80000000u, IN_BASE = 0x40000000u;
static constexpr uint32_t MASK = IN_BASE - 1, NONE = UINT32_MAX;

static void require(bool valid, const char *message) {
  if (!valid) {
    throw std::runtime_error(message);
  }
}

static uint32_t read32(const unsigned char *p) {
  return p[0] | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}

static void put32(unsigned char *p, uint32_t value) {
  for (unsigned i = 0; i < 4; ++i) {
    p[i] = static_cast<unsigned char>(value >> (i * 8));
  }
}

static Bytes read_file(const std::string &path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  require(bool(file), "cannot open image");
  Bytes data(size_t(file.tellg()));
  file.seekg(0);
  file.read(reinterpret_cast<char *>(data.data()), data.size());
  require(bool(file), "cannot read image");
  return data;
}

static void append(Bytes &out, const unsigned char *data, size_t size) {
  out.insert(out.end(), data, data + size);
}

static void append32(Bytes &out, uint32_t value) {
  unsigned char bytes[4];
  put32(bytes, value);
  append(out, bytes, 4);
}

struct Block {
  uint32_t offset, size, ref;
  bool code;
};

struct Gap {
  uint32_t offset, size;
};

int main(int argc, char **argv) {
  try {
    require(argc == 4, "usage: bench-root-pool dictionary.bin paged.index output-prefix");
    Bytes binary = read_file(argv[1]), index = read_file(argv[2]);
    require(binary.size() >= 40 && !std::memcmp(binary.data(), "FANYBIN\x0b", 8),
            "need v11 binary");
    uint32_t text_count = read32(binary.data() + 16), capacity = read32(binary.data() + 20);
    uint32_t old_pages = read32(binary.data() + 24), pool_size = read32(binary.data() + 28);
    uint32_t group_size = read32(binary.data() + 32);
    size_t entries_at = 40 + (old_pages ? 4352 * 4 : 0) + size_t(old_pages) * 256 * 4;
    size_t pool_at = entries_at + size_t(text_count) * 8 + size_t(capacity) * 4;
    require(pool_size < MASK && pool_at + pool_size + group_size == binary.size(), "bad sections");
    const auto *entries = binary.data() + entries_at, *pool = binary.data() + pool_at;
    constexpr size_t directory_bytes = 0x1101 * 4;
    require(index.size() >= directory_bytes + 12, "bad paged index");
    uint32_t pages = read32(index.data() + directory_bytes), slots = pages * 256;
    size_t dat_header = directory_bytes + 4 + size_t(slots) * 8;
    require(index.size() >= dat_header + 8, "bad root sections");
    uint32_t units = read32(index.data() + dat_header);
    require(!read32(index.data() + dat_header + 4) &&
                index.size() == dat_header + 8 + size_t(units) * 8,
            "bad DAT section");
    const auto *dat = index.data() + dat_header + 8;
    Bytes bases(size_t(slots) * 4);
    std::vector<uint32_t> root_codes(slots), offsets;
    std::vector<Gap> gaps;
    uint32_t branches = 0, start = 0;
    for (uint32_t i = 0; i < slots; ++i) {
      const auto *entry = index.data() + directory_bytes + 4 + size_t(i) * 8;
      uint32_t base = read32(entry), codes = read32(entry + 4);
      put32(bases.data() + size_t(i) * 4, base);
      root_codes[i] = codes;
      if (codes) {
        offsets.push_back((codes - 1) | CHILD);
      }
      if (base != NONE) {
        ++branches;
        if (i > start) {
          gaps.push_back({start * 4, (i - start) * 4});
        }
        start = i + 1;
      }
    }
    if (slots > start) {
      gaps.push_back({start * 4, (slots - start) * 4});
    }
    for (uint32_t i = 0; i < text_count; ++i) {
      offsets.push_back(read32(entries + size_t(i) * 8));
      offsets.push_back(read32(entries + size_t(i) * 8 + 4) | CHILD);
    }
    std::sort(offsets.begin(), offsets.end(),
              [](uint32_t a, uint32_t b) { return (a & ~CHILD) < (b & ~CHILD); });
    std::vector<Block> blocks;
    for (uint32_t marked : offsets) {
      uint32_t offset = marked & ~CHILD;
      require(offset < pool_size, "bad pool reference");
      if (!blocks.empty() && blocks.back().offset == offset) {
        blocks.back().code |= bool(marked & CHILD);
      } else {
        blocks.push_back({offset, 0, 0, bool(marked & CHILD)});
      }
    }
    offsets.clear();
    offsets.shrink_to_fit();
    require(!blocks.empty() && !blocks.front().offset, "fixture pool has an unreferenced prefix");
    for (size_t i = 0; i < blocks.size(); ++i) {
      blocks[i].size =
          (i + 1 < blocks.size() ? blocks[i + 1].offset : pool_size) - blocks[i].offset;
    }
    std::vector<uint32_t> order(blocks.size());
    for (uint32_t i = 0; i < order.size(); ++i) {
      order[i] = i;
    }
    std::sort(order.begin(), order.end(), [&](uint32_t a, uint32_t b) {
      return blocks[a].size != blocks[b].size ? blocks[a].size > blocks[b].size
                                              : blocks[a].offset < blocks[b].offset;
    });
    std::map<uint32_t, uint32_t> histogram;
    uint32_t free_bytes = 0, largest_gap = 0;
    for (auto gap : gaps) {
      ++histogram[gap.size];
      free_bytes += gap.size;
      largest_gap = std::max(largest_gap, gap.size);
    }
    for (unsigned mode = 0; mode < 3; ++mode) {
      const char *name = mode == 0 ? "plain" : mode == 1 ? "codes" : "all";
      Bytes packed_bases = bases, remaining_pool;
      std::multimap<uint32_t, uint32_t> available;
      for (auto gap : gaps) {
        available.emplace(gap.size, gap.offset);
      }
      for (auto &block : blocks) {
        block.ref = 0;
      }
      uint32_t moved_bytes = 0, moved_blocks = 0, moved_code_bytes = 0;
      if (mode) {
        for (uint32_t id : order) {
          auto &block = blocks[id];
          if (mode == 1 && !block.code) {
            continue;
          }
          auto gap = available.lower_bound(block.size);
          if (gap == available.end()) {
            continue;
          }
          uint32_t size = gap->first, offset = gap->second;
          std::memcpy(packed_bases.data() + offset, pool + block.offset, block.size);
          block.ref = IN_BASE | (offset + 1);
          moved_bytes += block.size;
          ++moved_blocks;
          if (block.code) {
            moved_code_bytes += block.size;
          }
          available.erase(gap);
          if (size > block.size) {
            available.emplace(size - block.size, offset + block.size);
          }
        }
      }
      for (auto &block : blocks) {
        if (!block.ref) {
          block.ref = uint32_t(remaining_pool.size()) + 1;
          append(remaining_pool, pool + block.offset, block.size);
        }
      }
      auto relocate = [&](uint32_t offset) {
        auto it = std::lower_bound(
            blocks.begin(), blocks.end(), offset,
            [](const Block &block, uint32_t value) { return block.offset < value; });
        require(it != blocks.end() && it->offset == offset, "unknown original reference");
        return it->ref;
      };
      Bytes image;
      append(image, reinterpret_cast<const unsigned char *>("FANYPAK1"), 8);
      for (uint32_t value : {uint32_t(0x1101), slots, units, text_count,
                             uint32_t(remaining_pool.size()), group_size}) {
        append32(image, value);
      }
      append(image, index.data(), directory_bytes);
      for (uint32_t i = 0; i < slots; ++i) {
        uint32_t flags = read32(bases.data() + size_t(i) * 4) != NONE ? CHILD : 0;
        append32(image, flags | (root_codes[i] ? relocate(root_codes[i] - 1) : 0));
      }
      append(image, packed_bases.data(), packed_bases.size());
      append(image, dat, size_t(units) * 8);
      for (uint32_t i = 0; i < text_count; ++i) {
        append32(image, relocate(read32(entries + size_t(i) * 8)));
        append32(image, relocate(read32(entries + size_t(i) * 8 + 4)));
      }
      append(image, remaining_pool.data(), remaining_pool.size());
      append(image, pool + pool_size, group_size);
      std::string path = std::string(argv[3]) + "." + name + ".bin";
      {
        std::ofstream file(path, std::ios::binary);
        file.write(reinterpret_cast<char *>(image.data()), image.size());
        require(bool(file), "cannot write packed image");
      }
      image = read_file(path); // Validate the serialized image, including all rewritten references.
      const auto *new_codes = image.data() + 32 + directory_bytes;
      const auto *new_bases = new_codes + size_t(slots) * 4;
      const auto *new_dat = new_bases + size_t(slots) * 4;
      const auto *new_entries = new_dat + size_t(units) * 8;
      const auto *new_pool = new_entries + size_t(text_count) * 8;
      auto resolve = [&](uint32_t ref, uint32_t size) {
        uint32_t offset = (ref & MASK) - 1;
        size_t limit = ref & IN_BASE ? size_t(slots) * 4 : remaining_pool.size();
        require((ref & MASK) && uint64_t(offset) + size <= limit,
                "relocated reference out of bounds");
        return (ref & IN_BASE ? new_bases : new_pool) + offset;
      };
      for (const auto &block : blocks) {
        require(!std::memcmp(resolve(block.ref, block.size), pool + block.offset, block.size),
                "relocated bytes differ");
      }
      for (uint32_t i = 0; i < slots; ++i) {
        uint32_t ref = read32(new_codes + size_t(i) * 4);
        bool branch = read32(bases.data() + size_t(i) * 4) != NONE;
        require(bool(ref & CHILD) == branch, "branch flag differs");
        if (branch) {
          require(read32(new_bases + size_t(i) * 4) == read32(bases.data() + size_t(i) * 4),
                  "base overwritten");
        }
        require((ref & ~CHILD) == (root_codes[i] ? relocate(root_codes[i] - 1) : 0),
                "root reference differs");
      }
      auto step = [&](uint32_t base, uint32_t cp) {
        int32_t signed_base;
        std::memcpy(&signed_base, &base, 4);
        int64_t at = int64_t(signed_base) + (cp & ((1u << 18) - 1));
        require(at >= 0 && uint64_t(at) < units && read32(new_dat + size_t(at) * 8 + 4) == cp + 1,
                "DAT transition differs");
        return uint32_t(at);
      };
      for (uint32_t i = 0; i < text_count; ++i) {
        uint32_t key_ref = read32(new_entries + size_t(i) * 8);
        uint32_t code_ref = read32(new_entries + size_t(i) * 8 + 4);
        require(key_ref == relocate(read32(entries + size_t(i) * 8)) &&
                    code_ref == relocate(read32(entries + size_t(i) * 8 + 4)),
                "text reference differs");
        const unsigned char *p = resolve(key_ref, 1);
        uint32_t base = NONE, state = NONE;
        bool first = true;
        while (*p) {
          uint32_t cp = *p++;
          if (cp >= 0xc0) {
            unsigned n = cp < 0xe0 ? 1 : cp < 0xf0 ? 2 : 3;
            cp &= (1u << (6 - n)) - 1;
            while (n--) {
              cp = (cp << 6) | (*p++ & 63);
            }
          }
          if (first) {
            require(cp <= 0x1100ff, "invalid fixture codepoint");
            uint32_t page = read32(image.data() + 32 + size_t(cp >> 8) * 4);
            require(page && page <= pages, "root page missing");
            uint32_t slot = (page - 1) * 256 + (cp & 255);
            require(read32(new_codes + size_t(slot) * 4) & CHILD, "root branch missing");
            base = read32(new_bases + size_t(slot) * 4);
            first = false;
          } else {
            state = step(base, cp);
            base = read32(new_dat + size_t(state) * 8);
          }
        }
        require(state != NONE && read32(new_dat + size_t(step(base, 0)) * 8) == i,
                "DAT terminal differs");
      }
      std::printf(
          "{\"mode\":\"%s\",\"image_bytes\":%zu,\"root_slots\":%u,\"branches\":%u,"
          "\"free_bytes\":%u,\"gap_count\":%zu,\"largest_gap\":%u,\"pool_bytes_before\":%u,"
          "\"pool_bytes_after\":%zu,\"moved_bytes\":%u,\"moved_blocks\":%u,\"moved_code_bytes\":%u,"
          "\"checked_blocks\":%zu,\"checked_text_keys\":%u,\"gap_histogram\":{",
          name, image.size(), slots, branches, free_bytes, gaps.size(), largest_gap, pool_size,
          remaining_pool.size(), moved_bytes, moved_blocks, moved_code_bytes, blocks.size(),
          text_count);
      bool comma = false;
      for (auto [length, count] : histogram) {
        std::printf("%s\"%u\":%u", comma ? "," : "", length, count);
        comma = true;
      }
      std::puts("}}");
    }
  } catch (const std::exception &error) {
    std::fprintf(stderr, "%s\n", error.what());
    return 1;
  }
}

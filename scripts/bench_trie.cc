/* Lookup experiment. KIND=0: Rime Darts; 1: byte DAT; 2: codepoint DAT;
 * 3: MARISA (one trie, huge cache, reused Agent). No runtime dependency. */
#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <limits>
#include <queue>
#include <stdexcept>
#include <utility>
#include <vector>

/* Independent prototype switches; zero preserves the original comparison. */
#ifndef BUILD_WIDE
#define BUILD_WIDE 0
#endif
#ifndef COMPRESS_FREE
#define COMPRESS_FREE 0
#endif
#ifndef PACK_STATS
#define PACK_STATS 0
#endif
#ifndef SIGNED_BASE
#define SIGNED_BASE 0
#endif
#ifndef MOD_BITS
#define MOD_BITS 0
#endif
#ifndef PAGED_ROOT
#define PAGED_ROOT 0
#endif
#if PAGED_ROOT && (!BUILD_WIDE || !MOD_BITS || !SIGNED_BASE || KIND != 2)
#error "paged root requires the wide-first signed modulo codepoint builder"
#endif

#if KIND == 0
#include <darts.h>
static Darts::DoubleArray trie;
#elif KIND == 3
#include <marisa.h>
static marisa::Trie trie;
static std::vector<uint32_t> ids;
#else
struct Unit {
  /* check: parent+1 normally, original label+1 with MOD_BITS; zero is empty.
   * Modulo mode reserves each base for one parent during construction. */
  uint32_t base = 0, check = 0;
};

static_assert(sizeof(Unit) == 8, "the comparison assumes eight-byte units");

static std::vector<Unit> units;
#if PAGED_ROOT
/* Root slots use check as code offset+1; base is the continuation, not a state ID.
 * Invalid UTF-8 byte tokens occupy one extra page after the Unicode pages. */
static uint32_t root_directory[0x1101] = {};
static std::vector<Unit> root_pages;
static Unit &root_slot(uint32_t cp) {
  uint32_t &page = root_directory[cp >> 8];
  if (!page) {
    page = uint32_t(root_pages.size() / 256) + 1;
    root_pages.resize(root_pages.size() + 256, Unit{UINT32_MAX, 0});
  }
  return root_pages[(page - 1) * 256 + (cp & 255)];
}
extern "C" void trie_root_code(uint32_t cp, uint32_t offset) {
  root_slot(cp).check = offset;
}
extern "C" uint32_t trie_root(uint32_t cp, uint32_t *base) {
  uint32_t page = cp <= 0x1100ff ? root_directory[cp >> 8] : 0;
  Unit entry = page ? root_pages[(page - 1) * 256 + (cp & 255)] : Unit{UINT32_MAX, 0};
  *base = entry.base;
  return entry.check;
}
#endif
#if KIND == 2 && MOD_BITS && SIGNED_BASE && defined(BENCH_PHRASES)
extern "C" uint32_t trie_base(uint32_t state) {
  return units[state].base;
}
extern "C" uint32_t trie_from_base(uint32_t base, uint32_t label) {
  int32_t offset;
  std::memcpy(&offset, &base, sizeof(offset));
  uint64_t next = uint64_t(int64_t(offset) + (label & ((1u << MOD_BITS) - 1)));
  return next < units.size() && units[next].check == label + 1 ? uint32_t(next) : UINT32_MAX;
}
#endif

static uint32_t edge_label(uint32_t cp) {
#if MOD_BITS
  return cp & ((1u << MOD_BITS) - 1);
#else
  return cp;
#endif
}
#if KIND == 2
static uint32_t decode(const unsigned char *&p) {
  uint32_t cp = *p++;
  if (cp >= 0xc0) {
    unsigned more = cp < 0xe0 ? 1 : cp < 0xf0 ? 2 : 3;
    cp &= (1u << (6 - more)) - 1;
    while (more--) {
      cp = (cp << 6) | (*p++ & 63);
    }
  }
  return cp;
}
#endif

static uint32_t step(uint32_t state, uint32_t label) {
#if SIGNED_BASE
  int32_t offset;
  std::memcpy(&offset, &units[state].base, sizeof(offset));
  /* Converting a negative result to u64 makes the single bounds check reject it. */
  uint64_t next = uint64_t(int64_t(offset) + edge_label(label));
#else
  uint64_t next = uint64_t(units[state].base) + edge_label(label);
#endif
#if MOD_BITS
  /* Unique bases distinguish parents; the original label rejects modulo aliases. */
  return next < units.size() && units[next].check == label + 1 ? uint32_t(next) : UINT32_MAX;
#else
  return next < units.size() && units[next].check == state + 1 ? uint32_t(next) : UINT32_MAX;
#endif
}

static uint32_t result(uint32_t state) {
  uint32_t end = step(state, 0);
  return end == UINT32_MAX ? end : units[end].base;
}
#endif

extern "C" size_t trie_build(const char **keys, const size_t *sizes, uint32_t count) {
#if KIND == 0
  std::vector<uint32_t> order(count);
  for (uint32_t i = 0; i < count; ++i) {
    order[i] = i;
  }
  std::sort(order.begin(), order.end(),
            [&](uint32_t a, uint32_t b) { return std::strcmp(keys[a], keys[b]) < 0; });
  std::vector<const char *> sorted(count);
  std::vector<size_t> lengths(count);
  std::vector<int> values(count);
  for (uint32_t i = 0; i < count; ++i) {
    sorted[i] = keys[order[i]];
    lengths[i] = sizes[order[i]];
    values[i] = int(order[i]);
  }
  if (trie.build(count, sorted.data(), lengths.data(), values.data())) {
    throw std::runtime_error("Darts build failed");
  }
  return trie.total_size();
#elif KIND == 3
  marisa::Keyset set;
  for (uint32_t i = 0; i < count; ++i) {
    set.push_back(keys[i], sizes[i]);
  }
  trie.build(set, 1 | MARISA_HUGE_CACHE);
  ids.resize(count);
  for (uint32_t i = 0; i < count; ++i) {
    ids[set[i].id()] = i;
  }
  return trie.io_size() + ids.size() * sizeof(uint32_t);
#else
  struct Node {
    std::vector<std::pair<uint32_t, uint32_t>> children;
    uint32_t value = UINT32_MAX;
  };

  std::vector<uint32_t> order(count);
  for (uint32_t i = 0; i < count; ++i) {
    order[i] = i;
  }
  std::sort(order.begin(), order.end(),
            [&](uint32_t a, uint32_t b) { return std::strcmp(keys[a], keys[b]) < 0; });
  std::vector<Node> nodes(1);
  std::vector<uint32_t> previous, path(1, 0);
  for (uint32_t id : order) {
    std::vector<uint32_t> labels;
    const auto *p = reinterpret_cast<const unsigned char *>(keys[id]);
    const auto *end = p + sizes[id];
    while (p != end) {
#if KIND == 1
      uint32_t label = *p++;
#else
      uint32_t label = decode(p);
#endif
      if (!label) {
        throw std::runtime_error("NUL is outside the fixture contract");
      }
      labels.push_back(label);
    }
    size_t shared = 0;
    while (shared < previous.size() && shared < labels.size() &&
           previous[shared] == labels[shared]) {
      ++shared;
    }
    path.resize(shared + 1);
    for (size_t i = shared; i < labels.size(); ++i) {
      uint32_t child = uint32_t(nodes.size());
      nodes[path.back()].children.emplace_back(labels[i], child);
      nodes.emplace_back();
      path.push_back(child);
    }
    nodes[path.back()].value = id;
    previous.swap(labels);
  }
  /* Temporary free-slot links make greedy packing deterministic. Occupied slots
   * retain their forward link, allowing a search to skip them after removal. */
  std::vector<uint32_t> next, prev;
#if MOD_BITS
  /* Build-only flags indexed by signed base + modulus. No runtime side table. */
  std::vector<uint8_t> used_bases;
#endif
  uint32_t head = 0, tail = 0, last_used = 0;
  auto grow = [&](size_t needed) {
    uint32_t old = uint32_t(units.size());
    size_t size = std::max(needed, std::max(size_t(256), units.size() * 2));
    if (size >= UINT32_MAX) {
      throw std::runtime_error("DAT too large");
    }
    units.resize(size);
    next.resize(size);
    prev.resize(size);
#if MOD_BITS
    used_bases.resize(size + (1u << MOD_BITS));
#endif
    for (uint32_t i = old; i < size; ++i) {
      next[i] = i + 1 < size ? i + 1 : 0;
      prev[i] = i == old ? tail : i - 1;
    }
    if (tail) {
      next[tail] = old;
    }
    if (!head) {
      head = old ? old : 1;
    }
    tail = uint32_t(size - 1);
  };
  grow(256);
#if PAGED_ROOT
  used_bases[(1u << MOD_BITS) - 1] = 1; // -1 marks a root without continuation.
#endif
  units[0].check = UINT32_MAX;
  auto occupy = [&](uint32_t at, uint32_t parent, uint32_t label) {
    if (prev[at]) {
      next[prev[at]] = next[at];
    }
    if (next[at]) {
      prev[next[at]] = prev[at];
    }
    if (head == at) {
      head = next[at];
    }
    if (tail == at) {
      tail = prev[at];
    }
#if MOD_BITS
    (void)parent;
    units[at].check = label + 1;
#else
    (void)label;
    units[at].check = parent + 1;
#endif
    last_used = std::max(last_used, at);
  };
#if PACK_STATS
  uint64_t attempts = 0, checks = 0, skips = 0;
#endif
#if BUILD_WIDE
  auto less = [&](auto a, auto b) {
    size_t x = nodes[a.first].children.size() + (nodes[a.first].value != UINT32_MAX);
    size_t y = nodes[b.first].children.size() + (nodes[b.first].value != UINT32_MAX);
    return x != y ? x < y : a.first > b.first;
  };
  std::priority_queue<std::pair<uint32_t, uint32_t>, std::vector<std::pair<uint32_t, uint32_t>>,
                      decltype(less)>
      pending(less);
  pending.emplace(0, 0);
  while (!pending.empty()) {
    auto [node_id, state] = pending.top();
    pending.pop();
#else
  std::vector<std::pair<uint32_t, uint32_t>> pending(1, {0, 0});
  for (size_t cursor = 0; cursor < pending.size(); ++cursor) {
    auto [node_id, state] = pending[cursor];
#endif
    const Node &node = nodes[node_id];
#if PAGED_ROOT
    if (!node_id) {
      for (auto [label, child] : node.children) {
        root_slot(label);
        pending.emplace(child, UINT32_MAX - label);
      }
      continue;
    }
#endif
    std::vector<uint32_t> labels;
    if (node.value != UINT32_MAX) {
      labels.push_back(0);
    }
    for (auto [label, child] : node.children) {
      (void)child;
      labels.push_back(edge_label(label));
    }
#if MOD_BITS
    std::sort(labels.begin(), labels.end());
    if (std::adjacent_find(labels.begin(), labels.end()) != labels.end()) {
      throw std::runtime_error("modulus collides within one parent's labels");
    }
#endif
    if (labels.empty()) {
      continue;
    }
#if SIGNED_BASE
    uint32_t anchor = head ? head : uint32_t(units.size()), base;
#else
    uint32_t anchor = std::max(head, labels.front() + 1), base;
#endif
    for (;;) {
#if PACK_STATS
      ++attempts;
#endif
      if (anchor >= units.size()) {
        grow(size_t(anchor) + 1);
      }
#if COMPRESS_FREE
      uint32_t first = anchor;
#endif
      while (units[anchor].check) {
#if PACK_STATS
        ++skips;
#endif
        if (!next[anchor]) {
#if COMPRESS_FREE
          uint32_t old_anchor = anchor;
#endif
          anchor = uint32_t(units.size());
          grow(size_t(anchor) + 1);
#if COMPRESS_FREE
          next[old_anchor] = anchor;
#endif
        } else {
          anchor = next[anchor];
        }
      }
#if COMPRESS_FREE
      /* Only occupied links are compressed; the live free list stays intact. */
      while (first != anchor) {
        uint32_t following = next[first];
        next[first] = anchor;
        first = following;
      }
#endif
      base = anchor - labels.front();
#if SIGNED_BASE
      if (int64_t(anchor) - labels.front() > INT32_MAX) {
        throw std::runtime_error("signed DAT offset too large");
      }
#endif
      uint64_t last_child = uint64_t(anchor) + labels.back() - labels.front();
      if (last_child >= units.size()) {
        grow(last_child + 1);
      }
      bool free = true;
#if MOD_BITS
      free = !used_bases[uint64_t(anchor) + (1u << MOD_BITS) - labels.front()];
#endif
      for (uint32_t label : labels) {
        if (!free) {
          break;
        }
#if PACK_STATS
        ++checks;
#endif
        if (units[anchor + (label - labels.front())].check) {
          free = false;
          break;
        }
      }
      if (free) {
        break;
      }
      anchor = next[anchor] ? next[anchor] : uint32_t(units.size());
    }
#if PAGED_ROOT
    if (state >= 0x80000000u) {
      root_slot(UINT32_MAX - state).base = base;
    } else
#endif
    {
      units[state].base = base;
    }
#if MOD_BITS
    used_bases[uint64_t(anchor) + (1u << MOD_BITS) - labels.front()] = 1;
#endif
    if (node.value != UINT32_MAX) {
      occupy(anchor, state, 0);
      units[anchor].base = node.value;
    }
    for (auto [label, child] : node.children) {
      uint32_t child_slot = anchor + (edge_label(label) - labels.front());
      occupy(child_slot, state, label);
#if BUILD_WIDE
      pending.emplace(child, child_slot);
#else
      pending.emplace_back(child, child_slot);
#endif
    }
  }
  units.resize(size_t(last_used) + 1);
  units.shrink_to_fit();
#if PACK_STATS
  size_t used = std::count_if(units.begin(), units.end(), [](auto u) { return u.check != 0; });
  uint64_t digest = 14695981039346656037ull;
  for (auto u : units) {
    digest = (digest ^ u.base) * 1099511628211ull;
    digest = (digest ^ u.check) * 1099511628211ull;
  }
  std::fprintf(stderr,
               "{\"slots\":%zu,\"used\":%zu,\"attempts\":%llu,\"checks\":%llu,\"skips\":%llu,"
               "\"digest\":%llu}\n",
               units.size(), used, (unsigned long long)attempts, (unsigned long long)checks,
               (unsigned long long)skips, (unsigned long long)digest);
#endif
  size_t bytes = units.size() * sizeof(Unit);
#if PAGED_ROOT
  bytes += sizeof(root_directory) + root_pages.size() * sizeof(Unit);
#endif
  return bytes;
#endif
}

extern "C" uint32_t trie_lookup(const char *key, size_t size) {
#if KIND == 0
  int value = trie.exactMatchSearch<int>(key, size);
  return value < 0 ? UINT32_MAX : uint32_t(value);
#elif KIND == 3
  static marisa::Agent agent;
  agent.set_query(key, size);
  return trie.lookup(agent) ? ids[agent.key().id()] : UINT32_MAX;
#else
  uint32_t state = 0;
  const auto *p = reinterpret_cast<const unsigned char *>(key);
  const auto *end = p + size;
  while (p != end) {
#if KIND == 1
    uint32_t label = *p++;
#else
    uint32_t label = decode(p);
#endif
    state = step(state, label);
    if (state == UINT32_MAX) {
      return state;
    }
  }
  return result(state);
#endif
}

#if KIND == 2
#ifdef BENCH_PHRASES
extern "C" size_t trie_image(FILE *file, int load) {
#if PAGED_ROOT
  uint32_t pages = uint32_t(root_pages.size() / 256);
  if (load) {
    if (std::fread(root_directory, sizeof(root_directory), 1, file) != 1 ||
        std::fread(&pages, 4, 1, file) != 1 || pages > 0x1101) {
      throw std::runtime_error("invalid root image");
    }
    root_pages.resize(size_t(pages) * 256);
    if (std::fread(root_pages.data(), sizeof(Unit), root_pages.size(), file) != root_pages.size()) {
      throw std::runtime_error("truncated root image");
    }
  } else {
    if (std::fwrite(root_directory, sizeof(root_directory), 1, file) != 1 ||
        std::fwrite(&pages, 4, 1, file) != 1 ||
        std::fwrite(root_pages.data(), sizeof(Unit), root_pages.size(), file) != root_pages.size()) {
      throw std::runtime_error("cannot write root image");
    }
  }
  std::fprintf(stderr, "root_pages=%u root_bytes=%zu\n", pages,
               sizeof(root_directory) + root_pages.size() * sizeof(Unit));
#endif
  uint64_t count = units.size();
  if (load) {
    if (std::fread(&count, sizeof(count), 1, file) != 1 || count > UINT32_MAX) {
      throw std::runtime_error("invalid benchmark Trie image");
    }
    units.resize(count);
    if (std::fread(units.data(), sizeof(Unit), count, file) != count) {
      throw std::runtime_error("truncated benchmark Trie image");
    }
  } else {
    if (std::fwrite(&count, sizeof(count), 1, file) != 1 ||
        std::fwrite(units.data(), sizeof(Unit), count, file) != count) {
      throw std::runtime_error("cannot write benchmark Trie image");
    }
  }
  size_t bytes = count * sizeof(Unit);
#if PAGED_ROOT
  bytes += sizeof(root_directory) + root_pages.size() * sizeof(Unit);
#endif
  return bytes;
}

extern "C" uint32_t trie_transition(uint32_t state, uint32_t token) {
  return step(state, token);
}

extern "C" uint32_t trie_value(uint32_t state) {
  return result(state);
}
#endif
extern "C" uint32_t trie_lookup_cp(const uint32_t *key, size_t size) {
  uint32_t state = 0;
  for (size_t i = 0; i < size; ++i) {
    state = step(state, key[i]);
    if (state == UINT32_MAX) {
      return state;
    }
  }
  return result(state);
}
#endif

/* Optional MARISA comparison for bench_binary.c; no production dependency. */
#include <marisa.h>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

static marisa::Trie trie;
static std::string image;
static std::vector<uint32_t> entries;
extern "C" size_t bench_marisa_build(const char **keys, const size_t *sizes, uint32_t count) {
  marisa::Keyset set;
  for (uint32_t i = 0; i < count; ++i) set.push_back(keys[i], sizes[i]);
  trie.build(set);
  entries.resize(count);
  for (uint32_t i = 0; i < count; ++i) entries[set[i].id()] = i;
  std::ostringstream stream;
  stream << trie;
  image = stream.str();
  trie.clear();
  trie.map(image.data(), image.size());
  return image.size() + entries.size() * sizeof(uint32_t);
}
extern "C" uint32_t bench_marisa_lookup(const char *key, size_t size) {
  marisa::Agent agent;
  agent.set_query(key, size);
  return trie.lookup(agent) ? entries[agent.key().id()] : UINT32_MAX;
}
extern "C" uint32_t bench_marisa_reuse(const char *key, size_t size) {
  static marisa::Agent agent;
  agent.set_query(key, size);
  return trie.lookup(agent) ? entries[agent.key().id()] : UINT32_MAX;
}

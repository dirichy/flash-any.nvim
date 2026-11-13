/* Build a codepoint DAT with a directly computed local modulus at each node.
 * Only packed eight-byte units survive construction. */
#include <stdlib.h>
#include "native.h"
#include "text.h"

typedef struct {
  uint32_t label, first, last, next, value, state, degree;
} Node;

typedef struct {
  uint32_t base, check, next, previous, quotient, kind;
} Slot;

typedef struct {
  uint32_t id, degree;
} Pending;

typedef struct {
  lua_State *L;
  Slot *slots;
  uint32_t capacity, head, tail, last;
  int owner;
} Packing;

static uint32_t token(Slice key, uint32_t *at) {
  uint32_t before = *at;
  int32_t cp = decode((const unsigned char *)key.data, key.size, at);
  return cp >= 0 ? (uint32_t)cp : 0x110000u + (unsigned char)key.data[before];
}

static int compare_keys(const void *left, const void *right) {
  const TrieKey *a = left, *b = right;
  uint32_t x = 0, y = 0;
  while (x < a->key.size && y < b->key.size) {
    uint32_t first = token(a->key, &x), second = token(b->key, &y);
    if (first != second) {
      return (first > second) - (first < second);
    }
  }
  return (x < a->key.size) - (y < b->key.size);
}

static void grow(Packing *packing, uint32_t needed) {
  uint64_t size = (uint64_t)packing->capacity * 2;
  if (size < needed) {
    size = needed;
  }
  if (size < 256) {
    size = 256;
  }
  if (needed > TRIE_MAX_UNITS) {
    luaL_error(packing->L, "binary Trie too large");
  }
  if (size > TRIE_MAX_UNITS) {
    size = TRIE_MAX_UNITS;
  }
  Slot *slots = lua_newuserdata(packing->L, (size_t)size * sizeof(Slot));
  uint32_t old = packing->capacity;
  if (old) {
    memcpy(slots, packing->slots, (size_t)old * sizeof(Slot));
  }
  memset(slots + old, 0, ((size_t)size - old) * sizeof(Slot));
  for (uint32_t i = old; i < size; ++i) {
    slots[i].next = i + 1 < size ? i + 1 : 0;
    slots[i].previous = i == old ? packing->tail : i - 1;
  }
  if (packing->tail) {
    slots[packing->tail].next = old;
  }
  if (!packing->head) {
    packing->head = old ? old : 1;
  }
  packing->tail = (uint32_t)size - 1;
  packing->capacity = (uint32_t)size;
  packing->slots = slots;
  lua_replace(packing->L, packing->owner);
}

static void occupy(Packing *packing, uint32_t at, uint32_t parent) {
  Slot *slots = packing->slots;
  if (slots[at].previous) {
    slots[slots[at].previous].next = slots[at].next;
  }
  if (slots[at].next) {
    slots[slots[at].next].previous = slots[at].previous;
  }
  if (packing->head == at) {
    packing->head = slots[at].next;
  }
  if (packing->tail == at) {
    packing->tail = slots[at].previous;
  }
  slots[at].check = parent + 1;
  if (at > packing->last) {
    packing->last = at;
  }
}

/* Wide nodes first improves packing. Heap entries contain only build-time data. */
static void enqueue(Pending *heap, uint32_t *count, uint32_t id, uint32_t degree) {
  uint32_t at = (*count)++;
  while (at && heap[(at - 1) / 2].degree < degree) {
    heap[at] = heap[(at - 1) / 2];
    at = (at - 1) / 2;
  }
  heap[at] = (Pending){id, degree};
}

static uint32_t dequeue(Pending *heap, uint32_t *count) {
  uint32_t id = heap[0].id, at = 0;
  Pending last = heap[--*count];
  while (at * 2 + 1 < *count) {
    uint32_t child = at * 2 + 1;
    if (child + 1 < *count && heap[child + 1].degree > heap[child].degree) {
      ++child;
    }
    if (heap[child].degree <= last.degree) {
      break;
    }
    heap[at] = heap[child];
    at = child;
  }
  heap[at] = last;
  return id;
}

/* Sort reversed labels: adjacent entries expose the longest shared low-bit
 * prefix. One pass derives the smallest collision-free power of two, without
 * trying different moduli or rebuilding the DAT. Include the terminal label 0. */
static uint32_t reverse_bits(uint32_t value) {
  value = ((value >> 1) & 0x55555555u) | ((value & 0x55555555u) << 1);
  value = ((value >> 2) & 0x33333333u) | ((value & 0x33333333u) << 2);
  value = ((value >> 4) & 0x0F0F0F0Fu) | ((value & 0x0F0F0F0Fu) << 4);
  value = ((value >> 8) & 0x00FF00FFu) | ((value & 0x00FF00FFu) << 8);
  return (value >> 16) | (value << 16);
}

static int compare_labels(const void *left, const void *right) {
  uint32_t a = *(const uint32_t *)left, b = *(const uint32_t *)right;
  return (a > b) - (a < b);
}

static unsigned node_bits(lua_State *L, const Node *nodes, const Node *node, uint32_t *labels) {
  uint32_t count = 0;
  if (node->value) {
    labels[count++] = 0;
  }
  for (uint32_t child = node->first; child; child = nodes[child].next) {
    labels[count++] = reverse_bits(nodes[child].label);
  }
  qsort(labels, count, sizeof(*labels), compare_labels);
  unsigned bits = TRIE_MIN_BITS;
  for (uint32_t i = 1; i < count; ++i) {
    uint32_t different = labels[i - 1] ^ labels[i];
    if (!different) {
      luaL_error(L, "duplicate binary Trie label");
    }
    unsigned shared = 0;
    for (uint32_t bit = 1u << 31; !(different & bit); bit >>= 1) {
      ++shared;
    }
    if (shared + 1 > bits) {
      bits = shared + 1;
    }
  }
  if (bits > TRIE_MAX_BITS) {
    luaL_error(L, "binary Trie label exceeds format limits");
  }
  return bits;
}

uint32_t *build_trie(lua_State *L, TrieKey *keys, uint32_t count, uint32_t *size) {
  *size = 0;
  if (!count) {
    return lua_newuserdata(L, 0);
  }
  qsort(keys, count, sizeof(*keys), compare_keys);
  uint64_t maximum = 1;
  uint32_t depth = 0;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t at = 0, points = 0;
    while (at < keys[i].key.size) {
      decode((const unsigned char *)keys[i].key.data, keys[i].key.size, &at);
      ++points;
    }
    maximum += points;
    if (points > depth) {
      depth = points;
    }
  }
  if (maximum > INT_MAX / sizeof(Node)) {
    return (luaL_error(L, "binary Trie too large"), NULL);
  }
  Node *nodes = lua_newuserdata(L, (size_t)maximum * sizeof(Node));
  memset(nodes, 0, sizeof(Node));
  uint32_t *path = lua_newuserdata(L, ((size_t)depth + 1) * sizeof(uint32_t));
  path[0] = 0;
  uint32_t used = 1, previous_depth = 0;
  for (uint32_t i = 0; i < count; ++i) {
    Slice key = keys[i].key;
    uint32_t at = 0, level = 0;
    int shared = 1;
    while (at < key.size) {
      uint32_t label = token(key, &at);
      shared = shared && level < previous_depth && nodes[path[level + 1]].label == label;
      if (!shared) {
        uint32_t child = used++, parent = path[level];
        nodes[child] = (Node){.label = label};
        if (nodes[parent].last) {
          nodes[nodes[parent].last].next = child;
        } else {
          nodes[parent].first = child;
        }
        nodes[parent].last = child;
        ++nodes[parent].degree;
        path[level + 1] = child;
      }
      ++level;
    }
    if (nodes[path[level]].value) {
      return (luaL_error(L, "duplicate binary text key"), NULL);
    }
    nodes[path[level]].value = keys[i].codes + 1;
    previous_depth = level;
  }
  uint32_t widest = 1;
  if ((uint64_t)used + count > TRIE_MAX_UNITS) {
    return (luaL_error(L, "binary Trie exceeds the 23-bit parent limit"), NULL);
  }
  for (uint32_t i = 0; i < used; ++i) {
    uint32_t degree = nodes[i].degree + (nodes[i].value != 0);
    if (degree > widest) {
      widest = degree;
    }
  }
  uint32_t *labels = lua_newuserdata(L, (size_t)widest * sizeof(uint32_t));
  Packing packing = {.L = L};
  lua_pushnil(L);
  packing.owner = lua_gettop(L);
  grow(&packing, 256);
  packing.slots[0].check = NONE;
  Pending *heap = lua_newuserdata(L, (size_t)used * sizeof(Pending));
  uint32_t pending = 0;
  enqueue(heap, &pending, 0, nodes[0].degree);
  while (pending) {
    Node *node = nodes + dequeue(heap, &pending);
    unsigned bits = node_bits(L, nodes, node, labels);
    uint32_t mask = (1u << bits) - 1;
    uint32_t minimum = node->value ? 0 : NONE, maximum_label = 0;
    for (uint32_t child = node->first; child; child = nodes[child].next) {
      uint32_t label = nodes[child].label & mask;
      if (label < minimum) {
        minimum = label;
      }
      if (label > maximum_label) {
        maximum_label = label;
      }
    }
    uint32_t anchor = packing.head ? packing.head : packing.capacity;
    for (;;) {
      if (anchor >= packing.capacity) {
        grow(&packing, anchor + 1);
      }
      while (packing.slots[anchor].check) {
        anchor = packing.slots[anchor].next ? packing.slots[anchor].next : packing.capacity;
        if (anchor >= packing.capacity) {
          grow(&packing, anchor + 1);
        }
      }
      uint64_t end = (uint64_t)anchor + maximum_label - minimum;
      if (end >= TRIE_MAX_UNITS) {
        return (luaL_error(L, "binary Trie too large"), NULL);
      }
      if (end >= packing.capacity) {
        grow(&packing, (uint32_t)end + 1);
      }
      int available = !node->value || !packing.slots[anchor].check;
      for (uint32_t child = node->first; available && child; child = nodes[child].next) {
        available = !packing.slots[anchor + (nodes[child].label & mask) - minimum].check;
      }
      if (available) {
        break;
      }
      anchor = packing.slots[anchor].next ? packing.slots[anchor].next : packing.capacity;
    }
    uint32_t base = anchor - minimum;
    packing.slots[node->state].base = base;
    packing.slots[node->state].kind = bits - TRIE_MIN_BITS;
    if (node->value) {
      occupy(&packing, anchor, node->state);
      packing.slots[anchor].base = node->value;
      packing.slots[anchor].kind = TRIE_TERMINAL;
    }
    for (uint32_t child = node->first; child; child = nodes[child].next) {
      uint32_t slot = anchor + (nodes[child].label & mask) - minimum;
      occupy(&packing, slot, node->state);
      packing.slots[slot].quotient = nodes[child].label >> bits;
      nodes[child].state = slot;
      enqueue(heap, &pending, child, nodes[child].degree + (nodes[child].value != 0));
    }
  }
  *size = packing.last + 1;
  uint32_t *units = lua_newuserdata(L, (size_t)*size * 8);
  for (uint32_t i = 0; i < *size; ++i) {
    const Slot *slot = packing.slots + i;
    uint64_t word = 0;
    if (!i || slot->check) {
      uint32_t parent = i ? slot->check : 0;
      word = (uint64_t)parent << 37 | (uint64_t)slot->kind << 60;
      word |= slot->kind == TRIE_TERMINAL
                  ? slot->base
                  : (slot->base & TRIE_BASE_MASK) | (uint64_t)slot->quotient << 24;
    }
    units[i * 2] = (uint32_t)word;
    units[i * 2 + 1] = (uint32_t)(word >> 32);
  }
  return units;
}

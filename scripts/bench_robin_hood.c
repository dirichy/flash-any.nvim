/* Standalone lookup experiment; does not change the runtime/binary format.
 * METHOD: 0 linear, 1 fingerprint, 2..4 RH packed 4/6/8 bits, 5 RH byte array. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef METHOD
#define METHOD 0
#endif
#define NONE UINT32_MAX
#define DISTANCE_BITS (METHOD == 2 ? 4 : METHOD == 3 ? 6 : METHOD == 4 ? 8 : 0)
#define DISTANCE_LIMIT (METHOD == 5 ? 255u : DISTANCE_BITS ? (1u << DISTANCE_BITS) - 1 : 0)

typedef struct {
  uint32_t offset, codes;
} Entry;

typedef struct {
  uint32_t offset, size, hash, expected;
} Query;

typedef struct {
  uint64_t probes, compares;
} Stats;

static Entry *entries;
static Query *queries[3];
static char *pool;
static uint32_t *slots, count, capacity, mask, fp_mask;
static uint8_t *distances;
static volatile uint64_t sink;

static void read_exact(void *p, size_t size, FILE *f) {
  if (fread(p, 1, size, f) != size) {
    fputs("truncated fixture\n", stderr);
    exit(2);
  }
}

/* Same per-codepoint FNV recurrence as the runtime; fixtures contain valid UTF-8. */
static uint32_t hash_key(const Query *q) {
  const unsigned char *p = (const unsigned char *)pool + q->offset;
  const unsigned char *end = p + q->size;
  uint32_t h = 2166136261u;
  while (p < end) {
    uint32_t cp = *p++;
    if (cp >= 0xc0) {
      unsigned more = cp < 0xe0 ? 1 : cp < 0xf0 ? 2 : 3;
      cp &= (1u << (6 - more)) - 1;
      while (more--) {
        cp = (cp << 6) | (*p++ & 63);
      }
    }
    h = (h ^ cp) * 16777619u;
  }
  return h;
}

static inline uint32_t tag(uint32_t hash) {
#if METHOD >= 2 && METHOD <= 4
  return (hash >> DISTANCE_BITS) & fp_mask;
#else
  return hash & fp_mask;
#endif
}

static inline uint32_t lookup(const Query *q, uint32_t h, Stats *stats) {
  uint32_t slot = h & mask;
#if METHOD >= 2
  uint32_t traveled = 0;
#endif
  for (;;) {
    uint32_t word = slots[slot];
    if (stats) {
      ++stats->probes;
    }
    if (!word) {
      return NONE;
    }
#if METHOD >= 2
#if METHOD == 5
    uint32_t distance = distances[slot];
#else
    uint32_t distance = word >> (32 - DISTANCE_BITS);
#endif
    /* All-ones is a saturated distance, not an exact value. Never stop on it. */
    if (distance < DISTANCE_LIMIT && distance < traveled) {
      return NONE;
    }
#endif
#if METHOD != 0
    if ((word & fp_mask) == tag(h))
#endif
    {
      uint32_t id = METHOD ? word & mask : word;
      const char *stored = pool + entries[id - 1].offset;
      if (stats) {
        ++stats->compares;
      }
      if (!strncmp(stored, pool + q->offset, q->size) && !stored[q->size]) {
        return id - 1;
      }
    }
    slot = (slot + 1) & mask;
#if METHOD >= 2
    ++traveled;
#endif
  }
}

static double seconds(void) {
  struct timespec t;
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

static double measure(Query *qs, unsigned rounds, int full) {
  uint64_t total = 0;
  double start = seconds();
  if (full) {
    for (unsigned r = 0; r < rounds; ++r) {
      for (uint32_t i = 0; i < count; ++i) {
        total += lookup(qs + i, hash_key(qs + i), NULL);
      }
    }
  } else {
    for (unsigned r = 0; r < rounds; ++r) {
      for (uint32_t i = 0; i < count; ++i) {
        total += lookup(qs + i, qs[i].hash, NULL);
      }
    }
  }
  double elapsed = seconds() - start;
  sink = total;
  return elapsed;
}

static int compare_double(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

int main(int argc, char **argv) {
  if (argc != 2) {
    return 2;
  }
  FILE *f = fopen(argv[1], "rb");
  if (!f) {
    return 2;
  }
  uint32_t header[3];
  read_exact(header, sizeof(header), f);
  count = header[0];
  capacity = header[1];
  mask = capacity - 1;
  if (!count || count >= capacity || (capacity & mask)) {
    return 2;
  }
  entries = calloc(count, sizeof(*entries));
  pool = malloc(header[2]);
  slots = calloc(capacity, sizeof(*slots));
  if (!entries || !pool || !slots) {
    return 2;
  }
  read_exact(entries, count * sizeof(*entries), f);
  read_exact(pool, header[2], f);
  for (unsigned j = 0; j < 3; ++j) {
    queries[j] = malloc(count * sizeof(Query));
    if (!queries[j]) {
      return 2;
    }
    read_exact(queries[j], count * sizeof(Query), f);
    for (uint32_t i = 0; i < count; ++i) {
      if (hash_key(queries[j] + i) != queries[j][i].hash) {
        return 3;
      }
    }
  }
  fclose(f);
  fp_mask = (UINT32_MAX >> DISTANCE_BITS) & ~mask;
  uint32_t *build_dist = calloc(capacity, sizeof(uint32_t));
  uint32_t *hashes = calloc(count, sizeof(uint32_t));
  if (!build_dist || !hashes) {
    return 2;
  }
  for (uint32_t i = 0; i < count; ++i) {
    Query *q = queries[0] + i;
    hashes[q->expected] = q->hash;
  }
  double build_start = seconds();
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t id = i + 1, at = hashes[i] & mask, distance = 0;
    while (slots[at]) {
#if METHOD >= 2
      if (build_dist[at] < distance) {
        uint32_t old = slots[at], old_distance = build_dist[at];
        slots[at] = id;
        build_dist[at] = distance;
        id = old;
        distance = old_distance;
      }
#endif
      at = (at + 1) & mask;
      ++distance;
    }
    slots[at] = id;
    build_dist[at] = distance;
  }
  uint32_t max_distance = 0, saturated = 0;
  if (METHOD == 5) {
    distances = calloc(capacity, 1);
  }
  if (METHOD == 5 && !distances) {
    return 2;
  }
  for (uint32_t at = 0; at < capacity; ++at) {
    if (!slots[at]) {
      continue;
    }
    if (build_dist[at] > max_distance) {
      max_distance = build_dist[at];
    }
#if METHOD >= 2
    uint32_t d = build_dist[at] < DISTANCE_LIMIT ? build_dist[at] : DISTANCE_LIMIT;
    if (build_dist[at] >= DISTANCE_LIMIT) {
      ++saturated;
    }
#endif
    slots[at] |= METHOD ? tag(hashes[slots[at] - 1]) : 0;
#if DISTANCE_BITS > 0
    slots[at] |= d << (32 - DISTANCE_BITS);
#endif
#if METHOD == 5
    distances[at] = (uint8_t)d;
#endif
  }
  double build_ms = (seconds() - build_start) * 1e3;
  free(build_dist);
  free(hashes);
  unsigned fp_bits = 0;
  for (uint32_t v = fp_mask; v; v >>= 1) {
    fp_bits += v & 1;
  }
  printf("{\"keys\":%u,\"capacity\":%u,\"bytes\":%llu,\"fp_bits\":%u,"
         "\"max_distance\":%u,\"saturated\":%u,\"build_ms\":%.4f,\"queries\":[",
         count, capacity, (unsigned long long)capacity * (METHOD == 5 ? 5 : 4),
         METHOD ? fp_bits : 0, max_distance, saturated, build_ms);
  for (unsigned j = 0; j < 3; ++j) {
    Stats sum = {0}, max = {0};
    for (uint32_t i = 0; i < count; ++i) {
      Stats one = {0};
      Query *q = queries[j] + i;
      uint32_t found = lookup(q, q->hash, &one);
      if (found != q->expected) {
        fprintf(stderr, "wrong result: set=%u query=%u got=%u expected=%u\n", j, i, found,
                q->expected);
        return 4;
      }
      sum.probes += one.probes;
      sum.compares += one.compares;
      if (one.probes > max.probes) {
        max.probes = one.probes;
      }
    }
    printf("%s{\"avg_probes\":%.6f,\"max_probes\":%llu,\"avg_compares\":%.6f,\"ns\":[",
           j ? "," : "", (double)sum.probes / count, (unsigned long long)max.probes,
           (double)sum.compares / count);
    for (int full = 0; full < 2; ++full) {
      unsigned rounds = 1;
      while (measure(queries[j], rounds, full) < 0.012 && rounds < 65536) {
        rounds *= 2;
      }
      double samples[3];
      for (unsigned s = 0; s < 3; ++s) {
        samples[s] = measure(queries[j], rounds, full) * 1e9 / rounds / count;
      }
      qsort(samples, 3, sizeof(double), compare_double);
      printf("%s%.4f", full ? "," : "", samples[1]);
    }
    printf("]}");
  }
  puts("]}");
  for (unsigned j = 0; j < 3; ++j) {
    free(queries[j]);
  }
  free(entries);
  free(pool);
  free(slots);
  free(distances);
  return 0;
}

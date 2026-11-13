#ifndef FLASH_ANY_TEXT_H
#define FLASH_ANY_TEXT_H

/* Sequential UTF-8 decoding and Unicode 17 grapheme boundaries.
 * Only the current boundary state is retained; no per-line index arrays.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>
#include "grapheme_data.h"

/* Must match the packed properties generated from scripts/data/grapheme_data.lua:
 * low 4 bits = GCB, bit 4 = Extended_Pictographic, bits 5–6 = InCB. */
enum {
  GCB_OTHER = 0,
  GCB_CR = 1,
  GCB_LF = 2,
  GCB_CONTROL = 3,
  GCB_EXTEND = 4,
  GCB_ZWJ = 5,
  GCB_RI = 6,
  GCB_PREPEND = 7,
  GCB_SPACING_MARK = 8,
  GCB_L = 9,
  GCB_V = 10,
  GCB_T = 11,
  GCB_LV = 12,
  GCB_LVT = 13,
  GCB_MASK = 0x0F,
  EXTENDED_PICTOGRAPHIC = 0x10,
  INCB_CONSONANT = 0x20,
  INCB_EXTEND = 0x40,
  INCB_LINKER = 0x60,
  INCB_MASK = 0x60,
};

enum { CONJUNCT_NONE, CONJUNCT_CONSONANT, CONJUNCT_LINKED };

static inline unsigned property(int32_t cp) {
  if (cp < 0) {
    return GCB_CONTROL;
  }
  if (cp < 128) {
    if (cp == 13) {
      return GCB_CR;
    }
    if (cp == 10) {
      return GCB_LF;
    }
    return (cp < 32 || cp == 127) ? GCB_CONTROL : GCB_OTHER;
  }
  if (cp >= 0xAC00 && cp <= 0xD7A3) {
    return (cp - 0xAC00) % 28 == 0 ? GCB_LV : GCB_LVT;
  }
  unsigned page = (unsigned)cp >> 8;
  unsigned lo = page_offsets[page], hi = page_offsets[page + 1], low = cp & 255;
  while (lo < hi) {
    unsigned mid = lo + (hi - lo) / 2;
    if (low < ranges[mid][0]) {
      hi = mid;
    } else if (low > ranges[mid][1]) {
      lo = mid + 1;
    } else {
      return ranges[mid][2];
    }
  }
  return GCB_OTHER;
}

/* Malformed UTF-8 consumes exactly one byte and returns -1. */
static inline int32_t decode(const unsigned char *s, uint32_t size, uint32_t *at) {
  uint32_t i = *at;
  unsigned a = s[i];
  *at = i + 1;
  if (a < 128) {
    return (int32_t)a;
  }
  if (a < 0xC2 || a > 0xF4 || i + 1 >= size) {
    return -1;
  }
  unsigned b = s[i + 1];
  if (b < 0x80 || b > 0xBF) {
    return -1;
  }
  if (a < 0xE0) {
    *at = i + 2;
    return (a - 0xC0) * 64 + b - 0x80;
  }
  if (i + 2 >= size) {
    return -1;
  }
  unsigned c = s[i + 2];
  if (c < 0x80 || c > 0xBF || (a == 0xE0 && b < 0xA0) || (a == 0xED && b >= 0xA0)) {
    return -1;
  }
  if (a < 0xF0) {
    *at = i + 3;
    return (a - 0xE0) * 4096 + (b - 0x80) * 64 + c - 0x80;
  }
  if (i + 3 >= size) {
    return -1;
  }
  unsigned d = s[i + 3];
  if (d < 0x80 || d > 0xBF || (a == 0xF0 && b < 0x90) || (a == 0xF4 && b >= 0x90)) {
    return -1;
  }
  *at = i + 4;
  return (a - 0xF0) * 262144 + (b - 0x80) * 4096 + (c - 0x80) * 64 + d - 0x80;
}

typedef struct {
  int previous;
  int regional_count;
  int pictographic_run; /* Extended_Pictographic followed only by Extend. */
  int zwj_after_pictographic;
  int conjunct; /* Consonant seen; linked means a Linker followed it. */
} GraphemeState;

/* Consume one scalar and report whether it begins a new grapheme. */
static inline int grapheme_break(GraphemeState *state, int32_t scalar) {
  unsigned prop = property(scalar);
  unsigned current = prop & GCB_MASK;
  unsigned incb = prop & INCB_MASK;
  int pictographic = (prop & EXTENDED_PICTOGRAPHIC) != 0;
  int boundary = 1;
  int previous = state->previous;

  /* UAX #29 rule order matters: controls break before Extend/ZWJ handling. */
  if (previous >= 0) {
    if (previous == GCB_CR && current == GCB_LF) {
      boundary = 0; /* GB3 */
    } else if ((previous >= GCB_CR && previous <= GCB_CONTROL) ||
               (current >= GCB_CR && current <= GCB_CONTROL)) {
      boundary = 1; /* GB4/5 */
    } else if (previous == GCB_L &&
               (current == GCB_L || current == GCB_V || current == GCB_LV || current == GCB_LVT)) {
      boundary = 0; /* GB6 */
    } else if ((previous == GCB_LV || previous == GCB_V) &&
               (current == GCB_V || current == GCB_T)) {
      boundary = 0; /* GB7 */
    } else if ((previous == GCB_LVT || previous == GCB_T) && current == GCB_T) {
      boundary = 0; /* GB8 */
    } else if (current == GCB_EXTEND || current == GCB_ZWJ || current == GCB_SPACING_MARK ||
               previous == GCB_PREPEND) {
      boundary = 0; /* GB9/9a/9b */
    } else if (state->conjunct == CONJUNCT_LINKED && incb == INCB_CONSONANT) {
      boundary = 0; /* GB9c: Indic consonant/linker chain. */
    } else if (previous == GCB_ZWJ && state->zwj_after_pictographic && pictographic) {
      boundary = 0; /* GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic. */
    } else if (previous == GCB_RI && current == GCB_RI && state->regional_count % 2 == 1) {
      boundary = 0; /* GB12/13: pair regional indicators from the start of the run. */
    }
    if (boundary) {
      state->regional_count = 0;
      state->pictographic_run = 0;
      state->conjunct = CONJUNCT_NONE;
    }
  }

  /* These summaries belong to the next boundary decision, after this scalar. */
  state->zwj_after_pictographic = current == GCB_ZWJ && state->pictographic_run;
  if (pictographic) {
    state->pictographic_run = 1;
  } else if (current != GCB_EXTEND) {
    state->pictographic_run = 0;
  }
  state->regional_count = current == GCB_RI ? state->regional_count + 1 : 0;
  if (incb == INCB_CONSONANT) {
    state->conjunct = CONJUNCT_CONSONANT;
  } else if (incb == INCB_LINKER && state->conjunct > CONJUNCT_NONE) {
    state->conjunct = CONJUNCT_LINKED;
  } else if (incb != INCB_EXTEND) {
    state->conjunct = CONJUNCT_NONE;
  }
  state->previous = (int)current;
  return boundary;
}

#endif

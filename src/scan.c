/* Text traversal: forward matching and build-time grapheme enumeration. */
#include "native.h"
#include "text.h"

/* CONSUMED carries a byte length; NEXT carries an ASCII key. PREVIEW carries
 * no continuation: it is the empty-next form, not a consumed-input result. */
typedef enum { EMIT_CONSUMED, EMIT_NEXT, EMIT_PREVIEW } EmitEvent;

typedef struct {
  const unsigned char *codes, *letter_codes;
  Slice glyph;
  const CodeGroups *groups;
  const char *input;
  uint32_t input_size, input_offset; /* Byte length and current input position. */
  uint32_t glyph_index;
  uint32_t glyph_after, glyph_end; /* Exclusive byte end and final scalar's start. */
  uint32_t text_size;
  uint32_t match_start;
  Match current; /* Independent of result storage, which may move when it grows. */
  Match *completed; /* Existing result receiving next-input bits, not a new match. */
  Requests *requests;
  int ascii, character, ignorecase, found;
  int complete;
} MatchContext;

static void request(Requests *requests, uint32_t glyph, uint32_t offset, uint32_t start) {
  uint32_t slot = glyph % requests->slots;
  uint32_t *starts = requests->starts + (size_t)slot * requests->width;
  /* Equal glyph/input positions have identical futures; retain the earliest start. */
  if (starts[offset] == NONE) {
    requests->offsets[(size_t)slot * requests->width + requests->counts[slot]++] = offset;
    starts[offset] = start;
  } else if (start < starts[offset]) {
    starts[offset] = start;
  }
}

static unsigned lower_ascii(unsigned key) {
  return key >= 'A' && key <= 'Z' ? key + ('a' - 'A') : key;
}

static int same_key(int ignorecase, unsigned left, unsigned right) {
  return left == right || (ignorecase && lower_ascii(left) == lower_ascii(right));
}

static void emit(MatchContext *context, EmitEvent event, uint32_t value) {
  if (context->character) {
    context->found = 1;
    return;
  }
  /* A completed input still examines the next glyph to reserve label keys. */
  if (context->completed) {
    if (event == EMIT_NEXT) {
      context->completed->next[value >> 6] |= (uint64_t)1 << (value & 63);
    }
    return;
  }
  uint32_t end_glyph = context->glyph_index;
  uint32_t after = context->glyph_after;
  int complete = event == EMIT_CONSUMED && value == context->input_size - context->input_offset;
  if (event != EMIT_CONSUMED || complete) {
    Match *match = &context->current;
    if (!match->valid) {
      match->valid = 1;
      match->start = context->match_start;
      match->end = context->glyph_end;
    } else if (context->match_start < match->start) {
      match->start = context->match_start;
    }
    if (event == EMIT_NEXT) {
      match->next[value >> 6] |= (uint64_t)1 << (value & 63);
    }
    /* Defer next-glyph label exclusions until that glyph is decoded. */
    if (complete && after < context->text_size) {
      context->complete = 1;
    }
  } else if (after < context->text_size) {
    request(context->requests, end_glyph + 1, context->input_offset + value, context->match_start);
  }
}

/* Case-insensitive rules reserve both spellings; exact codes reserve only their own. */
static void emit_key(MatchContext *context, unsigned key, int ignorecase) {
  emit(context, EMIT_NEXT, key);
  unsigned lower = lower_ascii(key);
  if (ignorecase && lower >= 'a' && lower <= 'z') {
    emit(context, EMIT_NEXT, key ^ ('a' - 'A'));
  }
}

/* A shorter query previews the whole glyph without consuming its remaining suffix. */
static void match_literal(MatchContext *context) {
  Slice glyph = context->glyph;
  uint32_t size = context->input_size - context->input_offset;
  if (!size) {
    if (context->completed) {
      context->completed->literal_start = context->glyph_after - glyph.size;
      context->completed->literal_size = glyph.size;
    }
    return;
  }
  uint32_t common = size < glyph.size ? size : glyph.size;
  if (context->input[context->input_offset] != glyph.data[0] ||
      memcmp(context->input + context->input_offset, glyph.data, common)) {
    return;
  }
  emit(context, size < glyph.size ? EMIT_PREVIEW : EMIT_CONSUMED, glyph.size);
}

/* All spellings share these semantics, whether inline or read through a group ID. */
typedef struct {
  uint32_t longest_prefix; /* All shorter positive lengths are valid consumption branches. */
  int has_initial;
} SpellingMatches;

static uint32_t match_spelling(MatchContext *context, unsigned mode, const unsigned char *code,
                               uint32_t length, SpellingMatches *matches) {
  uint32_t size = context->input_size - context->input_offset, common = 0;
  while (common < size && common < length &&
         same_key(context->ignorecase && mode == MATCH_LETTER, code[common],
                  (unsigned char)context->input[context->input_offset + common])) {
    ++common;
  }
  if (length > size && common == size) {
    emit_key(context, code[size], context->ignorecase && mode == MATCH_LETTER);
  }
  if (common == length && (mode == MATCH_FULL || mode == MATCH_SUFFIX || mode == MATCH_LETTER ||
                           (mode == MATCH_INITIAL && length > 1))) {
    emit(context, EMIT_CONSUMED, length);
  }
  if (mode == MATCH_INITIAL && common) {
    matches->has_initial = 1;
  }
  if (mode == MATCH_PREFIX && common > matches->longest_prefix) {
    matches->longest_prefix = common;
  }
  return common;
}

static void match_group(MatchContext *context, unsigned mode, unsigned id,
                        SpellingMatches *matches) {
  const CodeGroup *group = &context->groups->groups[id];
  uint32_t size = context->input_size - context->input_offset;
  if (group->first_byte < 128) {
    if (!size) {
      emit_key(context, group->first_byte, context->ignorecase && mode == MATCH_LETTER);
      return;
    }
    if (!same_key(context->ignorecase && mode == MATCH_LETTER,
                  (unsigned char)context->input[context->input_offset], group->first_byte)) {
      return;
    }
  }
  /* Keep matches from every spelling; a shorter branch may match the next glyph. */
  for (const unsigned char *p = group->begin; p < group->end;) {
    unsigned length = *p++;
    match_spelling(context, mode, p, length, matches);
    p += length;
  }
}

static void match_code_list(MatchContext *context, const unsigned char *codes, int letter_only) {
  if (!codes) {
    return;
  }
  const unsigned char *p = codes;
  uint32_t size = context->input_size - context->input_offset;
  SpellingMatches matches = {0};
  while (*p) {
    unsigned mode = *p++ - MATCHER_TAG;
    if (mode & GROUP_FLAG) {
      if (!letter_only || (mode & ~GROUP_FLAG) == MATCH_LETTER) {
        match_group(context, mode & ~GROUP_FLAG, read_u16(p), &matches);
      }
      p += 2;
      continue;
    }
    unsigned suffix_size = 0;
    const unsigned char *suffix = NULL;
    if (mode == MATCH_SUFFIX) {
      suffix_size = *p++;
      suffix = p;
      p += suffix_size;
    }
    const unsigned char *code = p;
    while (*p && *p < 128) {
      ++p;
    }
    uint32_t length = (uint32_t)(p - code);
    if (letter_only && mode != MATCH_LETTER) {
      continue;
    }
    if (mode == MATCH_LITERAL) {
      if (!size) {
        emit_key(context, code[0], context->ignorecase);
      } else if (same_key(context->ignorecase, (unsigned char)context->input[context->input_offset],
                          code[0])) {
        emit(context, EMIT_CONSUMED, 1);
      }
      continue;
    }
    uint32_t common = match_spelling(context, mode, code, length, &matches);
    if (mode == MATCH_SUFFIX && common == length) {
      uint32_t tail = 0, available = size - length;
      while (tail < available && tail < suffix_size &&
             suffix[tail] == (unsigned char)context->input[context->input_offset + length + tail]) {
        ++tail;
      }
      /* Omitting the suffix stays valid even when following text consumes the same keys. */
      if (tail == suffix_size) {
        emit(context, EMIT_CONSUMED, length + tail);
      } else if (tail == available) {
        emit(context, EMIT_NEXT, suffix[tail]);
      }
    }
  }
  /* Emit shared initial/prefix lengths once, even when several spellings agree. */
  if (matches.has_initial) {
    emit(context, EMIT_CONSUMED, 1);
  }
  for (uint32_t bytes = 1; bytes <= matches.longest_prefix; ++bytes) {
    emit(context, EMIT_CONSUMED, bytes);
  }
}

static void match_codes(MatchContext *context) {
  /* ASCII literal rules already live in the dictionary; other glyphs compare their text. */
  if (!context->ascii) {
    match_literal(context);
  }
  match_code_list(context, context->codes, 0);
  if (context->letter_codes) {
    /* A scalar hit never grants literal or ordinary code rules permission to skip a suffix. */
    match_code_list(context, context->letter_codes, 1);
  }
}

/* Grow only when a grapheme actually matches. Pointers are refreshed after
 * growth; the userdata at result_index owns the full result throughout scan(). */
static Result *append_match(lua_State *L, int result_index, Result *result, Match *match) {
  if (result->count == result->capacity) {
    uint32_t maximum = (INT_MAX - sizeof(Result)) / sizeof(Match);
    if (result->count == maximum) {
      luaL_error(L, "native result too large");
    }
    uint32_t capacity =
        result->capacity ? (result->capacity > maximum / 2 ? maximum : result->capacity * 2) : 64;
    Result *next = (Result *)lua_newuserdata(L, sizeof(Result) + (size_t)capacity * sizeof(Match));
    next->count = result->count;
    next->capacity = capacity;
    memcpy(next + 1, result + 1, (size_t)result->count * sizeof(Match));
    lua_replace(L, result_index);
    result = next;
  }
  ((Match *)(result + 1))[result->count++] = *match;
  return result;
}

typedef struct {
  uint32_t node;
  uint32_t glyph, col, before, after;
  int recognized;
} ActivePrefix;

/* Match a terminal against the input states saved at that text prefix's start.
 * Each result is still merged by its ending grapheme, as in single-glyph scans. */
static void match_phrase(MatchContext *context, Result *result, uint32_t origin,
                         const unsigned char *codes, int single) {
  Requests *requests = context->requests;
  uint32_t slot = origin % requests->slots;
  if (requests->lookahead[slot]) {
    context->completed = (Match *)(result + 1) + requests->lookahead[slot] - 1;
    context->input_offset = context->input_size;
    if (single) {
      match_codes(context);
    } else {
      match_code_list(context, codes, 0);
    }
    context->completed = NULL;
  }
  uint32_t *starts = requests->starts + (size_t)slot * requests->width;
  uint32_t *offsets = requests->offsets + (size_t)slot * requests->width;
  for (uint32_t i = 0; i < requests->counts[slot]; ++i) {
    context->input_offset = offsets[i];
    context->match_start = starts[context->input_offset];
    if (single) {
      match_codes(context);
    } else {
      match_code_list(context, codes, 0);
    }
  }
}

Result *scan_line(lua_State *L, int result_index, Result *result, Engine *instance, Slice text,
                  const char *input, uint32_t size, uint32_t row, Requests *requests, int character,
                  int ignorecase) {
  /* At most one live prefix per grapheme start; no key is longer than this many
   * codepoints. The extra request slot retains all live starts plus the successor. */
  if (instance->depth > (INT_MAX / sizeof(ActivePrefix)) - 1) {
    luaL_error(L, "native phrase workspace too large");
  }
  ActivePrefix *active = lua_newuserdata(L, ((size_t)instance->depth + 1) * sizeof(*active));
  if (!character) {
    memset(requests->starts, 255, (size_t)requests->slots * requests->width * sizeof(uint32_t));
    memset(requests->counts, 0, (size_t)requests->slots * sizeof(uint32_t));
    memset(requests->lookahead, 0, (size_t)requests->slots * sizeof(uint32_t));
  }
  MatchContext context = {0};
  context.groups = instance->groups;
  context.input = input;
  context.input_size = size;
  context.text_size = text.size;
  context.requests = requests;
  context.character = character;
  context.ignorecase = ignorecase;
  GraphemeState state = {.previous = -1};
  uint32_t at = 0, start = 0, before = NONE, last = 0, glyph = 0, count = 0, nactive = 0;
  int32_t first = -1;
  while (1) {
    uint32_t col = at;
    int32_t scalar =
        col < text.size ? decode((const unsigned char *)text.data, text.size, &at) : -1;
    int boundary = col == text.size || grapheme_break(&state, scalar);
    if (boundary && count) {
      context.glyph = (Slice){text.data + start, col - start};
      context.glyph_index = glyph;
      context.glyph_after = col;
      context.glyph_end = last;
      context.ascii = count == 1 && first >= 0 && first < 128;
      context.codes =
          count == 1 && first >= 0 ? scalar_codes(&instance->table, (uint32_t)first) : NULL;
      context.letter_codes = instance->letters && count > 1 && first >= 0
                                 ? scalar_codes(&instance->table, (uint32_t)first)
                                 : NULL;
      for (uint32_t i = 0; i < nactive; ++i) {
        ActivePrefix *p = active + i;
        if (p->glyph == glyph) {
          p->after = col;
          const unsigned char *codes = trie_codes(&instance->table, p->node);
          if (codes) {
            context.codes = codes;
          }
        }
      }
      memset(&context.current, 0, sizeof(context.current));
      context.complete = 0;
      if (!character) {
        uint32_t next_slot = (glyph + 1) % requests->slots;
        memset(requests->starts + (size_t)next_slot * requests->width, 255,
               (size_t)requests->width * sizeof(uint32_t));
        requests->counts[next_slot] = requests->lookahead[next_slot] = 0;
        request(requests, glyph, 0, start);
        match_phrase(&context, result, glyph, context.codes, 1);
      } else {
        context.input_offset = 0;
        context.found = 0;
        match_codes(&context);
        if (context.found) {
          Match match = {.row = row,
                         .start = start,
                         .end = start,
                         .before = before,
                         .after = col < text.size ? col : NONE,
                         .valid = 1};
          result = append_match(L, result_index, result, &match);
          for (uint32_t i = 0; i < nactive; ++i) {
            if (active[i].glyph == glyph) {
              active[i].recognized = 1;
            }
          }
        }
      }
      for (uint32_t i = 0; i < nactive; ++i) {
        ActivePrefix *p = active + i;
        if (p->glyph == glyph) {
          continue;
        }
        const unsigned char *codes = trie_codes(&instance->table, p->node);
        if (!codes) {
          continue;
        }
        if (!character) {
          match_phrase(&context, result, p->glyph, codes, 0);
        } else if (!p->recognized) {
          context.input_offset = 0;
          context.found = 0;
          match_code_list(&context, codes, 0);
          if (context.found) {
            Match match = {.row = row,
                           .start = p->col,
                           .end = p->col,
                           .before = p->before,
                           .after = p->after < text.size ? p->after : NONE,
                           .valid = 1};
            result = append_match(L, result_index, result, &match);
            p->recognized = 1;
          }
        }
      }
      if (!character && context.current.valid) {
        context.current.row = row;
        result = append_match(L, result_index, result, &context.current);
        if (context.complete && col < text.size) {
          requests->lookahead[(glyph + 1) % requests->slots] = result->count;
        }
      }
      ++glyph;
      before = start;
      count = 0;
    }
    if (col == text.size) {
      break;
    }
    if (!count) {
      start = col;
      first = scalar;
      active[nactive++] = (ActivePrefix){.node = 0, .glyph = glyph, .col = col, .before = before};
    }
    uint32_t remaining = 0;
    uint32_t value = scalar >= 0 ? (uint32_t)scalar : 0x110000u + (unsigned char)text.data[col];
    for (uint32_t i = 0; i < nactive; ++i) {
      ActivePrefix p = active[i];
      p.node = trie_step(&instance->table, p.node, value);
      if (p.node != NONE) {
        active[remaining++] = p;
      }
    }
    nactive = remaining;
    last = col;
    ++count;
  }
  lua_pop(L, 1);
  return result;
}

/* Build-time enumeration uses the same decoder/boundary state as scan_line.
 * The two closures differ only in whether boundaries are emitted or counted. */
int graphemes(lua_State *L) {
  luaL_checktype(L, 1, LUA_TSTRING);
  size_t size;
  const unsigned char *text = (const unsigned char *)lua_tolstring(L, 1, &size);
  if (size >= INT_MAX) {
    return luaL_error(L, "text too large");
  }
  int each = lua_toboolean(L, lua_upvalueindex(1));
  int codepoints = each && !lua_isnoneornil(L, 3);
  if (each) {
    luaL_checktype(L, 2, LUA_TFUNCTION);
    if (codepoints) {
      luaL_checktype(L, 3, LUA_TFUNCTION);
    }
  }
  GraphemeState state = {.previous = -1};
  uint32_t at = 0, start = 0, last = 0, count = 0, clusters = 0;
  while (1) {
    uint32_t col = at;
    int32_t scalar = col < size ? decode(text, (uint32_t)size, &at) : -1;
    if (codepoints && col < size) {
      lua_pushvalue(L, 3);
      lua_pushinteger(L, scalar);
      lua_pushinteger(L, at);
      lua_call(L, 2, 0);
    }
    if ((col == size || grapheme_break(&state, scalar)) && count) {
      ++clusters;
      if (each) {
        lua_pushvalue(L, 2);
        lua_pushinteger(L, start);
        lua_pushinteger(L, col);
        lua_pushinteger(L, count);
        lua_pushinteger(L, last);
        lua_call(L, 4, 0);
      }
      count = 0;
    }
    if (col == size) {
      break;
    }
    if (!count) {
      start = col;
    }
    last = col;
    ++count;
  }
  if (each) {
    return 0;
  }
  lua_pushinteger(L, clusters);
  return 1;
}

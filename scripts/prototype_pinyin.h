/* Experiment only: included by a patched copy of native.c, never by the plugin build. */
enum { PY_LETTERS = 26, PY_SKIP = 0xA0 };

typedef struct {
  uint32_t child[PY_LETTERS], terminal;
} PinyinNode;

typedef struct {
  uint32_t syllable, next;
} PinyinTerminal;

typedef struct {
  const unsigned char *data;
  uint32_t size;
} PinyinForm;

struct PinyinData {
  uint32_t count, nodes_used, terminals_used, ondemand, mode;
  PinyinForm *forms;
  PinyinNode *nodes;
  PinyinTerminal *terminals;
  uint32_t *first, *form_offsets;
};

struct PinyinMatch {
  uint32_t lengths, next;
};

static unsigned pinyin_u16(const unsigned char *s) {
  return s[0] | s[1] << 8;
}

static void pinyin_put_u16(luaL_Buffer *b, unsigned n) {
  luaL_addchar(b, n & 255);
  luaL_addchar(b, n >> 8);
}

/* C owns this experimental profile format as well as the dictionary format. */
static int pinyin_pack(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t count = lua_objlen(L, 1);
  if (!count || count > 16384) {
    return luaL_error(L, "invalid syllable count");
  }
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  pinyin_put_u16(&b, (unsigned)count);
  for (size_t i = 1; i <= count; ++i) {
    lua_rawgeti(L, 1, (int)i);
    luaL_checktype(L, -1, LUA_TTABLE);
    size_t n = lua_objlen(L, -1);
    lua_pop(L, 1);
    if (n > 65535) {
      return luaL_error(L, "too many spellings");
    }
    pinyin_put_u16(&b, (unsigned)n);
    for (size_t j = 1; j <= n; ++j) {
      lua_rawgeti(L, 1, (int)i);
      lua_rawgeti(L, -1, (int)j);
      size_t size;
      const char *s = luaL_checklstring(L, -1, &size);
      if (!size || size > 31) {
        return luaL_error(L, "invalid spelling length");
      }
      for (size_t k = 0; k < size; ++k) {
        if (s[k] < 'a' || s[k] > 'z') {
          return luaL_error(L, "prototype expects a-z spellings");
        }
      }
      lua_pop(L, 2);
      luaL_addchar(&b, size);
      luaL_addlstring(&b, s, size);
    }
  }
  luaL_pushresult(&b);
  return 1;
}

/* Both strategies share the same spellings; only precomputation needs a trie. */
static int pinyin_attach(lua_State *L) {
  Engine *instance = engine(L);
  size_t size;
  const unsigned char *blob = (const unsigned char *)luaL_checklstring(L, 2, &size);
  if (size < 2) {
    return luaL_error(L, "truncated syllable profile");
  }
  unsigned count = pinyin_u16(blob);
  if (!count || count > 16384) {
    return luaL_error(L, "invalid syllable profile");
  }
  size_t at = 2, nodes = 1, terminals = 1;
  for (unsigned id = 0; id < count; ++id) {
    if (at + 2 > size) {
      return luaL_error(L, "truncated syllable row");
    }
    unsigned n = pinyin_u16(blob + at);
    at += 2;
    terminals += n;
    for (unsigned j = 0; j < n; ++j) {
      if (at == size) {
        return luaL_error(L, "truncated spelling");
      }
      unsigned length = blob[at++];
      if (!length || length > 31 || at + length > size) {
        return luaL_error(L, "invalid spelling");
      }
      for (unsigned k = 0; k < length; ++k) {
        if (blob[at + k] < 'a' || blob[at + k] > 'z') {
          return luaL_error(L, "invalid spelling byte");
        }
      }
      at += length;
      nodes += length;
    }
  }
  if (at != size || nodes > UINT32_MAX || terminals > UINT32_MAX) {
    return luaL_error(L, "invalid syllable profile size");
  }
  int ondemand = lua_toboolean(L, 3);
  int mode = luaL_optint(L, 4, MATCH_INITIAL);
  if (mode != MATCH_FULL && mode != MATCH_INITIAL && mode != MATCH_PREFIX) {
    return luaL_error(L, "invalid pinyin matching mode");
  }
  size_t trie_nodes = ondemand ? 0 : nodes;
  size_t trie_terminals = ondemand ? 0 : (mode == MATCH_INITIAL ? terminals * 2 : terminals);
  size_t memory = sizeof(PinyinData) + terminals * sizeof(PinyinForm) +
                  trie_nodes * sizeof(PinyinNode) + trie_terminals * sizeof(PinyinTerminal) +
                  (2 * count + 1) * sizeof(uint32_t) + size;
  PinyinData *p = (PinyinData *)lua_newuserdata(L, memory);
  memset(p, 0, memory);
  p->count = count;
  p->ondemand = ondemand;
  p->mode = mode;
  p->nodes_used = 1;
  p->terminals_used = 1;
  p->forms = (PinyinForm *)(p + 1);
  p->nodes = (PinyinNode *)(p->forms + terminals);
  p->terminals = (PinyinTerminal *)(p->nodes + trie_nodes);
  p->first = (uint32_t *)(p->terminals + trie_terminals);
  p->form_offsets = p->first + count;
  unsigned char *copy = (unsigned char *)(p->form_offsets + count + 1);
  memcpy(copy, blob, size);
  blob = copy;
  unsigned forms_used = 0;
  at = 2;
  for (unsigned id = 0; id < count; ++id) {
    unsigned n = pinyin_u16(blob + at);
    at += 2;
    p->form_offsets[id] = forms_used;
    for (unsigned j = 0; j < n; ++j) {
      unsigned length = blob[at++], node = 0;
      p->forms[forms_used++] = (PinyinForm){blob + at, length};
      unsigned first = blob[at] - 'a';
      int initial = mode == MATCH_INITIAL && length > 1 && !(p->first[id] & (UINT32_C(1) << first));
      p->first[id] |= UINT32_C(1) << first;
      if (ondemand) {
        at += length;
        continue;
      }
      for (unsigned k = 0; k < length; ++k) {
        unsigned letter = blob[at++] - 'a';
        if (!p->nodes[node].child[letter]) {
          p->nodes[node].child[letter] = p->nodes_used++;
        }
        node = p->nodes[node].child[letter];
        if (initial && !k) {
          unsigned entry = p->terminals_used++;
          p->terminals[entry] = (PinyinTerminal){id, p->nodes[node].terminal};
          p->nodes[node].terminal = entry;
        }
      }
      unsigned entry = p->terminals_used++;
      p->terminals[entry] = (PinyinTerminal){id, p->nodes[node].terminal};
      p->nodes[node].terminal = entry;
    }
  }
  p->form_offsets[count] = forms_used;
  instance->pinyin = p;
  lua_getfenv(L, 1);
  lua_pushvalue(L, -2);
  lua_setfield(L, -2, "pinyin");
  lua_pushinteger(L, (lua_Integer)memory);
  return 1;
}

static void pinyin_pending(PinyinData *p, unsigned node, uint32_t next, uint32_t lengths,
                           PinyinMatch *row) {
  for (unsigned t = p->nodes[node].terminal; t; t = p->terminals[t].next) {
    row[p->terminals[t].syllable].next |= next;
    row[p->terminals[t].syllable].lengths |= lengths;
  }
  for (unsigned i = 0; i < PY_LETTERS; ++i) {
    if (p->nodes[node].child[i]) {
      pinyin_pending(p, p->nodes[node].child[i], next, lengths, row);
    }
  }
}

/* One graph per input, shared across every text line and every occurrence of a syllable. */
static PinyinMatch *pinyin_query(lua_State *L, PinyinData *p, const char *input, uint32_t size) {
  if (!p || p->ondemand) {
    return NULL;
  }
  size_t cells = ((size_t)size + 1) * p->count;
  if (cells > INT_MAX / sizeof(PinyinMatch)) {
    luaL_error(L, "pinyin graph too large");
  }
  PinyinMatch *graph = (PinyinMatch *)lua_newuserdata(L, cells * sizeof(PinyinMatch));
  memset(graph, 0, cells * sizeof(PinyinMatch));
  for (uint32_t offset = 0; offset < size; ++offset) {
    PinyinMatch *row = graph + (size_t)offset * p->count;
    unsigned node = 0;
    uint32_t end = offset;
    while (end < size && end - offset < 31) {
      unsigned letter = (unsigned char)input[end] - 'a';
      if (letter >= PY_LETTERS || !p->nodes[node].child[letter]) {
        break;
      }
      node = p->nodes[node].child[letter];
      ++end;
      if (p->mode == MATCH_PREFIX) {
        pinyin_pending(p, node, 0, UINT32_C(1) << (end - offset), row);
      }
      for (unsigned t = p->nodes[node].terminal; t; t = p->terminals[t].next) {
        row[p->terminals[t].syllable].lengths |= UINT32_C(1) << (end - offset);
      }
      if (end == size) {
        for (unsigned i = 0; i < PY_LETTERS; ++i) {
          if (p->nodes[node].child[i]) {
            pinyin_pending(p, p->nodes[node].child[i], UINT32_C(1) << i, 0, row);
          }
        }
      }
    }
  }
  for (unsigned id = 0; id < p->count; ++id) {
    graph[(size_t)size * p->count + id].next = p->first[id];
  }
  return graph;
}

/* Direct matcher: evaluate only this syllable at this stream position. */
static PinyinMatch pinyin_at(PinyinData *p, unsigned id, const char *input, uint32_t size) {
  PinyinMatch result = {0};
  if (!size) {
    result.next = p->first[id];
    return result;
  }
  unsigned letter = (unsigned char)input[0] - 'a';
  if (letter >= PY_LETTERS || !(p->first[id] & (UINT32_C(1) << letter))) {
    return result;
  }
  for (unsigned i = p->form_offsets[id]; i < p->form_offsets[id + 1]; ++i) {
    PinyinForm form = p->forms[i];
    uint32_t common = 0;
    while (common < size && common < form.size &&
           form.data[common] == (unsigned char)input[common]) {
      ++common;
    }
    if (common == size && common < form.size) {
      result.next |= UINT32_C(1) << (form.data[common] - 'a');
    }
    if (p->mode == MATCH_PREFIX) {
      result.lengths |= ((UINT32_C(1) << common) - 1) << 1;
    } else {
      if (common == form.size) {
        result.lengths |= UINT32_C(1) << common;
      }
      if (p->mode == MATCH_INITIAL && common) {
        result.lengths |= 2;
      }
    }
  }
  return result;
}

static void pinyin_match(MatchContext *context, unsigned id) {
  PinyinData *p = context->syllables;
  if (!p || id >= p->count) {
    return;
  }
  PinyinMatch direct;
  const PinyinMatch *m;
  if (p->ondemand) {
    direct = pinyin_at(p, id, context->input + context->input_offset,
                       context->input_size - context->input_offset);
    m = &direct;
  } else {
    m = context->pinyin + (size_t)context->input_offset * context->nsyllables + id;
  }
  for (uint32_t bits = m->lengths; bits; bits &= bits - 1) {
    emit(context, EMIT_CONSUMED, (uint32_t)__builtin_ctz(bits));
  }
  for (uint32_t bits = m->next; bits; bits &= bits - 1) {
    emit(context, EMIT_NEXT, 'a' + (uint32_t)__builtin_ctz(bits));
  }
}

/* Tiny NFA for one optional ASCII byte: 0xA0 followed by that byte.
 * The prototype uses initial matching, exactly like the current full-pinyin source. */
static uint64_t pinyin_skip_close(const unsigned char *code, uint32_t size, uint64_t states) {
  for (uint32_t i = 0; i < size; ++i) {
    if ((states & (UINT64_C(1) << i)) && code[i] == PY_SKIP) {
      states |= UINT64_C(1) << (i + 2);
    }
  }
  return states;
}

static void pinyin_skip_match(MatchContext *context, const unsigned char *code, uint32_t size) {
  uint32_t available = context->input_size - context->input_offset;
  const unsigned char *input = (const unsigned char *)context->input + context->input_offset;
  if (size > 62) {
    return;
  }
  if (available && input[0] == code[0]) {
    emit(context, EMIT_CONSUMED, 1);
  }
  uint64_t states = pinyin_skip_close(code, size, 1);
  for (uint32_t consumed = 0; states; ++consumed) {
    if (consumed && (states & (UINT64_C(1) << size))) {
      emit(context, EMIT_CONSUMED, consumed);
    }
    uint64_t next = 0;
    for (uint32_t i = 0; i < size; ++i) {
      if (!(states & (UINT64_C(1) << i))) {
        continue;
      }
      unsigned step = code[i] == PY_SKIP ? 2 : 1;
      unsigned key = code[i + step - 1];
      if (consumed == available) {
        emit(context, EMIT_NEXT, key);
      } else if (input[consumed] == key) {
        next |= UINT64_C(1) << (i + step);
      }
    }
    if (consumed == available) {
      break;
    }
    states = pinyin_skip_close(code, size, next);
  }
}

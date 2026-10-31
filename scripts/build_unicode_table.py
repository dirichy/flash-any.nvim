#!/usr/bin/env python3
"""Build short aliases from UnicodeData.txt into common Lua and full TSV."""
from __future__ import annotations
import argparse, re
from pathlib import Path

STOP = {
    'latin','greek','coptic','cyrillic','armenian','hebrew','arabic','syriac',
    'thaana','devanagari','bengali','gurmukhi','gujarati','oriya','tamil',
    'telugu','kannada','malayalam','thai','lao','tibetan','myanmar','georgian',
    'hangul','hiragana','katakana','bopomofo','han','yi','ethiopic',
    'capital','small','letter','character','sign','symbol','mark','modifier',
    'with','and','above','below','side','form','variant','type',
}
COMMON_RANGES = ((0x00A0,0x024F),(0x0370,0x052F),(0x0590,0x06FF),(0x0900,0x097F),
                 (0x1100,0x11FF),(0x2000,0x24FF),(0x3040,0x30FF))

def aliases(name: str, cp: int) -> list[str]:
    tokens = re.findall(r'[a-z0-9]+', name.lower())
    semantic = [t for t in tokens if t not in STOP]
    if not semantic: return []
    out=[]
    def add(s):
        if 1 < len(s) <= 24 and s not in out: out.append(s)
    add(''.join(semantic))
    if len(semantic) > 1: add(''.join(semantic[-2:]))
    add(semantic[-1])
    if len(semantic) > 1: add(''.join(x[0] for x in semantic))
    return out[:5]

def read(path):
    rows={}
    for line in path.read_text(encoding='ascii').splitlines():
        f=line.split(';')
        if len(f)<2 or f[1].startswith('<'): continue
        cp=int(f[0],16); char=chr(cp)
        if cp < 0xA0 or char in "\t\r\n\u2028\u2029": continue
        codes=aliases(f[1],cp)
        if codes: rows[char]=codes
    return rows

def lua_quote(value):
    return '"' + value.replace('\\', '\\\\').replace('\"', '\\"') + '"'

def write_lua(path, rows):
    with path.open('w',encoding='utf8') as out:
        out.write('return {\n')
        for c in sorted(rows,key=lambda x:x.encode()):
            out.write('  [%s] = {%s},\n' % (lua_quote(c), ', '.join(lua_quote(x) for x in rows[c])))
        out.write('}\n')

def write_tsv(path, rows):
    with path.open('w',encoding='utf8') as out:
        for c in sorted(rows,key=lambda x:x.encode()): out.write(c+'\t'+','.join(rows[c])+'\n')

def main():
    p=argparse.ArgumentParser(); p.add_argument('source',type=Path); p.add_argument('lua',type=Path); p.add_argument('tsv',type=Path); p.add_argument('--common-limit',type=int,default=0); a=p.parse_args()
    rows=read(a.source); common={c:v for c,v in rows.items() if any(lo<=ord(c)<=hi for lo,hi in COMMON_RANGES)}
    if a.common_limit: common=dict(list(sorted(common.items(),key=lambda x:x[0].encode()))[:a.common_limit])
    write_lua(a.lua,common); write_tsv(a.tsv,rows); print(f'common={len(common)} full={len(rows)}')
if __name__=='__main__': main()

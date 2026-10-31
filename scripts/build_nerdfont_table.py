#!/usr/bin/env python3
"""Build short aliases from Nerd Fonts glyphnames.json."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path
NAMESPACES={'nf','cod','md','mdi','fa','fas','far','fab','oct','weather','linux','dev','seti','custom','pom','pl','ple','ps','vs','material','iec','ph','smd','indent','websymbols','fae','mdc'}
def aliases(name):
    tokens=[x for x in re.split(r'[-_]+',name.lower()) if x]
    while tokens and tokens[0] in NAMESPACES: tokens.pop(0)
    if not tokens: return []
    out=[]
    def add(s):
        if 1 < len(s) <= 20 and s not in out: out.append(s)
    add(''.join(tokens)); add(tokens[-1])
    if len(tokens)>1: add(''.join(tokens[-2:]))
    if len(tokens)>1: add(''.join(x[0] for x in tokens))
    return out[:4]
def lua_quote(value):
    return '"' + value.replace('\\', '\\\\').replace('\"', '\\"') + '"'

def write_lua(path, rows):
    with path.open('w',encoding='utf8') as f:
        f.write('return {\n')
        for c in sorted(rows,key=lambda x:x.encode()): f.write('  [%s] = {%s},\n' % (lua_quote(c), ', '.join(lua_quote(x) for x in rows[c])))
        f.write('}\n')
def write_tsv(path, rows):
    with path.open('w',encoding='utf8') as f:
        for c in sorted(rows,key=lambda x:x.encode()): f.write(c+'\t'+','.join(rows[c])+'\n')
def main():
    p=argparse.ArgumentParser(); p.add_argument('source',type=Path); p.add_argument('lua',type=Path); p.add_argument('tsv',type=Path); p.add_argument('--common-from',type=Path); a=p.parse_args()
    raw=json.loads(a.source.read_text(encoding='utf8')); rows={}
    for key,item in raw.items():
        if key=='METADATA': continue
        char=item.get('char'); vals=aliases(key)
        if char and vals: rows[char]=sorted(set(rows.get(char,[])+vals))
    common_chars=set()
    if a.common_from:
        for line in a.common_from.read_text(encoding='utf8').splitlines():
            m=re.match(r"\s*\[(['\"])(.*?)\1\]",line)
            if m: common_chars.add(m.group(2))
    common={c:rows[c] for c in common_chars if c in rows}
    write_lua(a.lua,common); write_tsv(a.tsv,rows); print(f'common={len(common)} full={len(rows)}')
if __name__=='__main__': main()

#!/usr/bin/env python3
"""Validate pinned upstream dictionaries: --download fetches the original files."""
import argparse
import csv
import hashlib
import json
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.dev/real-tables'


def reference(text, case):
    """Independent format-specific reader; comparisons include every text/code pair."""
    fmt = case['format']
    lines = text.splitlines()
    rows = {}
    records = []
    if fmt == 'csv':
        records = list(csv.reader(lines))
        if case['options'].get('header'):
            records = records[1:]
    elif fmt == 'rime':
        start = lines.index('...') + 1
        records = [line.split('\t') for line in lines[start:] if line.strip() and not line.lstrip().startswith('#')]
    elif fmt == 'fcitx':
        start = next(i for i, line in enumerate(lines) if line.strip() in ('[Data]', '[数据]'))
        prefixes = []
        for line in lines[:start]:
            if '=' in line:
                key, value = line.strip().split('=', 1)
                if key in ('Prompt', '提示', 'ConstructPhrase', '构词') and value.strip():
                    prefixes.append(value.strip())
        for line in lines[start + 1:]:
            if line.strip() in ('[Phrase]', '[词组]'):
                break
            fields = line.split(None, 1)
            if len(fields) != 2 or any(fields[0].startswith(prefix) for prefix in prefixes):
                continue
            value = fields[1].strip()
            if value.startswith('"'):
                value = json.loads(value)
            records.append([value, fields[0]])
    elif fmt == 'ibus':
        start, end = lines.index('BEGIN_TABLE'), lines.index('END_TABLE')
        records = [line.split('\t') for line in lines[start+1:end] if line.strip() and not line.lstrip().startswith('###')]
    elif fmt == 'tsv':
        records = [line.split('\t') for line in lines if line.strip() and not line.startswith('#')]
    elif fmt == 'space':
        records = [line.split() for line in lines if line.strip() and not line.startswith('#')]
    if fmt == 'fcitx':
        text_index, code_index = 0, 1
    elif case['options'].get('columns'):
        columns = case['options']['columns']
        text_index, code_index = columns.index('text'), columns.index('code')
    elif fmt == 'ibus':
        text_index, code_index = 1, 0
    else:
        text_index, code_index = 0, 1
    for record in records:
        key = record[text_index] if fmt == 'fcitx' else record[text_index].strip()
        code = record[code_index].strip()
        if key and code:
            rows.setdefault(key, set()).add(code)
    return {key: sorted(values) for key, values in rows.items()}


def prepare(case, path):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == case['sha256'], f"checksum mismatch: {path}"
    model = reference(raw.decode('utf-8-sig'), case)
    expected = CACHE / (case['name'] + '-expected.json')
    expected.write_text(json.dumps(model, ensure_ascii=False), encoding='utf-8')
    # Single Unicode scalars are unambiguously single graphemes; do not use our
    # grapheme implementation to decide which native samples ought to match.
    pairs = [(key, code) for key, codes in sorted(model.items()) if len(key) == 1 for code in codes if key != code]
    stride = max(1, len(pairs) // 100)
    samples = pairs[::stride][:100]
    samples += [(key, code) for key, code in pairs if ',' in code or code.startswith('#')][:5]
    return {**case, 'file': str(path), 'expected': str(expected), 'samples': samples,
            'entries': len(model), 'pairs': sum(map(len, model.values())),
            'unicode_codes': sum(not code.isascii() for codes in model.values() for code in codes)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--nvim', default='nvim')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    cases = json.loads((ROOT/'tests/data/dictionaries.json').read_text())
    prepared = []
    for case in cases:
        path = CACHE / case['repo'].replace('/', '--') / case['path']
        if not path.exists():
            assert args.download, f"missing {path}; run with --download"
            url = f"https://raw.githubusercontent.com/{case['repo']}/{case['revision']}/" + urllib.parse.quote(case['path'])
            path.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(url, timeout=90) as response:
                raw = response.read()
            assert hashlib.sha256(raw).hexdigest() == case['sha256'], 'download checksum mismatch'
            temporary = path.with_suffix(path.suffix + '.download')
            temporary.write_bytes(raw)
            temporary.replace(path)
        prepared.append(prepare(case, path))
    # Same real CSV content, transcoded for Windows-style encoding coverage.
    original = next(case for case in prepared if case['name'] == 'csv-xhup')
    text = Path(original['file']).read_bytes().decode('utf-8-sig')
    # Match the host iconv's GB18030 revision (Python and libc may map ḿ differently).
    for encoding in ('gb18030', 'utf-16le'):
        path = CACHE / ('xhup-' + encoding + '.csv')
        encoded = subprocess.run(['iconv', '-f', 'UTF-8', '-t', encoding],
                                 input=text.encode('utf-8'), capture_output=True, check=True).stdout
        path.write_bytes(encoded)
        prepared.append({**original, 'name': 'csv-xhup-' + encoding,
                         'file': str(path), 'options': {**original['options'], 'encoding': encoding},
                         'derived_encoding': True})
    manifest = CACHE / 'cases.json'
    manifest.write_text(json.dumps(prepared, ensure_ascii=False), encoding='utf-8')
    process = subprocess.run([args.nvim, '--clean', '-l', str(ROOT/'tests/real_tables.lua'), str(manifest)], cwd=ROOT)
    raise SystemExit(process.returncode)


if __name__ == '__main__':
    main()

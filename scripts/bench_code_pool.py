"""Size-only prototype: encode repeated native matcher/code records in 1 or 2 bytes.

Requires historical v7/v8 input: python scripts/bench_code_pool.py old-package.bin ...
Writes .tokens prototypes beside inputs. These are not loadable by the C engine.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct


def records(data):
    result, at = [], 0
    while at < len(data):
        first = at
        mode = data[at]
        assert 0x80 <= mode <= 0x84 or 0x89 <= mode <= 0x8B
        at += 1
        if 0x89 <= mode <= 0x8B:
            at += 2
            assert at <= len(data)
            result.append(data[first:at])
            continue
        if mode == 0x84:
            size = data[at]
            assert 0 < size < 128
            at += 1 + size
        start = at
        while at < len(data) and data[at] < 128:
            at += 1
        assert at > start
        result.append(data[first:at])
    return result


def prototype(path):
    source = path.read_bytes()
    assert source[:8] in (b"FANYBIN\x07", b"FANYBIN\x08")
    header = list(struct.unpack_from("<8I", source, 8))
    count, pool_start = header[2], len(source) - header[5] - header[6]
    profile = source[pool_start + header[5]:]
    entries = list(struct.iter_unpack("<4I", source[40:40 + count * 16]))
    pool = source[pool_start:pool_start + header[5]]
    keys = [pool[key:key + size] for key, size, _, _ in entries]
    streams = [pool[code:code + size] for _, _, code, size in entries]
    parsed = {stream: records(stream) for stream in set(streams)}
    # Count bytes physically stored today, preserving existing whole-list sharing.
    frequency = Counter(record for group in parsed.values() for record in group)

    def candidates(width, excluded=()):
        scored = []
        for record, repeats in frequency.items():
            gain = repeats * (len(record) - width) - len(record) - 8
            if repeats > 1 and gain > 0 and record not in excluded:
                scored.append((gain, repeats, record))
        return [row[2] for row in sorted(scored, reverse=True)]

    short = candidates(1)[:32]
    long = candidates(2, short)[:8192]
    dictionary = short + long
    tokens = {record: bytes([0xC0 + i]) for i, record in enumerate(short)}
    tokens.update({record: bytes([0xE0 + (i >> 8), i & 255]) for i, record in enumerate(long)})
    encoded = {stream: b"".join(tokens.get(record, record) for record in group)
               for stream, group in parsed.items()}

    def decode(stream):
        expanded, at = [], 0
        while at < len(stream):
            tag = stream[at]
            if tag >= 0xE0:
                index = len(short) + ((tag & 31) << 8) + stream[at + 1]
                expanded.append(dictionary[index])
                at += 2
            elif tag >= 0xC0:
                expanded.append(dictionary[tag & 31])
                at += 1
            else:
                first = at
                assert 0x80 <= tag <= 0x84 or 0x89 <= tag <= 0x8B
                at += 1
                if 0x89 <= tag <= 0x8B:
                    at += 2
                    expanded.append(stream[first:at])
                    continue
                if tag == 0x84:
                    at += 1 + stream[at]
                while at < len(stream) and stream[at] < 128:
                    at += 1
                expanded.append(stream[first:at])
        return b"".join(expanded)

    for original, compact in encoded.items():
        assert decode(compact) == original, "prototype changed matching records"

    output_pool, offsets = bytearray(), {}

    def intern(value):
        if value not in offsets:
            offsets[value] = len(output_pool)
            output_pool.extend(value)
        return offsets[value]

    new_entries = bytearray()
    for key, stream in zip(keys, streams):
        compact = encoded[stream]
        new_entries.extend(struct.pack("<4I", intern(key), len(key), intern(compact), len(compact)))
    # Offset and length are counted for every dictionary entry, not just token bytes.
    directory = b"".join(struct.pack("<2I", intern(record), len(record)) for record in dictionary)
    # The size-only container keeps the profile verbatim with opaque index bytes.
    indexes = source[40 + count * 16:pool_start] + profile
    header[1] = 40 + len(new_entries) + len(indexes) + len(directory) + len(output_pool)
    header[5], header[6], header[7] = len(output_pool), len(dictionary), len(short)
    output = b"FANYTOK\x01" + struct.pack("<8I", *header) + new_entries + indexes + directory + output_pool
    assert len(output) == header[1]
    target = path.with_suffix(".tokens")
    target.write_bytes(output)
    restored = target.read_bytes()
    restored_pool = restored[-header[5]:]
    directory_at = 40 + len(new_entries) + len(indexes)
    restored_dictionary = []
    for offset, size in struct.iter_unpack("<2I", restored[directory_at:directory_at + len(directory)]):
        restored_dictionary.append(restored_pool[offset:offset + size])
    assert restored_dictionary == dictionary
    restored_entries = struct.iter_unpack("<4I", restored[40:40 + count * 16])
    for (key_at, key_size, code_at, code_size), key, original in zip(restored_entries, keys, streams):
        assert restored_pool[key_at:key_at + key_size] == key
        assert decode(restored_pool[code_at:code_at + code_size]) == original
    return dict(package=path.stem, entries=count, before=len(source), after=len(output),
                saved=len(source) - len(output), saved_pct=100 * (1 - len(output) / len(source)),
                short=len(short), long=len(long), directory_bytes=len(directory),
                dictionary_payload=sum(map(len, dictionary)), unique_lists=len(parsed),
                verified_records=sum(len(parsed[stream]) for stream in streams), output=str(target))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", type=Path, nargs="+")
    for package in parser.parse_args().packages:
        print(json.dumps(prototype(package)))

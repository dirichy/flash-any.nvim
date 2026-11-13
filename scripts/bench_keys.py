"""Shared deterministic key fixtures for standalone lookup benchmarks."""
import random
import struct


def hash_key(key):
    h = 2166136261
    for cp in map(ord, key):
        h = ((h ^ cp) * 16777619) & 0xFFFFFFFF
    return h


def write_fixture(path, keys, capacity=None, seed=20261112, misses=None):
    rng = random.Random(seed)
    keys = keys.copy()
    rng.shuffle(keys)
    present = set(keys)
    assert len(present) == len(keys) and keys and all("\0" not in k for k in keys)
    if capacity is None:
        capacity = 2
        while capacity * 3 < len(keys) * 4:
            capacity *= 2
    pool, entries = bytearray(), []

    def add(key):
        offset = len(pool)
        encoded = key.encode("utf-8")
        pool.extend(encoded + b"\0")
        return offset, len(encoded), hash_key(key)

    hits = []
    for i, key in enumerate(keys):
        offset, size, h = add(key)
        entries.append((offset, 0))
        hits.append((offset, size, h, i))
    if misses is None:
        near, random_misses = [], []
        alphabet = sorted(set("".join(keys)))
        for key in keys:
            changed = key
            while changed in present:
                changed = key[:-1] + rng.choice(alphabet)
            near.append((*add(changed), 0xFFFFFFFF))
            changed = key
            while changed in present:
                changed = "".join(rng.choices(alphabet, k=len(key)))
            random_misses.append((*add(changed), 0xFFFFFFFF))
    else:
        near, random_misses = misses
        assert all(k and "\0" not in k and k not in present for k in near + random_misses)
        near = [(*add(k), 0xFFFFFFFF) for k in near]
        random_misses = [(*add(k), 0xFFFFFFFF) for k in random_misses]
    assert len(near) == len(random_misses) == len(keys)
    queries = [hits, near, random_misses]
    for group in queries:
        rng.shuffle(group)
    with path.open("wb") as f:
        f.write(struct.pack("<III", len(keys), capacity, len(pool)))
        for entry in entries:
            f.write(struct.pack("<II", *entry))
        f.write(pool)
        for group in queries:
            for query in group:
                f.write(struct.pack("<IIII", *query))
    return dict(name=path.stem, keys=len(keys), capacity=capacity, load=len(keys) / capacity,
                path=str(path), pool_bytes=len(pool))

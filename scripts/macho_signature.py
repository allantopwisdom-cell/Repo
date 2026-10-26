"""Validate embedded CodeDirectory page hashes, not certificate trust or device policy."""
import hashlib
import struct

if not __debug__:
    raise RuntimeError("Signature validation requires Python without -O")


def verify_signature(binary, offset, size):
    signature = binary[offset:offset + size]
    assert len(signature) == size and size >= 12, 'truncated signature'
    magic, length, count = struct.unpack_from('>3I', signature)
    assert magic == 0xFADE0CC0 and 12 + 8 * count <= length <= size, 'invalid signature superblob'
    directories = []
    blobs, ranges = {}, []
    for i in range(count):
        slot, start = struct.unpack_from('>2I', signature, 12 + i * 8)
        assert start >= 12 + 8 * count and start + 8 <= length, 'invalid signature index'
        kind, blob_length = struct.unpack_from('>2I', signature, start)
        assert blob_length >= 8 and start + blob_length <= length, 'truncated signature blob'
        assert slot not in blobs, 'duplicate signature slot'
        assert not any(start < end and begin < start + blob_length for begin, end in ranges), 'overlapping signature blobs'
        assert slot in (0, 2) or 0x1000 <= slot <= 0x1005, 'unexpected signature payload/entitlements'
        blobs[slot] = signature[start:start + blob_length]
        ranges.append((start, start + blob_length))
        if slot == 0 or 0x1000 <= slot <= 0x1005:
            assert kind == 0xFADE0C02, 'expected CodeDirectory'
            directories.append(signature[start:start + blob_length])
    assert 0 in blobs and directories, 'primary CodeDirectory missing'
    for directory in directories:
        assert len(directory) >= 44
        _, _, version, flags, hash_offset, ident_offset, special, slots, limit = struct.unpack_from('>9I', directory)
        hash_size, hash_type, platform, page_exp = struct.unpack_from('>4B', directory, 36)
        assert version >= 0x20000 and 0 < limit == offset and page_exp <= 30
        assert 44 <= ident_offset < len(directory) and b'\0' in directory[ident_offset:hash_offset]
        algorithms = {1: ('sha1', 20), 2: ('sha256', 32), 3: ('sha256', 20), 4: ('sha384', 48)}
        assert hash_type in algorithms and hash_size == algorithms[hash_type][1], 'unsupported CodeDirectory hash'
        page_size = (1 << page_exp) if page_exp else max(limit, 1)
        assert slots == (limit + page_size - 1) // page_size
        assert hash_offset - special * hash_size >= 44
        assert hash_offset + slots * hash_size <= len(directory)
        for index in range(1, special + 1):
            stored = directory[hash_offset - index * hash_size:hash_offset - (index - 1) * hash_size]
            payload = blobs.get(index)
            expected = hashlib.new(algorithms[hash_type][0], payload).digest()[:hash_size] if payload else bytes(hash_size)
            assert stored == expected, f'CodeDirectory special slot {index} hash mismatch'
        for index in range(slots):
            page = binary[index * page_size:min(limit, (index + 1) * page_size)]
            calculated = hashlib.new(algorithms[hash_type][0], page).digest()[:hash_size]
            stored = directory[hash_offset + index * hash_size:hash_offset + (index + 1) * hash_size]
            assert calculated == stored, f'CodeDirectory page {index} hash mismatch'
    return len(directories)

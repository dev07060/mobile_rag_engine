"""Minimal Parquet reader for small flat string/int tables, standard library only (F2).

Enough for the AutoRAG files on Hugging Face (parquet-cpp-arrow, snappy or
uncompressed, data page v1/v2, PLAIN or dictionary encoding, optional or
required flat columns of BYTE_ARRAY / INT32 / INT64). Anything else raises.
Used so the evaluation scripts do not need pyarrow.
"""

from __future__ import annotations

import struct
from pathlib import Path


# ---- Thrift compact protocol (read only) ---------------------------------

class _T:
    def __init__(self, b: bytes, pos: int = 0):
        self.b, self.p = b, pos

    def byte(self) -> int:
        v = self.b[self.p]
        self.p += 1
        return v

    def varint(self) -> int:
        shift = out = 0
        while True:
            c = self.byte()
            out |= (c & 0x7F) << shift
            if not c & 0x80:
                return out
            shift += 7

    def zigzag(self) -> int:
        n = self.varint()
        return (n >> 1) ^ -(n & 1)

    def binary(self) -> bytes:
        n = self.varint()
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def value(self, t: int):
        if t in (1, 2):
            return t == 1
        if t == 3:
            return struct.unpack("b", bytes([self.byte()]))[0]
        if t in (4, 5, 6):
            return self.zigzag()
        if t == 7:
            v = struct.unpack("<d", self.b[self.p:self.p + 8])[0]
            self.p += 8
            return v
        if t == 8:
            return self.binary()
        if t in (9, 10):
            h = self.byte()
            n, et = h >> 4, h & 0x0F
            if n == 15:
                n = self.varint()
            return [self.value(et) for _ in range(n)]
        if t == 12:
            return self.struct()
        raise ValueError(f"thrift type {t}")

    def struct(self) -> dict:
        out, last = {}, 0
        while True:
            h = self.byte()
            if h == 0:
                return out
            t, d = h & 0x0F, h >> 4
            fid = last + d if d else self.zigzag()
            last = fid
            out[fid] = self.value(t)


# ---- Snappy ---------------------------------------------------------------

def _snappy(b: bytes) -> bytes:
    t = _T(b)
    n = t.varint()
    out = bytearray()
    while t.p < len(b):
        tag = t.byte()
        kind = tag & 3
        if kind == 0:
            ln = tag >> 2
            if ln >= 60:
                k = ln - 59
                ln = int.from_bytes(b[t.p:t.p + k], "little")
                t.p += k
            ln += 1
            out += b[t.p:t.p + ln]
            t.p += ln
            continue
        if kind == 1:
            ln = ((tag >> 2) & 7) + 4
            off = ((tag >> 5) << 8) | t.byte()
        elif kind == 2:
            ln = (tag >> 2) + 1
            off = int.from_bytes(b[t.p:t.p + 2], "little")
            t.p += 2
        else:
            ln = (tag >> 2) + 1
            off = int.from_bytes(b[t.p:t.p + 4], "little")
            t.p += 4
        for _ in range(ln):
            out.append(out[-off])
    if len(out) != n:
        raise ValueError("snappy length mismatch")
    return bytes(out)


def _decompress(codec: int, b: bytes, size: int) -> bytes:
    if codec == 0:
        return b
    if codec == 1:
        return _snappy(b)
    raise ValueError(f"codec {codec} not supported")


# ---- Encodings ------------------------------------------------------------

def _rle_bitpacked(b: bytes, bit_width: int, count: int) -> list[int]:
    t, out = _T(b), []
    byte_w = (bit_width + 7) // 8
    while len(out) < count and t.p < len(b):
        h = t.varint()
        if h & 1:
            groups = h >> 1
            nbytes = groups * bit_width
            chunk = int.from_bytes(b[t.p:t.p + nbytes], "little")
            t.p += nbytes
            mask = (1 << bit_width) - 1
            for i in range(groups * 8):
                out.append((chunk >> (i * bit_width)) & mask)
        else:
            v = int.from_bytes(b[t.p:t.p + byte_w], "little")
            t.p += byte_w
            out.extend([v] * (h >> 1))
    return out[:count]


def _plain(b: bytes, ptype: int, n: int) -> list:
    out, p = [], 0
    for _ in range(n):
        if ptype == 6:
            ln = struct.unpack_from("<i", b, p)[0]
            out.append(b[p + 4:p + 4 + ln].decode("utf-8"))
            p += 4 + ln
        elif ptype == 1:
            out.append(struct.unpack_from("<i", b, p)[0])
            p += 4
        elif ptype == 2:
            out.append(struct.unpack_from("<q", b, p)[0])
            p += 8
        else:
            raise ValueError(f"physical type {ptype} not supported")
    return out


def read_table(path: str | Path) -> list[dict]:
    b = Path(path).read_bytes()
    if b[:4] != b"PAR1" or b[-4:] != b"PAR1":
        raise ValueError("not a parquet file")
    mlen = struct.unpack("<i", b[-8:-4])[0]
    meta = _T(b[-8 - mlen:-8]).struct()
    schema = meta[2]
    leaves = [s for s in schema[1:] if 5 not in s]  # elements without num_children
    names = [s[4].decode() for s in leaves]
    optional = [s.get(3, 0) == 1 for s in leaves]
    cols = {n: [] for n in names}
    for rg in meta[4]:
        for ci, cc in enumerate(rg[1]):
            cm = cc[3]
            ptype, codec, nvals = cm[1], cm[4], cm[5]
            start = cm.get(11, cm[9])  # dictionary page offset, else data page offset
            t = _T(b, start)
            dictionary, got = None, []
            while len(got) < nvals:
                ph = t.struct()
                body = b[t.p:t.p + ph[3]]
                t.p += ph[3]
                kind = ph[1]
                if kind == 2:  # dictionary page
                    raw = _decompress(codec, body, ph[2])
                    dictionary = _plain(raw, ptype, ph[7][1])
                    continue
                if kind == 0:  # data page v1
                    raw = _decompress(codec, body, ph[2])
                    dh = ph[5]
                    n, enc = dh[1], dh[2]
                    p = 0
                    defs = [1] * n
                    if optional[ci]:
                        ln = struct.unpack_from("<i", raw, p)[0]
                        defs = _rle_bitpacked(raw[p + 4:p + 4 + ln], 1, n)
                        p += 4 + ln
                    vals_raw = raw[p:]
                elif kind == 3:  # data page v2
                    dh = ph[8]
                    n, enc = dh[1], dh[4]
                    dl, rl = dh[5], dh[6]
                    levels = body[:dl + rl]
                    comp = dh.get(7, True)
                    rest = _decompress(codec, body[dl + rl:], ph[2] - dl - rl) if comp else body[dl + rl:]
                    defs = _rle_bitpacked(levels[rl:rl + dl], 1, n) if optional[ci] else [1] * n
                    vals_raw = rest
                else:
                    raise ValueError(f"page type {kind}")
                present = sum(defs)
                if enc in (2, 8):  # PLAIN_DICTIONARY / RLE_DICTIONARY
                    bw = vals_raw[0]
                    idx = _rle_bitpacked(vals_raw[1:], bw, present)
                    vals = [dictionary[i] for i in idx]
                elif enc == 0:
                    vals = _plain(vals_raw, ptype, present)
                else:
                    raise ValueError(f"encoding {enc} not supported")
                it = iter(vals)
                got.extend(next(it) if d else None for d in defs)
            cols[names[ci]].extend(got)
    n = meta[3]
    return [{k: cols[k][i] for k in names} for i in range(n)]

"""Prints the smallest LOAD segment alignment of an ELF shared library.

Same value as the last column of `llvm-readelf -lW` for LOAD rows, without
needing the Android NDK. Prints nothing (and exits 1) for a file that is not
ELF or has no LOAD segment.

Usage: python3 elf_align.py <library.so>
"""

import struct
import sys

PT_LOAD = 1


def load_alignments(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:4] != b"\x7fELF":
        return []
    is64 = data[4] == 2
    endian = "<" if data[5] == 1 else ">"
    if is64:
        phoff, = struct.unpack_from(endian + "Q", data, 0x20)
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x36)
    else:
        phoff, = struct.unpack_from(endian + "I", data, 0x1C)
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x2A)
    alignments = []
    for i in range(phnum):
        offset = phoff + i * phentsize
        p_type, = struct.unpack_from(endian + "I", data, offset)
        if p_type != PT_LOAD:
            continue
        if is64:
            p_align, = struct.unpack_from(endian + "Q", data, offset + 0x30)
        else:
            p_align, = struct.unpack_from(endian + "I", data, offset + 0x1C)
        alignments.append(p_align)
    return alignments


if __name__ == "__main__":
    found = load_alignments(sys.argv[1])
    if not found:
        sys.exit(1)
    print(min(found))

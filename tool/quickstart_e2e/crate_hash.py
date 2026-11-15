"""Prints the Cargokit crate hash of a Rust crate.

Same inputs and steps as rust_builder/cargokit/build_tool/lib/src/crate_hash.dart:
every file under src/ sorted by path, then Cargo.toml, Cargo.lock, build.rs and
cargokit.yaml when present; each text file is hashed line by line without line
terminators; SHA-256 truncated to 128 bits. Cargokit downloads precompiled
binaries from the release `precompiled_<hash>`.

Usage: python3 crate_hash.py <manifest dir>
"""

import hashlib
import os
import sys


def lines(path):
    with open(path, encoding="utf-8", newline="") as handle:
        data = handle.read()
    # Dart's LineSplitter splits on \r\n, \n and \r.
    return data.replace("\r\n", "\n").replace("\r", "\n").split("\n")[
        : None if not data or data[-1] not in "\r\n" else -1
    ]


def crate_hash(manifest_dir):
    src = os.path.join(manifest_dir, "src")
    files = sorted(
        os.path.join(root, name)
        for root, _, names in os.walk(src)
        for name in names
    )
    for name in ("Cargo.toml", "Cargo.lock", "build.rs", "cargokit.yaml"):
        path = os.path.join(manifest_dir, name)
        if os.path.isfile(path):
            files.append(path)
    digest = hashlib.sha256()
    for path in files:
        for line in lines(path):
            digest.update(line.encode("utf-8"))
    return digest.digest()[:16].hex()


if __name__ == "__main__":
    print(crate_hash(sys.argv[1]))

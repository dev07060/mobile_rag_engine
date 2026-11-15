"""Prints every native symbol Dart looks up by name when MobileRag starts.

flutter_rust_bridge finds Rust functions with DynamicLibrary.lookup at runtime,
so a release binary that lost one (stripped, or not exported) only fails on the
user's device. The names come from the installed packages, not a fixed list:
the core `frb_*` and `store_dart_post_cobject` lookups in flutter_rust_bridge,
and the `frbgen_mobile_rag_engine_*` lookups generated into mobile_rag_engine.

Usage: python3 frb_symbols.py <app>/.dart_tool/package_config.json
"""

import json
import os
import re
import sys
from urllib.parse import unquote, urlparse

SOURCES = {
    "flutter_rust_bridge": (
        "lib/src/ffigen_generated/multi_package.dart",
        r"'((?:frb_|store_dart_post_cobject)[A-Za-z0-9_]*)'",
    ),
    "mobile_rag_engine": (
        "lib/src/rust/frb_generated.io.dart",
        r"'(frbgen_[A-Za-z0-9_]+)'",
    ),
}


def package_roots(config_path):
    with open(config_path, encoding="utf-8") as handle:
        config = json.load(handle)
    base = os.path.dirname(os.path.abspath(config_path))
    roots = {}
    for package in config["packages"]:
        uri = package["rootUri"]
        if uri.startswith("file:"):
            path = unquote(urlparse(uri).path)
            if re.match(r"^/[A-Za-z]:", path):
                path = path[1:]
        else:
            path = os.path.join(base, unquote(uri))
        roots[package["name"]] = os.path.normpath(path)
    return roots


def main(config_path):
    roots = package_roots(config_path)
    symbols = set()
    for package, (relative, pattern) in SOURCES.items():
        with open(os.path.join(roots[package], relative), encoding="utf-8") as handle:
            found = set(re.findall(pattern, handle.read()))
        if not found:
            sys.exit(f"no symbol lookups found in {package}/{relative}")
        symbols |= found
    for symbol in sorted(symbols):
        print(symbol)


if __name__ == "__main__":
    main(sys.argv[1])

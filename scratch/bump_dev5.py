import sys
import re

def bump_pubspec(path):
    with open(path, 'r') as f:
        content = f.read()
    content = re.sub(r'0\.20\.0-dev\.4', '0.20.0-dev.5', content)
    content = re.sub(r'0\.21\.0-dev\.4', '0.21.0-dev.5', content)
    with open(path, 'w') as f:
        f.write(content)

def main():
    bump_pubspec("rust_builder/pubspec.yaml")
    bump_pubspec("pubspec.yaml")

    # Changelogs
    with open("rust_builder/CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.20.0-dev.4", "## 0.20.0-dev.5\n* **Bug Fix**: Fixed a `PanicException` during Phase 2 of HNSW search by adding a missing cursor offset skip for `blob_len` (vector data) before reading `node_max_layer`.\n\n## 0.20.0-dev.4")
    with open("rust_builder/CHANGELOG.md", 'w') as f:
        f.write(content)

    with open("CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.21.0-dev.4", "## 0.21.0-dev.5\n* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.5` fixing HNSW Phase 2 binary offset calculation, preventing search panics.\n\n## 0.21.0-dev.4")
    content = content.replace("rag_engine_flutter: ^0.20.0-dev.4", "rag_engine_flutter: ^0.20.0-dev.5")
    with open("CHANGELOG.md", 'w') as f:
        f.write(content)

if __name__ == "__main__":
    main()

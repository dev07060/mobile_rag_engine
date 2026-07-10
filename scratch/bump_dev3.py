import sys
import re

def bump_pubspec(path):
    with open(path, 'r') as f:
        content = f.read()
    content = re.sub(r'0\.20\.0-dev\.2', '0.20.0-dev.3', content)
    content = re.sub(r'0\.21\.0-dev\.2', '0.21.0-dev.3', content)
    with open(path, 'w') as f:
        f.write(content)

def main():
    bump_pubspec("rust_builder/pubspec.yaml")
    bump_pubspec("pubspec.yaml")

    # Changelogs
    with open("rust_builder/CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.20.0-dev.2", "## 0.20.0-dev.3\n* **Critical Bug Fix**: Fixed HNSW and Linear search to read quantized blobs from `MMAP_STORE` via `mmap_id` when SQLite `embedding_i8` is empty. Fixed a false-positive in linear search fallback where empty arrays caused fake 0.0 similarity results.\n\n## 0.20.0-dev.2")
    with open("rust_builder/CHANGELOG.md", 'w') as f:
        f.write(content)

    with open("CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.21.0-dev.2", "## 0.21.0-dev.3\n* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.3` fixing MMAP data reading and false 0.0 similarities in linear search fallback.\n\n## 0.21.0-dev.2")
    content = content.replace("rag_engine_flutter: ^0.20.0-dev.2", "rag_engine_flutter: ^0.20.0-dev.3")
    with open("CHANGELOG.md", 'w') as f:
        f.write(content)

if __name__ == "__main__":
    main()

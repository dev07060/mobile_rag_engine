import sys
import re

def bump_pubspec(path):
    with open(path, 'r') as f:
        content = f.read()
    content = re.sub(r'0\.20\.0-dev\.3', '0.20.0-dev.4', content)
    content = re.sub(r'0\.21\.0-dev\.3', '0.21.0-dev.4', content)
    with open(path, 'w') as f:
        f.write(content)

def main():
    bump_pubspec("rust_builder/pubspec.yaml")
    bump_pubspec("pubspec.yaml")

    # Changelogs
    with open("rust_builder/CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.20.0-dev.3", "## 0.20.0-dev.4\n* **Bug Fix**: Fixed a binary header parsing bug in `custom_hnsw.rs` where the cursor size was `14` instead of `18` bytes, causing `failed to fill whole buffer` errors when loading the HNSW index.\n\n## 0.20.0-dev.3")
    with open("rust_builder/CHANGELOG.md", 'w') as f:
        f.write(content)

    with open("CHANGELOG.md", 'r') as f:
        content = f.read()
    content = content.replace("## 0.21.0-dev.3", "## 0.21.0-dev.4\n* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.4` fixing HNSW index loading (buffer size 14 -> 18).\n\n## 0.21.0-dev.3")
    content = content.replace("rag_engine_flutter: ^0.20.0-dev.3", "rag_engine_flutter: ^0.20.0-dev.4")
    with open("CHANGELOG.md", 'w') as f:
        f.write(content)

if __name__ == "__main__":
    main()

#!/bin/bash
# download_models.sh
# Downloads all-MiniLM-L6-v2 embedding model for mobile_rag_engine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/example/assets"

# Model URLs from Hugging Face
MINILM_ONNX_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_qint8_arm64.onnx"
MINILM_TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

# Output file names
ONNX_FILE="$ASSETS_DIR/model.onnx"
TOKENIZER_FILE="$ASSETS_DIR/tokenizer.json"

echo "📦 all-MiniLM-L6-v2 Embedding Model Downloader"
echo "================================================"

# Create assets directory if not exists
mkdir -p "$ASSETS_DIR"

# Download ONNX model if not exists
if [ -f "$ONNX_FILE" ]; then
    echo "✅ ONNX model already exists: $ONNX_FILE"
else
    echo "⬇️  Downloading all-MiniLM-L6-v2 ONNX model (INT8 quantized, ~23MB)..."
    curl -L -o "$ONNX_FILE" "$MINILM_ONNX_URL"
    echo "✅ Downloaded: $ONNX_FILE"
fi

# Download tokenizer if not exists
if [ -f "$TOKENIZER_FILE" ]; then
    echo "✅ Tokenizer already exists: $TOKENIZER_FILE"
else
    echo "⬇️  Downloading all-MiniLM-L6-v2 tokenizer..."
    curl -L -o "$TOKENIZER_FILE" "$MINILM_TOKENIZER_URL"
    echo "✅ Downloaded: $TOKENIZER_FILE"
fi

echo ""
echo "✅ All models downloaded successfully!"
echo "   ONNX: $(du -h "$ONNX_FILE" | cut -f1)"
echo "   Tokenizer: $(du -h "$TOKENIZER_FILE" | cut -f1)"

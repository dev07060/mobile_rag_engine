#!/bin/bash
# download_models.sh
# Downloads BGE-m3 embedding model for mobile_rag_engine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/example/assets"

# Model URLs from Hugging Face
BGE_M3_ONNX_URL="https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx"
BGE_M3_TOKENIZER_URL="https://huggingface.co/BAAI/bge-m3/resolve/main/tokenizer.json"

# Output file names
ONNX_FILE="$ASSETS_DIR/model.onnx"
TOKENIZER_FILE="$ASSETS_DIR/tokenizer.json"

echo "📦 BGE-m3 Embedding Model Downloader"
echo "======================================"

# Create assets directory if not exists
mkdir -p "$ASSETS_DIR"

# Download ONNX model if not exists
if [ -f "$ONNX_FILE" ]; then
    echo "✅ ONNX model already exists: $ONNX_FILE"
else
    echo "⬇️  Downloading BGE-m3 ONNX model (int8 quantized, ~542MB)..."
    curl -L -o "$ONNX_FILE" "$BGE_M3_ONNX_URL"
    echo "✅ Downloaded: $ONNX_FILE"
fi

# Download tokenizer if not exists
if [ -f "$TOKENIZER_FILE" ]; then
    echo "✅ Tokenizer already exists: $TOKENIZER_FILE"
else
    echo "⬇️  Downloading BGE-m3 tokenizer (~17MB)..."
    curl -L -o "$TOKENIZER_FILE" "$BGE_M3_TOKENIZER_URL"
    echo "✅ Downloaded: $TOKENIZER_FILE"
fi

echo ""
echo "✅ All models downloaded successfully!"
echo "   ONNX: $(du -h "$ONNX_FILE" | cut -f1)"
echo "   Tokenizer: $(du -h "$TOKENIZER_FILE" | cut -f1)"

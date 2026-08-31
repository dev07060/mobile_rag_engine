# Mobile RAG Engine Example

This example demonstrates the `mobile_rag_engine` package with the `MobileRag` facade.

## Repository Demo Initialization

This repository demo intentionally uses the advanced multilingual BGE-m3
two-asset path. For a new app, use the Q8_0 Model Pack setup, `--check`, and
manifest initialization in the package [Quick Start](../docs/guides/quick_start.md).

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize (just 1 line!)
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
  );
  
  runApp(const MyApp());
}

// Later in your app:

// 2. Add documents
await MobileRag.instance.addDocument('Your document text here');
await MobileRag.instance.addDocumentFromFile('/path/to/document.pdf');
await MobileRag.instance.rebuildIndex();

// 3. Search
final result = await MobileRag.instance.search('query', tokenBudget: 2000);
print(result.context.text);
```

## Running the Example

1. Download the demo's custom BGE-m3 model files to `assets/`:
   ```bash
   cd assets
   curl -L -o model.onnx "https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx"
   curl -L -o tokenizer.json "https://huggingface.co/BAAI/bge-m3/resolve/main/tokenizer.json"
   ```

2. Run:
   ```bash
   flutter run
   ```

## Features Demonstrated

- **Document ingestion** with auto-chunking
- **Semantic search** with vector similarity
- **PDF/DOCX import** using built-in parser
- **File attachment** via file_picker

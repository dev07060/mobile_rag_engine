import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/internal/asset_file_sync.dart';

void main() {
  late Directory dir;
  late Map<String, List<int>> assets;
  late int loads;

  Future<ByteData> loadAsset(String key) async {
    loads++;
    final bytes = assets[key];
    if (bytes == null) throw StateError('missing asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  Future<bool> sync(String asset, String target) =>
      syncAssetToFile(asset, '${dir.path}/$target', loadAsset: loadAsset);

  List<int> read(String target) =>
      File('${dir.path}/$target').readAsBytesSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('asset_file_sync_test');
    assets = {};
    loads = 0;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('copies a missing file and stamps it', () async {
    assets['assets/model.onnx'] = [1, 2, 3];

    expect(await sync('assets/model.onnx', 'model.onnx'), isTrue);

    expect(read('model.onnx'), [1, 2, 3]);
    final stamp =
        jsonDecode(
              File(
                '${dir.path}/model.onnx$assetStampSuffix',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(stamp['asset'], 'assets/model.onnx');
    expect(stamp['length'], 3);
    expect(stamp['sha256'], hasLength(64));
  });

  test('keeps an up-to-date copy', () async {
    assets['assets/model.onnx'] = [1, 2, 3];
    await sync('assets/model.onnx', 'model.onnx');
    final modified = File('${dir.path}/model.onnx').lastModifiedSync();

    expect(await sync('assets/model.onnx', 'model.onnx'), isFalse);

    expect(File('${dir.path}/model.onnx').lastModifiedSync(), modified);
    expect(loads, 2);
  });

  test(
    'rewrites a same-name model whose bytes changed in an app update',
    () async {
      assets['assets/model.onnx'] = [1, 2, 3];
      await sync('assets/model.onnx', 'model.onnx');

      // Same length, different content: only the hash can tell them apart.
      assets['assets/model.onnx'] = [9, 8, 7];
      expect(await sync('assets/model.onnx', 'model.onnx'), isTrue);

      expect(read('model.onnx'), [9, 8, 7]);
    },
  );

  test(
    'rewrites the fixed-name tokenizer when the tokenizer asset changes',
    () async {
      assets['assets/koen/tokenizer.json'] = utf8.encode('{"koen":true}');
      assets['assets/minilm/tokenizer.json'] = utf8.encode('{"minilm":true}');
      await sync('assets/koen/tokenizer.json', 'tokenizer.json');

      expect(
        await sync('assets/minilm/tokenizer.json', 'tokenizer.json'),
        isTrue,
      );

      expect(utf8.decode(read('tokenizer.json')), '{"minilm":true}');
    },
  );

  test('replaces an unstamped copy made by older versions', () async {
    File('${dir.path}/tokenizer.json').writeAsStringSync('stale');
    assets['assets/tokenizer.json'] = utf8.encode('fresh');

    expect(await sync('assets/tokenizer.json', 'tokenizer.json'), isTrue);

    expect(utf8.decode(read('tokenizer.json')), 'fresh');
    expect(await sync('assets/tokenizer.json', 'tokenizer.json'), isFalse);
  });

  test('rewrites a truncated copy even when its stamp matches', () async {
    assets['assets/model.onnx'] = [1, 2, 3];
    await sync('assets/model.onnx', 'model.onnx');
    File('${dir.path}/model.onnx').writeAsBytesSync([1]);

    expect(await sync('assets/model.onnx', 'model.onnx'), isTrue);

    expect(read('model.onnx'), [1, 2, 3]);
  });

  test('treats a corrupt stamp as missing', () async {
    assets['assets/model.onnx'] = [1, 2, 3];
    await sync('assets/model.onnx', 'model.onnx');
    File('${dir.path}/model.onnx$assetStampSuffix').writeAsStringSync('{');

    expect(await sync('assets/model.onnx', 'model.onnx'), isTrue);
    expect(await sync('assets/model.onnx', 'model.onnx'), isFalse);
  });

  test('leaves no temporary files behind', () async {
    assets['assets/model.onnx'] = [1, 2, 3];
    await sync('assets/model.onnx', 'model.onnx');
    assets['assets/model.onnx'] = [4, 5, 6, 7];
    await sync('assets/model.onnx', 'model.onnx');

    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'model.onnx', 'model.onnx$assetStampSuffix'});
  });
}

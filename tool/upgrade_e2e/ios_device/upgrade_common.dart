// Shared by the two phases of the iOS device upgrade check (M5,
// docs/milestones.md). Phase A runs on the last release from pub.dev, phase B
// on the package under test, in the same app and data container.

import 'dart:io';

import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

const modelPackAsset = 'assets/mobile_rag/model-pack.json';
const databaseName = 'm5_upgrade.sqlite';

// Two English and two Korean documents.
const documents = <String, String>{
  'sqlite_en.txt':
      'SQLite is a small, fast, self-contained SQL database engine that '
      'stores a whole database in a single file on disk. Write-ahead logging '
      'lets readers continue while a writer commits.',
  'backup_en.txt':
      'To back up your files, open Settings, choose Backups and turn on '
      'automatic backups. Backups run once a day while the phone is charging '
      'and connected to Wi-Fi.',
  'refund_ko.txt':
      '환불 정책: 구매한 날부터 14일 안에 앱의 설정 화면에서 환불을 신청할 수 '
      '있습니다. 환불은 결제한 수단으로 3영업일 안에 돌아갑니다.',
  'night_ko.txt':
      '야간 모드를 켜면 해가 진 뒤 화면 색이 따뜻한 색으로 바뀌어 눈의 피로를 '
      '줄여 줍니다. 설정의 디스플레이 메뉴에서 시간을 정할 수 있습니다.',
};

const queries = <String>[
  'How do readers keep working while a writer commits?',
  '환불은 며칠 안에 신청해야 하나요?',
];

Future<File> stateFile() async => File(
  '${(await getApplicationDocumentsDirectory()).path}/m5_upgrade_phase_a.json',
);

Future<File> resultFile() async => File(
  '${(await getApplicationDocumentsDirectory()).path}/m5_upgrade_phase_b.json',
);

Future<void> initializeEngine() => MobileRag.initialize(
  modelPack: const RagModelPack.asset(modelPackAsset),
  databaseName: databaseName,
);

/// Top hybrid hit per query, as the source name.
Future<Map<String, Object?>> topSources() async {
  final names = {
    for (final s in await MobileRag.instance.listSources()) s.id: s.name,
  };
  final out = <String, Object?>{};
  for (final q in queries) {
    final hits = await MobileRag.instance.searchHybrid(q, topK: 3);
    out[q] = [for (final h in hits) names[h.sourceId]];
  }
  return out;
}

void log(String line) {
  // ignore: avoid_print
  print('M5_UPGRADE $line');
}

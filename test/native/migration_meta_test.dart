import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/error.dart';
import 'package:mobile_rag_engine/src/rust/api/migration_meta.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as source_rag;
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> _ensureRustLoaded() async {
  if (!RustLib.instance.initialized) {
    await RustLib.init();
  }
}

Future<Directory> _freshDir() =>
    Directory.systemTemp.createTemp('mobile_rag_migration_meta_');

void main() {
  setUpAll(() async {
    await _ensureRustLoaded();
  });

  tearDown(() async {
    // Each test owns its own pool; close before moving on so the next test
    // can install a fresh one against a different sqlite file.
    await closeDbPool();
  });

  test(
    'new install records the engine\'s current axis baseline',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/new_install.sqlite';
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();

        final axes = await readMigrationAxes();

        expect(axes.sqlSchemaVersion, 1,
            reason: 'CURRENT_SQL_SCHEMA_VERSION ships as 1');
        expect(axes.hnswFormatVersion, 1);
        expect(axes.bm25StatsVersion, 1);
        expect(axes.embeddingFingerprint, '',
            reason: 'P0-2 will populate the fingerprint; P0-1 leaves it empty');
        expect(
          axes.lastEngineVersion.isNotEmpty,
          isTrue,
          reason: 'last_engine_version must record the build identifier',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'existing install (chunks table predates migration_meta) backfills to v0',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/upgrade.sqlite';

        // Simulate a pre-axis install: provision the legacy `sources` and
        // `chunks` tables with the column shape an old build would have left
        // behind BEFORE init_source_db's forward migrations and migration_meta
        // bootstrap run. We need enough columns for the existing in-place
        // upgrade SQL inside init_source_db to succeed.
        final seed = sqlite3.open(dbPath);
        try {
          seed.execute('''
            CREATE TABLE sources (
              id INTEGER PRIMARY KEY,
              content TEXT NOT NULL,
              content_hash TEXT UNIQUE,
              metadata TEXT,
              created_at INTEGER DEFAULT (strftime('%s', 'now'))
            )
          ''');
          seed.execute('''
            CREATE TABLE chunks (
              id INTEGER PRIMARY KEY,
              source_id INTEGER NOT NULL,
              chunk_index INTEGER NOT NULL,
              content TEXT NOT NULL,
              start_pos INTEGER NOT NULL,
              end_pos INTEGER NOT NULL,
              embedding BLOB NOT NULL,
              FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
            )
          ''');
        } finally {
          seed.dispose();
        }

        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();

        final axes = await readMigrationAxes();
        expect(axes.sqlSchemaVersion, 0,
            reason: 'pre-axis install must backfill to v0 so P1-3 can migrate');
        expect(axes.hnswFormatVersion, 0);
        expect(axes.bm25StatsVersion, 0);
        expect(axes.embeddingFingerprint, '');
        expect(axes.lastEngineVersion.isNotEmpty, isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'axes are sticky across reboots (last_engine_version refreshes only)',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/second_boot.sqlite';

        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        final first = await readMigrationAxes();
        await closeDbPool();

        // Hand-tamper one axis to simulate a future build that wrote v2.
        final db = sqlite3.open(dbPath);
        try {
          db.execute(
            "UPDATE migration_meta SET value = '0' WHERE key = 'sql_schema_version'",
          );
        } finally {
          db.dispose();
        }

        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        final second = await readMigrationAxes();

        expect(second.sqlSchemaVersion, 0,
            reason: 'axes must be sticky once persisted');
        expect(second.hnswFormatVersion, first.hnswFormatVersion);
        expect(second.bm25StatsVersion, first.bm25StatsVersion);
        expect(second.embeddingFingerprint, first.embeddingFingerprint);
        expect(second.lastEngineVersion, first.lastEngineVersion,
            reason: 'binary version did not change between boots');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'boot rejects a future axis value with UnsupportedMigrationVersion',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/future_axis.sqlite';

        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        final current = await readMigrationAxes();
        await closeDbPool();

        // Hand-write an axis the current build does not understand.
        final futureHnsw = current.hnswFormatVersion + 1;
        final db = sqlite3.open(dbPath);
        try {
          db.execute(
            'UPDATE migration_meta SET value = ? WHERE key = ?',
            ['$futureHnsw', 'hnsw_format_version'],
          );
        } finally {
          db.dispose();
        }

        await initDbPool(dbPath: dbPath, maxSize: 2);

        await expectLater(
          source_rag.initSourceDb(),
          throwsA(
            isA<RagError_UnsupportedMigrationVersion>()
                .having((e) => e.field0, 'axis', 'hnsw_format_version')
                .having((e) => e.field1, 'stored', futureHnsw)
                .having((e) => e.field2, 'supported',
                    current.hnswFormatVersion),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}

// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.

//! Four-axis migration metadata for on-device data evolution (Phase P0-1).
//!
//! Persists the engine's evolving compatibility surface as four independent
//! axes — SQL schema, HNSW format, BM25 stats, embedding fingerprint — plus
//! the engine version string of the last boot. Each axis is owned by a
//! different subsystem and evolves at its own cadence; binding them to a
//! single `db_version` would force unrelated rebuilds.
//!
//! Boot semantics:
//! * **New install** — every axis is written with the engine's current value.
//! * **Existing install** — integer axes are backfilled to `0` so future
//!   phases can apply migrations forward without ever silently discarding
//!   user data. The embedding fingerprint stays empty until Phase P0-2
//!   explicitly populates it from the loaded model.
//! * **Future axis** — if any persisted integer axis is greater than the
//!   build's supported value, boot is rejected with
//!   [`RagError::UnsupportedMigrationVersion`]. Downgrade is unsupported.

use crate::api::db_pool::get_connection;
use crate::api::error::RagError;
use log::info;
use rusqlite::{params, Connection};

/// SQL schema shape produced by the current `init_source_db`.
///
/// Bump when an axis-affecting schema change ships; Phase P1-3 will gate
/// forward migrations on this value.
pub const CURRENT_SQL_SCHEMA_VERSION: i64 = 1;

/// HNSW on-disk format the current build emits and can read.
///
/// Phase P1-4 will own bumps via a file envelope.
pub const CURRENT_HNSW_FORMAT_VERSION: i64 = 1;

/// BM25 stats algorithm/tokenizer baseline.
///
/// Phase P2-5 will own bumps when the tokenizer or scoring changes.
pub const CURRENT_BM25_STATS_VERSION: i64 = 1;

/// Engine build identifier persisted on every boot.
pub const CURRENT_ENGINE_VERSION: &str = env!("CARGO_PKG_VERSION");

pub const KEY_SQL_SCHEMA_VERSION: &str = "sql_schema_version";
pub const KEY_HNSW_FORMAT_VERSION: &str = "hnsw_format_version";
pub const KEY_BM25_STATS_VERSION: &str = "bm25_stats_version";
pub const KEY_EMBEDDING_FINGERPRINT: &str = "embedding_fingerprint";
pub const KEY_LAST_ENGINE_VERSION: &str = "last_engine_version";

/// Sentinel value persisted before Phase P0-2 registers a real fingerprint.
const EMPTY_FINGERPRINT: &str = "";

/// Read-only snapshot of the four versioning axes plus the last engine version.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationAxes {
    pub sql_schema_version: i64,
    pub hnsw_format_version: i64,
    pub bm25_stats_version: i64,
    /// Empty string means "not yet registered" (P0-2 will populate).
    pub embedding_fingerprint: String,
    pub last_engine_version: String,
}

/// Provision the `migration_meta` table. Safe to call repeatedly.
pub(crate) fn create_migration_meta_table(conn: &Connection) -> Result<(), RagError> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS migration_meta (
            key        TEXT PRIMARY KEY NOT NULL,
            value      TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

/// Detect whether the database held user data before this boot.
///
/// MUST be called before `CREATE TABLE IF NOT EXISTS sources/chunks`; once
/// those statements run there is no way to distinguish "fresh install" from
/// "upgrade that pre-dated migration_meta".
pub(crate) fn detect_existing_install(conn: &Connection) -> Result<bool, RagError> {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master
             WHERE type='table' AND name IN ('sources','chunks')",
            [],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(count > 0)
}

fn upsert_axis(conn: &Connection, key: &str, value: &str) -> Result<(), RagError> {
    conn.execute(
        "INSERT INTO migration_meta(key, value)
         VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET
             value = excluded.value,
             updated_at = strftime('%s', 'now')",
        params![key, value],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn read_axis_int(conn: &Connection, key: &str) -> Result<i64, RagError> {
    let raw: String = conn
        .query_row(
            "SELECT value FROM migration_meta WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(format!("migration_meta read '{key}': {e}")))?;
    raw.parse::<i64>().map_err(|e| {
        RagError::DatabaseError(format!(
            "migration_meta axis '{key}' is not an integer (value={raw}): {e}"
        ))
    })
}

fn read_axis_string(conn: &Connection, key: &str) -> Result<String, RagError> {
    conn.query_row(
        "SELECT value FROM migration_meta WHERE key = ?1",
        params![key],
        |row| row.get(0),
    )
    .map_err(|e| RagError::DatabaseError(format!("migration_meta read '{key}': {e}")))
}

pub(crate) fn read_axes_with(conn: &Connection) -> Result<MigrationAxes, RagError> {
    Ok(MigrationAxes {
        sql_schema_version: read_axis_int(conn, KEY_SQL_SCHEMA_VERSION)?,
        hnsw_format_version: read_axis_int(conn, KEY_HNSW_FORMAT_VERSION)?,
        bm25_stats_version: read_axis_int(conn, KEY_BM25_STATS_VERSION)?,
        embedding_fingerprint: read_axis_string(conn, KEY_EMBEDDING_FINGERPRINT)?,
        last_engine_version: read_axis_string(conn, KEY_LAST_ENGINE_VERSION)?,
    })
}

/// Read the current 4-axis state from `migration_meta`.
///
/// Intended for diagnostics, telemetry, and gating by future phases (P0-2
/// fingerprint, P1-3 SQL migrations, P1-4 HNSW envelope, P2-5 BM25 stats).
pub fn read_migration_axes() -> Result<MigrationAxes, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    read_axes_with(&conn)
}

fn bootstrap_axes(conn: &Connection, existing_install: bool) -> Result<bool, RagError> {
    let already_present: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM migration_meta WHERE key = ?1",
            params![KEY_SQL_SCHEMA_VERSION],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    if already_present > 0 {
        // Axes are sticky once written; only refresh the engine-version trace.
        upsert_axis(conn, KEY_LAST_ENGINE_VERSION, CURRENT_ENGINE_VERSION)?;
        return Ok(false);
    }

    let (sql_v, hnsw_v, bm25_v) = if existing_install {
        (0, 0, 0)
    } else {
        (
            CURRENT_SQL_SCHEMA_VERSION,
            CURRENT_HNSW_FORMAT_VERSION,
            CURRENT_BM25_STATS_VERSION,
        )
    };

    info!(
        "[migration_meta] bootstrap: existing_install={}, sql={}, hnsw={}, bm25={}, fingerprint='{}', engine='{}'",
        existing_install, sql_v, hnsw_v, bm25_v, EMPTY_FINGERPRINT, CURRENT_ENGINE_VERSION
    );

    upsert_axis(conn, KEY_SQL_SCHEMA_VERSION, &sql_v.to_string())?;
    upsert_axis(conn, KEY_HNSW_FORMAT_VERSION, &hnsw_v.to_string())?;
    upsert_axis(conn, KEY_BM25_STATS_VERSION, &bm25_v.to_string())?;
    upsert_axis(conn, KEY_EMBEDDING_FINGERPRINT, EMPTY_FINGERPRINT)?;
    upsert_axis(conn, KEY_LAST_ENGINE_VERSION, CURRENT_ENGINE_VERSION)?;
    Ok(true)
}

fn assert_no_unknown_future_axes(axes: &MigrationAxes) -> Result<(), RagError> {
    fn check(axis: &str, stored: i64, supported: i64) -> Result<(), RagError> {
        if stored > supported {
            return Err(RagError::UnsupportedMigrationVersion(
                axis.to_string(),
                stored,
                supported,
            ));
        }
        Ok(())
    }
    check(
        KEY_SQL_SCHEMA_VERSION,
        axes.sql_schema_version,
        CURRENT_SQL_SCHEMA_VERSION,
    )?;
    check(
        KEY_HNSW_FORMAT_VERSION,
        axes.hnsw_format_version,
        CURRENT_HNSW_FORMAT_VERSION,
    )?;
    check(
        KEY_BM25_STATS_VERSION,
        axes.bm25_stats_version,
        CURRENT_BM25_STATS_VERSION,
    )?;
    Ok(())
}

/// Bootstrap or refresh `migration_meta` in a single transaction and return
/// the resulting axis snapshot. Called by `init_source_db`.
pub(crate) fn initialize_migration_meta(
    existing_install: bool,
) -> Result<MigrationAxes, RagError> {
    let mut conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let tx = conn
        .transaction()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    create_migration_meta_table(&tx)?;
    let bootstrapped = bootstrap_axes(&tx, existing_install)?;
    let axes = read_axes_with(&tx)?;
    assert_no_unknown_future_axes(&axes)?;

    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    info!(
        "[migration_meta] axes: sql={}, hnsw={}, bm25={}, fingerprint='{}', engine='{}' (bootstrapped={})",
        axes.sql_schema_version,
        axes.hnsw_format_version,
        axes.bm25_stats_version,
        axes.embedding_fingerprint,
        axes.last_engine_version,
        bootstrapped,
    );
    Ok(axes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::db_pool::{close_db_pool, init_db_pool};
    use std::sync::Mutex;

    // The connection pool is process-global, so serialize migration_meta tests
    // to keep `init_db_pool`/`close_db_pool` from racing across threads.
    static POOL_GUARD: Mutex<()> = Mutex::new(());

    struct PoolHandle {
        _dir: tempfile::TempDir,
        _guard: std::sync::MutexGuard<'static, ()>,
    }

    impl Drop for PoolHandle {
        fn drop(&mut self) {
            close_db_pool();
        }
    }

    fn fresh_pool() -> PoolHandle {
        let guard = POOL_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.sqlite");
        init_db_pool(path.to_string_lossy().to_string(), 2).unwrap();
        PoolHandle {
            _dir: dir,
            _guard: guard,
        }
    }

    fn precreate_chunks_table(path: &std::path::Path) {
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute("CREATE TABLE chunks(id INTEGER PRIMARY KEY)", [])
            .unwrap();
    }

    #[test]
    fn new_install_records_current_axes() {
        let pool = fresh_pool();
        let axes = initialize_migration_meta(false).unwrap();
        assert_eq!(axes.sql_schema_version, CURRENT_SQL_SCHEMA_VERSION);
        assert_eq!(axes.hnsw_format_version, CURRENT_HNSW_FORMAT_VERSION);
        assert_eq!(axes.bm25_stats_version, CURRENT_BM25_STATS_VERSION);
        assert_eq!(axes.embedding_fingerprint, EMPTY_FINGERPRINT);
        assert_eq!(axes.last_engine_version, CURRENT_ENGINE_VERSION);
        drop(pool);
    }

    #[test]
    fn existing_install_backfills_v0() {
        let _guard = POOL_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.sqlite");
        precreate_chunks_table(&path);
        init_db_pool(path.to_string_lossy().to_string(), 2).unwrap();

        let existing = {
            let conn = get_connection().unwrap();
            detect_existing_install(&conn).unwrap()
        };
        assert!(existing, "pre-existing chunks table must be detected");

        let axes = initialize_migration_meta(existing).unwrap();
        assert_eq!(axes.sql_schema_version, 0);
        assert_eq!(axes.hnsw_format_version, 0);
        assert_eq!(axes.bm25_stats_version, 0);
        assert_eq!(axes.embedding_fingerprint, EMPTY_FINGERPRINT);
        assert_eq!(axes.last_engine_version, CURRENT_ENGINE_VERSION);

        close_db_pool();
    }

    #[test]
    fn second_boot_does_not_overwrite_axes() {
        let pool = fresh_pool();
        let first = initialize_migration_meta(false).unwrap();
        {
            let conn = get_connection().unwrap();
            upsert_axis(&conn, KEY_SQL_SCHEMA_VERSION, "0").unwrap();
        }
        let second = initialize_migration_meta(true).unwrap();
        assert_eq!(
            second.sql_schema_version, 0,
            "axes must be sticky once persisted"
        );
        assert_eq!(first.last_engine_version, second.last_engine_version);
        drop(pool);
    }

    #[test]
    fn future_axis_rejects_boot() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        {
            let conn = get_connection().unwrap();
            upsert_axis(
                &conn,
                KEY_HNSW_FORMAT_VERSION,
                &(CURRENT_HNSW_FORMAT_VERSION + 1).to_string(),
            )
            .unwrap();
        }
        match initialize_migration_meta(true) {
            Err(RagError::UnsupportedMigrationVersion(axis, stored, supported)) => {
                assert_eq!(axis, KEY_HNSW_FORMAT_VERSION);
                assert_eq!(stored, CURRENT_HNSW_FORMAT_VERSION + 1);
                assert_eq!(supported, CURRENT_HNSW_FORMAT_VERSION);
            }
            other => panic!("expected UnsupportedMigrationVersion, got {:?}", other),
        }
        drop(pool);
    }
}

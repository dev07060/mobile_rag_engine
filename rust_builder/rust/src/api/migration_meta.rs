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
/// Set to the *target* fingerprint while a reembed is in flight; empty
/// otherwise. Lets boot detect a resumable reembed after an interrupted run.
pub const KEY_EMBEDDING_FINGERPRINT_PENDING: &str = "embedding_fingerprint_pending";
pub const KEY_LAST_ENGINE_VERSION: &str = "last_engine_version";

/// Sentinel value persisted before Phase P0-2 registers a real fingerprint.
pub const EMPTY_FINGERPRINT: &str = "";

/// Read-only snapshot of all migration axes plus the last engine version.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationAxes {
    pub sql_schema_version: i64,
    pub hnsw_format_version: i64,
    pub bm25_stats_version: i64,
    /// Empty string means "not yet registered" — the boot probe will populate
    /// it on the first model load via [`write_embedding_fingerprint`].
    pub embedding_fingerprint: String,
    /// Non-empty while a reembed-to-`<value>` is in flight; empty otherwise.
    pub embedding_fingerprint_pending: String,
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

fn read_axis_string_or_empty(conn: &Connection, key: &str) -> Result<String, RagError> {
    use rusqlite::OptionalExtension;
    let value: Option<String> = conn
        .query_row(
            "SELECT value FROM migration_meta WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| RagError::DatabaseError(format!("migration_meta read '{key}': {e}")))?;
    Ok(value.unwrap_or_default())
}

pub(crate) fn read_axes_with(conn: &Connection) -> Result<MigrationAxes, RagError> {
    Ok(MigrationAxes {
        sql_schema_version: read_axis_int(conn, KEY_SQL_SCHEMA_VERSION)?,
        hnsw_format_version: read_axis_int(conn, KEY_HNSW_FORMAT_VERSION)?,
        bm25_stats_version: read_axis_int(conn, KEY_BM25_STATS_VERSION)?,
        embedding_fingerprint: read_axis_string(conn, KEY_EMBEDDING_FINGERPRINT)?,
        // Pending axis may be missing on installs that booted under P0-1; treat
        // a missing row as "no reembed pending" rather than a hard error.
        embedding_fingerprint_pending: read_axis_string_or_empty(
            conn,
            KEY_EMBEDDING_FINGERPRINT_PENDING,
        )?,
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

/// Insert `(key, value)` only when the key is absent. Existing rows are left
/// untouched — axes are sticky once written.
fn insert_axis_if_absent(
    conn: &Connection,
    key: &str,
    value: &str,
) -> Result<bool, RagError> {
    let changed = conn
        .execute(
            "INSERT INTO migration_meta(key, value)
             VALUES (?1, ?2)
             ON CONFLICT(key) DO NOTHING",
            params![key, value],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(changed > 0)
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
        // Axes are sticky once written; only refresh the engine-version trace
        // and backfill any axis keys introduced after this install's first boot.
        upsert_axis(conn, KEY_LAST_ENGINE_VERSION, CURRENT_ENGINE_VERSION)?;
        insert_axis_if_absent(conn, KEY_EMBEDDING_FINGERPRINT_PENDING, EMPTY_FINGERPRINT)?;
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
        "[migration_meta] bootstrap: existing_install={}, sql={}, hnsw={}, bm25={}, fingerprint='{}', pending='{}', engine='{}'",
        existing_install,
        sql_v,
        hnsw_v,
        bm25_v,
        EMPTY_FINGERPRINT,
        EMPTY_FINGERPRINT,
        CURRENT_ENGINE_VERSION
    );

    upsert_axis(conn, KEY_SQL_SCHEMA_VERSION, &sql_v.to_string())?;
    upsert_axis(conn, KEY_HNSW_FORMAT_VERSION, &hnsw_v.to_string())?;
    upsert_axis(conn, KEY_BM25_STATS_VERSION, &bm25_v.to_string())?;
    upsert_axis(conn, KEY_EMBEDDING_FINGERPRINT, EMPTY_FINGERPRINT)?;
    upsert_axis(conn, KEY_EMBEDDING_FINGERPRINT_PENDING, EMPTY_FINGERPRINT)?;
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

/// Describes whether the on-device embedding store is compatible with the
/// currently loaded model. Returned by [`detect_embedding_fingerprint_gate`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EmbeddingFingerprintGate {
    /// No fingerprint persisted yet; caller should write the current one
    /// before serving any requests. First-ever boot.
    RequiresInitialBaseline,
    /// Stored fingerprint matches `current_fingerprint`; safe to proceed.
    Ok,
    /// Stored fingerprint differs from `current_fingerprint`; reads and
    /// writes MUST be locked until either reembed completes or the user
    /// explicitly confirms a clear-and-restart.
    Mismatch {
        stored: String,
        current: String,
        /// Number of chunk rows still tagged with a non-current fingerprint.
        /// Useful for surfacing a "resume from N%" UI without an extra
        /// round-trip to count chunks.
        remaining_chunks: i64,
        /// True when `embedding_fingerprint_pending` already equals
        /// `current_fingerprint` — i.e. a reembed was previously started and
        /// can simply continue without a fresh user confirmation.
        resume_in_progress: bool,
    },
}

/// Inspect `migration_meta` against the currently loaded model fingerprint.
///
/// This call only **reads** state — it never mutates `embedding_fingerprint`
/// nor deletes embeddings. The caller is responsible for routing the gate
/// state to the user (Apply, Rebuild, Invalidate decisions per the data
/// migration plan).
pub fn detect_embedding_fingerprint_gate(
    current_fingerprint: String,
) -> Result<EmbeddingFingerprintGate, RagError> {
    if current_fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "current_fingerprint must be non-empty".to_string(),
        ));
    }
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let stored = read_axis_string(&conn, KEY_EMBEDDING_FINGERPRINT)?;
    let pending = read_axis_string_or_empty(&conn, KEY_EMBEDDING_FINGERPRINT_PENDING)?;

    if stored.is_empty() {
        return Ok(EmbeddingFingerprintGate::RequiresInitialBaseline);
    }
    if stored == current_fingerprint {
        return Ok(EmbeddingFingerprintGate::Ok);
    }

    let remaining = count_chunks_with_non_matching_fingerprint(&conn, &current_fingerprint)?;
    let resume_in_progress = !pending.is_empty() && pending == current_fingerprint;
    Ok(EmbeddingFingerprintGate::Mismatch {
        stored,
        current: current_fingerprint,
        remaining_chunks: remaining,
        resume_in_progress,
    })
}

fn count_chunks_with_non_matching_fingerprint(
    conn: &Connection,
    target: &str,
) -> Result<i64, RagError> {
    conn.query_row(
        "SELECT COUNT(*) FROM chunks
         WHERE COALESCE(embedding_fingerprint, '') <> ?1",
        params![target],
        |row| row.get(0),
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))
}

/// Record the engine's current model fingerprint as the persisted baseline.
///
/// Only callable when no baseline is present yet — i.e. when the previous
/// [`detect_embedding_fingerprint_gate`] returned
/// [`EmbeddingFingerprintGate::RequiresInitialBaseline`]. After this call,
/// every existing chunk is tagged as belonging to `fingerprint` so future
/// mismatches can compute `remaining_chunks` accurately.
///
/// Refuses to overwrite a non-empty baseline. Use the reembed/clear flows
/// to rotate an existing fingerprint instead.
pub fn write_embedding_fingerprint(fingerprint: String) -> Result<(), RagError> {
    if fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "fingerprint must be non-empty".to_string(),
        ));
    }
    let mut conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let tx = conn
        .transaction()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let stored = read_axis_string(&tx, KEY_EMBEDDING_FINGERPRINT)?;
    if !stored.is_empty() && stored != fingerprint {
        return Err(RagError::InvalidInput(format!(
            "embedding_fingerprint already set to '{stored}'; use the reembed \
             or clear-and-restart flows to rotate it (refusing to overwrite)"
        )));
    }
    upsert_axis(&tx, KEY_EMBEDDING_FINGERPRINT, &fingerprint)?;
    // Backfill chunks so future mismatch detection counts accurately.
    tx.execute(
        "UPDATE chunks
         SET embedding_fingerprint = ?1
         WHERE COALESCE(embedding_fingerprint, '') = ''",
        params![fingerprint],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    info!(
        "[migration_meta] embedding_fingerprint baseline set to '{}'",
        fingerprint
    );
    Ok(())
}

/// Begin a reembed-to-`target_fingerprint` flow.
///
/// Writes `embedding_fingerprint_pending = target_fingerprint` (sticky across
/// reboots, so the flow is resumable) and returns the number of chunks that
/// still need re-embedding. Idempotent — calling it again with the same
/// target is safe.
pub fn begin_embedding_reembed(target_fingerprint: String) -> Result<i64, RagError> {
    if target_fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "target_fingerprint must be non-empty".to_string(),
        ));
    }
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let pending = read_axis_string_or_empty(&conn, KEY_EMBEDDING_FINGERPRINT_PENDING)?;
    if !pending.is_empty() && pending != target_fingerprint {
        return Err(RagError::InvalidInput(format!(
            "reembed already pending towards '{pending}'; cannot retarget to \
             '{target_fingerprint}'"
        )));
    }
    upsert_axis(&conn, KEY_EMBEDDING_FINGERPRINT_PENDING, &target_fingerprint)?;
    let remaining = count_chunks_with_non_matching_fingerprint(&conn, &target_fingerprint)?;
    info!(
        "[migration_meta] reembed started: target='{}', remaining_chunks={}",
        target_fingerprint, remaining
    );
    Ok(remaining)
}

/// Count chunks still tagged with anything other than `target_fingerprint`.
///
/// Reads only — safe to call during progress polling.
pub fn count_chunks_needing_reembed(target_fingerprint: String) -> Result<i64, RagError> {
    if target_fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "target_fingerprint must be non-empty".to_string(),
        ));
    }
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    count_chunks_with_non_matching_fingerprint(&conn, &target_fingerprint)
}

/// Commit a completed reembed atomically.
///
/// Refuses to commit when any chunk still carries a non-matching fingerprint,
/// guarding against accidentally promoting `embedding_fingerprint` past a
/// partially completed run. On success: `embedding_fingerprint = target`,
/// `embedding_fingerprint_pending = ""`.
pub fn finalize_embedding_reembed(target_fingerprint: String) -> Result<(), RagError> {
    if target_fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "target_fingerprint must be non-empty".to_string(),
        ));
    }
    let mut conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let tx = conn
        .transaction()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let remaining = count_chunks_with_non_matching_fingerprint(&tx, &target_fingerprint)?;
    if remaining > 0 {
        return Err(RagError::InvalidInput(format!(
            "cannot finalize reembed: {remaining} chunk(s) still carry a \
             non-target fingerprint"
        )));
    }
    upsert_axis(&tx, KEY_EMBEDDING_FINGERPRINT, &target_fingerprint)?;
    upsert_axis(&tx, KEY_EMBEDDING_FINGERPRINT_PENDING, EMPTY_FINGERPRINT)?;
    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    info!(
        "[migration_meta] reembed finalized: stored='{}', pending=''",
        target_fingerprint
    );
    Ok(())
}

/// Magic confirmation string that callers must pass to
/// [`acknowledge_and_clear_embeddings`] to opt into destructive deletion.
/// The Dart facade wraps this behind a typed confirmation parameter so the
/// destructive choice is explicit at the call site.
pub const EMBEDDING_CLEAR_CONFIRMATION: &str =
    "I_UNDERSTAND_THIS_DELETES_ALL_ON_DEVICE_EMBEDDINGS";

/// Discard every chunk row (and therefore every embedding BLOB) for sources
/// the user has accepted as lost, then reset the fingerprint axes.
///
/// Refuses to do anything unless `confirmation` exactly equals
/// [`EMBEDDING_CLEAR_CONFIRMATION`]. This is the only public path that may
/// drop user embeddings; it must never be reachable from passive flows.
///
/// The `sources` rows are kept so the user can re-ingest them through the
/// normal ingestion path; only `chunks` (which hold the embeddings) are
/// removed.
pub fn acknowledge_and_clear_embeddings(
    confirmation: String,
    new_fingerprint: String,
) -> Result<i64, RagError> {
    if confirmation != EMBEDDING_CLEAR_CONFIRMATION {
        return Err(RagError::InvalidInput(
            "refusing to clear embeddings: confirmation token missing or \
             does not match EMBEDDING_CLEAR_CONFIRMATION"
                .to_string(),
        ));
    }
    if new_fingerprint.is_empty() {
        return Err(RagError::InvalidInput(
            "new_fingerprint must be non-empty when clearing embeddings"
                .to_string(),
        ));
    }
    let mut conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let tx = conn
        .transaction()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let deleted = tx
        .execute("DELETE FROM chunks", [])
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    upsert_axis(&tx, KEY_EMBEDDING_FINGERPRINT, &new_fingerprint)?;
    upsert_axis(&tx, KEY_EMBEDDING_FINGERPRINT_PENDING, EMPTY_FINGERPRINT)?;
    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    info!(
        "[migration_meta] embeddings cleared with confirmation; deleted={} chunks, new fingerprint='{}'",
        deleted, new_fingerprint
    );
    Ok(deleted as i64)
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

    fn provision_chunks_table() {
        let conn = get_connection().unwrap();
        conn.execute(
            "CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY,
                content TEXT NOT NULL,
                embedding BLOB,
                embedding_fingerprint TEXT
            )",
            [],
        )
        .unwrap();
    }

    fn insert_chunk(content: &str, fingerprint: Option<&str>) -> i64 {
        let conn = get_connection().unwrap();
        conn.execute(
            "INSERT INTO chunks(content, embedding, embedding_fingerprint)
             VALUES (?1, ?2, ?3)",
            rusqlite::params![content, vec![0u8; 4], fingerprint],
        )
        .unwrap();
        conn.last_insert_rowid()
    }

    #[test]
    fn new_install_records_current_axes() {
        let pool = fresh_pool();
        let axes = initialize_migration_meta(false).unwrap();
        assert_eq!(axes.sql_schema_version, CURRENT_SQL_SCHEMA_VERSION);
        assert_eq!(axes.hnsw_format_version, CURRENT_HNSW_FORMAT_VERSION);
        assert_eq!(axes.bm25_stats_version, CURRENT_BM25_STATS_VERSION);
        assert_eq!(axes.embedding_fingerprint, EMPTY_FINGERPRINT);
        assert_eq!(axes.embedding_fingerprint_pending, EMPTY_FINGERPRINT);
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
        assert_eq!(axes.embedding_fingerprint_pending, EMPTY_FINGERPRINT);
        assert_eq!(axes.last_engine_version, CURRENT_ENGINE_VERSION);

        close_db_pool();
    }

    #[test]
    fn p0_1_install_backfills_pending_axis() {
        // Simulate a database that booted under P0-1 (no pending axis key).
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        {
            let conn = get_connection().unwrap();
            conn.execute(
                "DELETE FROM migration_meta WHERE key = ?1",
                params![KEY_EMBEDDING_FINGERPRINT_PENDING],
            )
            .unwrap();
        }
        let axes = initialize_migration_meta(true).unwrap();
        assert_eq!(
            axes.embedding_fingerprint_pending, EMPTY_FINGERPRINT,
            "missing pending axis must be silently backfilled to empty"
        );
        drop(pool);
    }

    #[test]
    fn gate_requires_baseline_on_empty_fingerprint() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        let gate = detect_embedding_fingerprint_gate("model|384|f32".to_string()).unwrap();
        assert!(matches!(gate, EmbeddingFingerprintGate::RequiresInitialBaseline));
        drop(pool);
    }

    #[test]
    fn gate_ok_when_stored_matches_current() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        provision_chunks_table();
        write_embedding_fingerprint("model|384|f32".to_string()).unwrap();
        let gate = detect_embedding_fingerprint_gate("model|384|f32".to_string()).unwrap();
        assert!(matches!(gate, EmbeddingFingerprintGate::Ok));
        drop(pool);
    }

    #[test]
    fn gate_mismatch_reports_remaining_chunks() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        provision_chunks_table();
        write_embedding_fingerprint("old|384|f32".to_string()).unwrap();
        insert_chunk("c1", Some("old|384|f32"));
        insert_chunk("c2", Some("old|384|f32"));

        let gate = detect_embedding_fingerprint_gate("new|384|f32".to_string()).unwrap();
        match gate {
            EmbeddingFingerprintGate::Mismatch {
                stored,
                current,
                remaining_chunks,
                resume_in_progress,
            } => {
                assert_eq!(stored, "old|384|f32");
                assert_eq!(current, "new|384|f32");
                assert_eq!(remaining_chunks, 2);
                assert!(!resume_in_progress);
            }
            other => panic!("expected Mismatch, got {:?}", other),
        }
        drop(pool);
    }

    #[test]
    fn reembed_lifecycle_progresses_and_finalizes() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        provision_chunks_table();
        write_embedding_fingerprint("old".to_string()).unwrap();
        let c1 = insert_chunk("alpha", Some("old"));
        let c2 = insert_chunk("beta", Some("old"));

        let remaining = begin_embedding_reembed("new".to_string()).unwrap();
        assert_eq!(remaining, 2);

        // Resume signal becomes visible after begin_embedding_reembed.
        match detect_embedding_fingerprint_gate("new".to_string()).unwrap() {
            EmbeddingFingerprintGate::Mismatch {
                resume_in_progress, ..
            } => assert!(resume_in_progress),
            other => panic!("expected Mismatch, got {:?}", other),
        }

        // Tag the chunks one at a time and watch the remaining count drop.
        {
            let conn = get_connection().unwrap();
            conn.execute(
                "UPDATE chunks SET embedding_fingerprint = 'new' WHERE id = ?1",
                params![c1],
            )
            .unwrap();
        }
        assert_eq!(count_chunks_needing_reembed("new".to_string()).unwrap(), 1);

        // Finalize before completion must fail.
        match finalize_embedding_reembed("new".to_string()) {
            Err(RagError::InvalidInput(msg)) => {
                assert!(msg.contains("1 chunk"), "got: {msg}")
            }
            other => panic!("expected InvalidInput, got {:?}", other),
        }

        {
            let conn = get_connection().unwrap();
            conn.execute(
                "UPDATE chunks SET embedding_fingerprint = 'new' WHERE id = ?1",
                params![c2],
            )
            .unwrap();
        }
        finalize_embedding_reembed("new".to_string()).unwrap();
        let axes = read_migration_axes().unwrap();
        assert_eq!(axes.embedding_fingerprint, "new");
        assert_eq!(axes.embedding_fingerprint_pending, EMPTY_FINGERPRINT);
        drop(pool);
    }

    #[test]
    fn clear_requires_confirmation_token() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        provision_chunks_table();
        write_embedding_fingerprint("old".to_string()).unwrap();
        insert_chunk("alpha", Some("old"));

        match acknowledge_and_clear_embeddings("NOPE".to_string(), "new".to_string()) {
            Err(RagError::InvalidInput(msg)) => {
                assert!(msg.contains("confirmation"), "got: {msg}")
            }
            other => panic!("expected InvalidInput, got {:?}", other),
        }
        // Chunk must still exist after a refused clear — destructive paths
        // are gated behind the explicit confirmation token only.
        let conn = get_connection().unwrap();
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM chunks", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
        drop(pool);
    }

    #[test]
    fn clear_with_confirmation_wipes_chunks_and_rotates_axis() {
        let pool = fresh_pool();
        initialize_migration_meta(false).unwrap();
        provision_chunks_table();
        write_embedding_fingerprint("old".to_string()).unwrap();
        insert_chunk("alpha", Some("old"));
        insert_chunk("beta", Some("old"));

        let deleted = acknowledge_and_clear_embeddings(
            EMBEDDING_CLEAR_CONFIRMATION.to_string(),
            "new".to_string(),
        )
        .unwrap();
        assert_eq!(deleted, 2);
        let axes = read_migration_axes().unwrap();
        assert_eq!(axes.embedding_fingerprint, "new");
        assert_eq!(axes.embedding_fingerprint_pending, EMPTY_FINGERPRINT);
        drop(pool);
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

// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Licensed under the MIT License. You may obtain a copy of the License at
// https://opensource.org/licenses/MIT
//
// This software is provided "AS IS", without warranty of any kind, express or
// implied, including but not limited to the warranties of merchantability,
// fitness for a particular purpose, and noninfringement. In no event shall the
// authors or copyright holders be liable for any claim, damages, or other
// liability arising from the use of this software.
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.
//
//! Extended RAG API with sources and chunks for LLM-optimized context.

use crate::api::bm25_search::{bm25_add_documents, bm25_clear_index, is_bm25_index_loaded};
use crate::api::db_pool::get_connection;
use crate::api::error::RagError;
use crate::api::ingest_metrics::{
    legacy_counters_enabled, LEGACY_ADD_CHUNKS_IN, LEGACY_ADD_SOURCE_IN,
};
use crate::api::hnsw_index::{
    build_hnsw_index, clear_hnsw_index, is_hnsw_index_loaded, load_hnsw_index, save_hnsw_index,
    search_hnsw,
};
use crate::api::hybrid_search::{search_hybrid_meta_inner, RrfConfig, SearchFilter};
use crate::api::migration_meta::{detect_existing_install, initialize_migration_meta};
use crate::api::query_metrics::{
    record_hydrated_content_read, QueryContentReadGuard, QueryContentReadPhase,
};
use crate::api::tokenizer::count_plain_text_tokens_untruncated;
use crate::api::vector_math::{cosine_with_query_norm_f32, decode_f32_embedding, l2_norm_f32};
#[cfg(feature = "vector_quant_i8")]
use crate::api::vector_quant::{
    cosine_with_query_norm_i8_blob, dequantize_i8_to_f32, i8_vec_from_blob, l2_norm_i8,
    quantize_f32_to_i8, quantize_f32_to_u8_blob,
};
use crate::frb_generated::RustAutoOpaqueMoi as RustAutoOpaque;
use flutter_rust_bridge::frb;
use log::{debug, info};
use once_cell::sync::Lazy;
use regex::Regex;
use rusqlite::{params, OptionalExtension};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, RwLock};

pub const DEFAULT_COLLECTION_ID: &str = "__default__";

static ACTIVE_HNSW_COLLECTION: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));
static ACTIVE_BM25_COLLECTION: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));
static QUERY_TERM_SPLITTER: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"[\s\(\)\[\]\{\},.!?:;/|_\-]+"#).expect("valid query splitter regex")
});
static CJK_OR_HANGUL_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7A3]"#)
        .expect("valid cjk regex")
});

#[cfg(test)]
static SEARCH_META_TEST_HOOK: Lazy<RwLock<Option<fn()>>> = Lazy::new(|| RwLock::new(None));
#[cfg(test)]
static HANDLE_HYDRATION_TEST_HOOK: Lazy<RwLock<Option<fn()>>> = Lazy::new(|| RwLock::new(None));
#[cfg(test)]
static HANDLE_ASSEMBLE_TEST_HOOK: Lazy<RwLock<Option<fn()>>> = Lazy::new(|| RwLock::new(None));

fn hash_content(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn normalize_collection_id(collection_id: String) -> String {
    let trimmed = collection_id.trim();
    if trimmed.is_empty() {
        DEFAULT_COLLECTION_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

fn decode_structured_chunk_type(chunk_type: &str) -> (&str, Option<&str>) {
    let Some(separator) = chunk_type.find('|') else {
        return (chunk_type, None);
    };

    let raw_type = &chunk_type[..separator];
    let header_path = chunk_type[separator + 1..].trim();
    (
        raw_type,
        if header_path.is_empty() {
            None
        } else {
            Some(header_path)
        },
    )
}

fn render_context_text(content: &str, chunk_type: &str) -> String {
    let (_, header_path) = decode_structured_chunk_type(chunk_type);
    match header_path {
        Some(path) => format!("Header Path: {path}\n{content}"),
        None => content.to_string(),
    }
}

fn truncate_utf8_bytes(input: &str, max_bytes: usize) -> String {
    if input.len() <= max_bytes {
        return input.to_string();
    }

    let mut end = max_bytes.min(input.len());
    while end > 0 && !input.is_char_boundary(end) {
        end -= 1;
    }
    input[..end].to_string()
}

/// Build a `String` from a byte buffer that may end mid–UTF-8 character
/// (typical when SQLite returns `substr(CAST(content AS BLOB), 1, N)`).
/// The trailing partial codepoint is dropped; the result is a prefix of
/// the original UTF-8 string.
fn utf8_string_from_blob_prefix(mut bytes: Vec<u8>) -> String {
    let valid_up_to = match std::str::from_utf8(&bytes) {
        Ok(_) => bytes.len(),
        Err(err) => err.valid_up_to(),
    };
    bytes.truncate(valid_up_to);
    // SAFETY: bytes[..valid_up_to] is guaranteed valid UTF-8.
    String::from_utf8(bytes).expect("byte prefix validated as UTF-8")
}

fn get_collection_data_generation(
    conn: &rusqlite::Connection,
    collection_id: &str,
) -> Result<i64, RagError> {
    ensure_collection_row(conn, collection_id)?;
    conn.query_row(
        "SELECT data_generation FROM collection_index_state WHERE collection_id = ?1",
        params![collection_id],
        |row| row.get(0),
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))
}

fn ensure_collection_row(conn: &rusqlite::Connection, collection_id: &str) -> Result<(), RagError> {
    conn.execute(
        "INSERT OR IGNORE INTO collections(id, name) VALUES (?1, ?2)",
        params![collection_id, collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    conn.execute(
        "INSERT OR IGNORE INTO collection_index_state(collection_id, hnsw_dirty, bm25_dirty)
         VALUES (?1, 1, 1)",
        params![collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn mark_collection_dirty(conn: &rusqlite::Connection, collection_id: &str) -> Result<(), RagError> {
    ensure_collection_row(conn, collection_id)?;
    conn.execute(
        "UPDATE collection_index_state
         SET hnsw_dirty = 1,
             bm25_dirty = 1,
             last_error = NULL
         WHERE collection_id = ?1",
        params![collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn mark_collection_data_changed(
    conn: &rusqlite::Connection,
    collection_id: &str,
) -> Result<(), RagError> {
    ensure_collection_row(conn, collection_id)?;
    conn.execute(
        "UPDATE collection_index_state
         SET hnsw_dirty = 1,
             bm25_dirty = 1,
             data_generation = data_generation + 1,
             last_error = NULL
         WHERE collection_id = ?1",
        params![collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn mark_collection_hnsw_clean(
    conn: &rusqlite::Connection,
    collection_id: &str,
) -> Result<(), RagError> {
    ensure_collection_row(conn, collection_id)?;
    conn.execute(
        "UPDATE collection_index_state
         SET hnsw_dirty = 0,
             last_hnsw_built_at = strftime('%s', 'now'),
             last_error = NULL
         WHERE collection_id = ?1",
        params![collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn mark_collection_bm25_clean(
    conn: &rusqlite::Connection,
    collection_id: &str,
) -> Result<(), RagError> {
    ensure_collection_row(conn, collection_id)?;
    conn.execute(
        "UPDATE collection_index_state
         SET bm25_dirty = 0,
             last_bm25_built_at = strftime('%s', 'now'),
             last_error = NULL
         WHERE collection_id = ?1",
        params![collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(())
}

fn set_active_hnsw_collection(collection_id: &str) {
    let mut guard = ACTIVE_HNSW_COLLECTION.write().unwrap();
    *guard = Some(collection_id.to_string());
}

fn set_active_bm25_collection(collection_id: &str) {
    let mut guard = ACTIVE_BM25_COLLECTION.write().unwrap();
    *guard = Some(collection_id.to_string());
}

fn is_active_hnsw_collection(collection_id: &str) -> bool {
    let guard = ACTIVE_HNSW_COLLECTION.read().unwrap();
    guard.as_deref() == Some(collection_id)
}

fn is_active_bm25_collection(collection_id: &str) -> bool {
    let guard = ACTIVE_BM25_COLLECTION.read().unwrap();
    guard.as_deref() == Some(collection_id)
}

/// Initialize database with sources and chunks tables.
pub fn init_source_db() -> Result<(), RagError> {
    info!("[init_source_db] Initializing database tables");
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;

    // Detect upgrade-from-pre-axis installs BEFORE any `CREATE TABLE` runs,
    // otherwise the new install vs upgrade distinction is lost. We then ask
    // the migration_meta module to bootstrap or refresh the four axes and
    // reject boot if the persisted schema is newer than this build knows.
    let existing_install = detect_existing_install(&conn)?;
    drop(conn); // initialize_migration_meta opens its own transaction.
    let _axes = initialize_migration_meta(existing_install)?;

    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS sources (
            id INTEGER PRIMARY KEY,
            content TEXT NOT NULL,
            content_hash TEXT UNIQUE,
            metadata TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            name TEXT
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY,
            source_id INTEGER NOT NULL,
            collection_id TEXT NOT NULL DEFAULT '__default__',
            chunk_index INTEGER NOT NULL,
            content TEXT NOT NULL,
            start_pos INTEGER NOT NULL,
            end_pos INTEGER NOT NULL,
            chunk_type TEXT DEFAULT 'general',
            embedding BLOB NOT NULL,
            embedding_i8 BLOB,
            embedding_scale REAL,
            FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    // Migration: Add chunk_type if missing
    let has_chunk_type: bool = conn
        .prepare("SELECT chunk_type FROM chunks LIMIT 1")
        .is_ok();
    if !has_chunk_type {
        info!("[init_source_db] Migrating: adding chunk_type column");
        conn.execute(
            "ALTER TABLE chunks ADD COLUMN chunk_type TEXT DEFAULT 'general'",
            [],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    // Migration: Add name if missing
    let has_name: bool = conn.prepare("SELECT name FROM sources LIMIT 1").is_ok();
    if !has_name {
        info!("[init_source_db] Migrating: adding name column to sources");
        conn.execute("ALTER TABLE sources ADD COLUMN name TEXT", [])
            .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    // Migration: Add status if missing
    let has_status: bool = conn.prepare("SELECT status FROM sources LIMIT 1").is_ok();
    if !has_status {
        info!("[init_source_db] Migrating: adding status column to sources");
        // Default to 'completed' for existing sources (backward compatibility)
        conn.execute(
            "ALTER TABLE sources ADD COLUMN status TEXT DEFAULT 'completed'",
            [],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    // Migration: Add collection_id to sources if missing
    let has_source_collection_id: bool = conn
        .prepare("SELECT collection_id FROM sources LIMIT 1")
        .is_ok();
    if !has_source_collection_id {
        info!("[init_source_db] Migrating: adding collection_id to sources");
        conn.execute(
            "ALTER TABLE sources ADD COLUMN collection_id TEXT NOT NULL DEFAULT '__default__'",
            [],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    // Migration: Add collection_id to chunks if missing
    let has_chunk_collection_id: bool = conn
        .prepare("SELECT collection_id FROM chunks LIMIT 1")
        .is_ok();
    if !has_chunk_collection_id {
        info!("[init_source_db] Migrating: adding collection_id to chunks");
        conn.execute(
            "ALTER TABLE chunks ADD COLUMN collection_id TEXT NOT NULL DEFAULT '__default__'",
            [],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    let has_chunk_embedding_i8: bool = conn
        .prepare("SELECT embedding_i8 FROM chunks LIMIT 1")
        .is_ok();
    if !has_chunk_embedding_i8 {
        info!("[init_source_db] Migrating: adding embedding_i8 to chunks");
        conn.execute("ALTER TABLE chunks ADD COLUMN embedding_i8 BLOB", [])
            .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    let has_chunk_embedding_scale: bool = conn
        .prepare("SELECT embedding_scale FROM chunks LIMIT 1")
        .is_ok();
    if !has_chunk_embedding_scale {
        info!("[init_source_db] Migrating: adding embedding_scale to chunks");
        conn.execute("ALTER TABLE chunks ADD COLUMN embedding_scale REAL", [])
            .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    #[cfg(feature = "vector_quant_i8")]
    {
        let mut stmt = conn.prepare(
            "SELECT id, embedding FROM chunks WHERE embedding_i8 IS NULL OR embedding_scale IS NULL",
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
        let rows: Vec<(i64, Vec<u8>)> = stmt
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(|e| RagError::DatabaseError(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();

        for (id, embedding_blob) in rows {
            let Some(embedding) = decode_f32_embedding(&embedding_blob) else {
                continue;
            };
            if embedding.is_empty() {
                continue;
            }
            let (embedding_i8_bytes, embedding_scale) = quantize_f32_to_u8_blob(&embedding);
            conn.execute(
                "UPDATE chunks SET embedding_i8 = ?1, embedding_scale = ?2 WHERE id = ?3",
                params![embedding_i8_bytes, embedding_scale, id],
            )
            .map_err(|e| RagError::DatabaseError(e.to_string()))?;
        }
    }

    conn.execute(
        "CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            name TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS collection_index_state (
            collection_id TEXT PRIMARY KEY,
            hnsw_dirty INTEGER NOT NULL DEFAULT 1,
            bm25_dirty INTEGER NOT NULL DEFAULT 1,
            data_generation INTEGER NOT NULL DEFAULT 0,
            last_hnsw_built_at INTEGER,
            last_bm25_built_at INTEGER,
            last_error TEXT
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let has_data_generation: bool = conn
        .prepare("SELECT data_generation FROM collection_index_state LIMIT 1")
        .is_ok();
    if !has_data_generation {
        info!("[init_source_db] Migrating: adding data_generation to collection_index_state");
        conn.execute(
            "ALTER TABLE collection_index_state ADD COLUMN data_generation INTEGER NOT NULL DEFAULT 0",
            [],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    conn.execute(
        "INSERT OR IGNORE INTO collections(id, name) VALUES (?1, 'default')",
        params![DEFAULT_COLLECTION_ID],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    // Backfill chunk.collection_id from source.collection_id when upgrading older DBs.
    conn.execute(
        "UPDATE chunks
         SET collection_id = (
            SELECT s.collection_id FROM sources s WHERE s.id = chunks.source_id
         )
         WHERE collection_id = '__default__'
           AND EXISTS (SELECT 1 FROM sources s WHERE s.id = chunks.source_id)",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_chunks_source_id ON chunks(source_id)",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_sources_collection_id ON sources(collection_id)",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_chunks_collection_source_index
         ON chunks(collection_id, source_id, chunk_index)",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    ensure_collection_row(&conn, DEFAULT_COLLECTION_ID)?;

    info!("[init_source_db] Tables created");
    Ok(())
}

#[derive(Debug, Clone)]
pub struct AddSourceResult {
    pub source_id: i64,
    pub is_duplicate: bool,
    pub chunk_count: i32,
    pub message: String,
}

/// Add a source document (chunks added separately via add_chunks).
pub fn add_source(
    content: String,
    metadata: Option<String>,
    name: Option<String>,
) -> Result<AddSourceResult, RagError> {
    add_source_in_collection(DEFAULT_COLLECTION_ID.to_string(), content, metadata, name)
}

/// Add a source document to a specific collection (chunks added separately via add_chunks).
pub fn add_source_in_collection(
    collection_id: String,
    content: String,
    metadata: Option<String>,
    name: Option<String>,
) -> Result<AddSourceResult, RagError> {
    if legacy_counters_enabled() {
        LEGACY_ADD_SOURCE_IN.record(content.len() as u64);
    }
    let collection_id = normalize_collection_id(collection_id);
    info!(
        "[add_source_in_collection] collection={}, chars={}, name={:?}",
        collection_id,
        content.len(),
        name
    );

    // Preserve global UNIQUE(content_hash) compatibility while scoping dedupe by collection.
    let scoped_hash = hash_content(&format!("{}:{}", collection_id, content));
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    ensure_collection_row(&conn, &collection_id)?;

    let existing: Option<i64> = conn
        .query_row(
            "SELECT id FROM sources WHERE collection_id = ?1 AND content_hash = ?2",
            params![collection_id, scoped_hash],
            |row| row.get(0),
        )
        .ok();

    if let Some(id) = existing {
        info!("[add_source_in_collection] Duplicate found: {}", id);
        return Ok(AddSourceResult {
            source_id: id,
            is_duplicate: true,
            chunk_count: 0,
            message: format!("Source already exists (id={})", id),
        });
    }

    // New sources start as 'pending'
    conn.execute(
        "INSERT INTO sources (content, content_hash, metadata, name, status, collection_id)
         VALUES (?1, ?2, ?3, ?4, 'pending', ?5)",
        params![content, scoped_hash, metadata, name, collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let source_id = conn.last_insert_rowid();
    mark_collection_data_changed(&conn, &collection_id)?;
    info!("[add_source_in_collection] Created source: {}", source_id);

    Ok(AddSourceResult {
        source_id,
        is_duplicate: false,
        chunk_count: 0,
        message: "Source created".to_string(),
    })
}

/// Update processing status of a source (e.g., 'pending', 'processing', 'completed', 'failed').
pub fn update_source_status(source_id: i64, status: String) -> Result<(), RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let collection_id: Option<String> = conn
        .query_row(
            "SELECT collection_id FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let updated = conn
        .execute(
            "UPDATE sources SET status = ?1 WHERE id = ?2",
            params![status, source_id],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    if updated > 0 {
        if let Some(collection_id) = collection_id {
            mark_collection_data_changed(&conn, &collection_id)?;
        }
    }
    info!(
        "[update_source_status] Updated source {} to status '{}'",
        source_id, status
    );
    Ok(())
}

/// Claim a source for ingestion by atomically transitioning status to `processing`.
///
/// Returns true when claimed successfully. Only `pending` and `failed` sources
/// can be claimed. Sources already in `processing`/`completed` return false.
pub fn claim_source_for_ingestion(source_id: i64) -> Result<bool, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let collection_id: Option<String> = conn
        .query_row(
            "SELECT collection_id FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let updated = conn
        .execute(
            "UPDATE sources
             SET status = 'processing'
             WHERE id = ?1
               AND COALESCE(status, 'completed') IN ('pending', 'failed')",
            params![source_id],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    if updated > 0 {
        if let Some(collection_id) = collection_id {
            mark_collection_data_changed(&conn, &collection_id)?;
        }
    }
    Ok(updated > 0)
}

/// Get status of a source.
///
/// Returns `Ok(None)` if source does not exist or has NULL status.
pub fn get_source_status(source_id: i64) -> Result<Option<String>, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let status: Option<String> = conn
        .query_row(
            "SELECT status FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .flatten();
    Ok(status)
}

/// Delete all chunks for a source while keeping the source row.
///
/// Returns number of deleted chunks.
pub fn clear_source_chunks(source_id: i64) -> Result<i32, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let source_collection_id: Option<String> = conn
        .query_row(
            "SELECT collection_id FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let deleted = conn
        .execute(
            "DELETE FROM chunks WHERE source_id = ?1",
            params![source_id],
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    if deleted > 0 {
        if let Some(collection_id) = source_collection_id {
            mark_collection_data_changed(&conn, &collection_id)?;
        }
    }
    Ok(deleted as i32)
}

#[derive(Debug, Clone)]
pub struct SourceEntry {
    pub id: i64,
    pub name: Option<String>,
    pub created_at: i64,
    pub metadata: Option<String>,
    pub status: Option<String>,
    pub collection_id: String,
}

pub fn list_sources() -> Result<Vec<SourceEntry>, RagError> {
    list_sources_in_collection(DEFAULT_COLLECTION_ID.to_string())
}

pub fn list_sources_in_collection(collection_id: String) -> Result<Vec<SourceEntry>, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    // Coalesce null status to 'completed' for legacy rows if any remains (though strict migration sets default)
    let mut stmt = conn
        .prepare(
            "SELECT id, name, created_at, metadata, status, collection_id
             FROM sources
             WHERE collection_id = ?1
             ORDER BY id DESC",
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let sources = stmt
        .query_map(params![collection_id], |row| {
            Ok(SourceEntry {
                id: row.get(0)?,
                name: row.get(1)?,
                created_at: row.get(2)?,
                metadata: row.get(3)?,
                status: row.get(4)?,
                collection_id: row.get(5)?,
            })
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .collect();

    Ok(sources)
}

#[derive(Debug, Clone)]
pub struct ChunkData {
    pub content: String,
    pub chunk_index: i32,
    pub start_pos: i32,
    pub end_pos: i32,
    pub chunk_type: String,
    pub embedding: Vec<f32>,
}

/// Add chunks for a source (uses transaction for atomicity).
pub fn add_chunks(source_id: i64, chunks: Vec<ChunkData>) -> Result<i32, RagError> {
    if legacy_counters_enabled() {
        LEGACY_ADD_CHUNKS_IN
            .record(chunks.iter().map(|c| c.content.len() as u64).sum());
    }
    info!(
        "[add_chunks] Adding {} chunks for source {}",
        chunks.len(),
        source_id
    );

    let mut conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let tx = conn
        .transaction()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let source_collection_id: String = tx
        .query_row(
            "SELECT collection_id FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let has_chunk_embedding_i8: bool = tx
        .prepare("SELECT embedding_i8 FROM chunks LIMIT 1")
        .is_ok();
    let has_chunk_embedding_scale: bool = tx
        .prepare("SELECT embedding_scale FROM chunks LIMIT 1")
        .is_ok();

    for chunk in &chunks {
        let mut embedding_bytes: Vec<u8> = Vec::with_capacity(chunk.embedding.len() * 4);
        for f in &chunk.embedding {
            embedding_bytes.extend_from_slice(&f.to_ne_bytes());
        }

        #[cfg(feature = "vector_quant_i8")]
        {
            let (embedding_i8_bytes, embedding_scale) =
                quantize_f32_to_u8_blob(&chunk.embedding);

            if has_chunk_embedding_i8 && has_chunk_embedding_scale {
                tx.execute(
                    "INSERT INTO chunks (source_id, collection_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding, embedding_i8, embedding_scale)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                    params![
                        source_id,
                        source_collection_id,
                        chunk.chunk_index,
                        chunk.content,
                        chunk.start_pos,
                        chunk.end_pos,
                        chunk.chunk_type,
                        embedding_bytes,
                        embedding_i8_bytes,
                        embedding_scale
                    ],
                )
                .map_err(|e| RagError::DatabaseError(e.to_string()))?;
            } else {
                tx.execute(
                    "INSERT INTO chunks (source_id, collection_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    params![
                        source_id,
                        source_collection_id,
                        chunk.chunk_index,
                        chunk.content,
                        chunk.start_pos,
                        chunk.end_pos,
                        chunk.chunk_type,
                        embedding_bytes
                    ],
                )
                .map_err(|e| RagError::DatabaseError(e.to_string()))?;
            }
        }

        #[cfg(not(feature = "vector_quant_i8"))]
        {
            let _ = (has_chunk_embedding_i8, has_chunk_embedding_scale);
            tx.execute(
                "INSERT INTO chunks (source_id, collection_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    source_id,
                    source_collection_id,
                    chunk.chunk_index,
                    chunk.content,
                    chunk.start_pos,
                    chunk.end_pos,
                    chunk.chunk_type,
                    embedding_bytes
                ],
            )
            .map_err(|e| RagError::DatabaseError(e.to_string()))?;
        }
    }

    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    mark_collection_data_changed(&conn, &source_collection_id)?;
    info!("[add_chunks] Added {} chunks", chunks.len());
    Ok(chunks.len() as i32)
}

/// Rebuild HNSW index from chunks table.
pub fn rebuild_chunk_hnsw_index() -> Result<(), RagError> {
    rebuild_chunk_hnsw_index_for_collection(DEFAULT_COLLECTION_ID.to_string())
}

/// Rebuild HNSW index from chunks table for a specific collection.
pub fn rebuild_chunk_hnsw_index_for_collection(collection_id: String) -> Result<(), RagError> {
    let collection_id = normalize_collection_id(collection_id);
    info!(
        "[rebuild_chunk_hnsw] Starting for collection={}",
        collection_id
    );
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    ensure_collection_row(&conn, &collection_id)?;

    let has_chunk_embedding_i8: bool = conn
        .prepare("SELECT embedding_i8 FROM chunks LIMIT 1")
        .is_ok();
    let has_chunk_embedding_scale: bool = conn
        .prepare("SELECT embedding_scale FROM chunks LIMIT 1")
        .is_ok();
    let mut stmt = if has_chunk_embedding_i8 && has_chunk_embedding_scale {
        conn.prepare(
            "SELECT c.id, c.embedding, c.embedding_i8, c.embedding_scale
             FROM chunks c
             JOIN sources s ON s.id = c.source_id
             WHERE c.collection_id = ?1
               AND COALESCE(s.status, 'completed') = 'completed'",
        )
    } else {
        conn.prepare(
            "SELECT c.id, c.embedding, NULL AS embedding_i8, NULL AS embedding_scale
             FROM chunks c
             JOIN sources s ON s.id = c.source_id
             WHERE c.collection_id = ?1
               AND COALESCE(s.status, 'completed') = 'completed'",
        )
    }
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let points: Vec<(i64, Vec<f32>)> = stmt
        .query_map(params![collection_id], |row| {
            let id: i64 = row.get(0)?;
            let embedding_blob: Vec<u8> = row.get(1)?;
            let embedding_i8_blob: Option<Vec<u8>> = row.get(2)?;
            let embedding_scale: Option<f32> = row.get(3)?;

            #[cfg(feature = "vector_quant_i8")]
            let embedding = if let (Some(qblob), Some(scale)) =
                (embedding_i8_blob.as_deref(), embedding_scale)
            {
                let quantized = i8_vec_from_blob(qblob);
                let restored = dequantize_i8_to_f32(&quantized, scale);
                if restored.is_empty() {
                    decode_f32_embedding(&embedding_blob).unwrap_or_default()
                } else {
                    restored
                }
            } else {
                decode_f32_embedding(&embedding_blob).unwrap_or_default()
            };

            #[cfg(not(feature = "vector_quant_i8"))]
            let embedding = {
                let _ = (embedding_i8_blob, embedding_scale);
                decode_f32_embedding(&embedding_blob).unwrap_or_default()
            };
            Ok((id, embedding))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .filter(|(_, embedding)| !embedding.is_empty())
        .collect();

    if points.is_empty() {
        clear_hnsw_index();
    } else {
        build_hnsw_index(points).map_err(|e| RagError::InternalError(e.to_string()))?;
        info!("[rebuild_chunk_hnsw] Built index for {}", collection_id);
    }
    set_active_hnsw_collection(&collection_id);
    mark_collection_hnsw_clean(&conn, &collection_id)?;
    Ok(())
}

/// Rebuild BM25 index from chunks table.
pub fn rebuild_chunk_bm25_index() -> Result<(), RagError> {
    rebuild_chunk_bm25_index_for_collection(DEFAULT_COLLECTION_ID.to_string())
}

/// Rebuild BM25 index from chunks table for a specific collection.
pub fn rebuild_chunk_bm25_index_for_collection(collection_id: String) -> Result<(), RagError> {
    let collection_id = normalize_collection_id(collection_id);
    info!(
        "[rebuild_chunk_bm25] Starting for collection={}",
        collection_id
    );
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    ensure_collection_row(&conn, &collection_id)?;

    // Clear existing BM25 index
    bm25_clear_index();

    let mut stmt = conn
        .prepare(
            "SELECT c.id, c.content
             FROM chunks c
             JOIN sources s ON s.id = c.source_id
             WHERE c.collection_id = ?1
               AND COALESCE(s.status, 'completed') = 'completed'",
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let docs: Vec<(i64, String)> = stmt
        .query_map(params![collection_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .collect();

    if !docs.is_empty() {
        info!(
            "[rebuild_chunk_bm25] Building index from {} chunks",
            docs.len()
        );
        bm25_add_documents(docs);
    }
    set_active_bm25_collection(&collection_id);
    mark_collection_bm25_clean(&conn, &collection_id)?;
    info!("[rebuild_chunk_bm25] Complete");
    Ok(())
}

/// Check if BM25 index is loaded for chunks.
pub fn is_chunk_bm25_index_loaded() -> bool {
    is_bm25_index_loaded()
}

/// Save currently loaded HNSW index for a collection.
pub fn save_collection_hnsw_index(
    collection_id: String,
    base_path: String,
) -> Result<(), RagError> {
    let collection_id = normalize_collection_id(collection_id);
    save_hnsw_index(&base_path).map_err(|e| RagError::IoError(e.to_string()))?;
    set_active_hnsw_collection(&collection_id);
    Ok(())
}

/// Load HNSW index from disk and mark the collection as active.
pub fn load_collection_hnsw_index(
    collection_id: String,
    base_path: String,
) -> Result<bool, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let loaded = load_hnsw_index(&base_path).map_err(|e| RagError::IoError(e.to_string()))?;
    if loaded {
        set_active_hnsw_collection(&collection_id);
        let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
        let _ = mark_collection_hnsw_clean(&conn, &collection_id);
    }
    Ok(loaded)
}

/// Ensure the in-memory hybrid search indexes are switched to the target collection.
///
/// BM25 is rebuilt for the collection when not active, and HNSW is loaded (or rebuilt)
/// from the collection-specific path as needed.
pub fn activate_collection_for_hybrid_search(
    collection_id: String,
    base_path: String,
) -> Result<(), RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    ensure_collection_row(&conn, &collection_id)?;

    if !is_bm25_index_loaded() || !is_active_bm25_collection(&collection_id) {
        rebuild_chunk_bm25_index_for_collection(collection_id.clone())?;
    }

    if !is_hnsw_index_loaded() || !is_active_hnsw_collection(&collection_id) {
        let loaded = load_hnsw_index(&base_path).map_err(|e| RagError::IoError(e.to_string()))?;
        if loaded {
            set_active_hnsw_collection(&collection_id);
            let _ = mark_collection_hnsw_clean(&conn, &collection_id);
        } else {
            rebuild_chunk_hnsw_index_for_collection(collection_id.clone())?;
            save_hnsw_index(&base_path).map_err(|e| RagError::IoError(e.to_string()))?;
        }
    }

    Ok(())
}

#[derive(Debug, Clone)]
pub struct SearchMetaHybridOptions {
    pub top_k: u32,
    pub vector_weight: f64,
    pub bm25_weight: f64,
    pub source_ids: Option<Vec<i64>>,
    pub adjacent_chunks: i32,
}

#[derive(Debug, Clone)]
pub struct SearchHitMeta {
    pub chunk_id: i64,
    pub source_id: i64,
    pub chunk_index: i32,
    pub similarity: f64,
    pub raw_type: String,
    pub header_path_preview: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ChunkExcerptResult {
    pub chunk_id: i64,
    pub source_id: i64,
    pub chunk_index: i32,
    pub raw_type: String,
    pub header_path_preview: Option<String>,
    pub excerpt: String,
}

#[derive(Debug, Clone, Copy)]
pub enum ContextAssemblyStrategy {
    RelevanceFirst,
    DiverseSources,
    Chronological,
}

#[derive(Debug, Clone)]
pub struct AssembleContextOptions {
    pub token_budget: i32,
    pub strategy: ContextAssemblyStrategy,
    pub separator: String,
    pub single_source_mode: bool,
}

#[derive(Debug, Clone)]
pub struct AssembledContextV2 {
    pub text: String,
    pub exact_tokens: u32,
    pub included_chunk_ids: Vec<i64>,
    pub remaining_budget: i32,
    pub selected_source_id: Option<i64>,
}

#[derive(Debug, Clone)]
struct HydratedChunkRow {
    chunk_id: i64,
    source_id: i64,
    chunk_index: i32,
    content: String,
    chunk_type: String,
    similarity: f64,
    metadata: Option<String>,
}

#[frb(opaque)]
#[derive(Debug, Clone)]
pub struct SearchHandle {
    collection_id: String,
    data_generation: i64,
    query_text: String,
    base_hits: Vec<SearchHitMeta>,
    ordered_hits: Vec<SearchHitMeta>,
    _query_options: SearchMetaHybridOptions,
    /// Per-handle full-content cache shared across `assemble_context`,
    /// `hydrate_chunks`, and `get_chunk_excerpts`. The first call that
    /// pulls full chunk content for a chunk_id populates the entry; the
    /// subsequent calls on the same handle return from cache without
    /// hitting SQLite. Bounded reads (preview SUBSTR) intentionally do
    /// not populate the cache because the content is truncated. The
    /// handle's `data_generation` guard keeps the cache coherent —
    /// any mutation to the underlying collection invalidates the whole
    /// handle, the cache is discarded with it.
    content_cache: Arc<Mutex<HashMap<i64, ChunkSearchResult>>>,
}

impl SearchHandle {
    fn ensure_fresh_with_conn(&self, conn: &rusqlite::Connection) -> Result<i64, RagError> {
        let current_generation = get_collection_data_generation(&conn, &self.collection_id)?;
        if current_generation != self.data_generation {
            return Err(RagError::StaleSearchHandle(format!(
                "collection={} expected_generation={} current_generation={}",
                self.collection_id, self.data_generation, current_generation
            )));
        }
        Ok(current_generation)
    }

    fn ensure_generation_unchanged_with_conn(
        &self,
        conn: &rusqlite::Connection,
        start_generation: i64,
    ) -> Result<(), RagError> {
        let end_generation = get_collection_data_generation(conn, &self.collection_id)?;
        if end_generation != start_generation {
            return Err(RagError::ConcurrentMutation(format!(
                "collection={} changed during search handle operation start_generation={} end_generation={}",
                self.collection_id, start_generation, end_generation
            )));
        }
        Ok(())
    }

    fn allowed_chunk_ids(&self) -> HashSet<i64> {
        self.ordered_hits.iter().map(|hit| hit.chunk_id).collect()
    }

    fn resolved_chunk_ids(&self, chunk_ids: Vec<i64>) -> Vec<i64> {
        if chunk_ids.is_empty() {
            self.ordered_hits.iter().map(|hit| hit.chunk_id).collect()
        } else {
            chunk_ids
        }
    }

    fn validate_requested_chunk_ids(&self, chunk_ids: Vec<i64>) -> Result<Vec<i64>, RagError> {
        let allowed = self.allowed_chunk_ids();
        let requested_ids = self.resolved_chunk_ids(chunk_ids);
        let mut seen = HashSet::new();

        if let Some(duplicate) = requested_ids
            .iter()
            .find(|chunk_id| !seen.insert(**chunk_id))
        {
            return Err(RagError::InvalidInput(format!(
                "duplicate chunk_ids are not allowed: {}",
                duplicate
            )));
        }

        if let Some(missing) = requested_ids
            .iter()
            .find(|chunk_id| !allowed.contains(chunk_id))
        {
            return Err(RagError::InvalidInput(format!(
                "chunk_id {} is not part of this search handle",
                missing
            )));
        }

        Ok(requested_ids)
    }
}

#[frb]
impl SearchHandle {
    pub fn hit_meta(&self) -> Result<Vec<SearchHitMeta>, RagError> {
        let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
        self.ensure_fresh_with_conn(&conn)?;
        Ok(self.ordered_hits.clone())
    }

    pub fn hydrate_chunks(&self, chunk_ids: Vec<i64>) -> Result<Vec<ChunkSearchResult>, RagError> {
        let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
        let start_generation = self.ensure_fresh_with_conn(&conn)?;
        let requested_ids = self.validate_requested_chunk_ids(chunk_ids)?;
        run_handle_hydration_test_hook();

        let _read_guard = QueryContentReadGuard::enter(QueryContentReadPhase::FullHydrate);

        // Cache check: any chunk whose full content was already pulled by
        // a previous call on this handle (typically `assemble_context`)
        // returns from the cache and bypasses SQLite entirely.
        let (from_cache, missing) = partition_by_cache(&self.content_cache, &requested_ids);

        let (newly_fetched, stale_missing) = hydrate_chunk_search_results(
            &conn,
            &self.collection_id,
            missing,
            &self.ordered_hits,
        )?;
        self.ensure_generation_unchanged_with_conn(&conn, start_generation)?;
        if let Some(missing) = stale_missing.first() {
            return Err(RagError::StaleSearchHandle(format!(
                "chunk_id {} disappeared while hydrating search results",
                missing
            )));
        }
        populate_cache(&self.content_cache, &newly_fetched);

        let mut by_id: HashMap<i64, ChunkSearchResult> = from_cache
            .into_iter()
            .map(|c| (c.chunk_id, c))
            .collect();
        for chunk in newly_fetched {
            by_id.insert(chunk.chunk_id, chunk);
        }
        let mut ordered = Vec::with_capacity(requested_ids.len());
        for id in requested_ids {
            if let Some(chunk) = by_id.remove(&id) {
                ordered.push(chunk);
            }
        }
        Ok(ordered)
    }

    pub fn get_chunk_excerpts(
        &self,
        chunk_ids: Vec<i64>,
        max_bytes: u32,
    ) -> Result<Vec<ChunkExcerptResult>, RagError> {
        let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
        let start_generation = self.ensure_fresh_with_conn(&conn)?;
        let requested_ids = self.validate_requested_chunk_ids(chunk_ids)?;
        run_handle_hydration_test_hook();

        let _read_guard = QueryContentReadGuard::enter(QueryContentReadPhase::Preview);

        // Cache check: chunks whose full content is already in the cache
        // are truncated in Rust and surfaced without any SQLite read. The
        // bounded SUBSTR path runs only for the remaining ids, and its
        // truncated rows are intentionally NOT inserted into the cache
        // (would corrupt later full-hydrate calls).
        let (from_cache, missing) = partition_by_cache(&self.content_cache, &requested_ids);

        let (newly_fetched, stale_missing) = hydrate_chunk_previews(
            &conn,
            &self.collection_id,
            missing,
            &self.ordered_hits,
            max_bytes,
        )?;
        self.ensure_generation_unchanged_with_conn(&conn, start_generation)?;
        if let Some(missing) = stale_missing.first() {
            return Err(RagError::StaleSearchHandle(format!(
                "chunk_id {} disappeared while hydrating search results",
                missing
            )));
        }

        let mut by_id: HashMap<i64, ChunkSearchResult> = from_cache
            .into_iter()
            .map(|c| (c.chunk_id, c))
            .collect();
        for chunk in newly_fetched {
            by_id.insert(chunk.chunk_id, chunk);
        }

        Ok(requested_ids
            .into_iter()
            .filter_map(|id| {
                let chunk = by_id.remove(&id)?;
                let (raw_type, header_path) = decode_structured_chunk_type(&chunk.chunk_type);
                Some(ChunkExcerptResult {
                    chunk_id: chunk.chunk_id,
                    source_id: chunk.source_id,
                    chunk_index: chunk.chunk_index,
                    raw_type: raw_type.to_string(),
                    header_path_preview: header_path.map(|path| truncate_utf8_bytes(path, 256)),
                    excerpt: truncate_utf8_bytes(&chunk.content, max_bytes as usize),
                })
            })
            .collect())
    }

    pub fn assemble_context(
        &self,
        options: AssembleContextOptions,
    ) -> Result<AssembledContextV2, RagError> {
        let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
        let start_generation = self.ensure_fresh_with_conn(&conn)?;
        let built = assemble_context_internal(&conn, self, options)?;
        run_handle_assemble_test_hook();
        self.ensure_generation_unchanged_with_conn(&conn, start_generation)?;
        match built {
            AssemblyBuildResult::Complete(context) => Ok(context),
            AssemblyBuildResult::MissingChunks(missing_ids) => {
                let missing = missing_ids.first().copied().unwrap_or_default();
                Err(RagError::StaleSearchHandle(format!(
                    "chunk_id {} disappeared while assembling context",
                    missing
                )))
            }
        }
    }

    pub fn dispose(self) {}
}

pub fn search_meta_hybrid(
    collection_id: String,
    query_text: String,
    query_embedding: Vec<f32>,
    options: SearchMetaHybridOptions,
) -> Result<RustAutoOpaque<SearchHandle>, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let mut last_error = None;

    // Borrow the inputs across retry attempts so a transient
    // ConcurrentMutation does not force per-attempt clones of the
    // 1.5KB+ query embedding (and matching String/options copies).
    // `search_meta_hybrid_once` constructs the owned `SearchHandle`
    // payload internally, cloning only what the handle actually stores.
    for _attempt in 0..=1 {
        match search_meta_hybrid_once(
            &collection_id,
            &query_text,
            &query_embedding,
            &options,
        ) {
            Ok(handle) => return Ok(RustAutoOpaque::new(handle)),
            Err(err @ RagError::ConcurrentMutation(_)) => last_error = Some(err),
            Err(err) => return Err(err),
        }
    }

    Err(last_error.unwrap_or_else(|| {
        RagError::ConcurrentMutation(
            "search metadata creation raced with a concurrent mutation".to_string(),
        )
    }))
}

#[cfg(test)]
fn run_search_meta_test_hook() {
    if let Some(hook) = *SEARCH_META_TEST_HOOK.read().unwrap() {
        hook();
    }
}

#[cfg(not(test))]
fn run_search_meta_test_hook() {}

#[cfg(test)]
fn run_handle_hydration_test_hook() {
    if let Some(hook) = *HANDLE_HYDRATION_TEST_HOOK.read().unwrap() {
        hook();
    }
}

#[cfg(not(test))]
fn run_handle_hydration_test_hook() {}

#[cfg(test)]
fn run_handle_assemble_test_hook() {
    if let Some(hook) = *HANDLE_ASSEMBLE_TEST_HOOK.read().unwrap() {
        hook();
    }
}

#[cfg(not(test))]
fn run_handle_assemble_test_hook() {}

fn build_search_hit_meta(
    chunk_id: i64,
    source_id: i64,
    chunk_index: i32,
    similarity: f64,
    stored_chunk_type: &str,
) -> SearchHitMeta {
    let (raw_type, header_path) = decode_structured_chunk_type(stored_chunk_type);
    SearchHitMeta {
        chunk_id,
        source_id,
        chunk_index,
        similarity,
        raw_type: raw_type.to_string(),
        header_path_preview: header_path.map(|path| truncate_utf8_bytes(path, 256)),
    }
}

fn fetch_stored_chunk_types(
    conn: &rusqlite::Connection,
    collection_id: &str,
    chunk_ids: &[i64],
) -> Result<HashMap<i64, String>, RagError> {
    if chunk_ids.is_empty() {
        return Ok(HashMap::new());
    }

    let id_list = chunk_ids
        .iter()
        .map(|id| id.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!(
        "SELECT id, COALESCE(chunk_type, 'general')
         FROM chunks
         WHERE collection_id = ?1
           AND id IN ({id_list})"
    );

    let mut stmt = conn
        .prepare(&sql)
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let rows = stmt
        .query_map(params![collection_id], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut map = HashMap::new();
    for row in rows {
        let (chunk_id, chunk_type) = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;
        map.insert(chunk_id, chunk_type);
    }
    Ok(map)
}

fn fetch_adjacent_hit_meta(
    conn: &rusqlite::Connection,
    collection_id: &str,
    source_id: i64,
    min_index: i32,
    max_index: i32,
) -> Result<Vec<SearchHitMeta>, RagError> {
    let mut stmt = conn
        .prepare(
            "SELECT id, source_id, chunk_index, COALESCE(chunk_type, 'general')
             FROM chunks
             WHERE collection_id = ?1
               AND source_id = ?2
               AND chunk_index >= ?3
               AND chunk_index <= ?4
             ORDER BY chunk_index",
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let rows = stmt
        .query_map(
            params![collection_id, source_id, min_index, max_index],
            |row| {
                let chunk_id: i64 = row.get(0)?;
                let source_id: i64 = row.get(1)?;
                let chunk_index: i32 = row.get(2)?;
                let chunk_type: String = row.get(3)?;
                Ok(build_search_hit_meta(
                    chunk_id,
                    source_id,
                    chunk_index,
                    0.0,
                    &chunk_type,
                ))
            },
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut hits = Vec::new();
    for row in rows {
        hits.push(row.map_err(|e| RagError::DatabaseError(e.to_string()))?);
    }
    Ok(hits)
}

fn search_meta_hybrid_once(
    collection_id: &str,
    query_text: &str,
    query_embedding: &[f32],
    options: &SearchMetaHybridOptions,
) -> Result<SearchHandle, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let start_generation = get_collection_data_generation(&conn, collection_id)?;

    let effective_top_k = if options
        .source_ids
        .as_ref()
        .map(|ids| !ids.is_empty())
        .unwrap_or(false)
    {
        (options.top_k.saturating_mul(10)).clamp(50, 200)
    } else {
        options.top_k
    };

    let hybrid_results = search_hybrid_meta_inner(
        query_text.to_string(),
        query_embedding,
        effective_top_k,
        Some(RrfConfig {
            k: 60,
            vector_weight: options.vector_weight.clamp(0.0, 1.0),
            bm25_weight: options.bm25_weight.clamp(0.0, 1.0),
        }),
        Some(SearchFilter {
            source_ids: options.source_ids.clone(),
            metadata_like: None,
            collection_id: Some(collection_id.to_string()),
        }),
    )?;

    let base_results = hybrid_results
        .into_iter()
        .take(options.top_k as usize)
        .collect::<Vec<_>>();
    let base_chunk_ids = base_results
        .iter()
        .map(|result| result.doc_id)
        .collect::<Vec<_>>();
    let stored_chunk_types = fetch_stored_chunk_types(&conn, collection_id, &base_chunk_ids)?;

    let mut base_hits = Vec::new();
    for result in base_results {
        let stored_chunk_type = stored_chunk_types
            .get(&result.doc_id)
            .cloned()
            .unwrap_or_else(|| "general".to_string());
        base_hits.push(build_search_hit_meta(
            result.doc_id,
            result.source_id,
            result.chunk_index as i32,
            result.score,
            &stored_chunk_type,
        ));
    }

    let ordered_hits = if options.adjacent_chunks > 0 && !base_hits.is_empty() {
        let mut expanded = HashMap::<(i64, i32), SearchHitMeta>::new();
        for hit in &base_hits {
            expanded.insert((hit.source_id, hit.chunk_index), hit.clone());
        }

        for hit in &base_hits {
            let min_index = (hit.chunk_index - options.adjacent_chunks).max(0);
            let max_index = hit.chunk_index + options.adjacent_chunks;
            for adjacent in
                fetch_adjacent_hit_meta(&conn, collection_id, hit.source_id, min_index, max_index)?
            {
                expanded
                    .entry((adjacent.source_id, adjacent.chunk_index))
                    .or_insert(adjacent);
            }
        }

        let mut hits = expanded.into_values().collect::<Vec<_>>();
        hits.sort_by(|a, b| {
            a.source_id
                .cmp(&b.source_id)
                .then_with(|| a.chunk_index.cmp(&b.chunk_index))
        });
        hits
    } else {
        base_hits.clone()
    };

    run_search_meta_test_hook();

    let end_generation = get_collection_data_generation(&conn, collection_id)?;
    if end_generation != start_generation {
        return Err(RagError::ConcurrentMutation(format!(
            "collection={} changed while creating search handle",
            collection_id
        )));
    }

    Ok(SearchHandle {
        collection_id: collection_id.to_string(),
        data_generation: start_generation,
        query_text: query_text.to_string(),
        base_hits,
        ordered_hits,
        _query_options: options.clone(),
        content_cache: Arc::new(Mutex::new(HashMap::new())),
    })
}

/// Split `requested_ids` into rows already present in the handle's
/// content cache and chunk ids that still need a SQLite fetch. The
/// lock is held only long enough to clone matched entries out.
fn partition_by_cache(
    cache: &Mutex<HashMap<i64, ChunkSearchResult>>,
    requested_ids: &[i64],
) -> (Vec<ChunkSearchResult>, Vec<i64>) {
    let guard = cache.lock().expect("content_cache mutex poisoned");
    let mut from_cache = Vec::new();
    let mut missing = Vec::new();
    for &id in requested_ids {
        match guard.get(&id) {
            Some(cached) => from_cache.push(cached.clone()),
            None => missing.push(id),
        }
    }
    (from_cache, missing)
}

/// Insert newly-fetched full-content rows into the cache. `or_insert_with`
/// keeps the first writer's value if two calls race for the same id.
fn populate_cache(
    cache: &Mutex<HashMap<i64, ChunkSearchResult>>,
    rows: &[ChunkSearchResult],
) {
    let mut guard = cache.lock().expect("content_cache mutex poisoned");
    for row in rows {
        guard
            .entry(row.chunk_id)
            .or_insert_with(|| row.clone());
    }
}

fn hydrate_chunk_search_results(
    conn: &rusqlite::Connection,
    collection_id: &str,
    chunk_ids: Vec<i64>,
    hits: &[SearchHitMeta],
) -> Result<(Vec<ChunkSearchResult>, Vec<i64>), RagError> {
    if chunk_ids.is_empty() {
        return Ok((Vec::new(), Vec::new()));
    }

    let hit_by_id = hits
        .iter()
        .map(|hit| (hit.chunk_id, hit))
        .collect::<HashMap<_, _>>();
    let id_list = chunk_ids
        .iter()
        .map(|id| id.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), s.metadata
         FROM chunks c
         LEFT JOIN sources s ON c.source_id = s.id
         WHERE c.collection_id = ?1
           AND c.id IN ({id_list})"
    );

    let mut stmt = conn
        .prepare(&sql)
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let rows = stmt
        .query_map(params![collection_id], |row| {
            Ok(ChunkSearchResult {
                chunk_id: row.get(0)?,
                source_id: row.get(1)?,
                chunk_index: row.get(2)?,
                content: row.get(3)?,
                chunk_type: row.get(4)?,
                similarity: 0.0,
                metadata: row.get(5)?,
            })
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut hydrated_by_id = HashMap::new();
    for row in rows {
        let mut hydrated = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;
        record_hydrated_content_read(hydrated.content.len() as u64);
        if let Some(hit) = hit_by_id.get(&hydrated.chunk_id) {
            hydrated.similarity = hit.similarity;
        }
        hydrated_by_id.insert(hydrated.chunk_id, hydrated);
    }

    let mut ordered = Vec::with_capacity(chunk_ids.len());
    let mut missing_ids = Vec::new();
    for chunk_id in chunk_ids {
        if let Some(chunk) = hydrated_by_id.remove(&chunk_id) {
            ordered.push(chunk);
        } else {
            missing_ids.push(chunk_id);
        }
    }
    Ok((ordered, missing_ids))
}

/// Preview-only variant of [`hydrate_chunk_search_results`] that bounds
/// the per-row SQLite content read to `max_bytes`. Uses
/// `substr(CAST(c.content AS BLOB), 1, ?)` so the bound is byte-exact
/// (TEXT substr in SQLite indexes by character, which could overshoot
/// for multi-byte UTF-8). The trailing partial codepoint is dropped in
/// Rust via `utf8_string_from_blob_prefix`. The `sources` LEFT JOIN is
/// skipped because the only preview consumer (`ChunkExcerptResult`)
/// does not surface `metadata`.
fn hydrate_chunk_previews(
    conn: &rusqlite::Connection,
    collection_id: &str,
    chunk_ids: Vec<i64>,
    hits: &[SearchHitMeta],
    max_bytes: u32,
) -> Result<(Vec<ChunkSearchResult>, Vec<i64>), RagError> {
    if chunk_ids.is_empty() {
        return Ok((Vec::new(), Vec::new()));
    }

    let hit_by_id = hits
        .iter()
        .map(|hit| (hit.chunk_id, hit))
        .collect::<HashMap<_, _>>();
    let id_list = chunk_ids
        .iter()
        .map(|id| id.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!(
        "SELECT c.id, c.source_id, c.chunk_index,
                substr(CAST(c.content AS BLOB), 1, ?2),
                COALESCE(c.chunk_type, 'general')
         FROM chunks c
         WHERE c.collection_id = ?1
           AND c.id IN ({id_list})"
    );

    let mut stmt = conn
        .prepare(&sql)
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let max_bytes_i64 = max_bytes as i64;
    let rows = stmt
        .query_map(params![collection_id, max_bytes_i64], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i32>(2)?,
                row.get::<_, Vec<u8>>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut hydrated_by_id = HashMap::new();
    for row in rows {
        let (chunk_id, source_id, chunk_index, preview_bytes, chunk_type) =
            row.map_err(|e| RagError::DatabaseError(e.to_string()))?;
        record_hydrated_content_read(preview_bytes.len() as u64);
        let content = utf8_string_from_blob_prefix(preview_bytes);
        let mut hydrated = ChunkSearchResult {
            chunk_id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            similarity: 0.0,
            metadata: None,
        };
        if let Some(hit) = hit_by_id.get(&hydrated.chunk_id) {
            hydrated.similarity = hit.similarity;
        }
        hydrated_by_id.insert(hydrated.chunk_id, hydrated);
    }

    let mut ordered = Vec::with_capacity(chunk_ids.len());
    let mut missing_ids = Vec::new();
    for chunk_id in chunk_ids {
        if let Some(chunk) = hydrated_by_id.remove(&chunk_id) {
            ordered.push(chunk);
        } else {
            missing_ids.push(chunk_id);
        }
    }
    Ok((ordered, missing_ids))
}

fn extract_significant_query_terms(query: &str) -> Vec<String> {
    let mut terms = Vec::new();
    let mut seen = HashSet::new();
    for part in QUERY_TERM_SPLITTER.split(query) {
        let term = part.trim();
        if term.is_empty() {
            continue;
        }
        if !CJK_OR_HANGUL_RE.is_match(term) && term.chars().count() < 2 {
            continue;
        }
        let normalized = term.to_lowercase();
        if seen.insert(normalized.clone()) {
            terms.push(normalized);
        }
    }
    terms
}

fn filter_to_most_relevant_source(chunks: &[HydratedChunkRow], query: &str) -> Option<i64> {
    if chunks.is_empty() {
        return None;
    }

    let query_lower = query.to_lowercase();
    let query_terms = extract_significant_query_terms(query);
    let mut source_text_matches = HashMap::<i64, i32>::new();

    for chunk in chunks {
        let content_lower = chunk.content.to_lowercase();
        let mut match_count = 0;
        for term in &query_terms {
            if content_lower.contains(term) {
                match_count += 1;
            }
        }
        if content_lower.contains(&query_lower) || chunk.content.contains(query) {
            match_count += 100;
        }

        *source_text_matches.entry(chunk.source_id).or_insert(0) += match_count;
    }

    if let Some((source_id, best_match_count)) = source_text_matches
        .into_iter()
        .max_by_key(|(_, score)| *score)
    {
        if best_match_count > 0 {
            return Some(source_id);
        }
    }

    chunks
        .iter()
        .fold(HashMap::<i64, f64>::new(), |mut acc, chunk| {
            *acc.entry(chunk.source_id).or_insert(0.0) += chunk.similarity;
            acc
        })
        .into_iter()
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
        .map(|(source_id, _)| source_id)
}

fn diversify_sources(chunks: Vec<HydratedChunkRow>) -> Vec<HydratedChunkRow> {
    let mut diverse = Vec::new();
    let mut remaining = chunks;
    let mut last_source_id = None;

    while !remaining.is_empty() {
        if let Some(index) = remaining
            .iter()
            .position(|chunk| Some(chunk.source_id) != last_source_id)
        {
            let chunk = remaining.remove(index);
            last_source_id = Some(chunk.source_id);
            diverse.push(chunk);
        } else {
            diverse.extend(remaining.into_iter());
            break;
        }
    }

    diverse
}

fn order_chronologically(mut chunks: Vec<HydratedChunkRow>) -> Vec<HydratedChunkRow> {
    chunks.sort_by(|a, b| {
        a.source_id
            .cmp(&b.source_id)
            .then_with(|| a.chunk_index.cmp(&b.chunk_index))
    });
    chunks
}

struct RenderedSelectionState {
    separator: String,
    skip_headers: bool,
    chunk_text_cache: HashMap<i64, String>,
    token_count_cache: HashMap<String, u32>,
    selected_in_order: Vec<HydratedChunkRow>,
    source_order: Vec<i64>,
    selected_by_source: HashMap<i64, Vec<HydratedChunkRow>>,
    rendered_source_blocks: HashMap<i64, String>,
    rendered_text: String,
    measured_tokens: u32,
}

impl RenderedSelectionState {
    fn new(separator: String, skip_headers: bool) -> Self {
        Self {
            separator,
            skip_headers,
            chunk_text_cache: HashMap::new(),
            token_count_cache: HashMap::new(),
            selected_in_order: Vec::new(),
            source_order: Vec::new(),
            selected_by_source: HashMap::new(),
            rendered_source_blocks: HashMap::new(),
            rendered_text: String::new(),
            measured_tokens: 0,
        }
    }

    fn try_add_chunk(
        &mut self,
        chunk: &HydratedChunkRow,
        token_budget: i32,
    ) -> Result<bool, RagError> {
        let candidate_text = if self.skip_headers {
            self.render_candidate_without_headers(chunk)
        } else {
            self.render_candidate_with_headers(chunk)
        };
        let candidate_tokens = self.count_tokens(&candidate_text)?;
        if candidate_tokens as i32 > token_budget {
            return Ok(false);
        }

        self.accept_chunk(chunk.clone(), candidate_text, candidate_tokens);
        Ok(true)
    }

    fn render_candidate_without_headers(&mut self, chunk: &HydratedChunkRow) -> String {
        let rendered_chunk = self.render_chunk(chunk);
        if self.rendered_text.is_empty() {
            return rendered_chunk;
        }
        format!("{}{}{}", self.rendered_text, self.separator, rendered_chunk)
    }

    fn render_candidate_with_headers(&mut self, chunk: &HydratedChunkRow) -> String {
        let mut selected_for_source = self
            .selected_by_source
            .get(&chunk.source_id)
            .cloned()
            .unwrap_or_default();
        selected_for_source.push(chunk.clone());
        selected_for_source.sort_by(|a, b| a.chunk_index.cmp(&b.chunk_index));
        let candidate_block = self.render_source_block(chunk.source_id, &selected_for_source);

        let mut buffer = String::new();
        let mut source_order = self.source_order.clone();
        if !source_order.contains(&chunk.source_id) {
            source_order.push(chunk.source_id);
        }

        for (index, current_source_id) in source_order.iter().enumerate() {
            if index > 0 {
                buffer.push('\n');
            }
            if *current_source_id == chunk.source_id {
                buffer.push_str(&candidate_block);
            } else if let Some(existing) = self.rendered_source_blocks.get(current_source_id) {
                buffer.push_str(existing);
            }
        }

        buffer
    }

    fn accept_chunk(
        &mut self,
        chunk: HydratedChunkRow,
        rendered_text: String,
        measured_tokens: u32,
    ) {
        self.selected_in_order.push(chunk.clone());
        self.rendered_text = rendered_text;
        self.measured_tokens = measured_tokens;

        if self.skip_headers {
            return;
        }

        let selected_for_source = self.selected_by_source.entry(chunk.source_id).or_default();
        selected_for_source.push(chunk.clone());
        selected_for_source.sort_by(|a, b| a.chunk_index.cmp(&b.chunk_index));
        if !self.source_order.contains(&chunk.source_id) {
            self.source_order.push(chunk.source_id);
        }
        let rendered_source_chunks = selected_for_source.clone();
        let rendered_source_block =
            self.render_source_block(chunk.source_id, &rendered_source_chunks);
        self.rendered_source_blocks
            .insert(chunk.source_id, rendered_source_block);
    }

    fn count_tokens(&mut self, text: &str) -> Result<u32, RagError> {
        if let Some(tokens) = self.token_count_cache.get(text) {
            return Ok(*tokens);
        }
        let tokens = count_plain_text_tokens_untruncated(text)
            .map_err(|e| RagError::InternalError(e.to_string()))? as u32;
        self.token_count_cache.insert(text.to_string(), tokens);
        Ok(tokens)
    }

    fn render_chunk(&mut self, chunk: &HydratedChunkRow) -> String {
        if let Some(text) = self.chunk_text_cache.get(&chunk.chunk_id) {
            return text.clone();
        }
        let rendered = render_context_text(&chunk.content, &chunk.chunk_type);
        self.chunk_text_cache
            .insert(chunk.chunk_id, rendered.clone());
        rendered
    }

    fn render_source_block(&mut self, source_id: i64, chunks: &[HydratedChunkRow]) -> String {
        let mut buffer = String::new();
        buffer.push_str(&format!("<document id=\"{}\">\n", source_id));

        if let Some(metadata) = chunks.first().and_then(|chunk| chunk.metadata.clone()) {
            buffer.push_str("  <metadata>");
            buffer.push_str(&metadata);
            buffer.push_str("</metadata>\n");
        }

        buffer.push_str("  <content>\n");
        let rendered_chunks = chunks
            .iter()
            .map(|chunk| self.render_chunk(chunk))
            .collect::<Vec<_>>()
            .join("\n\n");
        buffer.push_str(&rendered_chunks);
        buffer.push_str("\n  </content>\n</document>\n");
        buffer
    }
}

fn hydrate_rows_for_assembly(
    conn: &rusqlite::Connection,
    collection_id: &str,
    hits: &[SearchHitMeta],
    cache: &Mutex<HashMap<i64, ChunkSearchResult>>,
) -> Result<(Vec<HydratedChunkRow>, Vec<i64>), RagError> {
    if hits.is_empty() {
        return Ok((Vec::new(), Vec::new()));
    }

    let _read_guard = QueryContentReadGuard::enter(QueryContentReadPhase::Assembly);

    let requested_ids: Vec<i64> = hits.iter().map(|hit| hit.chunk_id).collect();
    let (from_cache, missing) = partition_by_cache(cache, &requested_ids);

    let (newly_fetched, missing_ids) =
        hydrate_chunk_search_results(conn, collection_id, missing, hits)?;
    populate_cache(cache, &newly_fetched);

    let mut by_id: HashMap<i64, ChunkSearchResult> = from_cache
        .into_iter()
        .map(|c| (c.chunk_id, c))
        .collect();
    for chunk in newly_fetched {
        by_id.insert(chunk.chunk_id, chunk);
    }

    let ordered: Vec<HydratedChunkRow> = requested_ids
        .into_iter()
        .filter_map(|id| by_id.remove(&id))
        .map(|chunk| HydratedChunkRow {
            chunk_id: chunk.chunk_id,
            source_id: chunk.source_id,
            chunk_index: chunk.chunk_index,
            content: chunk.content,
            chunk_type: chunk.chunk_type,
            similarity: chunk.similarity,
            metadata: chunk.metadata,
        })
        .collect();

    Ok((ordered, missing_ids))
}

enum AssemblyBuildResult {
    Complete(AssembledContextV2),
    MissingChunks(Vec<i64>),
}

fn assemble_context_internal(
    conn: &rusqlite::Connection,
    handle: &SearchHandle,
    options: AssembleContextOptions,
) -> Result<AssemblyBuildResult, RagError> {
    let token_budget = options.token_budget.max(0);
    if handle.ordered_hits.is_empty() {
        return Ok(AssemblyBuildResult::Complete(AssembledContextV2 {
            text: String::new(),
            exact_tokens: 0,
            included_chunk_ids: Vec::new(),
            remaining_budget: token_budget,
            selected_source_id: None,
        }));
    }

    let selected_source_id = if options.single_source_mode {
        let (base_chunks, missing_ids) = hydrate_rows_for_assembly(
            conn,
            &handle.collection_id,
            &handle.base_hits,
            &handle.content_cache,
        )?;
        if !missing_ids.is_empty() {
            return Ok(AssemblyBuildResult::MissingChunks(missing_ids));
        }
        filter_to_most_relevant_source(&base_chunks, &handle.query_text)
    } else {
        None
    };

    let candidate_hits = match selected_source_id {
        Some(source_id) => handle
            .ordered_hits
            .iter()
            .filter(|hit| hit.source_id == source_id)
            .cloned()
            .collect::<Vec<_>>(),
        None => handle.ordered_hits.clone(),
    };

    let (mut chunks, missing_ids) = hydrate_rows_for_assembly(
        conn,
        &handle.collection_id,
        &candidate_hits,
        &handle.content_cache,
    )?;
    if !missing_ids.is_empty() {
        return Ok(AssemblyBuildResult::MissingChunks(missing_ids));
    }
    chunks = match options.strategy {
        ContextAssemblyStrategy::RelevanceFirst => chunks,
        ContextAssemblyStrategy::DiverseSources => diversify_sources(chunks),
        ContextAssemblyStrategy::Chronological => order_chronologically(chunks),
    };

    let mut state = RenderedSelectionState::new(options.separator, options.single_source_mode);
    for chunk in &chunks {
        let _ = state.try_add_chunk(chunk, token_budget)?;
    }

    Ok(AssemblyBuildResult::Complete(AssembledContextV2 {
        text: state.rendered_text.clone(),
        exact_tokens: if state.rendered_text.is_empty() {
            0
        } else {
            state.measured_tokens
        },
        included_chunk_ids: state
            .selected_in_order
            .iter()
            .map(|chunk| chunk.chunk_id)
            .collect(),
        remaining_budget: token_budget - state.measured_tokens as i32,
        selected_source_id,
    }))
}

fn resolve_system_instruction(system_instruction: Option<&str>, use_strict_mode: bool) -> String {
    if let Some(system_instruction) = system_instruction {
        return system_instruction.to_string();
    }

    if use_strict_mode {
        "Answer the question based ONLY on the documents below. If the information is not in the documents, say \"I could not find the information in the provided documents\".".to_string()
    } else {
        "Answer based on the following documents:".to_string()
    }
}

fn build_prompt_text(instruction: &str, context_text: &str, query: &str) -> String {
    format!(
        "{instruction}\n\n--- Reference Documents ---\n{context_text}\n--- End of Documents ---\n\nQuestion: {query}\n\nAnswer:"
    )
}

pub fn derive_context_budget_for_prompt_v2(
    full_prompt_budget: u32,
    query: String,
    system_instruction: Option<String>,
    use_strict_mode: bool,
    safety_margin_tokens: u32,
    fixed_prompt_overhead_tokens: Option<u32>,
) -> Result<u32, RagError> {
    let prompt_overhead_tokens = match fixed_prompt_overhead_tokens {
        Some(tokens) => tokens,
        None => {
            let instruction =
                resolve_system_instruction(system_instruction.as_deref(), use_strict_mode);
            let skeleton = build_prompt_text(&instruction, "", &query);
            count_plain_text_tokens_untruncated(&skeleton)
                .map_err(|e| RagError::InternalError(e.to_string()))? as u32
        }
    };

    Ok(full_prompt_budget
        .saturating_sub(prompt_overhead_tokens)
        .saturating_sub(safety_margin_tokens))
}

#[derive(Debug, Clone)]
pub struct ChunkSearchResult {
    pub chunk_id: i64,
    pub source_id: i64,
    pub chunk_index: i32,
    pub content: String,
    pub chunk_type: String,
    pub similarity: f64,
    pub metadata: Option<String>,
}

/// Search chunks by embedding similarity.
pub fn search_chunks(
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    search_chunks_in_collection(DEFAULT_COLLECTION_ID.to_string(), query_embedding, top_k)
}

/// Search chunks by embedding similarity in a specific collection.
pub fn search_chunks_in_collection(
    collection_id: String,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    info!(
        "[search_chunks] Searching collection={}, top_k={}",
        collection_id, top_k
    );

    // HNSW index is global in-memory; if active collection differs, rebuild scoped index.
    if !is_hnsw_index_loaded() || !is_active_hnsw_collection(&collection_id) {
        debug!(
            "[search_chunks] HNSW missing or different collection active. Rebuilding for {}",
            collection_id
        );
        rebuild_chunk_hnsw_index_for_collection(collection_id.clone())?;
    }

    if !is_hnsw_index_loaded() {
        debug!("[search_chunks] Falling back to linear scan");
        return search_chunks_linear_in_collection(&collection_id, query_embedding, top_k);
    }

    let hnsw_results = search_hnsw(query_embedding, top_k as usize)
        .map_err(|e| RagError::InternalError(e.to_string()))?;
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut results = Vec::new();
    for result in hnsw_results {
        let row: Option<(i64, i32, String, String, Option<String>)> = conn
            .query_row(
                "SELECT c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), s.metadata
                 FROM chunks c
                 JOIN sources s ON c.source_id = s.id
                 WHERE c.id = ?1
                   AND c.collection_id = ?2
                   AND COALESCE(s.status, 'completed') = 'completed'",
                params![result.id, &collection_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
            )
            .ok();

        if let Some((source_id, chunk_index, content, chunk_type, metadata)) = row {
            results.push(ChunkSearchResult {
                chunk_id: result.id,
                source_id,
                chunk_index,
                content,
                chunk_type,
                similarity: 1.0 - result.distance as f64,
                metadata,
            });
        }
    }

    info!("[search_chunks] Found {} results", results.len());
    Ok(results)
}

fn search_chunks_linear(
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    search_chunks_linear_in_collection(DEFAULT_COLLECTION_ID, query_embedding, top_k)
}

fn search_chunks_linear_in_collection(
    collection_id: &str,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let query_norm = l2_norm_f32(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let (query_i8, _query_i8_scale) = quantize_f32_to_i8(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let query_i8_norm = l2_norm_i8(&query_i8);

    let mut stmt = match conn.prepare(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, c.embedding_i8, s.metadata
         FROM chunks c
         JOIN sources s ON c.source_id = s.id
         WHERE c.collection_id = ?1
           AND COALESCE(s.status, 'completed') = 'completed'",
    ) {
        Ok(stmt) => stmt,
        Err(_) => conn
            .prepare(
                "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, NULL AS embedding_i8, s.metadata
                 FROM chunks c
                 JOIN sources s ON c.source_id = s.id
                 WHERE c.collection_id = ?1
                   AND COALESCE(s.status, 'completed') = 'completed'",
            )
            .map_err(|e| RagError::DatabaseError(e.to_string()))?,
    };

    let mut candidates: Vec<(f64, i64, i64, i32, String, String, Option<String>)> = Vec::new();

    let rows = stmt
        .query_map(params![collection_id], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get::<_, Vec<u8>>(5)?,
                row.get::<_, Option<Vec<u8>>>(6)?,
                row.get(7)?,
            ))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    for row in rows {
        let (
            id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            embedding_blob,
            embedding_i8_blob,
            metadata,
        ): (
            i64,
            i64,
            i32,
            String,
            String,
            Vec<u8>,
            Option<Vec<u8>>,
            Option<String>,
        ) = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;
        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &embedding_i8_blob;

        #[cfg(feature = "vector_quant_i8")]
        let similarity = if let Some(qblob) = embedding_i8_blob.as_deref() {
            if qblob.len() == query_i8.len() && query_i8_norm > 0.0 {
                cosine_with_query_norm_i8_blob(&query_i8, query_i8_norm, qblob) as f64
            } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
                if embedding.len() != query_embedding.len() {
                    continue;
                }
                cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
            } else {
                continue;
            }
        } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
            if embedding.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
        } else {
            continue;
        };

        #[cfg(not(feature = "vector_quant_i8"))]
        let similarity = if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
            if embedding.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
        } else {
            continue;
        };

        candidates.push((
            similarity as f64,
            id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            metadata,
        ));
    }

    candidates.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());

    Ok(candidates
        .into_iter()
        .take(top_k as usize)
        .map(
            |(sim, id, source_id, chunk_index, content, chunk_type, metadata)| ChunkSearchResult {
                chunk_id: id,
                source_id,
                chunk_index,
                content,
                chunk_type,
                similarity: sim,
                metadata,
            },
        )
        .collect())
}

/// Benchmark-only entrypoint for deterministic linear scan measurement.
///
/// This bypasses HNSW activation/rebuild and executes the exact
/// chunk linear-scan path directly for the given collection.
pub fn benchmark_search_chunks_linear_in_collection(
    collection_id: String,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    let normalized = normalize_collection_id(collection_id);
    search_chunks_linear_in_collection(&normalized, query_embedding, top_k)
}

/// Get source document by ID.
pub fn get_source(source_id: i64) -> Result<Option<String>, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(conn
        .query_row(
            "SELECT content FROM sources WHERE id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .ok())
}

/// Get all chunks for a source.
pub fn get_source_chunks(source_id: i64) -> Result<Vec<String>, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let mut stmt = conn
        .prepare("SELECT content FROM chunks WHERE source_id = ?1 ORDER BY chunk_index")
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let chunks: Vec<String> = stmt
        .query_map(params![source_id], |row| row.get(0))
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(chunks)
}

/// Get adjacent chunks by source_id and chunk_index range.
pub fn get_adjacent_chunks(
    source_id: i64,
    min_index: i32,
    max_index: i32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    info!(
        "[get_adjacent_chunks] source={}, range={}..{}",
        source_id, min_index, max_index
    );
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut stmt = conn.prepare(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), s.metadata 
         FROM chunks c 
         LEFT JOIN sources s ON c.source_id = s.id
         WHERE c.source_id = ?1 AND c.chunk_index >= ?2 AND c.chunk_index <= ?3 ORDER BY c.chunk_index"
    ).map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let chunks: Vec<ChunkSearchResult> = stmt
        .query_map(params![source_id, min_index, max_index], |row| {
            Ok(ChunkSearchResult {
                chunk_id: row.get(0)?,
                source_id: row.get(1)?,
                chunk_index: row.get(2)?,
                content: row.get(3)?,
                chunk_type: row.get(4)?,
                similarity: 0.0,
                metadata: row.get(5)?,
            })
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .collect();

    info!("[get_adjacent_chunks] Found {} chunks", chunks.len());
    Ok(chunks)
}

/// Delete a source and all its chunks.
pub fn delete_source(source_id: i64) -> Result<(), RagError> {
    delete_source_in_collection(DEFAULT_COLLECTION_ID.to_string(), source_id)
}

/// Delete a source and all its chunks in a specific collection.
pub fn delete_source_in_collection(collection_id: String, source_id: i64) -> Result<(), RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    conn.execute(
        "DELETE FROM chunks WHERE source_id = ?1 AND collection_id = ?2",
        params![source_id, &collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    conn.execute(
        "DELETE FROM sources WHERE id = ?1 AND collection_id = ?2",
        params![source_id, &collection_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    mark_collection_data_changed(&conn, &collection_id)?;
    info!("[delete_source] Deleted source {}", source_id);
    Ok(())
}

#[derive(Debug, Clone)]
pub struct SourceStats {
    pub source_count: i64,
    pub chunk_count: i64,
}

/// Get the number of chunks for a specific source.
pub fn get_source_chunk_count(source_id: i64) -> Result<i32, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let count: i32 = conn
        .query_row(
            "SELECT COUNT(*) FROM chunks WHERE source_id = ?1",
            params![source_id],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(count)
}

pub fn get_source_stats() -> Result<SourceStats, RagError> {
    get_source_stats_in_collection(DEFAULT_COLLECTION_ID.to_string())
}

pub fn get_source_stats_in_collection(collection_id: String) -> Result<SourceStats, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let source_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sources WHERE collection_id = ?1",
            params![collection_id],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let chunk_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM chunks WHERE collection_id = ?1",
            params![collection_id],
            |row| row.get(0),
        )
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    Ok(SourceStats {
        source_count,
        chunk_count,
    })
}

#[derive(Debug, Clone)]
pub struct ChunkForReembedding {
    pub chunk_id: i64,
    pub content: String,
}

/// Get all chunk IDs and contents for re-embedding.
pub fn get_all_chunk_ids_and_contents() -> Result<Vec<ChunkForReembedding>, RagError> {
    get_all_chunk_ids_and_contents_in_collection(DEFAULT_COLLECTION_ID.to_string())
}

pub fn get_all_chunk_ids_and_contents_in_collection(
    collection_id: String,
) -> Result<Vec<ChunkForReembedding>, RagError> {
    let collection_id = normalize_collection_id(collection_id);
    info!("[get_all_chunk_ids_and_contents] Starting");
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let mut stmt = conn
        .prepare("SELECT id, content FROM chunks WHERE collection_id = ?1 ORDER BY id")
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let chunks: Vec<ChunkForReembedding> = stmt
        .query_map(params![collection_id], |row| {
            Ok(ChunkForReembedding {
                chunk_id: row.get(0)?,
                content: row.get(1)?,
            })
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
        .collect();
    info!(
        "[get_all_chunk_ids_and_contents] Found {} chunks",
        chunks.len()
    );
    Ok(chunks)
}

/// Update embedding for a single chunk.
pub fn update_chunk_embedding(chunk_id: i64, embedding: Vec<f32>) -> Result<(), RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    let collection_id: Option<String> = conn
        .query_row(
            "SELECT collection_id FROM chunks WHERE id = ?1",
            params![chunk_id],
            |row| row.get(0),
        )
        .ok();
    let mut embedding_bytes: Vec<u8> = Vec::with_capacity(embedding.len() * 4);
    for f in &embedding {
        embedding_bytes.extend_from_slice(&f.to_ne_bytes());
    }
    conn.execute(
        "UPDATE chunks SET embedding = ?1 WHERE id = ?2",
        params![embedding_bytes, chunk_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    if let Some(cid) = collection_id {
        mark_collection_dirty(&conn, &cid)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::bm25_search::{bm25_clear_index, bm25_search};
    use crate::api::db_pool::{close_db_pool, init_db_pool};
    use crate::api::hnsw_index::clear_hnsw_index;
    use crate::api::tokenizer::init_tokenizer;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Mutex, OnceLock};
    use tokenizers::models::wordlevel::WordLevel;
    use tokenizers::pre_tokenizers::whitespace::Whitespace;
    use tokenizers::processors::bert::BertProcessing;
    use tokenizers::Tokenizer;

    fn test_guard() -> std::sync::MutexGuard<'static, ()> {
        static TEST_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
        TEST_MUTEX
            .get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn init_test_tokenizer() {
        let vocab_path = std::env::temp_dir().join("mobile_rag_engine_source_rag_test_vocab.json");
        std::fs::write(
            &vocab_path,
            r#"{"[UNK]":0,"install":1,"the":2,"package":3,"run":4,"smoke":5,"test":6,"guide":7,"setup":8,"[CLS]":9,"[SEP]":10}"#,
        )
        .expect("failed to write source_rag test vocab");

        let model = WordLevel::builder()
            .files(vocab_path.to_str().unwrap().to_string())
            .unk_token("[UNK]".to_string())
            .build()
            .expect("failed to build source_rag test tokenizer");
        let mut tokenizer = Tokenizer::new(model);
        tokenizer.with_pre_tokenizer(Some(Whitespace));
        tokenizer.with_post_processor(Some(BertProcessing::new(
            ("[SEP]".to_string(), 10),
            ("[CLS]".to_string(), 9),
        )));

        let tokenizer_path =
            std::env::temp_dir().join("mobile_rag_engine_source_rag_test_tokenizer.json");
        tokenizer
            .save(tokenizer_path.to_str().unwrap(), false)
            .expect("failed to save source_rag test tokenizer");
        init_tokenizer(tokenizer_path.to_str().unwrap().to_string())
            .expect("failed to init source_rag test tokenizer");
    }

    fn test_search_meta_hook_collection() -> &'static Mutex<Option<String>> {
        static HOOK_COLLECTION: OnceLock<Mutex<Option<String>>> = OnceLock::new();
        HOOK_COLLECTION.get_or_init(|| Mutex::new(None))
    }

    static SEARCH_META_HOOK_REMAINING: AtomicUsize = AtomicUsize::new(0);
    static SEARCH_META_HOOK_SERIAL: AtomicUsize = AtomicUsize::new(0);
    static HANDLE_HYDRATION_HOOK_REMAINING: AtomicUsize = AtomicUsize::new(0);
    static HANDLE_ASSEMBLE_HOOK_REMAINING: AtomicUsize = AtomicUsize::new(0);

    fn run_mutation_hook(remaining: &AtomicUsize) {
        if remaining
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |value| {
                if value > 0 {
                    Some(value - 1)
                } else {
                    None
                }
            })
            .is_err()
        {
            return;
        }

        let collection = test_search_meta_hook_collection()
            .lock()
            .unwrap()
            .clone()
            .expect("hook collection must be set");
        let serial = SEARCH_META_HOOK_SERIAL.fetch_add(1, Ordering::SeqCst);
        let created = add_source_in_collection(
            collection.clone(),
            format!("hook mutation {}", serial),
            None,
            Some(format!("hook-{serial}")),
        )
        .unwrap();
        update_source_status(created.source_id, "completed".to_string()).unwrap();
    }

    fn mutation_hook() {
        run_mutation_hook(&SEARCH_META_HOOK_REMAINING);
    }

    fn hydration_mutation_hook() {
        run_mutation_hook(&HANDLE_HYDRATION_HOOK_REMAINING);
    }

    fn assemble_mutation_hook() {
        run_mutation_hook(&HANDLE_ASSEMBLE_HOOK_REMAINING);
    }

    fn configure_search_meta_hook(collection: &str, remaining_mutations: usize) {
        *SEARCH_META_TEST_HOOK.write().unwrap() = Some(mutation_hook);
        *test_search_meta_hook_collection().lock().unwrap() = Some(collection.to_string());
        SEARCH_META_HOOK_REMAINING.store(remaining_mutations, Ordering::SeqCst);
    }

    fn clear_search_meta_hook() {
        *SEARCH_META_TEST_HOOK.write().unwrap() = None;
        *test_search_meta_hook_collection().lock().unwrap() = None;
        SEARCH_META_HOOK_REMAINING.store(0, Ordering::SeqCst);
    }

    fn configure_handle_hydration_hook(collection: &str, remaining_mutations: usize) {
        *HANDLE_HYDRATION_TEST_HOOK.write().unwrap() = Some(hydration_mutation_hook);
        *test_search_meta_hook_collection().lock().unwrap() = Some(collection.to_string());
        HANDLE_HYDRATION_HOOK_REMAINING.store(remaining_mutations, Ordering::SeqCst);
    }

    fn clear_handle_hydration_hook() {
        *HANDLE_HYDRATION_TEST_HOOK.write().unwrap() = None;
        *test_search_meta_hook_collection().lock().unwrap() = None;
        HANDLE_HYDRATION_HOOK_REMAINING.store(0, Ordering::SeqCst);
    }

    fn configure_handle_assemble_hook(collection: &str, remaining_mutations: usize) {
        *HANDLE_ASSEMBLE_TEST_HOOK.write().unwrap() = Some(assemble_mutation_hook);
        *test_search_meta_hook_collection().lock().unwrap() = Some(collection.to_string());
        HANDLE_ASSEMBLE_HOOK_REMAINING.store(remaining_mutations, Ordering::SeqCst);
    }

    fn clear_handle_assemble_hook() {
        *HANDLE_ASSEMBLE_TEST_HOOK.write().unwrap() = None;
        *test_search_meta_hook_collection().lock().unwrap() = None;
        HANDLE_ASSEMBLE_HOOK_REMAINING.store(0, Ordering::SeqCst);
    }

    fn setup_test_db(name: &str) -> PathBuf {
        let db_path = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&db_path);
        init_db_pool(db_path.to_str().unwrap().to_string(), 4).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();
        db_path
    }

    fn teardown_test_db(db_path: PathBuf) {
        clear_search_meta_hook();
        clear_handle_hydration_hook();
        clear_handle_assemble_hook();
        clear_hnsw_index();
        bm25_clear_index();
        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    fn fetch_chunk_rows(collection_id: &str) -> Vec<(i64, i64, i32, String)> {
        let conn = get_connection().unwrap();
        let mut stmt = conn
            .prepare(
                "SELECT id, source_id, chunk_index, COALESCE(chunk_type, 'general')
                 FROM chunks
                 WHERE collection_id = ?1
                 ORDER BY source_id, chunk_index, id",
            )
            .unwrap();
        let rows = stmt
            .query_map(params![collection_id], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i32>(2)?,
                    row.get::<_, String>(3)?,
                ))
            })
            .unwrap();
        rows.map(|row| row.unwrap()).collect()
    }

    fn seed_search_fixture(collection_id: &str) -> Vec<(i64, i64, i32, String)> {
        let source1 = add_source_in_collection(
            collection_id.to_string(),
            "Install the package.\nVerify the checksum.".to_string(),
            Some("{\"source\":\"guide\"}".to_string()),
            Some("guide".to_string()),
        )
        .unwrap();
        update_source_status(source1.source_id, "completed".to_string()).unwrap();
        add_chunks(
            source1.source_id,
            vec![ChunkData {
                content: "Install the package.".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 20,
                chunk_type: "text|Guide > Setup".to_string(),
                embedding: vec![1.0, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();

        let source2 = add_source_in_collection(
            collection_id.to_string(),
            "Run the smoke test.".to_string(),
            None,
            Some("smoke".to_string()),
        )
        .unwrap();
        update_source_status(source2.source_id, "completed".to_string()).unwrap();
        add_chunks(
            source2.source_id,
            vec![ChunkData {
                content: "Run the smoke test.".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 19,
                chunk_type: "general".to_string(),
                embedding: vec![0.6, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();

        rebuild_chunk_hnsw_index_for_collection(collection_id.to_string()).unwrap();
        rebuild_chunk_bm25_index_for_collection(collection_id.to_string()).unwrap();
        fetch_chunk_rows(collection_id)
    }

    fn build_handle_for_fixture(
        collection_id: &str,
        chunk_rows: &[(i64, i64, i32, String)],
    ) -> SearchHandle {
        let conn = get_connection().unwrap();
        let data_generation = get_collection_data_generation(&conn, collection_id).unwrap();
        let ordered_hits = chunk_rows
            .iter()
            .enumerate()
            .map(|(index, (chunk_id, source_id, chunk_index, chunk_type))| {
                build_search_hit_meta(
                    *chunk_id,
                    *source_id,
                    *chunk_index,
                    1.0 - (index as f64 * 0.1),
                    chunk_type,
                )
            })
            .collect::<Vec<_>>();

        SearchHandle {
            collection_id: collection_id.to_string(),
            data_generation,
            query_text: "install".to_string(),
            base_hits: ordered_hits.clone(),
            ordered_hits,
            _query_options: SearchMetaHybridOptions {
                top_k: chunk_rows.len() as u32,
                vector_weight: 1.0,
                bm25_weight: 0.0,
                source_ids: None,
                adjacent_chunks: 0,
            },
            content_cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    #[test]
    fn test_claim_source_for_ingestion_transitions() {
        let _guard = test_guard();
        let db_path = std::env::temp_dir().join("test_claim_source_for_ingestion.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();

        let source = add_source(
            "claim transition doc".to_string(),
            None,
            Some("claim".to_string()),
        )
        .unwrap();

        assert_eq!(
            get_source_status(source.source_id).unwrap(),
            Some("pending".to_string())
        );
        assert!(claim_source_for_ingestion(source.source_id).unwrap());
        assert_eq!(
            get_source_status(source.source_id).unwrap(),
            Some("processing".to_string())
        );
        assert!(!claim_source_for_ingestion(source.source_id).unwrap());

        update_source_status(source.source_id, "completed".to_string()).unwrap();
        assert!(!claim_source_for_ingestion(source.source_id).unwrap());

        update_source_status(source.source_id, "failed".to_string()).unwrap();
        assert!(claim_source_for_ingestion(source.source_id).unwrap());
        assert_eq!(
            get_source_status(source.source_id).unwrap(),
            Some("processing".to_string())
        );

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_clear_source_chunks_keeps_source_row() {
        let _guard = test_guard();
        let db_path = std::env::temp_dir().join("test_clear_source_chunks.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();

        let source = add_source(
            "clear chunks source content".to_string(),
            None,
            Some("clear".to_string()),
        )
        .unwrap();
        update_source_status(source.source_id, "completed".to_string()).unwrap();

        add_chunks(
            source.source_id,
            vec![
                ChunkData {
                    content: "chunk a".to_string(),
                    chunk_index: 0,
                    start_pos: 0,
                    end_pos: 7,
                    chunk_type: "text".to_string(),
                    embedding: vec![1.0, 0.0, 0.0, 0.0],
                },
                ChunkData {
                    content: "chunk b".to_string(),
                    chunk_index: 1,
                    start_pos: 8,
                    end_pos: 15,
                    chunk_type: "text".to_string(),
                    embedding: vec![0.9, 0.0, 0.0, 0.0],
                },
            ],
        )
        .unwrap();
        assert_eq!(get_source_chunk_count(source.source_id).unwrap(), 2);

        let deleted = clear_source_chunks(source.source_id).unwrap();
        assert_eq!(deleted, 2);
        assert_eq!(get_source_chunk_count(source.source_id).unwrap(), 0);
        assert!(get_source(source.source_id).unwrap().is_some());
        assert_eq!(clear_source_chunks(source.source_id).unwrap(), 0);

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_completed_filter_excludes_pending_and_failed_sources() {
        let _guard = test_guard();
        let db_path = std::env::temp_dir().join("test_completed_filter.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();

        let collection = "filtering".to_string();
        let completed =
            add_source_in_collection(collection.clone(), "completed doc".to_string(), None, None)
                .unwrap();
        let pending =
            add_source_in_collection(collection.clone(), "pending doc".to_string(), None, None)
                .unwrap();
        let failed =
            add_source_in_collection(collection.clone(), "failed doc".to_string(), None, None)
                .unwrap();

        update_source_status(completed.source_id, "completed".to_string()).unwrap();
        update_source_status(failed.source_id, "failed".to_string()).unwrap();
        // pending remains pending

        add_chunks(
            completed.source_id,
            vec![ChunkData {
                content: "sharedtoken completed".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 21,
                chunk_type: "text".to_string(),
                embedding: vec![1.0, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();
        add_chunks(
            pending.source_id,
            vec![ChunkData {
                content: "sharedtoken pending".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 19,
                chunk_type: "text".to_string(),
                embedding: vec![0.8, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();
        add_chunks(
            failed.source_id,
            vec![ChunkData {
                content: "sharedtoken failed".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 18,
                chunk_type: "text".to_string(),
                embedding: vec![0.7, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();

        rebuild_chunk_hnsw_index_for_collection(collection.clone()).unwrap();
        let hnsw_hits =
            search_chunks_in_collection(collection.clone(), vec![1.0, 0.0, 0.0, 0.0], 10).unwrap();
        assert_eq!(hnsw_hits.len(), 1);
        assert_eq!(hnsw_hits[0].source_id, completed.source_id);

        let linear_hits = benchmark_search_chunks_linear_in_collection(
            collection.clone(),
            vec![1.0, 0.0, 0.0, 0.0],
            10,
        )
        .unwrap();
        assert_eq!(linear_hits.len(), 1);
        assert_eq!(linear_hits[0].source_id, completed.source_id);

        rebuild_chunk_bm25_index_for_collection(collection).unwrap();
        let bm25_hits = bm25_search("sharedtoken".to_string(), 10);
        assert_eq!(bm25_hits.len(), 1);

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_metadata_retrieval() {
        let _guard = test_guard();
        // 1. Setup
        let db_path = std::env::temp_dir().join("test_metadata.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();

        // 2. Add Source with Metadata
        let metadata = r#"{"author": "Test Author", "year": 2025}"#;
        let source_res =
            add_source("Test Content".to_string(), Some(metadata.to_string()), None).unwrap();
        update_source_status(source_res.source_id, "completed".to_string()).unwrap();

        let chunk = ChunkData {
            content: "Test Chunk".to_string(),
            chunk_index: 0,
            start_pos: 0,
            end_pos: 10,
            chunk_type: "text".to_string(),
            embedding: vec![1.0, 0.0, 0.0, 0.0], // 4 dims
        };
        add_chunks(source_res.source_id, vec![chunk]).unwrap();

        // 3. Search (Linear Scan)
        let results = search_chunks(vec![1.0, 0.0, 0.0, 0.0], 1).unwrap();

        // 4. Verify Metadata
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].metadata, Some(metadata.to_string()));
        assert_eq!(results[0].source_id, source_res.source_id);

        // 5. Cleanup
        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_same_content_allowed_across_collections() {
        let _guard = test_guard();
        let db_path = std::env::temp_dir().join("test_collection_scoped_dedup.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();

        let business = add_source_in_collection(
            "business".to_string(),
            "shared content".to_string(),
            None,
            None,
        )
        .unwrap();
        let travel = add_source_in_collection(
            "travel".to_string(),
            "shared content".to_string(),
            None,
            None,
        )
        .unwrap();

        assert!(!business.is_duplicate);
        assert!(!travel.is_duplicate);
        assert_ne!(business.source_id, travel.source_id);

        let business_dup = add_source_in_collection(
            "business".to_string(),
            "shared content".to_string(),
            None,
            None,
        )
        .unwrap();
        assert!(business_dup.is_duplicate);
        assert_eq!(business_dup.source_id, business.source_id);

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_collection_scoped_search_and_stats_are_isolated() {
        let _guard = test_guard();
        let db_path = std::env::temp_dir().join("test_collection_scope_isolation.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();

        let business = add_source_in_collection(
            "business".to_string(),
            "business doc".to_string(),
            None,
            Some("biz".to_string()),
        )
        .unwrap();
        let travel = add_source_in_collection(
            "travel".to_string(),
            "travel doc".to_string(),
            None,
            Some("trip".to_string()),
        )
        .unwrap();
        update_source_status(business.source_id, "completed".to_string()).unwrap();
        update_source_status(travel.source_id, "completed".to_string()).unwrap();

        add_chunks(
            business.source_id,
            vec![ChunkData {
                content: "business chunk".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 14,
                chunk_type: "text".to_string(),
                embedding: vec![1.0, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();
        add_chunks(
            travel.source_id,
            vec![ChunkData {
                content: "travel chunk".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 12,
                chunk_type: "text".to_string(),
                embedding: vec![0.0, 1.0, 0.0, 0.0],
            }],
        )
        .unwrap();

        rebuild_chunk_hnsw_index_for_collection("business".to_string()).unwrap();
        let business_hits =
            search_chunks_in_collection("business".to_string(), vec![1.0, 0.0, 0.0, 0.0], 5)
                .unwrap();
        assert_eq!(business_hits.len(), 1);
        assert_eq!(business_hits[0].source_id, business.source_id);

        rebuild_chunk_hnsw_index_for_collection("travel".to_string()).unwrap();
        let travel_hits =
            search_chunks_in_collection("travel".to_string(), vec![0.0, 1.0, 0.0, 0.0], 5).unwrap();
        assert_eq!(travel_hits.len(), 1);
        assert_eq!(travel_hits[0].source_id, travel.source_id);

        let business_stats = get_source_stats_in_collection("business".to_string()).unwrap();
        let travel_stats = get_source_stats_in_collection("travel".to_string()).unwrap();
        assert_eq!(business_stats.source_count, 1);
        assert_eq!(business_stats.chunk_count, 1);
        assert_eq!(travel_stats.source_count, 1);
        assert_eq!(travel_stats.chunk_count, 1);

        delete_source_in_collection("travel".to_string(), travel.source_id).unwrap();
        let business_after = get_source_stats_in_collection("business".to_string()).unwrap();
        let travel_after = get_source_stats_in_collection("travel".to_string()).unwrap();
        assert_eq!(business_after.source_count, 1);
        assert_eq!(business_after.chunk_count, 1);
        assert_eq!(travel_after.source_count, 0);
        assert_eq!(travel_after.chunk_count, 0);

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_data_generation_defaults_and_mutations() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_data_generation_defaults_and_mutations.db");
        let collection = "zero-copy-generation";
        let conn = get_connection().unwrap();

        assert_eq!(
            get_collection_data_generation(&conn, collection).unwrap(),
            0
        );

        let source = add_source_in_collection(
            collection.to_string(),
            "generation source".to_string(),
            None,
            Some("gen".to_string()),
        )
        .unwrap();
        assert_eq!(
            get_collection_data_generation(&conn, collection).unwrap(),
            1
        );

        update_source_status(source.source_id, "completed".to_string()).unwrap();
        assert_eq!(
            get_collection_data_generation(&conn, collection).unwrap(),
            2
        );

        add_chunks(
            source.source_id,
            vec![ChunkData {
                content: "chunk body".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 10,
                chunk_type: "text".to_string(),
                embedding: vec![1.0, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();
        assert_eq!(
            get_collection_data_generation(&conn, collection).unwrap(),
            3
        );

        rebuild_chunk_hnsw_index_for_collection(collection.to_string()).unwrap();
        rebuild_chunk_bm25_index_for_collection(collection.to_string()).unwrap();
        assert_eq!(
            get_collection_data_generation(&conn, collection).unwrap(),
            3
        );

        teardown_test_db(db_path);
    }

    #[test]
    fn test_search_meta_hybrid_returns_bounded_header_preview_and_no_hot_path_metadata_blob() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_search_meta_hybrid_returns_bounded_header_preview.db");
        let collection = "zero-copy-preview";
        let long_header = format!("text|{}", "가이드 > ".repeat(60));
        let source = add_source_in_collection(
            collection.to_string(),
            "긴 헤더 테스트".to_string(),
            Some(
                "{\"very\":\"large metadata blob that should not appear in SearchHitMeta\"}"
                    .to_string(),
            ),
            Some("preview".to_string()),
        )
        .unwrap();
        update_source_status(source.source_id, "completed".to_string()).unwrap();
        add_chunks(
            source.source_id,
            vec![ChunkData {
                content: "긴 헤더를 가진 청크".to_string(),
                chunk_index: 0,
                start_pos: 0,
                end_pos: 24,
                chunk_type: long_header.clone(),
                embedding: vec![1.0, 0.0, 0.0, 0.0],
            }],
        )
        .unwrap();
        rebuild_chunk_hnsw_index_for_collection(collection.to_string()).unwrap();
        rebuild_chunk_bm25_index_for_collection(collection.to_string()).unwrap();

        let handle: SearchHandle = search_meta_hybrid_once(
            collection,
            "긴 헤더",
            &[1.0, 0.0, 0.0, 0.0],
            &SearchMetaHybridOptions {
                top_k: 1,
                vector_weight: 1.0,
                bm25_weight: 0.0,
                source_ids: None,
                adjacent_chunks: 0,
            },
        )
        .unwrap();
        let hits = handle.hit_meta().unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].raw_type, "text");
        let preview = hits[0].header_path_preview.clone().unwrap();
        assert!(preview.as_bytes().len() <= 256);
        assert!("가이드 > ".repeat(60).starts_with(&preview));

        let hydrated = handle.hydrate_chunks(vec![hits[0].chunk_id]).unwrap();
        assert_eq!(
            hydrated[0].metadata,
            Some(
                "{\"very\":\"large metadata blob that should not appear in SearchHitMeta\"}"
                    .to_string()
            )
        );
        assert_eq!(hydrated[0].chunk_type, long_header);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_search_handle_rejects_stale_hydration_after_mutation() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_search_handle_rejects_stale_hydration_after_mutation.db");
        let collection = "zero-copy-stale";
        let chunk_rows = seed_search_fixture(collection);
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        let _ = add_source_in_collection(
            collection.to_string(),
            "mutation source".to_string(),
            None,
            Some("mutation".to_string()),
        )
        .unwrap();

        let err = handle.hit_meta().unwrap_err();
        match err {
            RagError::StaleSearchHandle(msg) => {
                assert!(msg.contains("expected_generation"));
            }
            other => panic!("expected stale search handle error, got {:?}", other),
        }
        let err = handle.hydrate_chunks(vec![chunk_rows[0].0]).unwrap_err();
        assert!(matches!(err, RagError::StaleSearchHandle(_)));
        let err = handle
            .get_chunk_excerpts(vec![chunk_rows[0].0], 8)
            .unwrap_err();
        assert!(matches!(err, RagError::StaleSearchHandle(_)));
        let err = handle
            .assemble_context(AssembleContextOptions {
                token_budget: 100,
                strategy: ContextAssemblyStrategy::RelevanceFirst,
                separator: "\n\n---\n\n".to_string(),
                single_source_mode: false,
            })
            .unwrap_err();
        assert!(matches!(err, RagError::StaleSearchHandle(_)));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_search_meta_hybrid_retries_once_after_concurrent_mutation() {
        let _guard = test_guard();
        let db_path =
            setup_test_db("test_search_meta_hybrid_retries_once_after_concurrent_mutation.db");
        let collection = "zero-copy-retry";
        seed_search_fixture(collection);

        configure_search_meta_hook(collection, 1);
        let _opaque_handle = search_meta_hybrid(
            collection.to_string(),
            "install".to_string(),
            vec![1.0, 0.0, 0.0, 0.0],
            SearchMetaHybridOptions {
                top_k: 2,
                vector_weight: 1.0,
                bm25_weight: 0.0,
                source_ids: None,
                adjacent_chunks: 0,
            },
        )
        .unwrap();
        let hits: SearchHandle = search_meta_hybrid_once(
            collection,
            "install",
            &[1.0, 0.0, 0.0, 0.0],
            &SearchMetaHybridOptions {
                top_k: 2,
                vector_weight: 1.0,
                bm25_weight: 0.0,
                source_ids: None,
                adjacent_chunks: 0,
            },
        )
        .unwrap();
        assert_eq!(hits.hit_meta().unwrap().len(), 2);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_search_meta_hybrid_fails_after_repeated_concurrent_mutation() {
        let _guard = test_guard();
        let db_path =
            setup_test_db("test_search_meta_hybrid_fails_after_repeated_concurrent_mutation.db");
        let collection = "zero-copy-retry-fail";
        seed_search_fixture(collection);

        configure_search_meta_hook(collection, 2);
        let err = search_meta_hybrid(
            collection.to_string(),
            "install".to_string(),
            vec![1.0, 0.0, 0.0, 0.0],
            SearchMetaHybridOptions {
                top_k: 2,
                vector_weight: 1.0,
                bm25_weight: 0.0,
                source_ids: None,
                adjacent_chunks: 0,
            },
        )
        .unwrap_err();
        assert!(matches!(err, RagError::ConcurrentMutation(_)));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_batch_hydration_and_excerpt_preserve_requested_order() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_batch_hydration_and_excerpt_preserve_requested_order.db");
        let collection = "zero-copy-hydrate";
        let chunk_rows = seed_search_fixture(collection);
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        let requested = vec![chunk_rows[1].0, chunk_rows[0].0];
        let hydrated = handle.hydrate_chunks(requested.clone()).unwrap();
        assert_eq!(
            hydrated
                .iter()
                .map(|chunk| chunk.chunk_id)
                .collect::<Vec<_>>(),
            requested
        );
        assert_eq!(hydrated[0].content, "Run the smoke test.");

        let excerpts = handle.get_chunk_excerpts(requested.clone(), 10).unwrap();
        assert_eq!(
            excerpts
                .iter()
                .map(|chunk| chunk.chunk_id)
                .collect::<Vec<_>>(),
            requested
        );
        assert!(excerpts[0].excerpt.as_bytes().len() <= 10);
        assert!("Run the smoke test.".starts_with(&excerpts[0].excerpt));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_hydrate_and_excerpt_reject_duplicate_chunk_ids() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_hydrate_and_excerpt_reject_duplicate_chunk_ids.db");
        let collection = "zero-copy-duplicate";
        let chunk_rows = seed_search_fixture(collection);
        let handle = build_handle_for_fixture(collection, &chunk_rows);
        let duplicated = vec![chunk_rows[0].0, chunk_rows[0].0];

        let err = handle.hydrate_chunks(duplicated.clone()).unwrap_err();
        assert!(matches!(err, RagError::InvalidInput(_)));

        let err = handle.get_chunk_excerpts(duplicated, 12).unwrap_err();
        assert!(matches!(err, RagError::InvalidInput(_)));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_hydrate_returns_concurrent_mutation_when_generation_changes_mid_operation() {
        let _guard = test_guard();
        let db_path = setup_test_db(
            "test_hydrate_returns_concurrent_mutation_when_generation_changes_mid_operation.db",
        );
        let collection = "zero-copy-hydrate-race";
        let chunk_rows = seed_search_fixture(collection);
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        configure_handle_hydration_hook(collection, 1);
        let err = handle.hydrate_chunks(vec![chunk_rows[0].0]).unwrap_err();
        assert!(matches!(err, RagError::ConcurrentMutation(_)));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_excerpt_returns_concurrent_mutation_when_generation_changes_mid_operation() {
        let _guard = test_guard();
        let db_path = setup_test_db(
            "test_excerpt_returns_concurrent_mutation_when_generation_changes_mid_operation.db",
        );
        let collection = "zero-copy-excerpt-race";
        let chunk_rows = seed_search_fixture(collection);
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        configure_handle_hydration_hook(collection, 1);
        let err = handle
            .get_chunk_excerpts(vec![chunk_rows[0].0], 12)
            .unwrap_err();
        assert!(matches!(err, RagError::ConcurrentMutation(_)));

        teardown_test_db(db_path);
    }

    #[test]
    fn test_assemble_context_matches_grouped_rendering_contract() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_assemble_context_matches_grouped_rendering_contract.db");
        let collection = "zero-copy-context";
        let chunk_rows = seed_search_fixture(collection);
        init_test_tokenizer();
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        let assembled = handle
            .assemble_context(AssembleContextOptions {
                token_budget: 100,
                strategy: ContextAssemblyStrategy::RelevanceFirst,
                separator: "\n\n---\n\n".to_string(),
                single_source_mode: false,
            })
            .unwrap();

        let expected = "<document id=\"1\">\n  <metadata>{\"source\":\"guide\"}</metadata>\n  <content>\nHeader Path: Guide > Setup\nInstall the package.\n  </content>\n</document>\n\n<document id=\"2\">\n  <content>\nRun the smoke test.\n  </content>\n</document>\n".to_string();
        assert_eq!(assembled.text, expected);
        assert_eq!(
            assembled.exact_tokens,
            count_plain_text_tokens_untruncated(&expected).unwrap() as u32
        );
        assert_eq!(
            assembled.included_chunk_ids,
            chunk_rows.iter().map(|row| row.0).collect::<Vec<_>>()
        );
        assert_eq!(
            assembled.remaining_budget,
            100 - assembled.exact_tokens as i32
        );
        assert_eq!(assembled.selected_source_id, None);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_assemble_context_exposes_selected_source_id_for_single_source_mode() {
        let _guard = test_guard();
        let db_path = setup_test_db(
            "test_assemble_context_exposes_selected_source_id_for_single_source_mode.db",
        );
        let collection = "zero-copy-context-single-source";
        let chunk_rows = seed_search_fixture(collection);
        init_test_tokenizer();
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        let assembled = handle
            .assemble_context(AssembleContextOptions {
                token_budget: 100,
                strategy: ContextAssemblyStrategy::RelevanceFirst,
                separator: "\n\n---\n\n".to_string(),
                single_source_mode: true,
            })
            .unwrap();

        assert_eq!(assembled.selected_source_id, Some(1));
        assert_eq!(assembled.included_chunk_ids, vec![chunk_rows[0].0]);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_assemble_context_returns_concurrent_mutation_when_generation_changes_before_finalize() {
        let _guard = test_guard();
        let db_path = setup_test_db(
            "test_assemble_context_returns_concurrent_mutation_when_generation_changes_before_finalize.db",
        );
        let collection = "zero-copy-assemble-race";
        let chunk_rows = seed_search_fixture(collection);
        init_test_tokenizer();
        let handle = build_handle_for_fixture(collection, &chunk_rows);

        configure_handle_assemble_hook(collection, 1);
        let err = handle
            .assemble_context(AssembleContextOptions {
                token_budget: 100,
                strategy: ContextAssemblyStrategy::RelevanceFirst,
                separator: "\n\n---\n\n".to_string(),
                single_source_mode: false,
            })
            .unwrap_err();
        assert!(matches!(err, RagError::ConcurrentMutation(_)));

        teardown_test_db(db_path);
    }
}

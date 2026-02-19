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
use crate::api::hnsw_index::{
    build_hnsw_index, clear_hnsw_index, is_hnsw_index_loaded, load_hnsw_index, save_hnsw_index,
    search_hnsw,
};
use log::{debug, info};
use ndarray::Array1;
use once_cell::sync::Lazy;
use rusqlite::params;
use sha2::{Digest, Sha256};
use std::sync::RwLock;

pub const DEFAULT_COLLECTION_ID: &str = "__default__";

static ACTIVE_HNSW_COLLECTION: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));
static ACTIVE_BM25_COLLECTION: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

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
            last_hnsw_built_at INTEGER,
            last_bm25_built_at INTEGER,
            last_error TEXT
        )",
        [],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;

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
    mark_collection_dirty(&conn, &collection_id)?;
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
    conn.execute(
        "UPDATE sources SET status = ?1 WHERE id = ?2",
        params![status, source_id],
    )
    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    info!(
        "[update_source_status] Updated source {} to status '{}'",
        source_id, status
    );
    Ok(())
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

    for chunk in &chunks {
        let mut embedding_bytes: Vec<u8> = Vec::with_capacity(chunk.embedding.len() * 4);
        for f in &chunk.embedding {
            embedding_bytes.extend_from_slice(&f.to_ne_bytes());
        }

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
        ).map_err(|e| RagError::DatabaseError(e.to_string()))?;
    }

    tx.commit()
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;
    mark_collection_dirty(&conn, &source_collection_id)?;
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

    let mut stmt = conn
        .prepare("SELECT id, embedding FROM chunks WHERE collection_id = ?1")
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let points: Vec<(i64, Vec<f32>)> = stmt
        .query_map(params![collection_id], |row| {
            let id: i64 = row.get(0)?;
            let embedding_blob: Vec<u8> = row.get(1)?;
            let mut embedding = Vec::with_capacity(embedding_blob.len() / 4);
            for chunk in embedding_blob.chunks_exact(4) {
                embedding.push(f32::from_ne_bytes(chunk.try_into().unwrap()));
            }
            Ok((id, embedding))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?
        .filter_map(|r| r.ok())
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
        .prepare("SELECT id, content FROM chunks WHERE collection_id = ?1")
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
                 LEFT JOIN sources s ON c.source_id = s.id
                 WHERE c.id = ?1 AND c.collection_id = ?2",
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
    let mut stmt = conn.prepare(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, s.metadata 
         FROM chunks c
         LEFT JOIN sources s ON c.source_id = s.id
         WHERE c.collection_id = ?1"
    ).map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let query_vec = Array1::from(query_embedding.clone());
    let query_norm = query_vec.mapv(|x| x * x).sum().sqrt();

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
                row.get(6)?,
            ))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    for row in rows {
        let (id, source_id, chunk_index, content, chunk_type, embedding_blob, metadata): (
            i64,
            i64,
            i32,
            String,
            String,
            Vec<u8>,
            Option<String>,
        ) = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;

        let embedding: Vec<f32> = embedding_blob
            .chunks(4)
            .map(|chunk| f32::from_ne_bytes(chunk.try_into().unwrap()))
            .collect();

        if embedding.len() != query_embedding.len() {
            continue;
        }

        let target_vec = Array1::from(embedding);
        let target_norm = target_vec.mapv(|x| x * x).sum().sqrt();
        let dot_product = query_vec.dot(&target_vec);

        let similarity = if query_norm == 0.0 || target_norm == 0.0 {
            0.0
        } else {
            (dot_product / (query_norm * target_norm)) as f64
        };

        candidates.push((
            similarity,
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
    mark_collection_dirty(&conn, &collection_id)?;
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
    use crate::api::db_pool::{close_db_pool, init_db_pool};
    use crate::api::hnsw_index::clear_hnsw_index;

    #[test]
    fn test_metadata_retrieval() {
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
}

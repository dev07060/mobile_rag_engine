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
//! Simple RAG API for basic document storage and similarity search.

use crate::api::bm25_search::{bm25_add_document, bm25_add_documents, bm25_clear_index};
use crate::api::db_pool::get_connection;
use crate::api::hnsw_index::{
    build_hnsw_index, clear_hnsw_index, is_hnsw_index_loaded, search_hnsw,
};
use crate::api::incremental_index::{clear_buffer, incremental_add};
use crate::api::vector_math::{
    cosine_f32, cosine_with_query_norm_f32, decode_f32_embedding, decode_f32_embedding_or_warn,
    l2_norm_f32,
};
#[cfg(feature = "vector_quant_i8")]
use crate::api::vector_quant::{
    l2_norm_i8, quantize_f32_to_i8, quantize_f32_to_u8_blob, QueryQ8, cosine_similarity_q8,
};
use flutter_rust_bridge::frb;
use log::{debug, error, info, warn};
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

fn truncate_str(s: &str, max_chars: usize) -> &str {
    match s.char_indices().nth(max_chars) {
        Some((idx, _)) => &s[..idx],
        None => s,
    }
}

fn calculate_content_hash(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// Calculate cosine similarity between two vectors.
#[frb(sync)]
pub fn calculate_cosine_similarity(vec_a: Vec<f32>, vec_b: Vec<f32>) -> f64 {
    if vec_a.len() != vec_b.len() || vec_a.is_empty() {
        warn!(
            "[cosine] Vector length mismatch: a={}, b={}",
            vec_a.len(),
            vec_b.len()
        );
        return 0.0;
    }
    cosine_f32(&vec_a, &vec_b) as f64
}

/// Initialize database with docs table.
pub fn init_db() -> anyhow::Result<()> {
    info!("[init_db] Initializing database tables");
    let conn = get_connection()?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS docs (
            id INTEGER PRIMARY KEY,
            content TEXT NOT NULL,
            content_hash TEXT UNIQUE,
            embedding BLOB NOT NULL,
            embedding_i8 BLOB,
            embedding_scale REAL
        )",
        [],
    )?;

    let has_hash_column: bool = conn
        .prepare("SELECT content_hash FROM docs LIMIT 1")
        .is_ok();

    if !has_hash_column {
        info!("[init_db] Migrating: adding content_hash column");
        conn.execute("ALTER TABLE docs ADD COLUMN content_hash TEXT", [])?;

        let mut stmt = conn.prepare("SELECT id, content FROM docs WHERE content_hash IS NULL")?;
        let rows: Vec<(i64, String)> = stmt
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
            .filter_map(|r| r.ok())
            .collect();

        for (id, content) in rows {
            let hash = calculate_content_hash(&content);
            conn.execute(
                "UPDATE docs SET content_hash = ?1 WHERE id = ?2",
                params![hash, id],
            )?;
        }

        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_content_hash ON docs(content_hash)",
            [],
        )?;
    }

    let has_embedding_i8_column: bool = conn
        .prepare("SELECT embedding_i8 FROM docs LIMIT 1")
        .is_ok();
    if !has_embedding_i8_column {
        info!("[init_db] Migrating: adding embedding_i8 column");
        conn.execute("ALTER TABLE docs ADD COLUMN embedding_i8 BLOB", [])?;
    }

    let has_embedding_scale_column: bool = conn
        .prepare("SELECT embedding_scale FROM docs LIMIT 1")
        .is_ok();
    if !has_embedding_scale_column {
        info!("[init_db] Migrating: adding embedding_scale column");
        conn.execute("ALTER TABLE docs ADD COLUMN embedding_scale REAL", [])?;
    }

    #[cfg(feature = "vector_quant_i8")]
    {
        let mut stmt = conn.prepare(
            "SELECT id, embedding FROM docs WHERE embedding_i8 IS NULL OR embedding_scale IS NULL",
        )?;
        let rows: Vec<(i64, Vec<u8>)> = stmt
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
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
                "UPDATE docs SET embedding_i8 = ?1, embedding_scale = ?2 WHERE id = ?3",
                params![embedding_i8_bytes, embedding_scale, id],
            )?;
        }
    }

    rebuild_hnsw_index_internal(&conn)?;
    rebuild_bm25_index_internal(&conn)?;

    info!("[init_db] Initialization complete");
    Ok(())
}

fn rebuild_hnsw_index_internal(conn: &Connection) -> anyhow::Result<()> {
    let has_embedding_i8_column: bool = conn
        .prepare("SELECT embedding_i8 FROM docs LIMIT 1")
        .is_ok();
    let has_embedding_scale_column: bool = conn
        .prepare("SELECT embedding_scale FROM docs LIMIT 1")
        .is_ok();

    let mut stmt = if has_embedding_i8_column && has_embedding_scale_column {
        conn.prepare("SELECT id, embedding, embedding_i8, embedding_scale FROM docs")?
    } else {
        conn.prepare(
            "SELECT id, embedding, NULL AS embedding_i8, NULL AS embedding_scale FROM docs",
        )?
    };

    let points: Vec<(i64, Vec<f32>)> = stmt
        .query_map([], |row| {
            let id: i64 = row.get(0)?;
            let embedding_blob: Vec<u8> = row.get(1)?;
            let embedding_i8_blob: Option<Vec<u8>> = row.get(2)?;
            let embedding_scale: Option<f32> = row.get(3)?;

            // Build the HNSW graph using original high-precision f32 embeddings
            let _ = (embedding_i8_blob, embedding_scale);
            let embedding = decode_f32_embedding_or_warn(&embedding_blob, id);
            Ok((id, embedding))
        })?
        .filter_map(|r| r.ok())
        .filter(|(_, embedding)| !embedding.is_empty())
        .collect();

    if !points.is_empty() {
        build_hnsw_index(points)?;
    }
    Ok(())
}

/// Rebuild HNSW index.
pub fn rebuild_hnsw_index() -> anyhow::Result<()> {
    info!("[rebuild_hnsw] Starting index rebuild");
    let conn = get_connection()?;
    rebuild_hnsw_index_internal(&conn)?;
    info!("[rebuild_hnsw] Index rebuild complete");
    Ok(())
}

fn rebuild_bm25_index_internal(conn: &Connection) -> anyhow::Result<()> {
    let mut stmt = conn.prepare("SELECT id, content FROM docs")?;
    let docs: Vec<(i64, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .filter_map(|r| r.ok())
        .collect();
    if !docs.is_empty() {
        info!("[bm25] Building index from {} documents", docs.len());
        bm25_add_documents(docs);
    }
    Ok(())
}

/// Rebuild BM25 index.
pub fn rebuild_bm25_index() -> anyhow::Result<()> {
    info!("[rebuild_bm25] Starting index rebuild");
    let conn = get_connection()?;
    bm25_clear_index();
    rebuild_bm25_index_internal(&conn)?;
    info!("[rebuild_bm25] Index rebuild complete");
    Ok(())
}

#[derive(Debug, Clone)]
pub struct AddDocumentResult {
    pub success: bool,
    pub is_duplicate: bool,
    pub message: String,
}

/// Add document with embedding vector (with deduplication).
pub fn add_document(content: String, embedding: Vec<f32>) -> anyhow::Result<AddDocumentResult> {
    info!("[add_document] Saving document");
    debug!(
        "[add_document] content length: {} chars, embedding dims: {}",
        content.chars().count(),
        embedding.len()
    );

    if embedding.is_empty() {
        error!("[add_document] Embedding is empty!");
        return Ok(AddDocumentResult {
            success: false,
            is_duplicate: false,
            message: "Embedding vector is empty".to_string(),
        });
    }

    let content_hash = calculate_content_hash(&content);
    let conn = get_connection()?;

    let existing: Option<i64> = conn
        .query_row(
            "SELECT id FROM docs WHERE content_hash = ?1",
            params![content_hash],
            |row| row.get(0),
        )
        .ok();

    if let Some(id) = existing {
        info!("[add_document] Duplicate found (id={})", id);
        return Ok(AddDocumentResult {
            success: true,
            is_duplicate: true,
            message: format!("Document already exists (id={})", id),
        });
    }

    let mut embedding_bytes: Vec<u8> = Vec::with_capacity(embedding.len() * 4);
    for f in &embedding {
        embedding_bytes.extend_from_slice(&f.to_ne_bytes());
    }

    let has_embedding_i8_column: bool = conn
        .prepare("SELECT embedding_i8 FROM docs LIMIT 1")
        .is_ok();
    let has_embedding_scale_column: bool = conn
        .prepare("SELECT embedding_scale FROM docs LIMIT 1")
        .is_ok();

    #[cfg(feature = "vector_quant_i8")]
    {
        let (embedding_i8_bytes, embedding_scale) = quantize_f32_to_u8_blob(&embedding);

        if has_embedding_i8_column && has_embedding_scale_column {
            conn.execute(
                "INSERT INTO docs (content, content_hash, embedding, embedding_i8, embedding_scale)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    content,
                    content_hash,
                    embedding_bytes,
                    embedding_i8_bytes,
                    embedding_scale
                ],
            )?;
        } else {
            conn.execute(
                "INSERT INTO docs (content, content_hash, embedding) VALUES (?1, ?2, ?3)",
                params![content, content_hash, embedding_bytes],
            )?;
        }
    }

    #[cfg(not(feature = "vector_quant_i8"))]
    {
        let _ = (has_embedding_i8_column, has_embedding_scale_column);
        conn.execute(
            "INSERT INTO docs (content, content_hash, embedding) VALUES (?1, ?2, ?3)",
            params![content, content_hash, embedding_bytes],
        )?;
    }

    let doc_id = conn.last_insert_rowid();
    bm25_add_document(doc_id, content.clone());
    incremental_add(doc_id, embedding);

    info!("[add_document] Document saved (id={})", doc_id);
    Ok(AddDocumentResult {
        success: true,
        is_duplicate: false,
        message: "Document saved successfully".to_string(),
    })
}

/// Legacy add_document for backward compatibility.
pub fn add_document_simple(content: String, embedding: Vec<f32>) -> anyhow::Result<()> {
    let result = add_document(content, embedding)?;
    if result.success {
        Ok(())
    } else {
        Err(anyhow::anyhow!(result.message))
    }
}

/// Similarity-based search (uses HNSW).
pub fn search_similar(query_embedding: Vec<f32>, top_k: u32) -> anyhow::Result<Vec<String>> {
    info!(
        "[search] Starting search, query dims: {}, top_k: {}",
        query_embedding.len(),
        top_k
    );

    if query_embedding.is_empty() {
        return Err(anyhow::anyhow!("Query embedding is empty"));
    }

    if is_hnsw_index_loaded() {
        info!("[search] Using HNSW index");
        return search_with_hnsw(query_embedding, top_k);
    }

    info!("[search] No HNSW index, attempting to build...");
    let conn = get_connection()?;

    if let Ok(()) = rebuild_hnsw_index_internal(&conn) {
        if is_hnsw_index_loaded() {
            return search_with_hnsw(query_embedding, top_k);
        }
    }

    info!("[search] Using Linear Scan (no HNSW index)");
    search_with_linear_scan(query_embedding, top_k)
}

fn search_with_hnsw(query_embedding: Vec<f32>, top_k: u32) -> anyhow::Result<Vec<String>> {
    let hnsw_results = search_hnsw(query_embedding, top_k as usize)?;
    if hnsw_results.is_empty() {
        return Ok(Vec::new());
    }

    let conn = get_connection()?;
    let mut results: Vec<String> = Vec::new();

    for result in hnsw_results {
        if let Ok(content) = conn.query_row(
            "SELECT content FROM docs WHERE id = ?1",
            params![result.id],
            |row| row.get::<_, String>(0),
        ) {
            let similarity = 1.0 - result.distance;
            info!(
                "[search] HNSW result: similarity={:.4}, content='{}...'",
                similarity,
                truncate_str(&content, 15)
            );
            results.push(content);
        }
    }

    info!("[search] HNSW search complete, {} results", results.len());
    Ok(results)
}

fn search_with_linear_scan(query_embedding: Vec<f32>, top_k: u32) -> anyhow::Result<Vec<String>> {
    let conn = get_connection()?;

    let query_norm = l2_norm_f32(&query_embedding);
    let mut candidates: Vec<(f64, String)> = Vec::new();

    #[cfg(feature = "vector_quant_i8")]
    let (query_i8, _query_i8_scale) = quantize_f32_to_i8(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let query_i8_norm = l2_norm_i8(&query_i8);
    #[cfg(feature = "vector_quant_i8")]
    let query_q8 = QueryQ8::new(&query_embedding);

    let mut stmt = match conn.prepare("SELECT content, embedding, embedding_i8 FROM docs") {
        Ok(stmt) => stmt,
        Err(_) => conn.prepare("SELECT content, embedding, NULL AS embedding_i8 FROM docs")?,
    };

    let rows = stmt.query_map([], |row| {
        let content: String = row.get(0)?;
        let embedding_blob: Vec<u8> = row.get(1)?;
        let embedding_i8_blob: Option<Vec<u8>> = row.get(2)?;
        Ok((content, embedding_blob, embedding_i8_blob))
    })?;

    for row in rows {
        let (content, embedding_blob, embedding_i8_blob) = row?;
        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &embedding_i8_blob;

        #[cfg(feature = "vector_quant_i8")]
        let similarity = if let Some(qblob) = embedding_i8_blob.as_deref() {
            if (qblob.len() == query_i8.len() || qblob.len() % 36 == 0) && query_i8_norm > 0.0 {
                cosine_similarity_q8(&query_q8, qblob, &query_i8, query_i8_norm)
            } else if let Some(embedding_vec) = decode_f32_embedding(&embedding_blob) {
                if embedding_vec.len() != query_embedding.len() {
                    continue;
                }
                cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding_vec)
            } else {
                continue;
            }
        } else if let Some(embedding_vec) = decode_f32_embedding(&embedding_blob) {
            if embedding_vec.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding_vec)
        } else {
            continue;
        };

        #[cfg(not(feature = "vector_quant_i8"))]
        let similarity = if let Some(embedding_vec) = decode_f32_embedding(&embedding_blob) {
            if embedding_vec.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding_vec)
        } else {
            continue;
        };

        candidates.push((similarity as f64, content));
    }

    candidates.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
    let result: Vec<String> = candidates
        .into_iter()
        .take(top_k as usize)
        .map(|(_, content)| content)
        .collect();

    info!("[search] Linear search complete, {} results", result.len());
    Ok(result)
}

/// Benchmark-only entrypoint for deterministic linear scan measurement.
///
/// Unlike `search_similar`, this function bypasses HNSW and executes
/// the linear scan path directly.
pub fn benchmark_search_linear_scan(
    query_embedding: Vec<f32>,
    top_k: u32,
) -> anyhow::Result<Vec<String>> {
    search_with_linear_scan(query_embedding, top_k)
}

/// Get document count.
pub fn get_document_count() -> anyhow::Result<i64> {
    let conn = get_connection()?;
    Ok(conn.query_row("SELECT COUNT(*) FROM docs", [], |row| row.get(0))?)
}

/// Clear all documents.
pub fn clear_all_documents() -> anyhow::Result<()> {
    let conn = get_connection()?;
    conn.execute("DELETE FROM docs", [])?;
    clear_hnsw_index();
    bm25_clear_index();
    clear_buffer();
    info!("[clear] All documents and indexes deleted");
    Ok(())
}

// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.

pub mod activation_metrics;
pub mod bm25_search;
pub mod compression_utils;
pub(crate) mod custom_hnsw;
pub mod db_pool;
pub mod document_parser;
pub mod error;
pub mod hnsw_index;
pub mod hybrid_search;
pub mod incremental_index;
pub mod ingest_metrics;
pub mod ingest_session;
pub mod logger;
pub mod migration_meta;
pub(crate) mod mmap_store;
pub mod query_metrics;
pub mod runtime_info;
pub mod semantic_chunker;
pub mod simple;
pub(crate) mod simple_rag;
pub mod source_rag;
pub mod tokenizer;
pub mod user_intent;
pub(crate) mod vector_math;
#[cfg(feature = "vector_quant_i8")]
pub(crate) mod vector_quant;

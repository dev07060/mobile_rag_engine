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
//! BM25 Keyword Search for Hybrid RAG - lightweight implementation optimized for mobile.

use log::{debug, info};
use once_cell::sync::Lazy;
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;

static INVERTED_INDEX: Lazy<RwLock<InvertedIndex>> =
    Lazy::new(|| RwLock::new(InvertedIndex::new()));

#[derive(Clone, Debug)]
struct DocMeta {
    length: usize,
    #[allow(dead_code)]
    id: i64,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug)]
struct InvertedIndex {
    postings: HashMap<String, Vec<(i64, u32)>>,
    doc_meta: HashMap<i64, DocMeta>,
    doc_count: usize,
    avg_doc_length: f64,
    total_tokens: usize,
}

impl InvertedIndex {
    pub fn new() -> Self {
        Self {
            postings: HashMap::new(),
            doc_meta: HashMap::new(),
            doc_count: 0,
            avg_doc_length: 0.0,
            total_tokens: 0,
        }
    }

    pub fn add_document(&mut self, doc_id: i64, content: &str) {
        if self.doc_meta.contains_key(&doc_id) {
            return;
        }

        let tokens = tokenize_for_bm25(content);
        let doc_length = tokens.len();
        if doc_length == 0 {
            return;
        }

        let mut term_freqs: HashMap<String, u32> = HashMap::new();
        for token in &tokens {
            *term_freqs.entry(token.clone()).or_insert(0) += 1;
        }

        for (term, freq) in term_freqs {
            self.postings
                .entry(term)
                .or_insert_with(Vec::new)
                .push((doc_id, freq));
        }

        self.doc_meta.insert(
            doc_id,
            DocMeta {
                length: doc_length,
                id: doc_id,
            },
        );
        self.doc_count += 1;
        self.total_tokens += doc_length;
        self.avg_doc_length = self.total_tokens as f64 / self.doc_count as f64;
    }

    pub fn remove_document(&mut self, doc_id: i64) {
        if let Some(meta) = self.doc_meta.remove(&doc_id) {
            self.doc_count = self.doc_count.saturating_sub(1);
            self.total_tokens = self.total_tokens.saturating_sub(meta.length);
            self.avg_doc_length = if self.doc_count > 0 {
                self.total_tokens as f64 / self.doc_count as f64
            } else {
                0.0
            };

            for postings_list in self.postings.values_mut() {
                postings_list.retain(|(id, _)| *id != doc_id);
            }
            self.postings.retain(|_, v| !v.is_empty());
        }
    }

    pub fn search(&self, query: &str, top_k: usize) -> Vec<(i64, f64)> {
        if self.doc_count == 0 {
            return vec![];
        }

        let query_tokens = tokenize_for_bm25(query);
        if query_tokens.is_empty() {
            return vec![];
        }

        let k1 = 1.2;
        let b = 0.75;
        let mut scores: HashMap<i64, f64> = HashMap::new();

        for token in &query_tokens {
            if let Some(postings) = self.postings.get(token) {
                let n = postings.len() as f64;
                let idf = ((self.doc_count as f64 - n + 0.5) / (n + 0.5) + 1.0).ln();

                for &(doc_id, tf) in postings {
                    if let Some(meta) = self.doc_meta.get(&doc_id) {
                        let tf_f = tf as f64;
                        let doc_len = meta.length as f64;
                        let tf_component = (tf_f * (k1 + 1.0))
                            / (tf_f + k1 * (1.0 - b + b * (doc_len / self.avg_doc_length)));
                        *scores.entry(doc_id).or_insert(0.0) += idf * tf_component;
                    }
                }
            }
        }

        let mut results: Vec<(i64, f64)> = scores.into_iter().collect();
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(top_k);
        results
    }

    pub fn search_scoped_tokens(
        &self,
        query_tokens: &[String],
        scoped_doc_ids: &[i64],
        top_k: usize,
    ) -> Vec<(i64, f64)> {
        if self.doc_count == 0 || query_tokens.is_empty() || scoped_doc_ids.is_empty() {
            return vec![];
        }

        let mut scoped_ids = HashSet::with_capacity(scoped_doc_ids.len());
        let mut scoped_doc_count = 0usize;
        let mut scoped_total_tokens = 0usize;
        for doc_id in scoped_doc_ids {
            if !scoped_ids.insert(*doc_id) {
                continue;
            }
            if let Some(meta) = self.doc_meta.get(doc_id) {
                scoped_doc_count += 1;
                scoped_total_tokens += meta.length;
            }
        }

        if scoped_doc_count == 0 {
            return vec![];
        }

        let avg_doc_length = scoped_total_tokens as f64 / scoped_doc_count as f64;
        let k1 = 1.2;
        let b = 0.75;
        let mut scores: HashMap<i64, f64> = HashMap::new();

        for token in query_tokens {
            let Some(postings) = self.postings.get(token) else {
                continue;
            };

            let scoped_df = postings
                .iter()
                .filter(|(doc_id, _)| {
                    scoped_ids.contains(doc_id) && self.doc_meta.contains_key(doc_id)
                })
                .count();
            if scoped_df == 0 {
                continue;
            }

            let n = scoped_df as f64;
            let idf = ((scoped_doc_count as f64 - n + 0.5) / (n + 0.5) + 1.0).ln();

            for &(doc_id, tf) in postings {
                if !scoped_ids.contains(&doc_id) {
                    continue;
                }
                if let Some(meta) = self.doc_meta.get(&doc_id) {
                    let tf_f = tf as f64;
                    let doc_len = meta.length as f64;
                    let tf_component = (tf_f * (k1 + 1.0))
                        / (tf_f + k1 * (1.0 - b + b * (doc_len / avg_doc_length.max(1.0))));
                    *scores.entry(doc_id).or_insert(0.0) += idf * tf_component;
                }
            }
        }

        let mut results: Vec<(i64, f64)> = scores.into_iter().collect();
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(top_k);
        results
    }

    pub fn clear(&mut self) {
        self.postings.clear();
        self.doc_meta.clear();
        self.doc_count = 0;
        self.avg_doc_length = 0.0;
        self.total_tokens = 0;
    }

    pub fn len(&self) -> usize {
        self.doc_count
    }
    pub fn is_empty(&self) -> bool {
        self.doc_count == 0
    }
}

fn is_cjk_or_hangul(ch: char) -> bool {
    matches!(
        ch as u32,
        0x3040..=0x30FF | // Hiragana + Katakana
        0x3400..=0x4DBF | // CJK Extension A
        0x4E00..=0x9FFF | // CJK Unified Ideographs
        0xAC00..=0xD7A3   // Hangul Syllables
    )
}

fn keep_bm25_token(token: &str) -> bool {
    let mut chars = token.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if chars.next().is_some() {
        return true;
    }

    // Keep single-character tokens that are meaningful in practice:
    // CJK/Hangul glyphs, digits, and non-stopword ASCII identifiers (e.g., "c", "r").
    if is_cjk_or_hangul(first) || first.is_ascii_digit() {
        return true;
    }
    if first.is_ascii_alphabetic() {
        let lowered = first.to_ascii_lowercase();
        return lowered != 'a' && lowered != 'i';
    }
    false
}

pub(crate) fn tokenize_for_bm25(text: &str) -> Vec<String> {
    use unicode_segmentation::UnicodeSegmentation;

    // Use Unicode word segmentation for better CJK support
    // Handles Korean, Chinese, Japanese, and multi-language text
    text.unicode_words()
        .filter(|s| keep_bm25_token(s))
        .map(|s| s.to_lowercase())
        .collect()
}

/// Add document to BM25 index.
pub fn bm25_add_document(doc_id: i64, content: String) {
    let mut index = INVERTED_INDEX.write().unwrap();
    index.add_document(doc_id, &content);
    debug!("[bm25] Added document {} to index", doc_id);
}

/// Add multiple documents to BM25 index (batch).
pub fn bm25_add_documents(docs: Vec<(i64, String)>) {
    let doc_count = docs.len();
    let mut index = INVERTED_INDEX.write().unwrap();
    for (doc_id, content) in docs {
        index.add_document(doc_id, &content);
    }
    info!("[bm25] Added {} documents to index", doc_count);
}

/// Remove document from BM25 index.
pub fn bm25_remove_document(doc_id: i64) {
    let mut index = INVERTED_INDEX.write().unwrap();
    index.remove_document(doc_id);
    debug!("[bm25] Removed document {} from index", doc_id);
}

#[derive(Debug, Clone)]
pub struct Bm25SearchResult {
    pub doc_id: i64,
    pub score: f64,
}

/// Search using BM25.
pub fn bm25_search(query: String, top_k: u32) -> Vec<Bm25SearchResult> {
    let index = INVERTED_INDEX.read().unwrap();
    let results = index.search(&query, top_k as usize);
    debug!(
        "[bm25] Search for '{}' returned {} results",
        query,
        results.len()
    );
    results
        .into_iter()
        .map(|(doc_id, score)| Bm25SearchResult { doc_id, score })
        .collect()
}

pub(crate) fn bm25_search_scoped_tokens(
    query_tokens: &[String],
    scoped_doc_ids: &[i64],
    top_k: usize,
) -> Vec<Bm25SearchResult> {
    let index = INVERTED_INDEX.read().unwrap();
    let results = index.search_scoped_tokens(query_tokens, scoped_doc_ids, top_k);
    debug!(
        "[bm25] Scoped search over {} ids returned {} results",
        scoped_doc_ids.len(),
        results.len()
    );
    results
        .into_iter()
        .map(|(doc_id, score)| Bm25SearchResult { doc_id, score })
        .collect()
}

/// Clear BM25 index.
pub fn bm25_clear_index() {
    let mut index = INVERTED_INDEX.write().unwrap();
    index.clear();
    info!("[bm25] Index cleared");
}

/// Check if BM25 index is loaded.
pub fn is_bm25_index_loaded() -> bool {
    let index = INVERTED_INDEX.read().unwrap();
    !index.is_empty()
}

/// Get BM25 index document count.
pub fn bm25_get_document_count() -> usize {
    let index = INVERTED_INDEX.read().unwrap();
    index.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bm25_basic() {
        let mut index = InvertedIndex::new();
        index.add_document(1, "The quick brown fox jumps over the lazy dog");
        index.add_document(2, "The lazy cat sleeps all day");
        index.add_document(3, "Quick brown cats are rare");
        let results = index.search("lazy cat", 10);
        assert!(!results.is_empty());
        assert_eq!(results[0].0, 2);
    }

    #[test]
    fn test_tokenize_for_bm25() {
        let tokens = tokenize_for_bm25("Hello, World! This is a test.");
        assert!(tokens.contains(&"hello".to_string()));
        assert!(tokens.contains(&"world".to_string()));
    }

    #[test]
    fn test_tokenize_korean_basic() {
        // Korean sentence: "삼성전자 주가가 올랐다" (Samsung Electronics stock price rose)
        let tokens = tokenize_for_bm25("삼성전자 주가가 올랐다");
        assert!(tokens.contains(&"삼성전자".to_string()));
        assert!(tokens.contains(&"주가가".to_string()));
        assert!(tokens.contains(&"올랐다".to_string()));
    }

    #[test]
    fn test_tokenize_korean_mixed() {
        // Mixed Korean + English + numbers: "iPhone15 프로 출시"
        let tokens = tokenize_for_bm25("iPhone15 프로 출시");
        assert!(tokens.contains(&"iphone15".to_string()));
        assert!(tokens.contains(&"프로".to_string()));
        assert!(tokens.contains(&"출시".to_string()));
    }

    #[test]
    fn test_tokenize_korean_with_punctuation() {
        // Korean with punctuation: "안녕하세요! 반갑습니다."
        let tokens = tokenize_for_bm25("안녕하세요! 반갑습니다.");
        assert!(tokens.contains(&"안녕하세요".to_string()));
        assert!(tokens.contains(&"반갑습니다".to_string()));
        assert_eq!(tokens.len(), 2); // Only words, no punctuation
    }

    #[test]
    fn test_bm25_korean_search() {
        let mut index = InvertedIndex::new();
        index.add_document(1, "삼성전자 주가가 상승했습니다");
        index.add_document(2, "애플 아이폰 신제품 출시");
        index.add_document(3, "현대자동차 전기차 판매 증가");

        let results = index.search("삼성전자 주가", 10);
        assert!(!results.is_empty());
        assert_eq!(results[0].0, 1); // 삼성전자 document should be first
    }

    #[test]
    fn test_bm25_scoped_search_filters_and_uses_scope_stats() {
        let mut index = InvertedIndex::new();
        index.add_document(1, "apple apple checksum");
        index.add_document(2, "banana checksum");
        index.add_document(3, "apple checksum");

        let query_tokens = tokenize_for_bm25("apple");
        let scoped = index.search_scoped_tokens(&query_tokens, &[1, 2], 10);

        assert_eq!(scoped.len(), 1);
        assert_eq!(scoped[0].0, 1);

        let all = index.search_scoped_tokens(&query_tokens, &[1, 2, 3], 10);
        assert_eq!(all.len(), 2);
        assert!(all.iter().any(|(doc_id, _)| *doc_id == 3));
    }

    #[test]
    fn test_tokenize_single_char_cjk_and_code_tokens() {
        let tokens = tokenize_for_bm25("車 C R a i 7");
        assert!(tokens.contains(&"車".to_string()));
        assert!(tokens.contains(&"c".to_string()));
        assert!(tokens.contains(&"r".to_string()));
        assert!(tokens.contains(&"7".to_string()));
        assert!(!tokens.contains(&"a".to_string()));
        assert!(!tokens.contains(&"i".to_string()));
    }
}

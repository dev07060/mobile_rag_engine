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
//! Lightweight text compression for prompt optimization.

use std::collections::HashSet;
use std::ops::Range;

#[derive(Debug, Clone)]
pub struct CompressionOptions {
    pub remove_stopwords: bool,
    pub remove_duplicates: bool,
    pub language: String,
    pub level: i32,
}

impl Default for CompressionOptions {
    fn default() -> Self {
        Self {
            remove_stopwords: true,
            remove_duplicates: true,
            language: "en".to_string(),
            level: 1,
        }
    }
}

#[derive(Debug, Clone)]
pub struct CompressedText {
    pub text: String,
    pub original_chars: i32,
    pub compressed_chars: i32,
    pub ratio: f64,
    pub sentences_removed: i32,
    pub chars_saved_stopwords: i32,
    pub chars_saved_truncation: i32,
}

/// Full-width sentence terminators end a sentence wherever they appear.
fn is_cjk_terminator(ch: char) -> bool {
    matches!(ch, '。' | '！' | '？' | '｡')
}

/// Whether the char `ch` at byte `index` of `text` ends a sentence.
///
/// `.`, `?` and `!` end a sentence only before whitespace or the end of the
/// text, so decimals and versions ("3.14", "v1.2.3") stay whole.
fn ends_sentence(text: &str, index: usize, ch: char) -> bool {
    if is_cjk_terminator(ch) {
        return true;
    }
    matches!(ch, '.' | '?' | '!')
        && text[index + ch.len_utf8()..]
            .chars()
            .next()
            .map_or(true, char::is_whitespace)
}

/// Byte ranges of the sentences in `text`, each trimmed of whitespace.
fn sentence_ranges(text: &str) -> Vec<Range<usize>> {
    fn push_trimmed(text: &str, range: Range<usize>, out: &mut Vec<Range<usize>>) {
        let slice = &text[range.clone()];
        let start = range.start + (slice.len() - slice.trim_start().len());
        let end = range.start + slice.trim_end().len();
        if start < end {
            out.push(start..end);
        }
    }

    let mut ranges = Vec::new();
    let mut start = 0;
    for (index, ch) in text.char_indices() {
        if ends_sentence(text, index, ch) {
            let end = index + ch.len_utf8();
            push_trimmed(text, start..end, &mut ranges);
            start = end;
        }
    }
    push_trimmed(text, start..text.len(), &mut ranges);
    ranges
}

/// Split text into sentences.
pub fn split_sentences(text: String) -> Vec<String> {
    sentence_ranges(&text)
        .into_iter()
        .map(|range| text[range].to_string())
        .collect()
}

/// Calculate hash for sentence deduplication (FNV-1a).
pub fn sentence_hash(sentence: String) -> u64 {
    let normalized: String = sentence
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in normalized.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Compress text with deduplication and truncation.
pub fn compress_text(text: String, max_chars: i32, options: CompressionOptions) -> CompressedText {
    let original_chars = text.chars().count() as i32;

    if text.is_empty() {
        return CompressedText {
            text: String::new(),
            original_chars: 0,
            compressed_chars: 0,
            ratio: 1.0,
            sentences_removed: 0,
            chars_saved_stopwords: 0,
            chars_saved_truncation: 0,
        };
    }

    let ranges = sentence_ranges(&text);
    let original_sentence_count = ranges.len();

    // Keep each sentence once, and join kept sentences with the whitespace
    // that followed them in the input ("" between CJK sentences).
    let mut result = String::new();
    let mut kept_count = 0usize;
    let mut seen_hashes = HashSet::new();
    let mut separator = "";
    for (i, range) in ranges.iter().enumerate() {
        let sentence = &text[range.clone()];
        if options.remove_duplicates && !seen_hashes.insert(sentence_hash(sentence.to_string())) {
            continue;
        }
        if kept_count > 0 {
            result.push_str(separator);
        }
        result.push_str(sentence);
        kept_count += 1;
        separator = ranges
            .get(i + 1)
            .map_or("", |next| &text[range.end..next.start]);
    }
    let chars_before_truncation = result.chars().count() as i32;

    if max_chars > 0 && result.chars().count() > max_chars as usize {
        let cut = result
            .char_indices()
            .nth(max_chars as usize)
            .map_or(result.len(), |(index, _)| index);
        // End on the last sentence boundary inside the cut, judged against
        // the untruncated text (a "." right before the cut may be "3.14").
        let sentence_end = result[..cut]
            .char_indices()
            .filter(|&(index, ch)| ends_sentence(&result, index, ch))
            .last()
            .map(|(index, ch)| index + ch.len_utf8());
        result.truncate(sentence_end.unwrap_or(cut));
    }

    let chars_saved_truncation = chars_before_truncation - result.chars().count() as i32;
    let compressed_chars = result.chars().count() as i32;
    let sentences_removed = (original_sentence_count - kept_count) as i32;

    CompressedText {
        text: result,
        original_chars,
        compressed_chars,
        ratio: if original_chars > 0 {
            compressed_chars as f64 / original_chars as f64
        } else {
            1.0
        },
        sentences_removed,
        chars_saved_stopwords: 0,
        chars_saved_truncation,
    }
}

/// Quick compress with default options.
pub fn compress_text_simple(text: String, level: i32) -> String {
    compress_text(
        text,
        0,
        CompressionOptions {
            level,
            ..Default::default()
        },
    )
    .text
}

/// Check if text needs compression based on token estimate.
pub fn should_compress(text: String, token_threshold: i32) -> bool {
    text.chars().count() / 4 > token_threshold as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_sentences() {
        let sentences = split_sentences("Hello. World!".to_string());
        assert_eq!(sentences.len(), 2);
    }

    #[test]
    fn test_sentence_hash_identical() {
        let hash1 = sentence_hash("Hello World".to_string());
        let hash2 = sentence_hash("hello world".to_string());
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_compress_text_removes_duplicates() {
        let text = "First. Second. First.".to_string();
        let options = CompressionOptions {
            remove_duplicates: true,
            remove_stopwords: false,
            level: 1,
            ..Default::default()
        };
        let result = compress_text(text, 0, options);
        assert_eq!(result.sentences_removed, 1);
    }

    // Q3 A2: Korean, Japanese, Chinese, NFD Hangul, full-width, emoji and
    // decimals (Q0 test text rule).
    const MIXED: &str = "환불은 14일 이내에 가능합니다. 東京は大きい。大阪も大きい。\
北京是中国的首都！\u{1112}\u{1161}\u{11ab}\u{1100}\u{1173}\u{11af} ＲＡＧ 🚀 버전 3.14, v1.2.3 가격 ３.５달러.";

    fn no_dedupe() -> CompressionOptions {
        CompressionOptions {
            remove_duplicates: false,
            ..Default::default()
        }
    }

    #[test]
    fn test_compress_truncation_after_cjk_full_stop_does_not_panic() {
        let text = "東京は大きい。大阪も大きい。京都は古い".to_string();
        let result = compress_text(text, 12, no_dedupe());
        assert_eq!(result.text, "東京は大きい。");
    }

    #[test]
    fn test_compress_truncation_on_every_char_count_of_mixed_text() {
        let total = MIXED.chars().count() as i32;
        for max_chars in 1..=total {
            let result = compress_text(MIXED.to_string(), max_chars, CompressionOptions::default());
            assert!(result.text.chars().count() <= max_chars as usize);
            assert!(MIXED.starts_with(&result.text), "{max_chars}: {:?}", result.text);
        }
    }

    #[test]
    fn test_compress_keeps_decimals_versions_and_spacing() {
        let result = compress_text(MIXED.to_string(), 0, CompressionOptions::default());
        assert_eq!(result.text, MIXED);
        assert_eq!(result.sentences_removed, 0);
    }

    #[test]
    fn test_split_sentences_does_not_split_decimals_or_versions() {
        let sentences = split_sentences("Pi is 3.14 today. Use v1.2.3 now! 東京。大阪".to_string());
        assert_eq!(
            sentences,
            vec!["Pi is 3.14 today.", "Use v1.2.3 now!", "東京。", "大阪"]
        );
    }

    #[test]
    fn test_compress_removes_cjk_duplicate_without_adding_spaces() {
        let text = "東京は大きい。大阪も大きい。東京は大きい。京都は古い。".to_string();
        let result = compress_text(text, 0, CompressionOptions::default());
        assert_eq!(result.text, "東京は大きい。大阪も大きい。京都は古い。");
        assert_eq!(result.sentences_removed, 1);
    }

    #[test]
    fn test_compress_truncation_keeps_decimal_intact() {
        // The cut must land after "3.14 today." and not inside "3.14".
        let text = "Pi is 3.14 today. The rest is long enough to be cut".to_string();
        let result = compress_text(text, 30, no_dedupe());
        assert_eq!(result.text, "Pi is 3.14 today.");
    }
}

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
//! Semantic text chunking with paragraph-first strategy for multilingual support.

use crate::api::tokenizer::{count_tokens_untruncated, resolve_truncation_max_length};
use std::collections::HashMap;
use std::ops::Range;
use text_splitter::TextSplitter;

/// Chunk type classification.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChunkType {
    Definition,
    Example,
    List,
    Procedure,
    Comparison,
    General,
}

impl ChunkType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ChunkType::Definition => "definition",
            ChunkType::Example => "example",
            ChunkType::List => "list",
            ChunkType::Procedure => "procedure",
            ChunkType::Comparison => "comparison",
            ChunkType::General => "general",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "definition" => ChunkType::Definition,
            "example" => ChunkType::Example,
            "list" => ChunkType::List,
            "procedure" => ChunkType::Procedure,
            "comparison" => ChunkType::Comparison,
            _ => ChunkType::General,
        }
    }
}

/// Classify chunk by rule-based pattern matching.
#[flutter_rust_bridge::frb(sync)]
pub fn classify_chunk(text: &str) -> ChunkType {
    let text_lower = text.to_lowercase();

    // List detection
    let bullet_count = text
        .lines()
        .filter(|l| {
            let trimmed = l.trim();
            trimmed.starts_with("•")
                || trimmed.starts_with("●")
                || trimmed.starts_with("-")
                || trimmed.starts_with("*")
                || trimmed.starts_with("①")
                || trimmed.starts_with("②")
                || trimmed.starts_with("③")
                || trimmed.starts_with("④")
                || (trimmed.len() > 2
                    && trimmed.chars().next().map_or(false, |c| c.is_numeric())
                    && (trimmed.chars().nth(1) == Some('.') || trimmed.chars().nth(1) == Some(')')))
        })
        .count();
    if bullet_count >= 3 {
        return ChunkType::List;
    }

    // Definition patterns
    let definition_patterns = [
        "is defined as",
        "refers to",
        "means that",
        "is a type of",
        "can be defined as",
        "is known as",
    ];
    for pattern in definition_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Definition;
        }
    }

    // Example patterns
    let example_patterns = ["for example", "e.g.", "for instance", "such as", "example:"];
    for pattern in example_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Example;
        }
    }

    // Procedure patterns
    let procedure_patterns = [
        "step 1",
        "step 2",
        "first,",
        "then,",
        "finally,",
        "how to",
        "procedure",
        "instructions",
    ];
    let procedure_matches = procedure_patterns
        .iter()
        .filter(|p| text_lower.contains(*p))
        .count();
    if procedure_matches >= 2 {
        return ChunkType::Procedure;
    }

    // Comparison patterns
    let comparison_patterns = [
        "vs",
        "versus",
        "compared to",
        "in contrast",
        "on the other hand",
        "differs from",
        "difference between",
    ];
    for pattern in comparison_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Comparison;
        }
    }

    ChunkType::General
}

/// Semantic chunk result.
#[derive(Debug, Clone)]
pub struct SemanticChunk {
    pub index: i32,
    pub content: String,
    pub start_pos: i32,
    pub end_pos: i32,
    pub chunk_type: String,
}

trait TextSizer {
    fn size(&self, text: &str) -> Option<usize>;

    fn budget(&self, text: &str, max_chars: usize) -> usize;

    fn fits(&self, text: &str, max_chars: usize) -> bool {
        self.size(text)
            .map(|size| size <= self.budget(text, max_chars))
            .unwrap_or(true)
    }
}

struct CharSizer;

impl TextSizer for CharSizer {
    fn size(&self, text: &str) -> Option<usize> {
        Some(text.chars().count())
    }

    fn budget(&self, _text: &str, max_chars: usize) -> usize {
        max_chars
    }
}

struct PlainTextPlanner {
    max_chars: usize,
    char_sizer: CharSizer,
}

impl PlainTextPlanner {
    fn new(max_chars: usize) -> Self {
        Self {
            max_chars,
            char_sizer: CharSizer,
        }
    }

    fn fits_range(&self, text: &str, range: &Range<usize>) -> bool {
        let slice = &text[range.clone()];
        self.char_sizer.fits(slice, self.max_chars)
    }
}

fn line_content_end(line: &str) -> usize {
    line.trim_end_matches(|c| c == '\n' || c == '\r').len()
}

fn split_paragraph_ranges(text: &str) -> Vec<Range<usize>> {
    let mut paragraphs = Vec::new();
    let mut paragraph_start: Option<usize> = None;
    let mut paragraph_end = 0usize;
    let mut cursor = 0usize;

    for line in text.split_inclusive('\n') {
        let line_start = cursor;
        cursor += line.len();
        let line_end = line_start + line_content_end(line);
        let line_content = &text[line_start..line_end];

        if line_content.trim().is_empty() {
            if let Some(start) = paragraph_start.take() {
                paragraphs.push(start..paragraph_end);
            }
            continue;
        }

        if paragraph_start.is_none() {
            paragraph_start = Some(line_start);
        }
        paragraph_end = line_end;
    }

    if let Some(start) = paragraph_start {
        paragraphs.push(start..paragraph_end);
    }

    paragraphs
}

fn split_line_ranges(text: &str, range: &Range<usize>) -> Vec<Range<usize>> {
    let mut lines = Vec::new();
    let slice = &text[range.clone()];
    let mut cursor = range.start;

    for line in slice.split_inclusive('\n') {
        let line_start = cursor;
        cursor += line.len();
        let line_end = line_start + line_content_end(line);

        if line_end > line_start && !text[line_start..line_end].trim().is_empty() {
            lines.push(line_start..line_end);
        }
    }

    if cursor < range.end && !text[cursor..range.end].trim().is_empty() {
        lines.push(cursor..range.end);
    }

    lines
}

fn subslice_range(parent: &str, child: &str) -> Option<Range<usize>> {
    let parent_start = parent.as_ptr() as usize;
    let child_start = child.as_ptr() as usize;
    if child_start < parent_start {
        return None;
    }

    let local_start = child_start - parent_start;
    let local_end = local_start + child.len();
    if local_end > parent.len() {
        return None;
    }

    Some(local_start..local_end)
}

fn advance_by_chars(text: &str, start: usize, end: usize, char_count: usize) -> usize {
    if char_count == 0 {
        return start;
    }

    let slice = &text[start..end];
    let mut consumed = 0usize;
    for (offset, ch) in slice.char_indices() {
        consumed += 1;
        if consumed == char_count {
            return start + offset + ch.len_utf8();
        }
    }

    end
}

fn char_count_in_range(text: &str, range: &Range<usize>) -> usize {
    text[range.clone()].chars().count()
}

fn largest_fitting_prefix_end(
    text: &str,
    start: usize,
    end: usize,
    upper_char_count: usize,
    planner: &PlainTextPlanner,
) -> usize {
    let mut low = 1usize;
    let mut high = upper_char_count;
    let mut best = start;

    while low <= high {
        let mid = low + (high - low) / 2;
        let candidate_end = advance_by_chars(text, start, end, mid);
        if planner.fits_range(text, &(start..candidate_end)) {
            best = candidate_end;
            low = mid + 1;
        } else if mid == 1 {
            break;
        } else {
            high = mid - 1;
        }
    }

    best
}

fn split_hard_range(
    text: &str,
    range: Range<usize>,
    planner: &PlainTextPlanner,
) -> Vec<Range<usize>> {
    let mut parts = Vec::new();
    let mut cursor = range.start;

    while cursor < range.end {
        let remaining = cursor..range.end;
        let upper_char_count = char_count_in_range(text, &remaining).min(planner.max_chars.max(1));
        let tentative_end = advance_by_chars(text, cursor, range.end, upper_char_count);
        let candidate = cursor..tentative_end;

        if planner.fits_range(text, &candidate) {
            parts.push(candidate);
            cursor = tentative_end;
            continue;
        }

        let best_end =
            largest_fitting_prefix_end(text, cursor, range.end, upper_char_count, planner);
        let next_end = if best_end > cursor {
            best_end
        } else {
            advance_by_chars(text, cursor, range.end, 1)
        };

        parts.push(cursor..next_end);
        cursor = next_end;
    }

    parts
}

fn split_semantic_range(
    text: &str,
    range: Range<usize>,
    planner: &PlainTextPlanner,
) -> Vec<Range<usize>> {
    let slice = &text[range.clone()];
    let splitter = TextSplitter::new(planner.max_chars.max(1));
    let mut subranges = Vec::new();

    for piece in splitter.chunks(slice) {
        if piece.is_empty() {
            continue;
        }

        let Some(local_range) = subslice_range(slice, piece) else {
            return split_hard_range(text, range, planner);
        };
        subranges.push((range.start + local_range.start)..(range.start + local_range.end));
    }

    if subranges.is_empty() || (subranges.len() == 1 && subranges[0] == range) {
        return split_hard_range(text, range, planner);
    }

    let mut planned = Vec::new();
    for subrange in subranges {
        if planner.fits_range(text, &subrange) {
            planned.push(subrange);
        } else {
            planned.extend(split_hard_range(text, subrange, planner));
        }
    }

    planned
}

fn token_count_cache_key(range: &Range<usize>) -> (usize, usize) {
    (range.start, range.end)
}

fn cached_token_count(
    text: &str,
    range: &Range<usize>,
    cache: &mut HashMap<(usize, usize), usize>,
) -> Option<usize> {
    let key = token_count_cache_key(range);
    if let Some(count) = cache.get(&key) {
        return Some(*count);
    }

    let count = count_tokens_untruncated(&text[range.clone()]).ok()?;
    cache.insert(key, count);
    Some(count)
}

fn fits_token_budget(
    text: &str,
    range: &Range<usize>,
    cache: &mut HashMap<(usize, usize), usize>,
) -> bool {
    let slice = &text[range.clone()];
    cached_token_count(text, range, cache)
        .map(|count| count <= resolve_truncation_max_length(slice))
        .unwrap_or(true)
}

fn largest_token_fitting_prefix_end(
    text: &str,
    start: usize,
    end: usize,
    upper_char_count: usize,
    cache: &mut HashMap<(usize, usize), usize>,
) -> usize {
    let mut low = 1usize;
    let mut high = upper_char_count;
    let mut best = start;

    while low <= high {
        let mid = low + (high - low) / 2;
        let candidate_end = advance_by_chars(text, start, end, mid);
        if fits_token_budget(text, &(start..candidate_end), cache) {
            best = candidate_end;
            low = mid + 1;
        } else if mid == 1 {
            break;
        } else {
            high = mid - 1;
        }
    }

    best
}

fn split_token_budget_range(
    text: &str,
    range: Range<usize>,
    max_chars: usize,
    cache: &mut HashMap<(usize, usize), usize>,
) -> Vec<Range<usize>> {
    let mut parts = Vec::new();
    let mut cursor = range.start;

    while cursor < range.end {
        let remaining = cursor..range.end;
        if fits_token_budget(text, &remaining, cache) {
            parts.push(remaining);
            break;
        }

        let upper_char_count = char_count_in_range(text, &remaining).min(max_chars.max(1));
        let best_end =
            largest_token_fitting_prefix_end(text, cursor, range.end, upper_char_count, cache);
        let next_end = if best_end > cursor {
            best_end
        } else {
            advance_by_chars(text, cursor, range.end, 1)
        };

        parts.push(cursor..next_end);
        cursor = next_end;
    }

    parts
}

fn enforce_token_budget(
    text: &str,
    ranges: Vec<Range<usize>>,
    max_chars: usize,
) -> Vec<Range<usize>> {
    let mut cache = HashMap::new();
    let mut validated = Vec::new();

    for range in ranges {
        if fits_token_budget(text, &range, &mut cache) {
            validated.push(range);
        } else {
            validated.extend(split_token_budget_range(text, range, max_chars, &mut cache));
        }
    }

    validated
}

fn plan_plain_text_ranges_char_budget(text: &str, max_chars: usize) -> Vec<Range<usize>> {
    let planner = PlainTextPlanner::new(max_chars);
    let mut chunks = Vec::new();

    for paragraph in split_paragraph_ranges(text) {
        if planner.fits_range(text, &paragraph) {
            chunks.push(paragraph);
            continue;
        }

        let mut line_buffer: Option<Range<usize>> = None;
        for line in split_line_ranges(text, &paragraph) {
            let is_article_start = is_article_title(text[line.clone()].trim());
            let candidate = match &line_buffer {
                Some(buffer) => buffer.start..line.end,
                None => line.clone(),
            };

            if !is_article_start && planner.fits_range(text, &candidate) {
                line_buffer = Some(candidate);
                continue;
            }

            if let Some(buffer) = line_buffer.take() {
                chunks.push(buffer);
            }

            if planner.fits_range(text, &line) {
                line_buffer = Some(line);
            } else {
                chunks.extend(split_semantic_range(text, line, &planner));
            }
        }

        if let Some(buffer) = line_buffer.take() {
            chunks.push(buffer);
        }
    }

    chunks
}

fn plan_plain_text_ranges(text: &str, max_chars: usize) -> Vec<Range<usize>> {
    enforce_token_budget(
        text,
        plan_plain_text_ranges_char_budget(text, max_chars),
        max_chars,
    )
}

fn build_semantic_chunk(text: &str, range: Range<usize>, index: i32) -> SemanticChunk {
    let content = &text[range.clone()];
    let chunk_type = classify_chunk(content.trim()).as_str().to_string();
    SemanticChunk {
        index,
        content: content.to_string(),
        start_pos: range.start as i32,
        end_pos: range.end as i32,
        chunk_type,
    }
}

fn materialize_semantic_chunks(text: &str, ranges: Vec<Range<usize>>) -> Vec<SemanticChunk> {
    ranges
        .into_iter()
        .enumerate()
        .map(|(index, range)| build_semantic_chunk(text, range, index as i32))
        .collect()
}

fn overlap_start(text: &str, range: &Range<usize>, overlap_chars: usize) -> usize {
    if overlap_chars == 0 {
        return range.end;
    }

    let total_chars = char_count_in_range(text, range);
    if total_chars <= overlap_chars {
        return range.start;
    }

    advance_by_chars(text, range.start, range.end, total_chars - overlap_chars)
}

/// Split text into semantic chunks using paragraph-first strategy.
#[flutter_rust_bridge::frb(sync)]
pub fn semantic_chunk(text: String, max_chars: i32) -> Vec<SemanticChunk> {
    if text.is_empty() {
        return vec![];
    }

    materialize_semantic_chunks(
        &text,
        plan_plain_text_ranges(&text, max_chars.max(100) as usize),
    )
}

#[allow(dead_code)]
fn is_article_title(_line: &str) -> bool {
    false
}

/// Split text with overlap (API compatibility wrapper).
#[flutter_rust_bridge::frb(sync)]
pub fn semantic_chunk_with_overlap(
    text: String,
    max_chars: i32,
    overlap_chars: i32,
) -> Vec<SemanticChunk> {
    if text.is_empty() {
        return vec![];
    }

    let base_ranges = plan_plain_text_ranges(&text, max_chars.max(100) as usize);
    let overlap = overlap_chars.max(0) as usize;

    if overlap == 0 || base_ranges.len() <= 1 {
        return materialize_semantic_chunks(&text, base_ranges);
    }

    let ranges = base_ranges
        .iter()
        .enumerate()
        .map(|(index, range)| {
            if index == 0 {
                range.clone()
            } else {
                overlap_start(&text, &base_ranges[index - 1], overlap)..range.end
            }
        })
        .collect();

    materialize_semantic_chunks(&text, ranges)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::tokenizer::{
        count_tokens_untruncated, count_tokens_untruncated_call_count, init_tokenizer,
        reset_count_tokens_untruncated_call_count, resolve_truncation_max_length,
    };
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    use tokenizers::models::wordlevel::WordLevel;
    use tokenizers::pre_tokenizers::whitespace::Whitespace;
    use uuid::Uuid;

    static TOKENIZER_TEST_MUTEX: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn init_test_tokenizer() {
        let suffix = Uuid::new_v4().to_string();
        let vocab_path =
            std::env::temp_dir().join(format!("mobile_rag_engine_test_vocab_{suffix}.json"));
        std::fs::write(&vocab_path, r#"{"[UNK]":0,"hello":1,"world":2}"#)
            .expect("failed to write test vocab");

        let model = WordLevel::builder()
            .files(vocab_path.to_str().unwrap().to_string())
            .unk_token("[UNK]".to_string())
            .build()
            .expect("failed to build test tokenizer");
        let mut tokenizer = tokenizers::Tokenizer::new(model);
        tokenizer.with_pre_tokenizer(Some(Whitespace));

        let tokenizer_path =
            std::env::temp_dir().join(format!("mobile_rag_engine_test_tokenizer_{suffix}.json"));
        tokenizer
            .save(tokenizer_path.to_str().unwrap(), false)
            .expect("failed to save test tokenizer");
        init_tokenizer(tokenizer_path.to_str().unwrap().to_string())
            .expect("failed to init tokenizer");
    }

    fn assert_chunk_matches_source(text: &str, chunk: &SemanticChunk) {
        let start = chunk.start_pos as usize;
        let end = chunk.end_pos as usize;
        assert!(
            text.is_char_boundary(start),
            "start_pos {} is not on a char boundary for {:?}",
            start,
            chunk.content
        );
        assert!(
            text.is_char_boundary(end),
            "end_pos {} is not on a char boundary for {:?}",
            end,
            chunk.content
        );
        assert_eq!(&text[start..end], chunk.content);
    }

    #[test]
    fn test_semantic_chunk_basic() {
        let text = "This is the first sentence. This is the second sentence.";
        let chunks = semantic_chunk(text.to_string(), 50);
        assert!(!chunks.is_empty());
    }

    #[test]
    fn test_empty_text() {
        let chunks = semantic_chunk("".to_string(), 100);
        assert!(chunks.is_empty());
    }

    #[test]
    fn test_classify_chunk_definition() {
        assert_eq!(
            classify_chunk("A blockchain is defined as a distributed ledger."),
            ChunkType::Definition
        );
    }

    #[test]
    fn test_classify_chunk_list() {
        let list_text = "Features:\n• Item1\n• Item2\n• Item3";
        assert_eq!(classify_chunk(list_text), ChunkType::List);
    }

    #[test]
    fn test_chunk_type_string_conversion() {
        assert_eq!(ChunkType::Definition.as_str(), "definition");
        assert_eq!(ChunkType::from_str("definition"), ChunkType::Definition);
        assert_eq!(ChunkType::from_str("unknown"), ChunkType::General);
    }

    #[test]
    fn test_semantic_chunk_with_overlap_applies_prefix() {
        let text = "First chunk content here.\n\nSecond chunk starts here.";
        let chunks = semantic_chunk_with_overlap(text.to_string(), 500, 5);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].content, "First chunk content here.");
        assert!(chunks[1].content.starts_with("here."));
        assert!(chunks[1].content.contains("Second chunk starts here."));
    }

    #[test]
    fn test_semantic_chunk_with_overlap_zero_overlap_is_noop() {
        let text = "First paragraph.\n\nSecond paragraph.";
        let plain = semantic_chunk(text.to_string(), 500);
        let overlapped = semantic_chunk_with_overlap(text.to_string(), 500, 0);
        assert_eq!(plain.len(), overlapped.len());
        assert_eq!(plain[0].content, overlapped[0].content);
        assert_eq!(plain[1].content, overlapped[1].content);
    }

    #[test]
    fn test_semantic_chunk_offsets_are_raw_byte_ranges() {
        let text = "  첫 문단🙂\n\n둘째 문단";
        let chunks = semantic_chunk(text.to_string(), 500);

        assert_eq!(chunks.len(), 2);
        for chunk in &chunks {
            assert_chunk_matches_source(text, chunk);
        }
    }

    #[test]
    fn test_semantic_chunk_with_overlap_preserves_raw_source_slice() {
        let text = "Alpha beta gamma.\n\n둘째 문단🙂.";
        let chunks = semantic_chunk_with_overlap(text.to_string(), 500, 6);

        assert_eq!(chunks.len(), 2);
        for chunk in &chunks {
            assert_chunk_matches_source(text, chunk);
        }
    }

    #[test]
    fn test_semantic_chunk_respects_tokenizer_budget_before_runtime_truncation() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();

        let text = std::iter::repeat("hello")
            .take(700)
            .collect::<Vec<_>>()
            .join(" ");
        let chunks = semantic_chunk(text, 5000);

        assert!(chunks.len() > 1);
        for chunk in &chunks {
            let token_count = count_tokens_untruncated(&chunk.content).unwrap();
            assert!(token_count <= resolve_truncation_max_length(&chunk.content));
        }
    }

    #[test]
    fn test_semantic_chunk_token_count_guard_for_long_repeated_tokens() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();
        reset_count_tokens_untruncated_call_count();

        let text = std::iter::repeat("hello world")
            .take(240)
            .collect::<Vec<_>>()
            .join("\n");
        let chunks = semantic_chunk(text, 5000);

        assert_eq!(chunks.len(), 1);
        assert!(count_tokens_untruncated_call_count() <= 20);
    }

    #[test]
    fn test_semantic_chunk_token_count_guard_for_long_cjk_input() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();
        reset_count_tokens_untruncated_call_count();

        let text = std::iter::repeat("가나다라마바사")
            .take(220)
            .collect::<Vec<_>>()
            .join("\n");
        let chunks = semantic_chunk(text, 5000);

        assert_eq!(chunks.len(), 1);
        assert!(count_tokens_untruncated_call_count() <= 20);
    }
}

// =============================================================================
// Structure-Aware Chunking (Markdown)
// =============================================================================

/// Structured chunk with header path for context inheritance.
#[derive(Debug, Clone)]
pub struct StructuredChunk {
    pub index: i32,
    pub content: String,
    pub header_path: String, // e.g., "# Installation > ## Windows"
    pub chunk_type: String,  // "text", "code", "table", "header"
    pub start_pos: i32,
    pub end_pos: i32,
    pub batch_id: Option<String>,
    pub batch_index: Option<i32>,
    pub batch_total: Option<i32>,
}

/// Chunking strategy for structure-aware chunking.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChunkingStrategy {
    Recursive, // Default paragraph-based
    Markdown,  // Header-based with structure preservation
}

/// Markdown chunk with structure preservation and metadata inheritance.
///
/// - Splits by Markdown headers (#, ##, ###)
/// - Preserves code blocks (```) as single units
/// - Preserves tables (|---|) as single units
/// - Inherits header path as metadata
#[flutter_rust_bridge::frb(sync)]
pub fn markdown_chunk(text: String, max_chars: i32) -> Vec<StructuredChunk> {
    if text.is_empty() {
        return vec![];
    }

    let max_chars_usize = max_chars.max(100) as usize;
    let mut chunks = Vec::new();
    let mut chunk_index = 0i32;

    // Track header hierarchy for breadcrumbs
    let mut header_stack: Vec<(i32, String)> = vec![]; // (level, header_text)

    let sections = split_by_headers(&text);

    for section in sections {
        // Update header stack based on section header
        if let Some((level, header_text)) = &section.header {
            // Pop headers of same or lower level
            while !header_stack.is_empty() && header_stack.last().unwrap().0 >= *level {
                header_stack.pop();
            }
            header_stack.push((*level, header_text.clone()));
        }

        // Build header path
        let header_path = header_stack
            .iter()
            .map(|(_, h)| h.as_str())
            .collect::<Vec<_>>()
            .join(" > ");

        let content = &text[section.content_range.clone()];
        if content.is_empty() {
            continue;
        }

        // Determine chunk type (includes language for code blocks)
        let chunk_type = if section.is_code_block {
            match &section.code_language {
                Some(lang) if !lang.is_empty() => format!("code:{}", lang),
                _ => "code".to_string(),
            }
        } else if section.is_table {
            "table".to_string()
        } else if section.header.is_some() && content.lines().count() <= 2 {
            "header".to_string()
        } else {
            "text".to_string()
        };

        let section_char_count = content.chars().count();
        let sub_ranges = if section_char_count <= max_chars_usize {
            vec![section.content_range.clone()]
        } else if section.is_table || section.is_code_block {
            split_by_line_ranges(&text, &section.content_range, max_chars_usize)
        } else {
            plan_plain_text_subranges(&text, &section.content_range, max_chars_usize)
        };

        let batch_id: Option<String> = if section.is_code_block && sub_ranges.len() > 1 {
            Some(uuid::Uuid::new_v4().to_string())
        } else {
            None
        };
        let total_chunks = sub_ranges.len();

        for (i, sub_range) in sub_ranges.into_iter().enumerate() {
            let sub_type = if section.is_code_block || section.is_table {
                chunk_type.clone()
            } else if chunk_type == "header" && total_chunks == 1 {
                chunk_type.clone()
            } else {
                "text".to_string()
            };

            chunks.push(StructuredChunk {
                index: chunk_index,
                content: text[sub_range.clone()].to_string(),
                header_path: header_path.clone(),
                chunk_type: sub_type,
                start_pos: sub_range.start as i32,
                end_pos: sub_range.end as i32,
                batch_id: batch_id.clone(),
                batch_index: batch_id.as_ref().map(|_| i as i32),
                batch_total: batch_id.as_ref().map(|_| total_chunks as i32),
            });
            chunk_index += 1;
        }
    }

    chunks
}

// =============================================================================
// Helper structures and functions
// =============================================================================

struct Section {
    header: Option<(i32, String)>, // (level, header_text)
    content_range: Range<usize>,
    is_code_block: bool,
    is_table: bool,
    code_language: Option<String>, // e.g., "rust", "bash", "yaml"
}

#[derive(Debug, Clone, Copy)]
struct MarkdownLine {
    start: usize,
    end: usize,
    content_end: usize,
}

fn trim_range(text: &str, mut range: Range<usize>) -> Option<Range<usize>> {
    while range.start < range.end {
        let slice = &text[range.start..range.end];
        let line_end = slice
            .find('\n')
            .map(|offset| range.start + offset + 1)
            .unwrap_or(range.end);
        let line = &text[range.start..line_end];
        let content_end = range.start + line_content_end(line);
        if text[range.start..content_end].trim().is_empty() {
            range.start = line_end;
        } else {
            break;
        }
    }

    while range.start < range.end {
        let ch = text[range.start..range.end].chars().next_back().unwrap();
        if ch == '\n' || ch == '\r' {
            range.end -= ch.len_utf8();
            continue;
        }

        let slice = &text[range.start..range.end];
        let line_start = slice
            .rfind('\n')
            .map(|offset| range.start + offset + 1)
            .unwrap_or(range.start);
        if text[line_start..range.end].trim().is_empty() {
            range.end = line_start;
        } else {
            break;
        }
    }

    (range.start < range.end).then_some(range)
}

fn markdown_line_ranges(text: &str) -> Vec<MarkdownLine> {
    let mut lines = Vec::new();
    let mut cursor = 0usize;

    for line in text.split_inclusive('\n') {
        let start = cursor;
        cursor += line.len();
        let content_end = start + line_content_end(line);
        lines.push(MarkdownLine {
            start,
            end: cursor,
            content_end,
        });
    }

    if lines.is_empty() && !text.is_empty() {
        lines.push(MarkdownLine {
            start: 0,
            end: text.len(),
            content_end: text.len(),
        });
    }

    lines
}

fn is_markdown_header(line: &str) -> bool {
    line.starts_with('#')
}

fn parse_markdown_header(line: &str) -> (i32, String) {
    let level = line.chars().take_while(|c| *c == '#').count() as i32;
    let header_text = line.trim_start_matches('#').trim().to_string();
    (level, header_text)
}

fn is_table_line(line: &str) -> bool {
    line.starts_with('|') && line.ends_with('|')
}

fn parse_code_block_language(line: &str) -> Option<String> {
    let trimmed = line.trim().trim_start_matches('`').trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn flush_text_section(
    text: &str,
    sections: &mut Vec<Section>,
    current_text_start: &mut Option<usize>,
    current_text_header: &mut Option<(i32, String)>,
    end: usize,
) {
    let Some(start) = current_text_start.take() else {
        return;
    };
    let header = current_text_header.take();

    if let Some(content_range) = trim_range(text, start..end) {
        sections.push(Section {
            header,
            content_range,
            is_code_block: false,
            is_table: false,
            code_language: None,
        });
    }
}

fn plan_plain_text_subranges(
    text: &str,
    range: &Range<usize>,
    max_chars: usize,
) -> Vec<Range<usize>> {
    let local_ranges = plan_plain_text_ranges(&text[range.clone()], max_chars);
    if local_ranges.is_empty() {
        return vec![range.clone()];
    }

    local_ranges
        .into_iter()
        .map(|local| (range.start + local.start)..(range.start + local.end))
        .collect()
}

fn split_by_line_ranges(text: &str, range: &Range<usize>, max_chars: usize) -> Vec<Range<usize>> {
    let planner = PlainTextPlanner::new(max_chars.max(1));
    let mut chunks = Vec::new();
    let mut current_start: Option<usize> = None;
    let mut current_end = range.start;
    let mut current_chars = 0usize;
    let mut cursor = range.start;

    for line in text[range.clone()].split_inclusive('\n') {
        let line_start = cursor;
        cursor += line.len();
        let line_end = cursor;
        let line_chars = line.chars().count();

        if let Some(start) = current_start {
            if current_chars + line_chars <= max_chars {
                current_end = line_end;
                current_chars += line_chars;
                continue;
            }

            if let Some(trimmed) = trim_range(text, start..current_end) {
                chunks.push(trimmed);
            }
            current_start = None;
            current_chars = 0;
        }

        if line_chars <= max_chars {
            current_start = Some(line_start);
            current_end = line_end;
            current_chars = line_chars;
        } else {
            for subrange in split_hard_range(text, line_start..line_end, &planner) {
                if let Some(trimmed) = trim_range(text, subrange) {
                    chunks.push(trimmed);
                }
            }
        }
    }

    if let Some(start) = current_start {
        if let Some(trimmed) = trim_range(text, start..current_end) {
            chunks.push(trimmed);
        }
    }

    chunks
}

/// Split text by markdown headers while preserving code blocks and tables.
fn split_by_headers(text: &str) -> Vec<Section> {
    let lines = markdown_line_ranges(text);
    let mut sections: Vec<Section> = vec![];
    let mut current_text_start: Option<usize> = None;
    let mut current_text_header: Option<(i32, String)> = None;
    let mut index = 0usize;

    while index < lines.len() {
        let line = lines[index];
        let line_text = &text[line.start..line.content_end];
        let trimmed = line_text.trim();

        if trimmed.starts_with("```") {
            flush_text_section(
                text,
                &mut sections,
                &mut current_text_start,
                &mut current_text_header,
                line.start,
            );

            let block_start = line.start;
            let language = parse_code_block_language(line_text);
            let mut block_end = line.end;
            index += 1;

            while index < lines.len() {
                let candidate = lines[index];
                let candidate_text = &text[candidate.start..candidate.content_end];
                block_end = candidate.end;
                index += 1;
                if candidate_text.trim().starts_with("```") {
                    break;
                }
            }

            if let Some(content_range) = trim_range(text, block_start..block_end) {
                sections.push(Section {
                    header: None,
                    content_range,
                    is_code_block: true,
                    is_table: false,
                    code_language: language,
                });
            }
            continue;
        }

        if is_table_line(trimmed) {
            flush_text_section(
                text,
                &mut sections,
                &mut current_text_start,
                &mut current_text_header,
                line.start,
            );

            let table_start = line.start;
            let mut table_end = line.end;
            index += 1;

            while index < lines.len() {
                let candidate = lines[index];
                let candidate_text = &text[candidate.start..candidate.content_end];
                if !is_table_line(candidate_text.trim()) {
                    break;
                }
                table_end = candidate.end;
                index += 1;
            }

            if let Some(content_range) = trim_range(text, table_start..table_end) {
                sections.push(Section {
                    header: None,
                    content_range,
                    is_code_block: false,
                    is_table: true,
                    code_language: None,
                });
            }
            continue;
        }

        if is_markdown_header(line_text) {
            flush_text_section(
                text,
                &mut sections,
                &mut current_text_start,
                &mut current_text_header,
                line.start,
            );
            current_text_start = Some(line.start);
            current_text_header = Some(parse_markdown_header(line_text));
            index += 1;
            continue;
        }

        if current_text_start.is_none() {
            current_text_start = Some(line.start);
        }

        index += 1;
    }

    flush_text_section(
        text,
        &mut sections,
        &mut current_text_start,
        &mut current_text_header,
        text.len(),
    );

    sections
}

#[cfg(test)]
mod markdown_tests {
    use super::*;

    fn assert_structured_chunk_matches_source(text: &str, chunk: &StructuredChunk) {
        let start = chunk.start_pos as usize;
        let end = chunk.end_pos as usize;
        assert!(
            text.is_char_boundary(start),
            "start_pos {} is not on a char boundary for {:?}",
            start,
            chunk.content
        );
        assert!(
            text.is_char_boundary(end),
            "end_pos {} is not on a char boundary for {:?}",
            end,
            chunk.content
        );
        assert_eq!(&text[start..end], chunk.content);
    }

    #[test]
    fn test_markdown_chunk_basic() {
        let text = "# Title\n\nSome content here.\n\n## Subtitle\n\nMore content.";
        let chunks = markdown_chunk(text.to_string(), 500);
        assert!(!chunks.is_empty());
        // Check header path inheritance
        let last_chunk = chunks.last().unwrap();
        assert!(last_chunk.header_path.contains("Title"));
    }

    #[test]
    fn test_code_block_preservation() {
        let text = "# Code Example\n\n```rust\nfn main() {\n    println!(\"Hello\");\n}\n```\n\nText after code.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find code chunk (chunk_type is "code" or "code:language")
        let code_chunk = chunks.iter().find(|c| c.chunk_type.starts_with("code"));
        assert!(code_chunk.is_some());
        let chunk = code_chunk.unwrap();
        assert!(chunk.content.contains("fn main()"));
        // Verify language detection
        assert!(chunk.chunk_type == "code:rust" || chunk.chunk_type == "code");
    }

    #[test]
    fn test_table_preservation() {
        let text = "# Data\n\n| Name | Value |\n|------|-------|\n| A | 1 |\n| B | 2 |\n\nEnd.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find table chunk
        let table_chunk = chunks.iter().find(|c| c.chunk_type == "table");
        assert!(table_chunk.is_some());
        assert!(table_chunk.unwrap().content.contains("|------|"));
    }

    #[test]
    fn test_markdown_offsets_skip_leading_blank_lines_but_match_raw_source() {
        let text = "\n\n# Title\n\n## Section\n\nBody.";
        let chunks = markdown_chunk(text.to_string(), 500);

        assert!(!chunks.is_empty());
        for chunk in &chunks {
            assert_structured_chunk_matches_source(text, chunk);
        }

        let first_chunk = &chunks[0];
        assert_eq!(first_chunk.content, "# Title");
        assert_eq!(
            first_chunk.start_pos as usize,
            text.find("# Title").unwrap()
        );
    }

    #[test]
    fn test_markdown_header_chunk_offsets_are_raw_byte_ranges() {
        let text = "# Title\n\n## Section\n\nBody.";
        let chunks = markdown_chunk(text.to_string(), 500);

        let header_chunk = chunks.iter().find(|chunk| chunk.chunk_type == "header");
        assert!(header_chunk.is_some());
        assert_structured_chunk_matches_source(text, header_chunk.unwrap());
    }

    #[test]
    fn test_markdown_text_split_offsets_are_raw_byte_ranges() {
        let body = std::iter::repeat("첫 번째 문장입니다. 두 번째 문장입니다🙂.")
            .take(8)
            .collect::<Vec<_>>()
            .join("\n\n");
        let text = format!("# Guide\n\n{body}");
        let chunks = markdown_chunk(text.clone(), 100);

        assert!(chunks.len() >= 2);
        for chunk in &chunks {
            assert_structured_chunk_matches_source(&text, chunk);
        }
    }

    #[test]
    fn test_header_path_inheritance() {
        let text =
            "# Main\n\nIntro.\n\n## Section A\n\nContent A.\n\n### Subsection\n\nDeep content.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find deepest chunk
        let deep_chunk = chunks.iter().find(|c| c.content.contains("Deep content"));
        assert!(deep_chunk.is_some());
        assert!(deep_chunk.unwrap().header_path.contains("Main"));
        assert!(deep_chunk.unwrap().header_path.contains("Section A"));
        assert!(deep_chunk.unwrap().header_path.contains("Subsection"));
    }

    #[test]
    fn test_large_code_block_splitting() {
        // Create code block larger than max_chars (100 minimum enforced)
        // We need content > 100 chars.
        // 6 lines of ~20 chars = 120 chars.
        let code_body = "let a = 10000000000;\nlet b = 20000000000;\nlet c = 30000000000;\nlet d = 40000000000;\nlet e = 50000000000;\nlet f = 60000000000;";
        let text = format!("```rust\n{}\n```", code_body);

        // max_chars=100 (clamped internally if we pass less, but we pass 100 to be explicit)
        let chunks = markdown_chunk(text.clone(), 100);

        assert!(chunks.len() >= 2);
        for chunk in &chunks {
            assert!(chunk.chunk_type == "code:rust");
            assert_structured_chunk_matches_source(&text, chunk);
            // Verify no split mid-line (simple check: no partial variable names if lines are atomic)
            assert!(!chunk.content.contains("let a = 10000000000;let"));
        }
    }

    #[test]
    fn test_large_table_splitting() {
        // Table needs to be > 100 chars.
        // Header: | Col1 | Col2 |\n|---|---| (25 chars)
        // Rows: | Val1 | Val2 | (15 chars)
        // Need > 100 total. 25 + 15*6 = 115.
        let header = "| Col1 | Col2 |\n|---|---|";
        let row = "| Val1 | Val2 |";
        let text = format!(
            "{}\n{}\n{}\n{}\n{}\n{}\n{}",
            header, row, row, row, row, row, row
        );

        let chunks = markdown_chunk(text.clone(), 100);

        assert!(chunks.len() >= 2);
        for chunk in &chunks {
            assert_eq!(chunk.chunk_type, "table");
            assert_structured_chunk_matches_source(&text, chunk);
        }
        assert!(chunks[0].content.starts_with("| Col1 | Col2 |"));
        assert!(chunks
            .iter()
            .skip(1)
            .all(|chunk| !chunk.content.starts_with("| Col1 | Col2 |")));
    }

    #[test]
    fn test_code_block_linking() {
        // Need > 100 chars to force split (min_chars clamped to 100)
        let code_body = "let a = 10000000000;\nlet b = 20000000000;\nlet c = 30000000000;\nlet d = 40000000000;\nlet e = 50000000000;\nlet f = 60000000000;";
        let text = format!("```\n{}\n```", code_body);
        // Force split with max_chars=100
        let chunks = markdown_chunk(text, 100);

        assert!(chunks.len() >= 2);

        // Check first chunk has linking info
        let first_chunk = &chunks[0];
        assert!(first_chunk.batch_id.is_some());
        assert!(first_chunk.batch_index.is_some());
        assert!(first_chunk.batch_total.is_some());

        let batch_id = first_chunk.batch_id.as_ref().unwrap();
        let total = first_chunk.batch_total.unwrap();

        // Check all chunks share batch_id and have correct total
        for (i, chunk) in chunks.iter().enumerate() {
            assert_eq!(chunk.batch_id.as_ref().unwrap(), batch_id);
            assert_eq!(chunk.batch_total.unwrap(), total);
            assert_eq!(chunk.batch_index.unwrap(), i as i32);
        }
    }
}

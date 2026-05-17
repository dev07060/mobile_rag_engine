// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Document-to-Text (DTT) module for PDF and DOCX text extraction

use anyhow::{anyhow, Result};
use regex::Regex;

/// Upper bound on the iterated CJK<->CJK single-newline fold passes.
/// Each pass strictly reduces the count of CJK-bracketed line breaks, so
/// fixed-point is reached in O(N) iterations for a paragraph of N chars;
/// the cap is a defensive ceiling, not a tuning parameter.
const CJK_FOLD_MAX_ITER: usize = 32;

/// Minimum non-whitespace character count that `extract_text_from_pdf`
/// considers "successful" extraction. PDFs below this threshold (typically
/// scanned/image-only documents that pdf_extract reads as empty pages) are
/// surfaced as `Err` so the caller can decide on OCR fallback rather than
/// silently indexing 0-chunk sources.
const MIN_EXTRACTED_NON_WHITESPACE: usize = 16;

fn is_private_use_code_point(code_point: u32) -> bool {
    (0xE000..=0xF8FF).contains(&code_point)
        || (0xF0000..=0xFFFFD).contains(&code_point)
        || (0x100000..=0x10FFFD).contains(&code_point)
}

fn is_noncharacter_code_point(code_point: u32) -> bool {
    (0xFDD0..=0xFDEF).contains(&code_point)
        || ((code_point & 0xFFFE) == 0xFFFE && code_point <= 0x10FFFF)
}

/// Normalize extraction artifacts from PDF text runs.
///
/// Some PDFs encode spaces with private-use or non-printable characters,
/// which appear as "tofu" boxes in UI. Convert them to regular spaces so
/// chunking/embedding receives clean text.
fn normalize_extracted_text(raw: &str) -> String {
    let mut normalized = String::with_capacity(raw.len());

    for ch in raw.chars() {
        let code_point = ch as u32;
        let mapped = match ch {
            // Normalize line separators to '\n'
            '\r' | '\u{2028}' | '\u{2029}' => Some('\n'),

            // Space-like separators seen in PDF extraction output
            '\t'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{180E}'
            | '\u{2000}'..='\u{200A}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            | '\u{FFFC}'
            | '\u{FFFD}' => Some(' '),

            // Keep soft hyphen as explicit hyphen so dehyphenation still works.
            '\u{00AD}' => Some('-'),

            // Formatting chars we do not want in chunk text
            '\u{034F}' | '\u{061C}' | '\u{200B}' | '\u{200C}' | '\u{200D}' | '\u{2060}'
            | '\u{FEFF}' => None,

            // Other controls/private/noncharacters are treated as separators
            _ if ch.is_control() && ch != '\n' => Some(' '),
            _ if is_private_use_code_point(code_point)
                || is_noncharacter_code_point(code_point) =>
            {
                Some(' ')
            }
            _ => Some(ch),
        };

        if let Some(output_char) = mapped {
            normalized.push(output_char);
        }
    }

    normalized
}

/// Remove page number from the end of a page text (if present)
/// Only removes if the last non-empty line is purely numeric
fn remove_trailing_page_number(page_text: &str) -> String {
    let lines: Vec<&str> = page_text.lines().collect();
    if lines.is_empty() {
        return page_text.to_string();
    }

    // Find last non-empty line
    let mut last_content_idx = lines.len() - 1;
    while last_content_idx > 0 && lines[last_content_idx].trim().is_empty() {
        last_content_idx -= 1;
    }

    let last_line = lines[last_content_idx].trim();

    // Check if last line is purely numeric (likely page number)
    if !last_line.is_empty() && last_line.chars().all(|c| c.is_ascii_digit()) {
        // Remove the page number line
        let mut result: Vec<&str> = lines[..last_content_idx].to_vec();
        result.extend_from_slice(&lines[last_content_idx + 1..]);
        result.join("\n")
    } else {
        page_text.to_string()
    }
}

/// Join hyphenated word at page boundary
/// If page ends with "word-" and next page starts with "continuation",
/// join them as "wordcontinuation"
fn join_pages(pages: Vec<String>) -> String {
    if pages.is_empty() {
        return String::new();
    }

    // First, clean all pages by removing trailing page numbers
    let cleaned_pages: Vec<String> = pages
        .iter()
        .map(|page| normalize_extracted_text(page))
        .map(|page| remove_trailing_page_number(&page))
        .collect();

    // Include standard hyphen (-), soft hyphen (\u{00AD}), hyphen (\u{2010}), non-breaking hyphen (\u{2011})
    let hyphen_end_re = Regex::new(r"(\w+)[-\u{00AD}\u{2010}\u{2011}]\s*$").unwrap();
    let word_start_re = Regex::new(r"^\s*(\w+)").unwrap();

    let mut result = String::new();

    for (i, page) in cleaned_pages.iter().enumerate() {
        if i == 0 {
            result = page.clone();
            continue;
        }

        let result_trimmed = result.trim_end();
        let page_trimmed = page.trim_start();

        let is_cjk_page_boundary =
            match (result_trimmed.chars().last(), page_trimmed.chars().next()) {
                (Some(left), Some(right)) => is_cjk(left) && is_cjk(right),
                _ => false,
            };
        if is_cjk_page_boundary {
            result = result_trimmed.to_string();
            result.push_str(page_trimmed);
            continue;
        }

        let hyphenation = {
            let result_trimmed = result.trim_end();
            hyphen_end_re.captures(result_trimmed).map(|caps| {
                (
                    result_trimmed.len(),
                    caps.get(1).unwrap().as_str().to_string(),
                    caps.get(0).unwrap().as_str().len(),
                )
            })
        };

        if let Some((trimmed_len, word_part1, match_len)) = hyphenation {
            let page_trimmed = page.trim_start();

            // Check if current page starts with word continuation
            if let Some(next_caps) = word_start_re.captures(page_trimmed) {
                let word_part2 = next_caps.get(1).unwrap().as_str();

                // Remove trailing "word-" from result
                let match_start = trimmed_len - match_len;
                result.truncate(match_start);
                result.push_str(&word_part1);
                result.push_str(word_part2);

                // Add rest of current page (after the first word)
                let rest_start = next_caps.get(1).unwrap().end();
                result.push_str(&page_trimmed[rest_start..]);
                continue;
            }
        }

        // No hyphenation case: just add space and continue
        result.push(' ');
        result.push_str(page);
    }

    // Handle in-line hyphenation (line breaks within pages)
    // Only join when: word- + newline + lowercase continuation
    // Preserves real compound words like "user-facing", "data-binding"
    // Also handles soft hyphens etc.
    //
    // Applied before paragraph splitting so PDF column-wrap artifacts where
    // a hyphenated word spans what looks like a blank line still merge.
    let inline_hyphen_re =
        Regex::new(r"(\w+)[-\u{00AD}\u{2010}\u{2011}]\s*[\r\n]+\s*([a-z]\w*)").unwrap();
    let normalized_result = normalize_extracted_text(&result);
    let dehyphenated = inline_hyphen_re
        .replace_all(&normalized_result, "$1$2")
        .into_owned();

    // Split on paragraph breaks (one or more consecutive blank lines).
    // Preserving these as `\n\n` in the output is what lets the downstream
    // chunker (semantic_chunker::split_paragraph_ranges) find semantic
    // break points instead of treating every PDF as a single paragraph.
    let paragraph_break_re = Regex::new(r"\n[ \t]*(?:\n[ \t]*)+").unwrap();

    // CJK<->CJK across a SINGLE line break only — paragraph breaks must
    // never be eaten by this rule (the previous `[\r\n]+` form silently
    // glued adjacent Korean paragraphs together).
    let cjk_inline_newline_re = Regex::new(
        r"([\p{Han}\p{Hangul}\p{Hiragana}\p{Katakana}])[\r\n]([\p{Han}\p{Hangul}\p{Hiragana}\p{Katakana}])",
    )
    .unwrap();

    // Within a paragraph, collapse remaining whitespace runs (line breaks,
    // multiple spaces) to a single space. \n\n was already stripped by the
    // paragraph split above, so this only touches intra-paragraph layout.
    let intra_paragraph_ws_re = Regex::new(r"[ \t\r\n]+").unwrap();

    let mut paragraphs: Vec<String> = Vec::new();
    for raw_paragraph in paragraph_break_re.split(&dehyphenated) {
        if raw_paragraph.trim().is_empty() {
            continue;
        }

        // Iterate CJK<->CJK single-newline fold to a fixed point. A single
        // non-iterated regex pass only consumes alternating pairs and
        // leaves stranded syllables that the whitespace collapse later
        // turns into orphan tokens (e.g. "해\n지\n환\n급\n금" → "해지 환급 금").
        let mut cjk_joined: String = raw_paragraph.to_string();
        for _ in 0..CJK_FOLD_MAX_ITER {
            let next = cjk_inline_newline_re.replace_all(&cjk_joined, "$1$2");
            if next.as_ref() == cjk_joined.as_str() {
                break;
            }
            cjk_joined = next.into_owned();
        }

        let cleaned = intra_paragraph_ws_re
            .replace_all(&cjk_joined, " ")
            .trim()
            .to_string();
        if !cleaned.is_empty() {
            paragraphs.push(cleaned);
        }
    }

    paragraphs.join("\n\n")
}

fn is_extraction_effectively_empty(text: &str) -> bool {
    text.chars().filter(|c| !c.is_whitespace()).count() < MIN_EXTRACTED_NON_WHITESPACE
}

/// Extract text content from a PDF file (bytes)
/// Uses page-by-page extraction for safe page number removal and hyphenation handling.
///
/// Returns `Err` when the joined output falls below
/// `MIN_EXTRACTED_NON_WHITESPACE` characters. pdf_extract reports
/// scanned/image-only PDFs as a vector of empty strings (no error), so without
/// this guard a 0-chunk source would be silently indexed and the user would
/// see an "ingested but unsearchable" mystery. Surfacing as `Err` lets the
/// caller decide on OCR fallback or a "scanned PDF not supported" message.
pub fn extract_text_from_pdf(file_bytes: Vec<u8>) -> Result<String> {
    let pages = pdf_extract::extract_text_from_mem_by_pages(&file_bytes)
        .map_err(|e| anyhow!("PDF extraction failed: {:?}", e))?;
    let joined = join_pages(pages);
    if is_extraction_effectively_empty(&joined) {
        return Err(anyhow!(
            "PDF text extraction returned fewer than {} non-whitespace characters; PDF may be scanned/image-only",
            MIN_EXTRACTED_NON_WHITESPACE,
        ));
    }
    Ok(joined)
}

/// Extract text content from a DOCX file (bytes)
pub fn extract_text_from_docx(file_bytes: Vec<u8>) -> Result<String> {
    docx_lite::extract_text_from_bytes(&file_bytes)
        .map_err(|e| anyhow!("DOCX extraction failed: {}", e))
}

/// Auto-detect document type and extract text
/// Uses magic bytes to determine file format
pub fn extract_text_from_document(file_bytes: Vec<u8>) -> Result<String> {
    const MAX_FILE_SIZE: usize = 50 * 1024 * 1024; // 50MB

    if file_bytes.len() > MAX_FILE_SIZE {
        return Err(anyhow!(
            "File too large ({} bytes). Maximum supported size is 50MB.",
            file_bytes.len()
        ));
    }

    if file_bytes.len() < 4 {
        return Err(anyhow!("File too small to determine format"));
    }

    // PDF magic bytes: %PDF
    if file_bytes.starts_with(b"%PDF") {
        return extract_text_from_pdf(file_bytes);
    }

    // DOCX magic bytes: PK (ZIP archive)
    if file_bytes.starts_with(b"PK") {
        return extract_text_from_docx(file_bytes);
    }

    Err(anyhow!(
        "Unsupported document format. Expected PDF or DOCX."
    ))
}

/// Decode UTF-8 text bytes without altering content semantics.
pub fn extract_text_from_utf8(file_bytes: Vec<u8>) -> Result<String> {
    String::from_utf8(file_bytes).map_err(|e| anyhow!("UTF-8 decode failed: {}", e))
}

/// Read a file and extract text according to extension / magic bytes.
///
/// Text-like files (`.txt`, `.md`, `.markdown`) are decoded as UTF-8.
/// Binary document types fall back to the existing document extractor.
pub fn extract_text_from_file(file_path: String) -> Result<String> {
    let bytes = std::fs::read(&file_path)
        .map_err(|e| anyhow!("Failed to read file '{}': {}", file_path, e))?;
    let extension = std::path::Path::new(&file_path)
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase());

    match extension.as_deref() {
        Some("txt" | "md" | "markdown") => extract_text_from_utf8(bytes),
        _ => extract_text_from_document(bytes),
    }
}

// Helper to check for CJK characters
fn is_cjk(c: char) -> bool {
    // Basic ranges for CJK Unified Ideographs, Hangul, Hiragana, Katakana
    // This is a simplified check.
    let u = c as u32;
    (u >= 0x4E00 && u <= 0x9FFF) || // CJK Unified Ideographs
    (u >= 0x3040 && u <= 0x309F) || // Hiragana
    (u >= 0x30A0 && u <= 0x30FF) || // Katakana
    (u >= 0xAC00 && u <= 0xD7AF) // Hangul Syllables
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_remove_trailing_page_number() {
        let text = "Some content here.\n\n42";
        let result = remove_trailing_page_number(text);
        assert!(!result.contains("42"));
        assert!(result.contains("Some content here."));
    }

    #[test]
    fn test_remove_trailing_page_number_no_number() {
        let text = "Some content here.\nMore content.";
        let result = remove_trailing_page_number(text);
        assert_eq!(result, text);
    }

    #[test]
    fn test_join_pages_dehyphenation() {
        let pages = vec![
            "This is a hyphen-".to_string(),
            "ated word in the text.".to_string(),
        ];
        let result = join_pages(pages);
        assert!(result.contains("hyphenated"));
        assert!(!result.contains("hyphen-"));
    }

    #[test]
    fn test_extract_unsupported_format() {
        let bytes = vec![0x00, 0x01, 0x02, 0x03];
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Unsupported"));
    }

    #[test]
    fn test_file_too_small() {
        let bytes = vec![0x50, 0x4B]; // Only 2 bytes
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("too small"));
    }

    #[test]
    fn test_file_too_large() {
        // Create a vector that exceeds MAX_FILE_SIZE
        let bytes = vec![0u8; 51 * 1024 * 1024]; // 51MB
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("too large"));
    }

    #[test]
    fn test_weird_hyphens() {
        // Standard hyphen
        let pages = vec!["highly-read-\n\nable".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "highly-readable");

        let pages_soft = vec!["highly-read\u{00AD}\n\nable".to_string()];
        let result_soft = join_pages(pages_soft);
        assert_eq!(
            result_soft, "highly-readable",
            "Soft hyphen SHOULD match regex now"
        );
    }

    #[test]
    fn test_normalize_extracted_text_handles_mixed_unicode_artifacts() {
        let raw = "보험금의\u{E000}지급\u{200B}절차\u{2028}안내\u{FFFD}";
        let normalized = normalize_extracted_text(raw);
        assert_eq!(normalized, "보험금의 지급절차\n안내 ");
    }

    #[test]
    fn test_normalize_weird_pdf_space_artifacts() {
        let pages = vec![
            "적립금의\u{E000}적립비율\u{200B}을\u{FFFD}변경할\u{0091}수\u{FDD0}있습니다."
                .to_string(),
        ];
        let result = join_pages(pages);
        assert_eq!(result, "적립금의 적립비율을 변경할 수 있습니다.");
    }

    #[test]
    fn test_join_pages_collapses_cjk_linebreak_without_inserting_space() {
        let pages = vec!["해\n지환급금".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "해지환급금");
    }

    #[test]
    fn test_join_pages_preserves_explicit_spacing_around_cjk_linebreak() {
        let pages = vec!["계약자적립금을 인출할 수 \n있습니다.".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "계약자적립금을 인출할 수 있습니다.");
    }

    #[test]
    fn test_join_pages_collapses_cjk_page_boundary_without_inserting_space() {
        let pages = vec!["보험계약의 해".to_string(), "지환급금 안내".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "보험계약의 해지환급금 안내");
    }

    #[test]
    fn test_join_pages_normalizes_dense_cjk_linebreak_sequence() {
        // Dense single-syllable column wrapping was previously left
        // partially joined ("해지 환급 금") because a single regex pass
        // only consumed alternating CJK<->newline<->CJK pairs. The
        // iterated fold now reaches a fixed point and produces one
        // contiguous run.
        let pages = vec!["해\n지\n환\n급\n금".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "해지환급금");
        assert!(!result.contains('\n'));
    }

    #[test]
    fn test_join_pages_preserves_paragraph_break_between_sentences() {
        let pages = vec!["First paragraph here.\n\nSecond paragraph here.".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "First paragraph here.\n\nSecond paragraph here.");
    }

    #[test]
    fn test_join_pages_preserves_korean_paragraph_break() {
        // The CJK-newline rule previously matched [\r\n]+ and silently
        // glued adjacent Korean paragraphs together ("보고서문제 정의").
        // The fix narrows the rule to single \n and splits on paragraph
        // breaks first, so the downstream chunker can find this boundary.
        let pages = vec!["심층 시장 조사 보고서\n\n문제 정의: 무엇을 풀려는가".to_string()];
        let result = join_pages(pages);
        assert!(!result.contains("보고서문제"));
        assert_eq!(result, "심층 시장 조사 보고서\n\n문제 정의: 무엇을 풀려는가");
    }

    #[test]
    fn test_join_pages_collapses_blank_line_run_to_single_paragraph_break() {
        let pages = vec!["A.\n\n\n\nB.".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "A.\n\nB.");
    }

    #[test]
    fn test_is_extraction_effectively_empty_threshold() {
        assert!(is_extraction_effectively_empty(""));
        assert!(is_extraction_effectively_empty("   \n\n\t  "));
        // 15 non-whitespace chars → below threshold
        assert!(is_extraction_effectively_empty(&"a".repeat(15)));
        // 16 non-whitespace chars → at threshold, not empty
        assert!(!is_extraction_effectively_empty(&"a".repeat(16)));
        assert!(!is_extraction_effectively_empty(
            "This is a normal sentence with enough content."
        ));
    }

    #[test]
    fn test_join_pages_preserves_compound_word_without_dehyphenation_when_no_linebreak() {
        let pages = vec!["The user-facing guide stays intact.".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "The user-facing guide stays intact.");
    }

    #[test]
    fn test_join_pages_handles_pdf_like_artifact_cases() {
        let cases = vec![
            (
                vec!["보험금의\u{E000}지급\u{200B}절차".to_string()],
                "보험금의 지급절차",
            ),
            (vec!["해\u{2028}지환급금".to_string()], "해지환급금"),
            (vec!["A\u{00AD}\npple".to_string()], "Apple"),
        ];

        for (pages, expected) in cases {
            let result = join_pages(pages);
            assert_eq!(result, expected);
        }
    }

    #[test]
    fn test_extract_text_from_utf8_preserves_exact_text() {
        let original = "Guide > Setup\nInstall dependencies.\n한글 줄도 유지";
        let extracted = extract_text_from_utf8(original.as_bytes().to_vec()).unwrap();
        assert_eq!(extracted, original);
    }

    #[test]
    fn test_extract_text_from_file_for_text_like_extensions() {
        let temp_dir = std::env::temp_dir();
        let txt_path = temp_dir.join("document_parser_extract_text_from_file.txt");
        let md_path = temp_dir.join("document_parser_extract_text_from_file.md");

        std::fs::write(&txt_path, "plain text body").unwrap();
        std::fs::write(&md_path, "# Guide\nInstall dependencies").unwrap();

        let txt = extract_text_from_file(txt_path.to_string_lossy().into_owned()).unwrap();
        let md = extract_text_from_file(md_path.to_string_lossy().into_owned()).unwrap();

        assert_eq!(txt, "plain text body");
        assert_eq!(md, "# Guide\nInstall dependencies");

        let _ = std::fs::remove_file(txt_path);
        let _ = std::fs::remove_file(md_path);
    }

    fn classify_chars(s: &str) -> (usize, usize, usize, usize, usize) {
        let chars: Vec<char> = s.chars().collect();
        let total = chars.len();
        let ascii_letter = chars.iter().filter(|c| c.is_ascii_alphabetic()).count();
        let hangul = chars
            .iter()
            .filter(|c| matches!(**c as u32, 0xAC00..=0xD7AF))
            .count();
        let digit = chars.iter().filter(|c| c.is_ascii_digit()).count();
        let space = chars.iter().filter(|c| c.is_whitespace()).count();
        (total, ascii_letter, hangul, digit, space)
    }

    fn dump_extracted(label: &str, fixture_rel: &str) {
        // Resolve example/assets/sample_data relative to crate root (rust_builder/rust)
        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let path = manifest
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join(fixture_rel);
        let bytes = std::fs::read(&path).expect("read pdf fixture");
        let pages = pdf_extract::extract_text_from_mem_by_pages(&bytes).expect("raw pages");
        let joined = extract_text_from_pdf(bytes).expect("extract_text_from_pdf");

        println!("======== {} ({}) ========", label, fixture_rel);
        let (t, a, h, d, w) = classify_chars(&joined);
        println!(
            "joined chars: total={} ascii_letter={} hangul={} digit={} whitespace={}",
            t, a, h, d, w
        );
        println!("page count: {}", pages.len());
        println!(
            "newlines in joined output: {}  paragraph breaks: {}",
            joined.matches('\n').count(),
            joined.matches("\n\n").count()
        );

        // Survived "weird" characters (post-extraction)
        let mut weird = std::collections::BTreeMap::<char, usize>::new();
        for ch in joined.chars() {
            let cp = ch as u32;
            let is_weird = (ch.is_control() && ch != '\n')
                || is_private_use_code_point(cp)
                || is_noncharacter_code_point(cp)
                || matches!(
                    ch,
                    '\u{200B}'
                        | '\u{200C}'
                        | '\u{200D}'
                        | '\u{2060}'
                        | '\u{FEFF}'
                        | '\u{FFFC}'
                        | '\u{FFFD}'
                );
            if is_weird {
                *weird.entry(ch).or_insert(0) += 1;
            }
        }
        if weird.is_empty() {
            println!("weird-chars survived: none");
        } else {
            println!("weird-chars survived ({} distinct):", weird.len());
            for (ch, count) in weird.iter().take(20) {
                println!("  U+{:04X} x{}", *ch as u32, count);
            }
        }

        // Orphan single Hangul flanked by spaces — symptom of incomplete CJK linebreak collapse
        let collected: Vec<char> = joined.chars().collect();
        let mut orphan = 0usize;
        let mut orphan_examples = Vec::new();
        for i in 1..collected.len().saturating_sub(1) {
            if collected[i - 1] == ' '
                && collected[i + 1] == ' '
                && matches!(collected[i] as u32, 0xAC00..=0xD7AF)
            {
                orphan += 1;
                if orphan_examples.len() < 6 {
                    let lo = i.saturating_sub(10);
                    let hi = (i + 11).min(collected.len());
                    orphan_examples.push(collected[lo..hi].iter().collect::<String>());
                }
            }
        }
        println!(
            "orphan-Hangul (space + 1 syllable + space) count: {}",
            orphan
        );
        for ex in &orphan_examples {
            println!("  ctx: ...{}...", ex);
        }

        // Detect runs of digit clusters or weird substrings
        let digit_clusters = joined
            .split_whitespace()
            .filter(|w| w.len() >= 3 && w.chars().all(|c| c.is_ascii_digit()))
            .count();
        println!("standalone numeric tokens (>=3 digits): {}", digit_clusters);

        let head: String = joined.chars().take(500).collect();
        let n = joined.chars().count();
        let skip = n.saturating_sub(500);
        let tail: String = joined.chars().skip(skip).collect();
        println!("--- HEAD 500 ---\n{}\n--- TAIL 500 ---\n{}", head, tail);

        if pages.len() >= 3 {
            let mid = pages.len() / 2;
            let raw_mid: String = pages[mid].chars().take(400).collect();
            println!(
                "--- RAW page[{}] (pre-normalize) head 400 ---\n{:?}",
                mid, raw_mid
            );
        }
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_sample_eng_pdf() {
        dump_extracted("ENG", "example/assets/sample_data/sample_eng.pdf");
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_sample_kor_pdf() {
        dump_extracted("KOR", "example/assets/sample_data/sample_kor.pdf");
    }

    fn long_hangul_run(joined: &str) -> Vec<usize> {
        // Run lengths of consecutive Hangul syllables uninterrupted by whitespace.
        // Long runs (e.g. >=12) typically indicate eaten space at section/heading
        // boundaries (Korean is word-spaced; natural Korean tokens rarely exceed
        // ~6-8 syllables without a space).
        let mut runs = Vec::new();
        let mut cur: usize = 0;
        for ch in joined.chars() {
            let is_hangul = matches!(ch as u32, 0xAC00..=0xD7AF);
            if is_hangul {
                cur += 1;
            } else if !ch.is_whitespace() {
                // Non-hangul, non-whitespace breaks the run but we still count
                cur = 0;
            } else {
                if cur > 0 {
                    runs.push(cur);
                }
                cur = 0;
            }
        }
        if cur > 0 {
            runs.push(cur);
        }
        runs
    }

    fn script_glue_count(joined: &str) -> usize {
        // Count Hangul<->{ASCII letter|digit} transitions without intervening space.
        // These are virtually always layout/heading glue artifacts.
        let mut count = 0usize;
        let chars: Vec<char> = joined.chars().collect();
        for w in chars.windows(2) {
            let a_h = matches!(w[0] as u32, 0xAC00..=0xD7AF);
            let b_h = matches!(w[1] as u32, 0xAC00..=0xD7AF);
            let a_other = w[0].is_ascii_alphanumeric();
            let b_other = w[1].is_ascii_alphanumeric();
            if (a_h && b_other) || (a_other && b_h) {
                count += 1;
            }
        }
        count
    }

    struct ExtractSummary {
        label: String,
        page_count: usize,
        chars: usize,
        hangul: usize,
        ascii: usize,
        digit: usize,
        newlines: usize,
        paragraph_breaks: usize,
        weird_kinds: usize,
        weird_total: usize,
        orphan_hangul: usize,
        long_hangul_runs_ge12: usize,
        max_hangul_run: usize,
        script_glue: usize,
        numeric_tokens_ge3: usize,
        extract_ms: u128,
        ok: bool,
        err: Option<String>,
    }

    fn summarize_one(label: &str, fixture_rel: &str) -> ExtractSummary {
        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let path = manifest
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join(fixture_rel);
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(e) => {
                return ExtractSummary {
                    label: label.to_string(),
                    page_count: 0,
                    chars: 0,
                    hangul: 0,
                    ascii: 0,
                    digit: 0,
                    newlines: 0,
                    paragraph_breaks: 0,
                    weird_kinds: 0,
                    weird_total: 0,
                    orphan_hangul: 0,
                    long_hangul_runs_ge12: 0,
                    max_hangul_run: 0,
                    script_glue: 0,
                    numeric_tokens_ge3: 0,
                    extract_ms: 0,
                    ok: false,
                    err: Some(format!("read error: {}", e)),
                };
            }
        };

        let page_count = pdf_extract::extract_text_from_mem_by_pages(&bytes)
            .map(|p| p.len())
            .unwrap_or(0);

        let t0 = std::time::Instant::now();
        let joined_res = extract_text_from_pdf(bytes);
        let extract_ms = t0.elapsed().as_millis();

        let joined = match joined_res {
            Ok(s) => s,
            Err(e) => {
                return ExtractSummary {
                    label: label.to_string(),
                    page_count,
                    chars: 0,
                    hangul: 0,
                    ascii: 0,
                    digit: 0,
                    newlines: 0,
                    paragraph_breaks: 0,
                    weird_kinds: 0,
                    weird_total: 0,
                    orphan_hangul: 0,
                    long_hangul_runs_ge12: 0,
                    max_hangul_run: 0,
                    script_glue: 0,
                    numeric_tokens_ge3: 0,
                    extract_ms,
                    ok: false,
                    err: Some(format!("{}", e)),
                };
            }
        };

        let (t_total, a, h, d, _w) = classify_chars(&joined);
        let newlines = joined.matches('\n').count();
        let paragraph_breaks = joined.matches("\n\n").count();

        let mut weird = std::collections::BTreeMap::<char, usize>::new();
        for ch in joined.chars() {
            let cp = ch as u32;
            let is_weird = (ch.is_control() && ch != '\n')
                || is_private_use_code_point(cp)
                || is_noncharacter_code_point(cp)
                || matches!(
                    ch,
                    '\u{200B}'
                        | '\u{200C}'
                        | '\u{200D}'
                        | '\u{2060}'
                        | '\u{FEFF}'
                        | '\u{FFFC}'
                        | '\u{FFFD}'
                );
            if is_weird {
                *weird.entry(ch).or_insert(0) += 1;
            }
        }
        let weird_kinds = weird.len();
        let weird_total: usize = weird.values().sum();

        let collected: Vec<char> = joined.chars().collect();
        let mut orphan = 0usize;
        for i in 1..collected.len().saturating_sub(1) {
            if collected[i - 1] == ' '
                && collected[i + 1] == ' '
                && matches!(collected[i] as u32, 0xAC00..=0xD7AF)
            {
                orphan += 1;
            }
        }

        let runs = long_hangul_run(&joined);
        let long_runs = runs.iter().filter(|r| **r >= 12).count();
        let max_run = runs.iter().copied().max().unwrap_or(0);
        let glue = script_glue_count(&joined);

        let digit_clusters = joined
            .split_whitespace()
            .filter(|w| w.len() >= 3 && w.chars().all(|c| c.is_ascii_digit()))
            .count();

        ExtractSummary {
            label: label.to_string(),
            page_count,
            chars: t_total,
            hangul: h,
            ascii: a,
            digit: d,
            newlines,
            paragraph_breaks,
            weird_kinds,
            weird_total,
            orphan_hangul: orphan,
            long_hangul_runs_ge12: long_runs,
            max_hangul_run: max_run,
            script_glue: glue,
            numeric_tokens_ge3: digit_clusters,
            extract_ms,
            ok: true,
            err: None,
        }
    }

    fn print_top_long_runs(label: &str, fixture_rel: &str, k: usize) {
        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let path = manifest
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join(fixture_rel);
        let bytes = std::fs::read(&path).unwrap();
        let joined = match extract_text_from_pdf(bytes) {
            Ok(s) => s,
            Err(_) => return,
        };

        // Find top-k longest Hangul runs and their textual context.
        // Walk through joined text marking each run with start char index.
        let chars: Vec<char> = joined.chars().collect();
        let mut runs: Vec<(usize, usize)> = Vec::new();
        let mut i = 0;
        while i < chars.len() {
            if matches!(chars[i] as u32, 0xAC00..=0xD7AF) {
                let start = i;
                while i < chars.len() && matches!(chars[i] as u32, 0xAC00..=0xD7AF) {
                    i += 1;
                }
                runs.push((start, i - start));
            } else {
                i += 1;
            }
        }
        runs.sort_by(|a, b| b.1.cmp(&a.1));
        runs.truncate(k);

        println!("--- top {} Hangul runs in {} ---", k, label);
        for (start, len) in runs {
            let lo = start.saturating_sub(12);
            let hi = (start + len + 12).min(chars.len());
            let ctx: String = chars[lo..hi].iter().collect();
            println!("  len={:3}  …{}…", len, ctx);
        }
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_all_pdf_fixtures() {
        let fixtures: &[(&str, &str)] = &[
            ("sample_eng", "example/assets/sample_data/sample_eng.pdf"),
            ("sample_kor", "example/assets/sample_data/sample_kor.pdf"),
            ("kor_ins_20120401", "example/assets/sample_data/20120401_10101_1.pdf"),
            ("kor_ins_20200101", "example/assets/sample_data/20200101_10108_1.pdf"),
            ("kor_drone_2021", "example/assets/sample_data/2021-국방드론.pdf"),
            ("kor_misc_202302", "example/assets/sample_data/202302091039136320.pdf"),
            ("kor_dod_china_2025", "example/assets/sample_data/2025 미국방부 년례 보고서 - 중국 군사력 보고서.pdf"),
            ("kor_accel_2026", "example/assets/sample_data/2026년 글로벌 액셀러레이팅 지원사업 창업기업 모집 공고.pdf"),
            ("arxiv_2005_11401", "example/assets/sample_data/2005.11401v4.pdf"),
            ("arxiv_2205_14135", "example/assets/sample_data/2205.14135v2.pdf"),
            ("arxiv_2509_01092", "example/assets/sample_data/2509.01092v2.pdf"),
            ("arxiv_2603_18196", "example/assets/sample_data/2603.18196v1.pdf"),
        ];

        let mut summaries: Vec<ExtractSummary> = Vec::new();
        for (label, path) in fixtures {
            summaries.push(summarize_one(label, path));
        }

        println!("===== PDF EXTRACTION SUMMARY (12 fixtures) =====");
        println!(
            "{:<20} {:>4} {:>5} {:>8} {:>7} {:>7} {:>5} {:>4} {:>5} {:>5} {:>6} {:>6} {:>6} {:>5} {:>5}",
            "label",
            "p",
            "ms",
            "chars",
            "hangul",
            "ascii",
            "digit",
            "nl",
            "para",
            "wkind",
            "wtot",
            "orph",
            "glue",
            "lrun",
            "mrun",
        );
        for s in &summaries {
            if !s.ok {
                println!(
                    "{:<20}  ERR: {}",
                    s.label,
                    s.err.clone().unwrap_or_default()
                );
                continue;
            }
            println!(
                "{:<20} {:>4} {:>5} {:>8} {:>7} {:>7} {:>5} {:>4} {:>5} {:>5} {:>6} {:>6} {:>6} {:>5} {:>5}",
                s.label,
                s.page_count,
                s.extract_ms,
                s.chars,
                s.hangul,
                s.ascii,
                s.digit,
                s.newlines,
                s.paragraph_breaks,
                s.weird_kinds,
                s.weird_total,
                s.orphan_hangul,
                s.script_glue,
                s.long_hangul_runs_ge12,
                s.max_hangul_run,
            );
        }
        println!("legend:");
        println!("  p=pages  ms=extract_ms  nl=newlines  para=blank-line paragraph breaks");
        println!("  wkind/wtot=weird-char distinct kinds / total occurrences");
        println!("  orph=single Hangul flanked by spaces (CJK linebreak symptom)");
        println!("  glue=Hangul<->ASCII alnum boundary count w/o space (heading-glue symptom)");
        println!("  lrun=runs of >=12 consecutive Hangul (eaten space symptom)  mrun=max run len");
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_glue_examples() {
        // For the 3 most Korean-heavy fixtures, print the longest Hangul runs.
        let picks: &[(&str, &str)] = &[
            ("sample_kor", "example/assets/sample_data/sample_kor.pdf"),
            ("kor_dod_china_2025", "example/assets/sample_data/2025 미국방부 년례 보고서 - 중국 군사력 보고서.pdf"),
            ("kor_drone_2021", "example/assets/sample_data/2021-국방드론.pdf"),
            ("kor_accel_2026", "example/assets/sample_data/2026년 글로벌 액셀러레이팅 지원사업 창업기업 모집 공고.pdf"),
            ("kor_ins_20120401", "example/assets/sample_data/20120401_10101_1.pdf"),
        ];
        for (label, path) in picks {
            print_top_long_runs(label, path, 5);
        }
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_dense_cjk_linebreak_artifact() {
        // Companion dump for test_join_pages_normalizes_dense_cjk_linebreak_sequence
        // — useful for visual inspection when tweaking the CJK fold parameters.
        let pages = vec!["해\n지\n환\n급\n금".to_string()];
        let result = join_pages(pages);
        println!("dense CJK linebreak result: {:?}", result);
        assert!(!result.contains('\n'));
    }

    #[test]
    #[ignore = "stress benchmark"]
    fn bench_join_pages_stress_corpus() {
        let pages = (0..500)
            .map(|index| {
                if index % 2 == 0 {
                    format!(
                        "보험금의\u{E000}지급 절차 {}\n해\n지환급금 안내\nhighly-read-\n\nable",
                        index
                    )
                } else {
                    format!(
                        "Policy section {} user-facing guidance\n계약자적립금을 인출할 수 \n있습니다.",
                        index
                    )
                }
            })
            .collect::<Vec<_>>();

        let start = std::time::Instant::now();
        let result = join_pages(pages);
        let elapsed = start.elapsed();

        assert!(!result.is_empty());
        eprintln!("join_pages stress corpus elapsed: {:?}", elapsed);
    }
}

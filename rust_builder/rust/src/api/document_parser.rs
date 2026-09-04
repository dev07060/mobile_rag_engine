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

/// Largest adjacent-duplicate unit length (in chars) considered when
/// dedup'ing double-rendered text. Caps the inner loop cost; doubles longer
/// than this are uncommon and would still be partially collapsed via the
/// greedy walk.
const DEDUP_MAX_UNIT_CHARS: usize = 32;

/// Smallest adjacent-duplicate unit length the heuristic will collapse.
/// Set to 3 to avoid corrupting natural English text: an L=2 walker would
/// match the `in` inside `training` (chars 3..5 == chars 5..7) and rewrite
/// it to `traing`. Empirically every L=2 hit in the arxiv corpus was a
/// false positive (`in`, `er`, `ot`, `20`, `00`, `66`). Cost: the short
/// double-strike artifacts `독일독일`, `미국미국` (L=2) are no longer
/// collapsed; they survive but are no worse than they were pre-PR-B.
const DEDUP_MIN_UNIT_CHARS: usize = 3;

/// A page is rewritten by `dedup_adjacent_repeats` when EITHER its
/// adjacent-duplicate density (chars that would be removed / total chars)
/// reaches this fraction, OR the match count meets
/// [DEDUP_MIN_MATCHES_TRIGGER]. The density rule catches the common
/// "every-glyph double-rendered" page; the match-count rule catches the
/// long page where the artifact is dense locally but diluted by clean
/// content in tables/labels.
const DEDUP_DENSITY_TRIGGER: f64 = 0.05;

/// Secondary trigger: a page with this many independent adjacent-duplicate
/// matches is dedup'd even when density falls below
/// [DEDUP_DENSITY_TRIGGER]. The cutoff is calibrated against the 12-fixture
/// corpus: clean Korean pages top out at ~5 matches/page (background noise
/// from short coincidental repeats), while pages showing the
/// double-rendering artifact have 8+ matches even when the page is
/// otherwise full of clean tabular text — see the `dump_dedup_density_per_page`
/// diagnostic for the empirical gap.
const DEDUP_MIN_MATCHES_TRIGGER: usize = 8;

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

/// Locate adjacent character-level duplicates within a single page.
///
/// Walks left to right and, at each position, finds the longest unit length
/// L (2..=DEDUP_MAX_UNIT_CHARS) such that `text[i..i+L] == text[i+L..i+2L]`
/// AND no character in the matched span is whitespace. Returns an ordered
/// list of `(start_char_index, unit_len)` matches plus the total duplicate
/// character count (one copy per match).
///
/// The no-whitespace constraint is the key false-positive guard: natural
/// Korean repetitions ("네 네", "또 또 다른") and English ones ("the the",
/// list bullets) all carry an intervening space, while the PDF
/// double-stroke artifact ("해당시해당시", "②②", "독일독일") does not.
fn find_adjacent_repeats(text: &str) -> (Vec<(usize, usize)>, usize) {
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    let mut matches = Vec::new();
    let mut removed = 0usize;

    if n < 4 {
        return (matches, 0);
    }

    let mut i = 0usize;
    while i < n {
        let max_l = ((n - i) / 2).min(DEDUP_MAX_UNIT_CHARS);
        let mut best_l = 0usize;

        // Prefer the longest valid unit so e.g. "법인등기사항전부증명서법인등기사항전부증명서"
        // collapses as one 12-char match rather than several short ones.
        for l in (DEDUP_MIN_UNIT_CHARS..=max_l).rev() {
            let end2 = i + 2 * l;
            let span = &chars[i..end2];
            if span.iter().any(|c| c.is_whitespace()) {
                continue;
            }
            if span[..l] == span[l..] {
                best_l = l;
                break;
            }
        }

        if best_l > 0 {
            matches.push((i, best_l));
            removed += best_l;
            i += 2 * best_l;
        } else {
            i += 1;
        }
    }

    (matches, removed)
}

/// Remove double-rendered text within a page, but only when the duplicate
/// density is high enough to indicate a PDF-level rendering defect rather
/// than a few accidental short repeats.
///
/// See [DEDUP_DENSITY_TRIGGER] for the gate value; see
/// [find_adjacent_repeats] for the matching algorithm.
fn dedup_adjacent_repeats(text: &str) -> String {
    let (matches, removed) = find_adjacent_repeats(text);
    if matches.is_empty() {
        return text.to_string();
    }

    let total_chars = text.chars().count();
    if total_chars == 0 {
        return text.to_string();
    }
    let density = removed as f64 / total_chars as f64;
    let density_fires = density >= DEDUP_DENSITY_TRIGGER;
    let count_fires = matches.len() >= DEDUP_MIN_MATCHES_TRIGGER;
    if !density_fires && !count_fires {
        return text.to_string();
    }

    // Rebuild the page in a single left-to-right pass, dropping the second
    // copy of each match. `matches` is in ascending order of start position
    // and non-overlapping (the walker advances past each consumed pair).
    let chars: Vec<char> = text.chars().collect();
    let mut out: String = String::with_capacity(text.len());
    let mut cursor = 0usize;
    for (start, len) in matches {
        // Append everything before the match unchanged.
        for ch in &chars[cursor..start] {
            out.push(*ch);
        }
        // Keep exactly one copy.
        for ch in &chars[start..start + len] {
            out.push(*ch);
        }
        // Skip the duplicate copy.
        cursor = start + 2 * len;
    }
    for ch in &chars[cursor..] {
        out.push(*ch);
    }
    out
}

/// Join hyphenated word at page boundary
/// If page ends with "word-" and next page starts with "continuation",
/// join them as "wordcontinuation"
fn join_pages(pages: Vec<String>) -> String {
    if pages.is_empty() {
        return String::new();
    }

    // First, clean all pages by removing trailing page numbers and any
    // PDF double-stroke duplicates. Dedup runs per-page so the density
    // gate compares against a single page's content, not the whole doc —
    // a corrupt single page in a clean book still gets fixed without
    // dragging the doc-level density below the trigger.
    let cleaned_pages: Vec<String> = pages
        .iter()
        .map(|page| normalize_extracted_text(page))
        .map(|page| remove_trailing_page_number(&page))
        .map(|page| dedup_adjacent_repeats(&page))
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

/// Whether a below-threshold PDF extraction should carry the
/// `scanned/image-only` marker that the host app keys on to offer OCR.
///
/// Within the below-threshold branch every readable page is, by definition,
/// effectively empty (the joined text is under the threshold). A page that
/// pdf_extract parsed at all yet contributed almost no text is the signature of
/// a scanned/image-only page OCR can recover. So the marker is kept whenever at
/// least one page parsed successfully (`failed_page_count < page_count`), and
/// also when no page failed at all (`failed_page_count == 0`: the pure-scanned
/// case, plus the degenerate zero-page document, preserving prior behavior). It
/// is withheld only when EVERY page failed to parse, where no readable page
/// exists to suggest a recoverable scan and OCR will not help.
///
/// The decision is intentionally count-based (content-agnostic): a readable
/// page holding a few stray characters alongside failed pages still routes to
/// OCR. This favors recall — surfacing OCR guidance for a possibly-recoverable
/// document — over precisely fingerprinting corruption, so a scanned PDF that
/// also has a stray bad page is never silently dropped.
fn should_include_scanned_marker(page_count: usize, failed_page_count: usize) -> bool {
    failed_page_count == 0 || failed_page_count < page_count
}

/// Build the user-visible error for a PDF whose joined text fell below
/// [MIN_EXTRACTED_NON_WHITESPACE] non-whitespace characters.
///
/// The message embeds the `scanned/image-only` marker the host app keys on to
/// offer OCR for exactly the recoverable cases (see
/// [should_include_scanned_marker]); a fully-failed extraction omits it. Kept as
/// a pure function so the exact wording — including the marker placement the
/// Dart classifier depends on — is unit-testable without a PDF fixture.
fn below_threshold_error_message(page_count: usize, failed_pages: &[u32]) -> String {
    let failed_count = failed_pages.len();
    if !should_include_scanned_marker(page_count, failed_count) {
        // Every page failed to extract → no readable page, no scanned-layer
        // evidence; OCR will not help, so omit the marker.
        return format!(
            "PDF text extraction returned fewer than {} non-whitespace characters; \
             {} of {} page(s) failed to extract (pages: {:?})",
            MIN_EXTRACTED_NON_WHITESPACE, failed_count, page_count, failed_pages,
        );
    }
    if failed_count == 0 {
        // Pure scanned/image-only: every page parsed but yielded almost no text.
        return format!(
            "PDF text extraction returned fewer than {} non-whitespace characters; PDF may be scanned/image-only",
            MIN_EXTRACTED_NON_WHITESPACE,
        );
    }
    // Mixed: at least one page parsed (almost no text → scanned) while other
    // pages failed. Keep the marker so OCR still fires, and report the failures
    // for diagnostics, so a scanned PDF with a stray corrupt page is not
    // misrouted away from OCR.
    format!(
        "PDF text extraction returned fewer than {} non-whitespace characters; \
         {} of {} page(s) failed to extract (pages: {:?}); PDF may be scanned/image-only",
        MIN_EXTRACTED_NON_WHITESPACE, failed_count, page_count, failed_pages,
    )
}

/// Extract one page of text via pdf_extract's PlainTextOutput. Returns the
/// page string on success, or `Err(panic|extract-error)` on failure so the
/// caller can decide how to react. Each page extraction is its own
/// `catch_unwind` so a panic in one page (malformed content stream, unusual
/// font tables) does not abort the whole document.
fn extract_single_page(
    doc: &pdf_extract::Document,
    page_num: u32,
) -> std::result::Result<String, String> {
    let raw = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut buffer = String::new();
        let outcome = {
            let mut output = pdf_extract::PlainTextOutput::new(&mut buffer);
            pdf_extract::output_doc_page(doc, &mut output, page_num)
        };
        outcome.map(|_| buffer)
    }));

    match raw {
        Ok(Ok(text)) => Ok(text),
        Ok(Err(err)) => Err(format!("output_doc_page error: {:?}", err)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "non-string panic payload".to_string()
            };
            Err(format!("panic: {}", msg))
        }
    }
}

/// Extract text content from a PDF file (bytes)
///
/// Walks the document one page at a time so a single malformed/unsupported
/// page can be skipped without aborting the whole document. Failed pages
/// are replaced with an empty string and a warning so the rest of the PDF
/// still flows downstream; the skip count is included in the error message
/// if the overall extraction ends up below
/// [MIN_EXTRACTED_NON_WHITESPACE] characters.
///
/// Returns `Err` when the joined output falls below
/// [MIN_EXTRACTED_NON_WHITESPACE] characters. pdf_extract reports
/// scanned/image-only PDFs as a vector of empty strings (no error), so
/// without this guard a 0-chunk source would be silently indexed and the
/// user would see an "ingested but unsearchable" mystery.
pub fn extract_text_from_pdf(file_bytes: Vec<u8>) -> Result<String> {
    // Loading + decryption can fail wholesale — those errors are still
    // fatal: there are no pages to fall back to.
    let doc = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        pdf_extract::Document::load_mem(&file_bytes)
    }))
    .map_err(|_| anyhow!("PDF load panicked"))?
    .map_err(|e| anyhow!("PDF extraction failed: {:?}", e))?;

    if doc.is_encrypted() {
        // Match upstream behavior: a missing password makes content
        // extraction silently produce empty pages. Surface this as Err.
        return Err(anyhow!(
            "PDF is encrypted; password-based decryption is not supported"
        ));
    }

    // get_pages() returns a BTreeMap<u32, ObjectId> with the canonical set
    // of page numbers reachable from the page tree, in order. Iterating
    // those keys is the safe page enumeration — it avoids both off-by-one
    // and unbounded-iteration footguns that a naive `1..` loop would have
    // on malformed page trees.
    let page_numbers: Vec<u32> = doc.get_pages().keys().copied().collect();
    let page_count = page_numbers.len();
    let mut pages: Vec<String> = Vec::with_capacity(page_count);
    let mut failed_pages: Vec<u32> = Vec::new();

    for page_num in page_numbers {
        match extract_single_page(&doc, page_num) {
            Ok(text) => pages.push(text),
            Err(reason) => {
                // Mirror the upstream "empty page on failure" shape so
                // join_pages can keep its page-boundary semantics intact;
                // record the page number for the caller-visible summary.
                log::warn!(
                    "PDF page {} extraction failed, skipping: {}",
                    page_num,
                    reason,
                );
                pages.push(String::new());
                failed_pages.push(page_num);
            }
        }
    }

    let joined = join_pages(pages);
    if is_extraction_effectively_empty(&joined) {
        return Err(anyhow!(below_threshold_error_message(
            page_count,
            &failed_pages
        )));
    }

    if !failed_pages.is_empty() {
        log::warn!(
            "PDF extraction recovered after skipping {} failed page(s): {:?}",
            failed_pages.len(),
            failed_pages,
        );
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
    use std::collections::BTreeMap;
    use std::fs::OpenOptions;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Clone, Copy)]
    struct PdfFixture {
        set: &'static str,
        label: &'static str,
        fixture_rel: &'static str,
        optional: bool,
    }

    const TRACKED_PDF_SMOKE_FIXTURES: &[PdfFixture] = &[
        PdfFixture {
            set: "smoke",
            label: "sample_eng",
            fixture_rel: "example/assets/sample_data/sample_eng.pdf",
            optional: false,
        },
        PdfFixture {
            set: "smoke",
            label: "sample_kor",
            fixture_rel: "example/assets/sample_data/sample_kor.pdf",
            optional: false,
        },
    ];

    /// Per-fixture quality floors for the tracked PDF smoke gate.
    ///
    /// `MIN_EXTRACTED_NON_WHITESPACE` (16) is the floor the parser *itself*
    /// already enforces before returning `Ok`, so asserting against it in a
    /// test is tautological — it can never fail. These floors instead sit well
    /// below the values actually observed on the committed fixtures (measured
    /// via `extract_text_from_pdf`):
    ///   sample_eng: 206,817 non-whitespace chars (246,969 total) /
    ///               1,714 paragraph breaks;
    ///   sample_kor: 6,270 non-whitespace chars (7,981 total) / 4,961 Hangul.
    /// So a catastrophic regression — text collapsing to a fraction, lost
    /// paragraph structure, lost CJK, or a key anchor phrase corrupted — fails
    /// CI, while routine parser tuning stays comfortably inside the margin.
    /// This gate is a *volume/structure/anchor* smoke floor; finer-grained CJK
    /// spacing-quality metrics (orphan Hangul, script glue, long runs) are
    /// tracked by the diagnostic dump (`dump_all_pdf_fixtures`), not gated here.
    struct SmokeFloor {
        label: &'static str,
        /// Minimum non-whitespace `char` count the extraction must yield.
        min_nonwhitespace: usize,
        /// Minimum blank-line paragraph breaks (`\n\n`); 0 disables the check.
        min_paragraph_breaks: usize,
        /// Minimum Hangul syllables; 0 disables the check (non-CJK fixtures).
        min_hangul: usize,
        /// Substrings that must survive extraction.
        must_contain: &'static [&'static str],
    }

    const TRACKED_PDF_SMOKE_FLOORS: &[SmokeFloor] = &[
        SmokeFloor {
            label: "sample_eng",
            min_nonwhitespace: 100_000, // observed 206_817
            min_paragraph_breaks: 400,  // observed 1_714
            min_hangul: 0,
            must_contain: &["Insurance Contracts"],
        },
        SmokeFloor {
            label: "sample_kor",
            min_nonwhitespace: 3_000, // observed 6_270
            min_paragraph_breaks: 0,  // kor sample has too few blank-line breaks to gate on
            min_hangul: 1_000,        // observed 4_961
            // Contiguous-Hangul anchors from the doc (title + recurring body
            // term): give the CJK fixture content teeth, not just volume — a
            // regression that garbles Korean tokens trips these.
            must_contain: &["맞춤형", "스마트폰"],
        },
    ];

    const LOCAL_PDF_DIAGNOSTIC_FIXTURES: &[PdfFixture] = &[
        PdfFixture {
            set: "local",
            label: "kor_ins_20120401",
            fixture_rel: "example/assets/sample_data/20120401_10101_1.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "kor_ins_20200101",
            fixture_rel: "example/assets/sample_data/20200101_10108_1.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "kor_drone_2021",
            fixture_rel: "example/assets/sample_data/2021-국방드론.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "kor_misc_202302",
            fixture_rel: "example/assets/sample_data/202302091039136320.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "kor_dod_china_2025",
            fixture_rel: "example/assets/sample_data/2025 미국방부 년례 보고서 - 중국 군사력 보고서.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "kor_accel_2026",
            fixture_rel: "example/assets/sample_data/2026년 글로벌 액셀러레이팅 지원사업 창업기업 모집 공고.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "arxiv_2005_11401",
            fixture_rel: "example/assets/sample_data/2005.11401v4.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "arxiv_2205_14135",
            fixture_rel: "example/assets/sample_data/2205.14135v2.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "arxiv_2509_01092",
            fixture_rel: "example/assets/sample_data/2509.01092v2.pdf",
            optional: true,
        },
        PdfFixture {
            set: "local",
            label: "arxiv_2603_18196",
            fixture_rel: "example/assets/sample_data/2603.18196v1.pdf",
            optional: true,
        },
    ];

    fn repo_root() -> PathBuf {
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        manifest.parent().unwrap().parent().unwrap().to_path_buf()
    }

    fn fixture_path(rel: &str) -> PathBuf {
        repo_root().join(rel)
    }

    fn load_fixture(rel: &str) -> Vec<u8> {
        let path = fixture_path(rel);
        std::fs::read(&path).expect("read fixture")
    }

    fn try_load_fixture(rel: &str) -> Option<Vec<u8>> {
        std::fs::read(fixture_path(rel)).ok()
    }

    #[test]
    fn test_extract_text_from_pdf_happy_path_with_real_fixture() {
        // End-to-end smoke test through the page-by-page loop on a real PDF.
        // Confirms doc load + single-page output + join_pages wiring all work
        // and that we still produce non-trivial English text from sample_eng.
        let bytes = load_fixture("example/assets/sample_data/sample_eng.pdf");
        let out = extract_text_from_pdf(bytes).expect("sample_eng extract");
        // Use a stable phrase from the document header (IFRS 17 standard).
        assert!(
            out.contains("Insurance Contracts"),
            "head: {}",
            &out[..200.min(out.len())]
        );
        // Paragraph breaks from PR A must still be preserved on this path.
        assert!(out.contains("\n\n"));
    }

    #[test]
    fn test_tracked_pdf_smoke_fixtures_extract() {
        for fixture in TRACKED_PDF_SMOKE_FIXTURES {
            // Fail closed: a tracked fixture with no quality floor would
            // otherwise pass on extraction alone, re-introducing a toothless
            // gate. Force every tracked fixture to declare its expectations.
            let floor = TRACKED_PDF_SMOKE_FLOORS
                .iter()
                .find(|f| f.label == fixture.label)
                .unwrap_or_else(|| {
                    panic!(
                        "no TRACKED_PDF_SMOKE_FLOORS entry for tracked fixture '{}'; \
                         add one so the smoke gate has teeth",
                        fixture.label
                    )
                });

            let bytes = load_fixture(fixture.fixture_rel);
            let out = extract_text_from_pdf(bytes)
                .unwrap_or_else(|err| panic!("{} extract failed: {}", fixture.label, err));

            let nonwhitespace = out.chars().filter(|c| !c.is_whitespace()).count();
            assert!(
                nonwhitespace >= floor.min_nonwhitespace,
                "{}: extracted {} non-whitespace chars, expected >= {} (extraction-quality regression?)",
                fixture.label, nonwhitespace, floor.min_nonwhitespace,
            );

            let paragraph_breaks = out.matches("\n\n").count();
            assert!(
                paragraph_breaks >= floor.min_paragraph_breaks,
                "{}: {} paragraph breaks, expected >= {} (lost paragraph structure?)",
                fixture.label,
                paragraph_breaks,
                floor.min_paragraph_breaks,
            );

            if floor.min_hangul > 0 {
                let (_, _, hangul, _, _) = classify_chars(&out);
                assert!(
                    hangul >= floor.min_hangul,
                    "{}: {} Hangul syllables, expected >= {} (CJK extraction regression?)",
                    fixture.label,
                    hangul,
                    floor.min_hangul,
                );
            }

            for needle in floor.must_contain {
                assert!(
                    out.contains(needle),
                    "{}: extracted text missing required substring {:?}",
                    fixture.label,
                    needle,
                );
            }
        }

        // Fail closed in the other direction too: an orphaned floor (e.g. one
        // left behind after a fixture rename) must not silently go dead.
        for floor in TRACKED_PDF_SMOKE_FLOORS {
            assert!(
                TRACKED_PDF_SMOKE_FIXTURES
                    .iter()
                    .any(|fixture| fixture.label == floor.label),
                "orphaned TRACKED_PDF_SMOKE_FLOORS entry '{}' has no matching tracked fixture",
                floor.label,
            );
        }
    }

    #[test]
    fn test_extract_text_from_pdf_rejects_non_pdf_bytes() {
        // Document::load_mem fails -> outer load error path (no page-level
        // fallback to fall back to).
        let result = extract_text_from_pdf(b"this is not a PDF, just text".to_vec());
        assert!(result.is_err());
        let msg = result.unwrap_err().to_string();
        assert!(
            msg.contains("PDF extraction failed") || msg.contains("PDF load panicked"),
            "got: {}",
            msg,
        );
    }

    #[test]
    fn test_extract_text_from_pdf_empty_doc_returns_error() {
        // Header alone — Document::load_mem rejects this so we hit the
        // load-error path, not the "below MIN" path. Either way: structured
        // Err, no panic, no silent success.
        let result = extract_text_from_pdf(b"%PDF-1.4\n".to_vec());
        assert!(result.is_err());
    }

    #[test]
    fn test_extract_single_page_returns_err_for_out_of_range_page() {
        // The per-page wrapper must surface "page does not exist" as a
        // structured Err so the outer loop can record + skip rather than
        // panic. We feed a real PDF and ask for a page number well past
        // the actual page count.
        let bytes = load_fixture("example/assets/sample_data/sample_eng.pdf");
        let doc = pdf_extract::Document::load_mem(&bytes).unwrap();
        let actual_pages = doc.get_pages().len() as u32;
        let result = extract_single_page(&doc, actual_pages + 100);
        assert!(result.is_err(), "got: {:?}", result);
    }

    #[test]
    #[ignore = "depends on an untracked scanned-PDF fixture; PR A's \
                test_is_extraction_effectively_empty_threshold covers the same \
                guard at unit level"]
    fn test_extract_text_from_pdf_scanned_pdf_still_returns_min_error() {
        // PR A behavior preserved through PR C: a scanned/image-only PDF
        // (no extractable text on any page) lands on the "below MIN" Err.
        let Some(bytes) = try_load_fixture("example/assets/sample_data/202302091039136320.pdf")
        else {
            eprintln!("skipping local scanned-PDF diagnostic fixture");
            return;
        };
        let result = extract_text_from_pdf(bytes);
        assert!(result.is_err(), "expected scanned-PDF Err, got Ok");
        let msg = result.unwrap_err().to_string();
        // Assert the full cross-layer contract the Dart classifier depends on:
        // a scanned PDF must carry the "scanned/image-only" marker, not just the
        // shared below-threshold prefix. Guards against the producer-side string
        // drifting out of sync with isOcrRequiredPdfExtractionError.
        assert!(
            msg.contains("fewer than")
                && msg.contains("non-whitespace")
                && msg.contains("scanned/image-only"),
            "got: {}",
            msg,
        );
    }

    #[test]
    fn test_dedup_collapses_korean_doubles_when_dense() {
        // L>=3 doubles ("한국청년...", "해당시해당시") collapse on a dense
        // page. L=2 doubles ("독일독일", "미국미국") survive by design —
        // see DEDUP_MIN_UNIT_CHARS for why L=2 is excluded.
        let page = "해당시해당시 한국청년한국청년기업가정신재단기업가정신재단 독일독일";
        let out = dedup_adjacent_repeats(page);
        assert_eq!(out, "해당시 한국청년기업가정신재단 독일독일");
    }

    #[test]
    fn test_dedup_collapses_long_compound_double() {
        // Single occurrence in an otherwise short page still triggers because
        // the 26 removed chars out of ~26+~30 = ~46% density exceeds 5%.
        let page = "법인등기사항전부증명서법인등기사항전부증명서 구 법인등기부등본";
        let out = dedup_adjacent_repeats(page);
        assert_eq!(out, "법인등기사항전부증명서 구 법인등기부등본");
    }

    #[test]
    fn test_dedup_leaves_short_l2_doubles_alone() {
        // L=2 units like "②②", "독일독일" survive by design — the L>=3
        // minimum guards against English false positives (training→traing).
        let page = "독일독일 ②② 미국미국";
        assert_eq!(dedup_adjacent_repeats(page), page);
    }

    #[test]
    fn test_dedup_does_not_corrupt_english_training_word() {
        // Regression guard for the L=2 walker bug: "training" contains
        // chars[3..5]=="in"==chars[5..7], which an L>=2 walker on a fired
        // page would rewrite to "traing". Build a page that easily fires
        // the count gate (12 L=3 doubles) and verify "training" is intact.
        let mut page = String::new();
        for _ in 0..12 {
            page.push_str("해당시해당시 ");
        }
        page.push_str("Before pretraining, run the training loop on training data");
        let out = dedup_adjacent_repeats(&page);
        assert!(out.contains("pretraining"));
        assert!(out.contains("training loop"));
        assert!(out.contains("training data"));
        assert!(
            !out.contains("traing"),
            "training must not be corrupted: {}",
            out
        );
    }

    #[test]
    fn test_dedup_leaves_natural_repetition_with_space() {
        // Real Korean text where the same word legitimately repeats with
        // an intervening space must not be touched.
        let page = "네 네 잘 알겠습니다. 또 또 다른 의견이 있나요?";
        assert_eq!(dedup_adjacent_repeats(page), page);
    }

    #[test]
    fn test_dedup_leaves_legit_compound_nouns() {
        // Legal-statute / proper-noun compounds (long Hangul runs without
        // an inner duplicate) must pass through unchanged.
        let page = "어린이놀이시설안전관리법 제2조 두산모빌리티이노베이션 주요 성능";
        assert_eq!(dedup_adjacent_repeats(page), page);
    }

    #[test]
    fn test_dedup_below_both_triggers_is_a_noop() {
        // One short accidental double in an otherwise long clean page —
        // density well below 5% AND matches well below the 8-match secondary
        // trigger. Must NOT rewrite.
        let lorem = "보험 계약은 약관에 따라 체결됩니다. 보험금 지급은 청구일로부터 \
                     영업일 기준 3일 이내에 처리되며, 지급 사유와 지급 방식은 ";
        let mut page = String::new();
        for _ in 0..6 {
            page.push_str(lorem);
        }
        page.push_str("독일독일");
        assert_eq!(dedup_adjacent_repeats(&page), page);
    }

    #[test]
    fn test_dedup_fires_on_high_match_count_low_density() {
        // Mimics the kor_accel_2026 borderline case: a long page with many
        // L>=3 doubles but lots of clean tabular text in between. Density
        // alone (~3-4%) wouldn't trigger; the 8+ match count must.
        let clean_filler = " 계약일자 발행기관 검토자 승인자 시행일자 비고 첨부 참고 별첨 자료 ";
        let mut page = String::new();
        for _ in 0..15 {
            page.push_str(clean_filler);
        }
        // Insert 10 L>=3 doubles scattered through the page.
        for word in [
            "국토부",
            "외교부",
            "법무부",
            "통일부",
            "행안부",
            "산업부",
            "환경부",
            "고용부",
            "복지부",
            "여가부",
        ] {
            page.push(' ');
            page.push_str(word);
            page.push_str(word);
        }
        let out = dedup_adjacent_repeats(&page);
        for word in [
            "국토부",
            "외교부",
            "법무부",
            "통일부",
            "행안부",
            "산업부",
            "환경부",
            "고용부",
            "복지부",
            "여가부",
        ] {
            let doubled = format!("{word}{word}");
            assert!(
                !out.contains(&doubled),
                "doubled token {} should be collapsed",
                doubled
            );
            assert!(out.contains(word), "single copy of {} should remain", word);
        }
    }

    #[test]
    fn test_dedup_does_not_cross_whitespace() {
        // Whitespace separator breaks the no-whitespace constraint. With
        // L>=3 only the longer Korean compound double collapses; the
        // space-separated and L=2 ones are left intact.
        let page = "독일 독일 미국미국 한국청년한국청년 일본일본 영국영국";
        let out = dedup_adjacent_repeats(page);
        assert_eq!(out, "독일 독일 미국미국 한국청년 일본일본 영국영국");
    }

    #[test]
    fn test_dedup_picks_longest_match_first() {
        // Greedy-longest avoids collapsing only a prefix.
        // "ABCDEABCDE" must collapse as one L=5 match (matches >= 3 only,
        // density 50%), not pick a shorter sub-match.
        let page = "ABCDEABCDE ABCDEABCDE ABCDEABCDE";
        let out = dedup_adjacent_repeats(page);
        assert_eq!(out, "ABCDE ABCDE ABCDE");
    }

    #[test]
    fn test_dedup_handles_unicode_boundaries_safely() {
        // Units measured in chars, not bytes — multi-byte chars must not
        // be split. L=5 matches qualify under the L>=3 rule.
        let page = "ABC가나ABC가나 XYZ다라XYZ다라";
        let out = dedup_adjacent_repeats(page);
        assert_eq!(out, "ABC가나 XYZ다라");
    }

    #[test]
    fn test_dedup_short_input_is_noop() {
        assert_eq!(dedup_adjacent_repeats(""), "");
        assert_eq!(dedup_adjacent_repeats("가"), "가");
        assert_eq!(dedup_adjacent_repeats("가나"), "가나");
        // Six chars are required to fit even the smallest (L=3) match.
        assert_eq!(dedup_adjacent_repeats("가나다라마"), "가나다라마");
    }

    #[test]
    fn test_dedup_runs_in_join_pages_pipeline() {
        // End-to-end: dedup is applied during join_pages, after page-number
        // removal and before cross-page hyphenation/CJK fold. L=3+ double
        // collapses; L=2 ("독일독일") survives by design.
        let pages = vec!["독일독일 한국청년한국청년기업가정신재단기업가정신재단".to_string()];
        let joined = join_pages(pages);
        assert_eq!(joined, "독일독일 한국청년기업가정신재단");
    }

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
        assert_eq!(
            result,
            "심층 시장 조사 보고서\n\n문제 정의: 무엇을 풀려는가"
        );
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
    fn test_should_include_scanned_marker() {
        // Marker kept: at least one page parsed (readable but text-less → the
        // scanned/image-only signature OCR can recover), even alongside
        // failures. Covers Finding #1: a scanned PDF with a stray corrupt page.
        assert!(
            should_include_scanned_marker(1, 0),
            "single-page pure scanned"
        );
        assert!(
            should_include_scanned_marker(5, 0),
            "multi-page pure scanned"
        );
        assert!(should_include_scanned_marker(5, 1), "mixed: 1 of 5 failed");
        assert!(should_include_scanned_marker(5, 4), "mixed: 4 of 5 failed");
        assert!(
            should_include_scanned_marker(2, 1),
            "boundary: 1 of 2 failed"
        );
        assert!(
            should_include_scanned_marker(0, 0),
            "degenerate zero-page doc preserves prior scanned behavior"
        );

        // Marker withheld only when EVERY page failed to parse: no readable
        // page, no scanned-layer evidence, OCR cannot help.
        assert!(!should_include_scanned_marker(1, 1), "single page failed");
        assert!(!should_include_scanned_marker(5, 5), "every page failed");
    }

    #[test]
    fn test_below_threshold_error_message() {
        // The Dart classifier (isOcrRequiredPdfExtractionError) routes to OCR
        // when the message contains BOTH "PDF text extraction returned fewer
        // than" AND "scanned/image-only". These assertions pin the exact
        // producer-side format so it cannot drift out of sync with that
        // contract without failing here.

        // Pure scanned: marker present, no page-failure summary.
        let m = below_threshold_error_message(5, &[]);
        assert!(m.contains("PDF text extraction returned fewer than"), "{m}");
        assert!(m.contains("scanned/image-only"), "{m}");
        assert!(!m.contains("failed to extract"), "{m}");

        // Mixed (1 of 5 failed): keeps the marker AND reports the failures —
        // exactly the string the Dart mixed-case test mirrors. Covers Finding #1.
        let m = below_threshold_error_message(5, &[3]);
        assert!(m.contains("PDF text extraction returned fewer than"), "{m}");
        assert!(
            m.contains("1 of 5 page(s) failed to extract (pages: [3])"),
            "{m}"
        );
        assert!(m.contains("scanned/image-only"), "{m}");

        // Mixed (3 of 5 failed): higher failure ratio still routes to OCR.
        let m = below_threshold_error_message(5, &[0, 1, 2]);
        assert!(
            m.contains("3 of 5 page(s) failed to extract (pages: [0, 1, 2])"),
            "{m}"
        );
        assert!(m.contains("scanned/image-only"), "{m}");

        // Fully failed (every page): NO marker — OCR cannot help.
        let m = below_threshold_error_message(3, &[0, 1, 2]);
        assert!(
            m.contains("3 of 3 page(s) failed to extract (pages: [0, 1, 2])"),
            "{m}"
        );
        assert!(!m.contains("scanned/image-only"), "{m}");
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
        set: String,
        status: String,
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
        log_path: Option<String>,
    }

    impl ExtractSummary {
        fn empty(fixture: &PdfFixture, status: &str, err: Option<String>) -> Self {
            Self {
                set: fixture.set.to_string(),
                status: status.to_string(),
                label: fixture.label.to_string(),
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
                err,
                log_path: None,
            }
        }
    }

    fn diagnostics_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/pdf_diagnostics")
    }

    fn diagnostic_log_path(diagnostics_dir: &Path, fixture: &PdfFixture) -> PathBuf {
        diagnostics_dir.join(format!("{}_{}.log", fixture.set, fixture.label))
    }

    fn diagnostic_log_display(log_path: &Path) -> String {
        let file_name = log_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("unknown.log");
        format!("rust_builder/rust/target/pdf_diagnostics/{}", file_name)
    }

    fn short_error(err: &str) -> String {
        let compact = err.split_whitespace().collect::<Vec<_>>().join(" ");
        const MAX_CHARS: usize = 120;
        if compact.chars().count() <= MAX_CHARS {
            return compact;
        }
        let mut shortened: String = compact.chars().take(MAX_CHARS).collect();
        shortened.push_str("...");
        shortened
    }

    fn summarize_one_inner(fixture: &PdfFixture, path: &Path) -> ExtractSummary {
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(e) => {
                return ExtractSummary::empty(fixture, "ERR", Some(format!("read error: {}", e)));
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
                    set: fixture.set.to_string(),
                    status: "ERR".to_string(),
                    label: fixture.label.to_string(),
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
                    log_path: None,
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
            set: fixture.set.to_string(),
            status: "OK".to_string(),
            label: fixture.label.to_string(),
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
            log_path: None,
        }
    }

    fn summarize_one(fixture: &PdfFixture, diagnostics_dir: &Path) -> ExtractSummary {
        let path = fixture_path(fixture.fixture_rel);
        if !path.exists() {
            let status = if fixture.optional { "SKIP" } else { "ERR" };
            return ExtractSummary::empty(
                fixture,
                status,
                Some(format!("missing fixture: {}", fixture.fixture_rel)),
            );
        }

        let _ = std::fs::create_dir_all(diagnostics_dir);
        let log_path = diagnostic_log_path(diagnostics_dir, fixture);
        let stdout_redirect = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&log_path)
            .ok()
            .and_then(|file| gag::Redirect::stdout(file).ok());
        let stderr_redirect = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .ok()
            .and_then(|file| gag::Redirect::stderr(file).ok());

        let mut summary = summarize_one_inner(fixture, &path);

        drop(stderr_redirect);
        drop(stdout_redirect);

        if let Ok(meta) = std::fs::metadata(&log_path) {
            if meta.len() > 0 {
                summary.log_path = Some(diagnostic_log_display(&log_path));
            } else {
                let _ = std::fs::remove_file(&log_path);
            }
        }

        summary
    }

    fn summary_tsv(summaries: &[ExtractSummary]) -> String {
        let mut out = String::from(
            "set\tstatus\tlabel\tpages\tms\tchars\thangul\tascii\tdigit\tnl\tpara\tweird_kinds\tweird_total\torph\tglue\tlong_run\tmax_run\tnum_tokens_ge3\tlog\terror\n",
        );
        for s in summaries {
            out.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                s.set,
                s.status,
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
                s.numeric_tokens_ge3,
                s.log_path.as_deref().unwrap_or("-"),
                s.err.as_deref().map(short_error).unwrap_or_default(),
            ));
        }
        out
    }

    fn write_summary_files(
        summaries: &[ExtractSummary],
        diagnostics_dir: &Path,
    ) -> std::io::Result<(PathBuf, PathBuf)> {
        std::fs::create_dir_all(diagnostics_dir)?;
        let body = summary_tsv(summaries);
        let latest = diagnostics_dir.join("latest_summary.tsv");
        std::fs::write(&latest, &body)?;

        let epoch = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let timestamped = diagnostics_dir.join(format!("summary_{}.tsv", epoch));
        std::fs::write(&timestamped, body)?;
        Ok((latest, timestamped))
    }

    #[derive(Clone, Copy)]
    struct BaselineMetrics {
        chars: usize,
        para: usize,
        weird_total: usize,
        glue: usize,
        long_run: usize,
        max_run: usize,
    }

    fn summary_key(set: &str, label: &str) -> String {
        format!("{}\t{}", set, label)
    }

    fn header_index(headers: &[&str], name: &str) -> Option<usize> {
        headers.iter().position(|header| *header == name)
    }

    fn field<'a>(fields: &'a [&str], headers: &[&str], name: &str) -> Option<&'a str> {
        header_index(headers, name).and_then(|idx| fields.get(idx).copied())
    }

    fn parse_usize_field(fields: &[&str], headers: &[&str], name: &str) -> usize {
        field(fields, headers, name)
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(0)
    }

    fn parse_baseline_summary(path: &Path) -> BTreeMap<String, BaselineMetrics> {
        let Ok(content) = std::fs::read_to_string(path) else {
            return BTreeMap::new();
        };
        let mut lines = content.lines();
        let Some(header_line) = lines.next() else {
            return BTreeMap::new();
        };
        let headers: Vec<&str> = header_line.split('\t').collect();
        let mut out = BTreeMap::new();

        for line in lines {
            let fields: Vec<&str> = line.split('\t').collect();
            if field(&fields, &headers, "status") != Some("OK") {
                continue;
            }
            let Some(set) = field(&fields, &headers, "set") else {
                continue;
            };
            let Some(label) = field(&fields, &headers, "label") else {
                continue;
            };
            out.insert(
                summary_key(set, label),
                BaselineMetrics {
                    chars: parse_usize_field(&fields, &headers, "chars"),
                    para: parse_usize_field(&fields, &headers, "para"),
                    weird_total: parse_usize_field(&fields, &headers, "weird_total"),
                    glue: parse_usize_field(&fields, &headers, "glue"),
                    long_run: parse_usize_field(&fields, &headers, "long_run"),
                    max_run: parse_usize_field(&fields, &headers, "max_run"),
                },
            );
        }

        out
    }

    fn signed_delta(current: usize, baseline: usize) -> String {
        format!("{:+}", current as i128 - baseline as i128)
    }

    fn print_baseline_delta(summaries: &[ExtractSummary]) {
        let Ok(baseline_path) = std::env::var("PDF_DIAGNOSTICS_BASELINE") else {
            return;
        };
        let baseline = parse_baseline_summary(Path::new(&baseline_path));
        if baseline.is_empty() {
            println!("baseline delta: no readable OK rows in {}", baseline_path);
            return;
        }

        println!("===== PDF DIAGNOSTIC DELTA vs {} =====", baseline_path);
        println!(
            "{:<8} {:<20} {:>7} {:>6} {:>7} {:>6} {:>8} {:>7}",
            "set", "label", "chars", "para", "weird", "glue", "longrun", "maxrun"
        );
        for s in summaries.iter().filter(|s| s.ok) {
            let key = summary_key(&s.set, &s.label);
            let Some(base) = baseline.get(&key) else {
                continue;
            };
            println!(
                "{:<8} {:<20} {:>7} {:>6} {:>7} {:>6} {:>8} {:>7}",
                s.set,
                s.label,
                signed_delta(s.chars, base.chars),
                signed_delta(s.paragraph_breaks, base.para),
                signed_delta(s.weird_total, base.weird_total),
                signed_delta(s.script_glue, base.glue),
                signed_delta(s.long_hangul_runs_ge12, base.long_run),
                signed_delta(s.max_hangul_run, base.max_run),
            );
        }
    }

    fn print_top_long_runs(label: &str, fixture_rel: &str, k: usize) {
        let Some(bytes) = try_load_fixture(fixture_rel) else {
            println!(
                "--- top {} Hangul runs in {}: SKIP missing fixture ---",
                k, label
            );
            return;
        };
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
        let diagnostics_dir = diagnostics_dir();
        let mut summaries: Vec<ExtractSummary> = Vec::new();
        for fixture in TRACKED_PDF_SMOKE_FIXTURES
            .iter()
            .chain(LOCAL_PDF_DIAGNOSTIC_FIXTURES.iter())
        {
            summaries.push(summarize_one(fixture, &diagnostics_dir));
        }

        let (latest_summary, timestamped_summary) =
            write_summary_files(&summaries, &diagnostics_dir).expect("write PDF summary files");

        println!(
            "===== PDF EXTRACTION SUMMARY ({} fixtures: tracked smoke + local diagnostic) =====",
            summaries.len()
        );
        println!(
            "{:<8} {:<6} {:<20} {:>5} {:>5} {:>8} {:>5} {:>9} {:>6} {:>8} {:>7} {}",
            "set",
            "status",
            "label",
            "pages",
            "ms",
            "chars",
            "para",
            "weird",
            "glue",
            "longrun",
            "maxrun",
            "log",
        );
        for s in &summaries {
            if !s.ok {
                println!(
                    "{:<8} {:<6} {:<20} {:>5} {:>5} {:>8} {:>5} {:>9} {:>6} {:>8} {:>7} {}",
                    s.set,
                    s.status,
                    s.label,
                    s.page_count,
                    s.extract_ms,
                    "-",
                    "-",
                    "-",
                    "-",
                    "-",
                    "-",
                    s.err.as_deref().map(short_error).unwrap_or_default(),
                );
                continue;
            }
            println!(
                "{:<8} {:<6} {:<20} {:>5} {:>5} {:>8} {:>5} {:>9} {:>6} {:>8} {:>7} {}",
                s.set,
                s.status,
                s.label,
                s.page_count,
                s.extract_ms,
                s.chars,
                s.paragraph_breaks,
                format!("{}/{}", s.weird_kinds, s.weird_total),
                s.script_glue,
                s.long_hangul_runs_ge12,
                s.max_hangul_run,
                s.log_path.as_deref().unwrap_or("-"),
            );
        }
        println!("summary: {}", latest_summary.display());
        println!("snapshot: {}", timestamped_summary.display());
        println!("legend: weird=distinct/total; longrun=runs of >=12 consecutive Hangul");
        print_baseline_delta(&summaries);
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_dedup_match_samples_arxiv() {
        // Show exactly what the dedup heuristic would collapse on the arxiv
        // PDFs so we can judge whether the recent count-gate is catching
        // real PDF artifacts or false-positive equation noise.
        let picks: &[(&str, &str)] = &[
            (
                "arxiv_2005_11401",
                "example/assets/sample_data/2005.11401v4.pdf",
            ),
            (
                "arxiv_2205_14135",
                "example/assets/sample_data/2205.14135v2.pdf",
            ),
            (
                "arxiv_2509_01092",
                "example/assets/sample_data/2509.01092v2.pdf",
            ),
            (
                "arxiv_2603_18196",
                "example/assets/sample_data/2603.18196v1.pdf",
            ),
        ];
        for (label, rel) in picks {
            let Some(bytes) = try_load_fixture(rel) else {
                println!(
                    "\n=== arxiv dedup-match samples: {} SKIP missing fixture ===",
                    label
                );
                continue;
            };
            let pages = pdf_extract::extract_text_from_mem_by_pages(&bytes).unwrap();

            println!("\n=== arxiv dedup-match samples: {} ===", label);
            for (idx, raw_page) in pages.iter().enumerate() {
                let page = normalize_extracted_text(raw_page);
                let page = remove_trailing_page_number(&page);
                let total = page.chars().count();
                if total == 0 {
                    continue;
                }
                let (matches, removed) = find_adjacent_repeats(&page);
                let density = removed as f64 / total as f64;
                let density_fires = density >= DEDUP_DENSITY_TRIGGER;
                let count_fires = matches.len() >= DEDUP_MIN_MATCHES_TRIGGER;
                if !density_fires && !count_fires {
                    continue;
                }
                println!(
                    "  page[{:3}] chars={:>5} matches={:>3} dup={:>3} density={:.3} {}",
                    idx,
                    total,
                    matches.len(),
                    removed,
                    density,
                    if density_fires {
                        "DENSITY"
                    } else {
                        "COUNT-ONLY"
                    }
                );
                let chars: Vec<char> = page.chars().collect();
                for (start, len) in matches.iter().take(8) {
                    let lo = start.saturating_sub(8);
                    let hi = (start + 2 * len + 8).min(chars.len());
                    let ctx: String = chars[lo..hi].iter().collect();
                    let unit: String = chars[*start..*start + *len].iter().collect();
                    println!("    L={:2}  unit={:?}  ctx=…{}…", len, unit, ctx);
                }
            }
        }
    }

    #[test]
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_dedup_density_per_page() {
        // Diagnose which pages of doubled-text PDFs sit below the density
        // trigger so we can judge whether DEDUP_DENSITY_TRIGGER is set
        // correctly (vs needing to be lowered / per-page tuned).
        let picks: &[(&str, &str)] = &[
            ("kor_accel_2026", "example/assets/sample_data/2026년 글로벌 액셀러레이팅 지원사업 창업기업 모집 공고.pdf"),
            ("kor_ins_20200101", "example/assets/sample_data/20200101_10108_1.pdf"),
            ("kor_drone_2021_clean_sample", "example/assets/sample_data/2021-국방드론.pdf"),
            ("kor_ins_20120401", "example/assets/sample_data/20120401_10101_1.pdf"),
            ("sample_kor", "example/assets/sample_data/sample_kor.pdf"),
        ];
        for (label, rel) in picks {
            let Some(bytes) = try_load_fixture(rel) else {
                println!("\n=== density per page: {} SKIP missing fixture ===", label);
                continue;
            };
            let pages = pdf_extract::extract_text_from_mem_by_pages(&bytes).unwrap();

            println!(
                "\n=== density per page: {} (trigger >= {:.2}) ===",
                label, DEDUP_DENSITY_TRIGGER
            );
            for (idx, raw_page) in pages.iter().enumerate() {
                let page = normalize_extracted_text(raw_page);
                let page = remove_trailing_page_number(&page);
                let total = page.chars().count();
                if total == 0 {
                    continue;
                }
                let (matches, removed) = find_adjacent_repeats(&page);
                let density = removed as f64 / total as f64;
                let fired = density >= DEDUP_DENSITY_TRIGGER;
                let marker = if fired { "FIRED" } else { "skip " };
                println!(
                    "  page[{:3}] chars={:>5} dup_chars={:>4} density={:.3} matches={:>3} {}",
                    idx,
                    total,
                    removed,
                    density,
                    matches.len(),
                    marker
                );
            }
        }
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
    #[ignore = "analysis dump — run with --ignored --nocapture"]
    fn dump_chunk_distribution_after_extraction() {
        // Surface how paragraph-aware extraction reshapes the downstream
        // chunker's output: count, mean/min/max char size, and how many
        // chunks contain CJK (Hangul) content. Useful diff between
        // pre-PR-A baseline (all text in one paragraph -> uniformly
        // max_chars-sized chunks) and post-PR-A behavior (smaller, more
        // semantic chunks).
        use crate::api::semantic_chunker::semantic_chunk;
        let fixtures: &[(&str, &str)] = &[
            ("sample_eng", "example/assets/sample_data/sample_eng.pdf"),
            ("sample_kor", "example/assets/sample_data/sample_kor.pdf"),
            (
                "kor_ins_20200101",
                "example/assets/sample_data/20200101_10108_1.pdf",
            ),
            (
                "kor_drone_2021",
                "example/assets/sample_data/2021-국방드론.pdf",
            ),
        ];

        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        const MAX_CHARS: i32 = 800;

        println!("===== CHUNK DISTRIBUTION @ max_chars={} =====", MAX_CHARS);
        println!(
            "{:<22} {:>6} {:>7} {:>7} {:>5} {:>5} {:>7}",
            "label", "text", "chunks", "mean", "min", "max", "cjk_ch"
        );
        for (label, fixture_rel) in fixtures {
            let path = manifest
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join(fixture_rel);
            let bytes = match std::fs::read(&path) {
                Ok(b) => b,
                Err(e) => {
                    println!("{:<22} READ ERR: {}", label, e);
                    continue;
                }
            };
            let text = match extract_text_from_pdf(bytes) {
                Ok(s) => s,
                Err(e) => {
                    println!("{:<22} EXTRACT ERR: {}", label, e);
                    continue;
                }
            };
            let chunks = semantic_chunk(text.clone(), MAX_CHARS);
            let sizes: Vec<usize> = chunks.iter().map(|c| c.content.chars().count()).collect();
            let total_chars = text.chars().count();
            let n = sizes.len();
            let mean = if n == 0 {
                0
            } else {
                sizes.iter().sum::<usize>() / n
            };
            let min = sizes.iter().copied().min().unwrap_or(0);
            let max = sizes.iter().copied().max().unwrap_or(0);
            let cjk_chunks = chunks
                .iter()
                .filter(|c| {
                    c.content
                        .chars()
                        .any(|ch| matches!(ch as u32, 0xAC00..=0xD7AF))
                })
                .count();
            println!(
                "{:<22} {:>6} {:>7} {:>7} {:>5} {:>5} {:>7}",
                label, total_chars, n, mean, min, max, cjk_chunks
            );
        }
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

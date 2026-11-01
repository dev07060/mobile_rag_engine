// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Minimal in-house OOXML (DOCX) text reader.
//
// Lives outside `crate::api` on purpose: flutter_rust_bridge only scans
// `api/`, so nothing here becomes part of the FFI surface. The public entry
// point is `api::document_parser::extract_text_from_docx`.
//
// Why not `docx-lite`: it configures quick-xml with `trim_text(true)`, which
// deletes `<w:t xml:space="preserve"> </w:t>` runs (words merge), drops
// `w:tab`/`w:br`, moves every table to the end of the document, replaces the
// anchor paragraph with text-box text, ignores headers/footers/notes, and
// decompresses parts with an unbounded `read_to_string` (zip bomb -> OOM).
//
// Output shape (plain text, consumed by the Recursive chunker):
// - one paragraph per line; `w:tab` -> `\t`, `w:br`/`w:cr` -> `\n`;
// - tables in place, one row per line, cells joined by ` | `; inside a cell,
//   paragraphs are joined by ` / ` and a nested table is rendered inline as
//   `[r1c1 | r1c2; r2c1 | r2c2]`;
// - a text box's content follows its anchor paragraph;
// - deleted / moved-from revision text is skipped, inserted text is kept;
// - headers, footers, footnotes and endnotes are appended after the body, in
//   that order (numeric part order within a kind), each part once, with
//   byte-identical part texts emitted only once.

use std::collections::HashSet;
use std::io::{Cursor, Read};

use anyhow::{anyhow, Result};
use quick_xml::events::{BytesStart, Event};
use quick_xml::name::{Namespace, ResolveResult};
use quick_xml::NsReader;

/// Transitional and Strict WordprocessingML namespaces.
const W_NS: &[&[u8]] = &[
    b"http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    b"http://purl.oclc.org/ooxml/wordprocessingml/main",
];
const MC_NS: &[u8] = b"http://schemas.openxmlformats.org/markup-compatibility/2006";

const MAIN_PART: &str = "word/document.xml";

/// Resource limits for reading an untrusted DOCX container.
///
/// The decompression budget shared by every XML part we read is
/// `clamp(max_compression_ratio * input_len, min_uncompressed_bytes,
/// total_uncompressed_bytes)` (see [DocxLimits::budget_for]).
#[derive(Clone, Copy, Debug)]
pub(crate) struct DocxLimits {
    /// Absolute cap on decompressed bytes, whatever the input size.
    pub total_uncompressed_bytes: u64,
    /// Budget per byte of input (the whole container, media included).
    pub max_compression_ratio: u64,
    /// Floor of the ratio budget, so tiny documents always fit.
    pub min_uncompressed_bytes: u64,
    /// Maximum number of entries in the zip central directory.
    pub max_entries: usize,
}

impl DocxLimits {
    /// Absolute cap 200 MB = 4x the 50 MB input cap. Only text-bearing XML
    /// parts are decompressed (never media).
    ///
    /// The cap alone is not enough on a phone: a ~200 KB DOCX could inflate to
    /// 200 MB of XML, and the extracted text is held next to it, which iOS
    /// jetsam kills (no unwind, so `catch_unwind` cannot help). So the budget
    /// also scales with the input: text-only OOXML parts typically compress
    /// 5-20x, and the input length also counts media and zip overhead, so
    /// 100x is generous for real documents while a bomb (1000:1+) is cut off
    /// at ~100x its own size. The 16 MB floor keeps tiny-but-valid files
    /// (a few KB of highly repetitive XML) working.
    ///
    /// Entry count: real documents have tens to a few hundred entries; 10k
    /// leaves ample room and bounds per-entry bookkeeping.
    pub(crate) const DEFAULT: DocxLimits = DocxLimits {
        total_uncompressed_bytes: 200 * 1024 * 1024,
        max_compression_ratio: 100,
        min_uncompressed_bytes: 16 * 1024 * 1024,
        max_entries: 10_000,
    };

    /// Decompression budget for a container of `input_len` bytes.
    pub(crate) fn budget_for(&self, input_len: usize) -> u64 {
        (input_len as u64)
            .saturating_mul(self.max_compression_ratio)
            .max(self.min_uncompressed_bytes)
            .min(self.total_uncompressed_bytes)
    }
}

/// Upper bound on the up-front allocation for one part. The declared size
/// comes from the (untrusted) zip header, so it only sizes the first
/// allocation up to this cap; larger parts grow the buffer as they inflate.
const MAX_PREALLOCATED_PART_BYTES: u64 = 16 * 1024 * 1024;

/// Extract plain text from DOCX bytes with [DocxLimits::DEFAULT].
pub(crate) fn extract_docx_text(bytes: &[u8]) -> Result<String> {
    extract_docx_text_with_limits(bytes, DocxLimits::DEFAULT)
}

pub(crate) fn extract_docx_text_with_limits(bytes: &[u8], limits: DocxLimits) -> Result<String> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))
        .map_err(|e| anyhow!("not a valid DOCX (zip) container: {}", e))?;

    if archive.len() > limits.max_entries {
        return Err(anyhow!(
            "DOCX has too many zip entries ({} > {})",
            archive.len(),
            limits.max_entries
        ));
    }

    let names: Vec<String> = archive.file_names().map(str::to_owned).collect();
    if !names.iter().any(|n| n == MAIN_PART) {
        return Err(anyhow!("not a DOCX document: missing {}", MAIN_PART));
    }

    let mut budget = limits.budget_for(bytes.len());

    let main_xml = read_part(&mut archive, MAIN_PART, &mut budget)?;
    let mut out = walk_part(&main_xml).map_err(|e| anyhow!("{}: {}", MAIN_PART, e))?;
    drop(main_xml);

    let mut seen_texts: HashSet<String> = HashSet::new();
    for part in auxiliary_parts(&names) {
        let xml = read_part(&mut archive, &part, &mut budget)?;
        // A malformed header/footer/notes part must not sink the body text.
        let text = match walk_part(&xml) {
            Ok(t) => t,
            Err(e) => {
                log::warn!("DOCX: skipping unreadable part {}: {}", part, e);
                continue;
            }
        };
        let text = text.trim_matches('\n');
        if text.trim().is_empty() || seen_texts.contains(text) {
            continue;
        }
        if !out.is_empty() && !out.ends_with("\n\n") {
            out.push_str(if out.ends_with('\n') { "\n" } else { "\n\n" });
        }
        out.push_str(text);
        out.push('\n');
        seen_texts.insert(text.to_owned());
    }

    Ok(finalize(out))
}

/// Header, footer, footnote and endnote parts, in a stable order.
fn auxiliary_parts(names: &[String]) -> Vec<String> {
    fn numbered(names: &[String], stem: &str) -> Vec<String> {
        let prefix = format!("word/{}", stem);
        let mut found: Vec<(u64, String)> = names
            .iter()
            .filter_map(|n| {
                let digits = n.strip_prefix(&prefix)?.strip_suffix(".xml")?;
                if !digits.bytes().all(|b| b.is_ascii_digit()) {
                    return None;
                }
                let idx = if digits.is_empty() {
                    0
                } else {
                    digits.parse().ok()?
                };
                Some((idx, n.clone()))
            })
            .collect();
        found.sort();
        found.dedup_by(|a, b| a.1 == b.1);
        found.into_iter().map(|(_, n)| n).collect()
    }
    let mut parts = numbered(names, "header");
    parts.extend(numbered(names, "footer"));
    for fixed in ["word/footnotes.xml", "word/endnotes.xml"] {
        if names.iter().any(|n| n == fixed) {
            parts.push(fixed.to_owned());
        }
    }
    parts
}

/// Decompress one entry under the shared byte budget. The declared size is
/// checked first (cheap rejection, no allocation), then the stream is read
/// through `take(budget + 1)` so a header that understates the size cannot
/// push us past the limit.
fn read_part<R: Read + std::io::Seek>(
    archive: &mut zip::ZipArchive<R>,
    name: &str,
    budget: &mut u64,
) -> Result<String> {
    let entry = archive
        .by_name(name)
        .map_err(|e| anyhow!("DOCX part {} unreadable: {}", name, e))?;
    let declared = entry.size();
    if declared > *budget {
        return Err(decompression_limit_error(name));
    }
    let mut raw = Vec::with_capacity(declared.min(MAX_PREALLOCATED_PART_BYTES) as usize);
    entry
        .take(*budget + 1)
        .read_to_end(&mut raw)
        .map_err(|e| anyhow!("DOCX part {} could not be decompressed: {}", name, e))?;
    if raw.len() as u64 > *budget {
        return Err(decompression_limit_error(name));
    }
    *budget -= raw.len() as u64;
    // OOXML parts are UTF-8 (UTF-16 is legal but not produced in practice);
    // decode lossily rather than failing the whole document.
    Ok(match String::from_utf8(raw) {
        Ok(s) => s,
        Err(e) => String::from_utf8_lossy(e.as_bytes()).into_owned(),
    })
}

fn decompression_limit_error(name: &str) -> anyhow::Error {
    anyhow!(
        "DOCX decompressed size limit exceeded while reading {} \
         (possible zip bomb); refusing to extract",
        name
    )
}

/// Collapse 3+ consecutive newlines and trim trailing spaces on each line.
///
/// Works in place on the walker's buffer (the output is never longer than
/// the input), so the extracted text is not copied a third time.
fn finalize(text: String) -> String {
    let mut bytes = text.into_bytes();
    let len = bytes.len();
    let mut write = 0usize;
    let mut newlines = 0usize;
    let mut start = 0usize;
    loop {
        let end = bytes[start..]
            .iter()
            .position(|&b| b == b'\n')
            .map_or(len, |i| start + i);
        let mut line_end = end;
        while line_end > start && bytes[line_end - 1] == b' ' {
            line_end -= 1;
        }
        // Split only at ASCII '\n' / ' ', so every line is valid UTF-8.
        let blank = std::str::from_utf8(&bytes[start..line_end])
            .map_or(false, |line| line.trim().is_empty());
        if blank {
            newlines += 1;
        } else {
            // `write <= start` holds: every separator written here stands
            // for at least as many '\n' bytes already consumed.
            if write > 0 {
                bytes[write] = b'\n';
                write += 1;
                if newlines > 1 {
                    bytes[write] = b'\n';
                    write += 1;
                }
            }
            newlines = 1;
            bytes.copy_within(start..line_end, write);
            write += line_end - start;
        }
        if end == len {
            break;
        }
        start = end + 1;
    }
    bytes.truncate(write);
    String::from_utf8(bytes).expect("finalize keeps UTF-8 boundaries")
}

// ---------------------------------------------------------------------------
// XML walk
// ---------------------------------------------------------------------------

#[derive(PartialEq)]
enum SinkKind {
    Root,
    Cell,
    TextBox,
}

struct Sink {
    kind: SinkKind,
    buf: String,
}

#[derive(Default)]
struct Table {
    rows: Vec<Vec<String>>,
    cur_row: Option<Vec<String>>,
}

#[derive(Default)]
struct Paragraph {
    /// Finished text boxes anchored in this paragraph, emitted after it.
    pending_text_boxes: Vec<String>,
}

struct Walker {
    sinks: Vec<Sink>,
    tables: Vec<Table>,
    paragraphs: Vec<Paragraph>,
    run_depth: usize,
    text_depth: usize,
    deleted_depth: usize,
    /// Depth counter while inside an element whose content is ignored
    /// (`mc:Fallback` duplicates of text boxes).
    skip_depth: usize,
}

impl Walker {
    fn new() -> Self {
        Walker {
            sinks: vec![Sink {
                kind: SinkKind::Root,
                buf: String::new(),
            }],
            tables: Vec::new(),
            paragraphs: Vec::new(),
            run_depth: 0,
            text_depth: 0,
            deleted_depth: 0,
            skip_depth: 0,
        }
    }

    fn sink(&mut self) -> &mut String {
        // `sinks` always holds the root; pops never remove it.
        &mut self.sinks.last_mut().expect("root sink").buf
    }

    fn push_text(&mut self, s: &str) {
        if self.deleted_depth == 0 {
            self.sink().push_str(s);
        }
    }

    fn start(&mut self, local: &[u8], e: &BytesStart) {
        match local {
            b"p" => self.paragraphs.push(Paragraph::default()),
            b"r" => self.run_depth += 1,
            b"t" => self.text_depth += 1,
            b"del" | b"moveFrom" => self.deleted_depth += 1,
            b"tbl" => self.tables.push(Table::default()),
            b"tr" => {
                if let Some(t) = self.tables.last_mut() {
                    t.cur_row = Some(Vec::new());
                }
            }
            b"tc" => self.sinks.push(Sink {
                kind: SinkKind::Cell,
                buf: String::new(),
            }),
            b"txbxContent" => self.sinks.push(Sink {
                kind: SinkKind::TextBox,
                buf: String::new(),
            }),
            _ => self.empty(local, e),
        }
    }

    /// Handles self-closing elements (and the leaf meaning of a Start).
    fn empty(&mut self, local: &[u8], e: &BytesStart) {
        // Structural elements whose mere presence matters: `<w:tc/>` is an
        // empty cell (dropping it shifts the remaining columns left),
        // `<w:p/>` an empty paragraph, `<w:tr/>` an empty row. Treat them as
        // an immediately closed Start; `start` never routes these back here.
        if matches!(local, b"p" | b"tc" | b"tr") {
            self.start(local, e);
            self.end(local);
            return;
        }
        if self.run_depth == 0 {
            // `w:tab` also appears in `w:pPr/w:tabs` as a tab-stop definition.
            return;
        }
        match local {
            b"tab" | b"ptab" => self.push_text("\t"),
            b"br" | b"cr" => self.push_text("\n"),
            b"noBreakHyphen" => self.push_text("-"),
            _ => {}
        }
    }

    fn end(&mut self, local: &[u8]) {
        match local {
            b"p" => self.end_paragraph(),
            b"r" => self.run_depth = self.run_depth.saturating_sub(1),
            b"t" => self.text_depth = self.text_depth.saturating_sub(1),
            b"del" | b"moveFrom" => self.deleted_depth = self.deleted_depth.saturating_sub(1),
            b"tc" => self.end_cell(),
            b"tr" => {
                if let Some(t) = self.tables.last_mut() {
                    if let Some(row) = t.cur_row.take() {
                        t.rows.push(row);
                    }
                }
            }
            b"tbl" => self.end_table(),
            b"txbxContent" => self.end_text_box(),
            _ => {}
        }
    }

    fn end_paragraph(&mut self) {
        let para = self.paragraphs.pop().unwrap_or_default();
        let buf = self.sink();
        buf.push('\n');
        for tb in para.pending_text_boxes {
            buf.push_str(&tb);
            buf.push('\n');
        }
    }

    fn end_cell(&mut self) {
        if self
            .sinks
            .last()
            .map(|s| s.kind != SinkKind::Cell)
            .unwrap_or(true)
        {
            return; // unbalanced markup; ignore
        }
        let cell = self.sinks.pop().expect("cell sink");
        let text = cell
            .buf
            .split('\n')
            .map(|l| l.trim())
            .filter(|l| !l.is_empty())
            .collect::<Vec<_>>()
            .join(" / ");
        match self.tables.last_mut() {
            Some(t) => t.cur_row.get_or_insert_with(Vec::new).push(text),
            None => {
                let buf = self.sink();
                buf.push_str(&text);
                buf.push('\n');
            }
        }
    }

    fn end_table(&mut self) {
        let Some(mut table) = self.tables.pop() else {
            return;
        };
        if let Some(row) = table.cur_row.take() {
            table.rows.push(row);
        }
        let rows: Vec<String> = table
            .rows
            .iter()
            .filter(|r| r.iter().any(|c| !c.is_empty()))
            .map(|r| r.join(" | "))
            .collect();
        if rows.is_empty() {
            return;
        }
        let in_cell = self
            .sinks
            .last()
            .map(|s| s.kind == SinkKind::Cell)
            .unwrap_or(false);
        let buf = self.sink();
        if !buf.is_empty() && !buf.ends_with('\n') {
            buf.push('\n');
        }
        if in_cell {
            buf.push('[');
            buf.push_str(&rows.join("; "));
            buf.push_str("]\n");
        } else {
            for row in rows {
                buf.push_str(&row);
                buf.push('\n');
            }
        }
    }

    fn end_text_box(&mut self) {
        if self
            .sinks
            .last()
            .map(|s| s.kind != SinkKind::TextBox)
            .unwrap_or(true)
        {
            return;
        }
        let tb = self.sinks.pop().expect("text box sink");
        let text = tb.buf.trim_matches('\n').to_owned();
        if text.trim().is_empty() {
            return;
        }
        match self.paragraphs.last_mut() {
            Some(anchor) => anchor.pending_text_boxes.push(text),
            None => {
                let buf = self.sink();
                buf.push_str(&text);
                buf.push('\n');
            }
        }
    }

    fn finish(mut self) -> String {
        // Unclosed containers (truncated XML): fold whatever was collected
        // back into the root instead of losing it.
        while self.sinks.len() > 1 {
            let s = self.sinks.pop().expect("non-root sink");
            let buf = self.sink();
            buf.push_str(&s.buf);
        }
        self.sinks.pop().map(|s| s.buf).unwrap_or_default()
    }
}

fn is_w(ns: &ResolveResult) -> bool {
    matches!(ns, ResolveResult::Bound(Namespace(n)) if W_NS.contains(n))
}

fn is_mc(ns: &ResolveResult) -> bool {
    matches!(ns, ResolveResult::Bound(Namespace(n)) if *n == MC_NS)
}

/// Walk one WordprocessingML part in document order, preserving whitespace.
fn walk_part(xml: &str) -> Result<String> {
    let mut reader = NsReader::from_str(xml);
    {
        let cfg = reader.config_mut();
        cfg.trim_text(false);
        cfg.check_end_names = false; // tolerate sloppy producers
        cfg.allow_unmatched_ends = true;
        cfg.expand_empty_elements = false;
    }
    let mut w = Walker::new();

    loop {
        let (ns, event) = reader
            .read_resolved_event()
            .map_err(|e| anyhow!("malformed XML: {}", e))?;
        if w.skip_depth > 0 {
            match event {
                Event::Start(_) => w.skip_depth += 1,
                Event::End(_) => w.skip_depth -= 1,
                Event::Eof => break,
                _ => {}
            }
            continue;
        }
        match event {
            Event::Start(e) => {
                let local = e.local_name();
                if is_mc(&ns) && local.as_ref() == b"Fallback" {
                    // mc:Choice already carries the same content (e.g. the
                    // DrawingML text box); the VML fallback would duplicate it.
                    w.skip_depth = 1;
                } else if is_w(&ns) {
                    w.start(local.as_ref(), &e);
                }
            }
            Event::Empty(e) => {
                if is_w(&ns) {
                    w.empty(e.local_name().as_ref(), &e);
                }
            }
            Event::End(e) => {
                if is_w(&ns) {
                    w.end(e.local_name().as_ref());
                }
            }
            Event::Text(t) => {
                if w.text_depth > 0 {
                    match t.unescape() {
                        Ok(s) => w.push_text(&s),
                        Err(_) => w.push_text(&String::from_utf8_lossy(&t)),
                    }
                }
            }
            Event::CData(t) => {
                if w.text_depth > 0 {
                    w.push_text(&String::from_utf8_lossy(&t));
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(w.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    const NS: &str = concat!(
        r#"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" "#,
        r#"xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" "#,
        r#"xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" "#,
        r#"xmlns:v="urn:schemas-microsoft-com:vml""#,
    );

    fn document(body: &str) -> String {
        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}<w:sectPr/></w:body></w:document>"#
        )
    }

    fn part(root: &str, inner: &str) -> String {
        format!(r#"<?xml version="1.0" encoding="UTF-8"?><w:{root} {NS}>{inner}</w:{root}>"#)
    }

    fn p(text: &str) -> String {
        format!(r#"<w:p><w:r><w:t xml:space="preserve">{text}</w:t></w:r></w:p>"#)
    }

    fn tc(inner: &str) -> String {
        format!("<w:tc><w:tcPr/>{inner}</w:tc>")
    }

    fn tbl(rows: &[&[String]]) -> String {
        let mut s = String::from("<w:tbl><w:tblPr/>");
        for r in rows {
            s.push_str("<w:tr>");
            for c in r.iter() {
                s.push_str(c);
            }
            s.push_str("</w:tr>");
        }
        s.push_str("</w:tbl>");
        s
    }

    fn zip_parts(parts: &[(&str, &str)]) -> Vec<u8> {
        let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
        let opts = zip::write::FileOptions::default();
        w.start_file("[Content_Types].xml", opts).unwrap();
        w.write_all(b"<Types/>").unwrap();
        for (name, xml) in parts {
            w.start_file(*name, opts).unwrap();
            w.write_all(xml.as_bytes()).unwrap();
        }
        w.finish().unwrap().into_inner()
    }

    fn docx(body: &str) -> Vec<u8> {
        zip_parts(&[(MAIN_PART, &document(body))])
    }

    fn extract(bytes: &[u8]) -> String {
        extract_docx_text(bytes).expect("extract")
    }

    /// Overwrite the central-directory "uncompressed size" of `name`.
    fn patch_declared_size(bytes: &mut [u8], name: &str, size: u32) {
        let sig = b"PK\x01\x02";
        let mut i = 0;
        while i + 46 <= bytes.len() {
            if &bytes[i..i + 4] == sig {
                let name_len = u16::from_le_bytes([bytes[i + 28], bytes[i + 29]]) as usize;
                if &bytes[i + 46..i + 46 + name_len] == name.as_bytes() {
                    bytes[i + 24..i + 28].copy_from_slice(&size.to_le_bytes());
                    return;
                }
            }
            i += 1;
        }
        panic!("central directory entry {} not found", name);
    }

    #[test]
    fn preserves_spaces_across_runs() {
        let body = concat!(
            r#"<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:t xml:space="preserve"> </w:t></w:r>"#,
            r#"<w:r><w:rPr><w:b/></w:rPr><w:t>world</w:t></w:r>"#,
            r#"<w:r><w:t xml:space="preserve"> and  more</w:t></w:r></w:p>"#,
        );
        assert_eq!(extract(&docx(body)), "Hello world and  more");
    }

    #[test]
    fn preserves_korean_text_and_spaces() {
        let body = concat!(
            r#"<w:p><w:r><w:t>안녕하세요</w:t></w:r><w:r><w:t xml:space="preserve"> </w:t></w:r>"#,
            r#"<w:r><w:t>세계</w:t></w:r></w:p>"#,
            r#"<w:p><w:r><w:t xml:space="preserve">모바일 RAG 엔진 테스트</w:t></w:r></w:p>"#,
        );
        assert_eq!(
            extract(&docx(body)),
            "안녕하세요 세계\n모바일 RAG 엔진 테스트"
        );
    }

    #[test]
    fn maps_tab_and_breaks() {
        // The w:tab inside w:pPr/w:tabs is a tab-stop definition, not text.
        let body = concat!(
            r#"<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>"#,
            r#"<w:r><w:t>Name</w:t><w:tab/><w:t>Value</w:t><w:br/><w:t>Next</w:t>"#,
            r#"<w:cr/><w:t>Last</w:t></w:r></w:p>"#,
        );
        assert_eq!(extract(&docx(body)), "Name\tValue\nNext\nLast");
    }

    #[test]
    fn keeps_table_in_place_with_multi_paragraph_cells() {
        let body = format!(
            "{}{}{}",
            p("Before the table."),
            tbl(&[
                &[tc(&p("A")), tc(&p("B"))],
                &[tc(&format!("{}{}", p("C1"), p("C2"))), tc(&p("D"))],
            ]),
            p("After the table."),
        );
        assert_eq!(
            extract(&docx(&body)),
            "Before the table.\nA | B\nC1 / C2 | D\nAfter the table."
        );
    }

    #[test]
    fn recurses_into_nested_tables() {
        let inner = tbl(&[&[tc(&p("n1")), tc(&p("n2"))], &[tc(&p("n3")), tc(&p("n4"))]]);
        let body = tbl(&[&[tc(&format!("{}{}", p("X"), inner)), tc(&p("Y"))]]);
        assert_eq!(extract(&docx(&body)), "X / [n1 | n2; n3 | n4] | Y");
    }

    #[test]
    fn reads_text_box_after_anchor_paragraph_once() {
        let tb = format!(
            "<w:txbxContent>{}{}</w:txbxContent>",
            p("Boxed one"),
            p("Boxed two")
        );
        let body = format!(
            concat!(
                r#"<w:p><w:r><w:t xml:space="preserve">Anchor text </w:t></w:r><w:r>"#,
                r#"<mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wps:wsp><wps:txbx>{tb}"#,
                r#"</wps:txbx></wps:wsp></w:drawing></mc:Choice><mc:Fallback><w:pict><v:shape>"#,
                r#"<v:textbox>{tb}</v:textbox></v:shape></w:pict></mc:Fallback></mc:AlternateContent>"#,
                r#"</w:r><w:r><w:t>continues.</w:t></w:r></w:p>{next}"#,
            ),
            tb = tb,
            next = p("Next paragraph."),
        );
        assert_eq!(
            extract(&docx(&body)),
            "Anchor text continues.\nBoxed one\nBoxed two\nNext paragraph."
        );
    }

    #[test]
    fn appends_headers_footers_and_notes_once_in_order() {
        let notes = |root: &str, el: &str, text: &str| {
            part(
                root,
                &format!(
                    concat!(
                        r#"<w:{el} w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:{el}>"#,
                        r#"<w:{el} w:id="1">{p}</w:{el}>"#,
                    ),
                    el = el,
                    p = p(text)
                ),
            )
        };
        let bytes = zip_parts(&[
            (MAIN_PART, &document(&p("Body text."))),
            (
                "word/endnotes.xml",
                &notes("endnotes", "endnote", "An endnote."),
            ),
            ("word/footer1.xml", &part("ftr", &p("Page footer"))),
            ("word/header2.xml", &part("hdr", &p("Company Header"))),
            ("word/header1.xml", &part("hdr", &p("Company Header"))),
            ("word/header10.xml", &part("hdr", &p("Tenth header"))),
            (
                "word/footnotes.xml",
                &notes("footnotes", "footnote", "A footnote."),
            ),
        ]);
        assert_eq!(
            extract(&bytes),
            "Body text.\n\nCompany Header\n\nTenth header\n\nPage footer\n\nA footnote.\n\nAn endnote."
        );
    }

    #[test]
    fn skips_deleted_revisions_keeps_insertions() {
        let body = concat!(
            r#"<w:p><w:r><w:t xml:space="preserve">Keep </w:t></w:r>"#,
            r#"<w:del w:id="1" w:author="a"><w:r><w:delText xml:space="preserve">gone </w:delText></w:r></w:del>"#,
            r#"<w:moveFrom w:id="2" w:author="a"><w:r><w:t xml:space="preserve">moved </w:t></w:r></w:moveFrom>"#,
            r#"<w:ins w:id="3" w:author="a"><w:r><w:t>added</w:t></w:r></w:ins></w:p>"#,
        );
        assert_eq!(extract(&docx(body)), "Keep added");
    }

    #[test]
    fn unescapes_entities() {
        let body = r#"<w:p><w:r><w:t>R&amp;D &lt;draft&gt;</w:t></w:r></w:p>"#;
        assert_eq!(extract(&docx(body)), "R&D <draft>");
    }

    #[test]
    fn rejects_honest_oversized_entry_without_inflating() {
        // ~4 MB of highly compressible text vs a 1 MB budget.
        let big = format!("<w:p><w:r><w:t>{}</w:t></w:r></w:p>", "a".repeat(4 << 20));
        let bytes = docx(&big);
        assert!(
            bytes.len() < 64 * 1024,
            "fixture should be tiny: {}",
            bytes.len()
        );
        let limits = DocxLimits {
            total_uncompressed_bytes: 1 << 20,
            max_compression_ratio: u64::MAX,
            min_uncompressed_bytes: 0,
            max_entries: 100,
        };
        let err = extract_docx_text_with_limits(&bytes, limits).unwrap_err();
        assert!(err.to_string().contains("size limit"), "got: {err}");
    }

    #[test]
    fn take_bounds_entry_with_lying_size_header() {
        // Central directory claims 100 bytes; the stream inflates to ~4 MB.
        // Only `take(budget + 1)` stands between us and the full inflate.
        let big = format!("<w:p><w:r><w:t>{}</w:t></w:r></w:p>", "a".repeat(4 << 20));
        let mut bytes = docx(&big);
        patch_declared_size(&mut bytes, MAIN_PART, 100);
        let limits = DocxLimits {
            total_uncompressed_bytes: 1 << 20,
            max_compression_ratio: u64::MAX,
            min_uncompressed_bytes: 0,
            max_entries: 100,
        };
        let err = extract_docx_text_with_limits(&bytes, limits).unwrap_err();
        assert!(err.to_string().contains("size limit"), "got: {err}");
    }

    #[test]
    fn default_limits_reject_declared_bomb_before_allocating() {
        // A ~4 GB declared size must be refused up front by the default
        // limits (no `Vec::with_capacity(4 GB)`, no inflate).
        let mut bytes = docx(&p("tiny"));
        patch_declared_size(&mut bytes, MAIN_PART, 0xFFFF_FF00);
        let err = extract_docx_text(&bytes).unwrap_err();
        assert!(err.to_string().contains("size limit"), "got: {err}");
    }

    #[test]
    fn default_limits_reject_small_highly_compressible_docx_by_ratio() {
        // ~24 MB of XML in a container of a few tens of KB: under the 200 MB
        // absolute cap, but far above 100x its own size and the 16 MB floor.
        let big = format!("<w:p><w:r><w:t>{}</w:t></w:r></w:p>", "a".repeat(24 << 20));
        let bytes = docx(&big);
        assert!(
            bytes.len() < 160 * 1024,
            "fixture should be small: {}",
            bytes.len()
        );
        let budget = DocxLimits::DEFAULT.budget_for(bytes.len());
        assert_eq!(budget, 16 * 1024 * 1024, "small input gets the floor");
        let err = extract_docx_text(&bytes).unwrap_err();
        assert!(err.to_string().contains("size limit"), "got: {err}");
    }

    #[test]
    fn ratio_budget_is_clamped_between_floor_and_absolute_cap() {
        let d = DocxLimits::DEFAULT;
        assert_eq!(d.budget_for(0), 16 * 1024 * 1024);
        assert_eq!(d.budget_for(1024 * 1024), 100 * 1024 * 1024);
        assert_eq!(d.budget_for(50 * 1024 * 1024), 200 * 1024 * 1024);
        assert_eq!(d.budget_for(usize::MAX), 200 * 1024 * 1024);
    }

    #[test]
    fn keeps_self_closing_cells_paragraphs_and_rows() {
        // An empty middle cell must keep its column, not shift C left.
        let body = format!(
            "{}{}{}<w:p/><w:p/>{}",
            p("Before."),
            format!(
                "<w:tbl><w:tr>{}<w:tc/>{}</w:tr><w:tr/><w:tr>{}{}{}</w:tr></w:tbl>",
                tc(&p("A")),
                tc(&p("C")),
                tc(&p("D")),
                tc(&p("E")),
                tc(&p("F")),
            ),
            p("Then."),
            p("After a gap."),
        );
        assert_eq!(
            extract(&docx(&body)),
            "Before.\nA |  | C\nD | E | F\nThen.\n\nAfter a gap."
        );
    }

    #[test]
    fn finalize_collapses_blank_runs_and_trims_trailing_spaces() {
        assert_eq!(finalize(String::new()), "");
        assert_eq!(finalize("\n\n  \n".to_string()), "");
        assert_eq!(
            finalize("\n a  \nb\n\n\n\t\nc d \n\n한글  \n".to_string()),
            " a\nb\n\nc d\n\n한글"
        );
    }

    #[test]
    fn budget_is_shared_across_parts() {
        let body = p(&"b".repeat(600 * 1024));
        let footer = part("ftr", &p(&"f".repeat(600 * 1024)));
        let bytes = zip_parts(&[(MAIN_PART, &document(&body)), ("word/footer1.xml", &footer)]);
        let limits = DocxLimits {
            total_uncompressed_bytes: 1 << 20,
            max_compression_ratio: u64::MAX,
            min_uncompressed_bytes: 0,
            max_entries: 100,
        };
        let err = extract_docx_text_with_limits(&bytes, limits).unwrap_err();
        assert!(err.to_string().contains("word/footer1.xml"), "got: {err}");
    }

    #[test]
    fn rejects_too_many_entries() {
        let parts: Vec<(String, String)> = (0..20)
            .map(|i| (format!("word/media/x{i}.bin"), String::new()))
            .collect();
        let doc = document(&p("x"));
        let mut all: Vec<(&str, &str)> = parts
            .iter()
            .map(|(a, b)| (a.as_str(), b.as_str()))
            .collect();
        all.push((MAIN_PART, &doc));
        let limits = DocxLimits {
            total_uncompressed_bytes: 1 << 20,
            max_compression_ratio: u64::MAX,
            min_uncompressed_bytes: 0,
            max_entries: 10,
        };
        let err = extract_docx_text_with_limits(&zip_parts(&all), limits).unwrap_err();
        assert!(
            err.to_string().contains("too many zip entries"),
            "got: {err}"
        );
    }

    #[test]
    fn corrupt_and_truncated_zips_error_without_panicking() {
        assert!(extract_docx_text(b"PK\x03\x04 definitely not a zip archive").is_err());
        let full = docx(&p("Hello world"));
        for cut in [full.len() / 4, full.len() / 2, full.len() - 10] {
            assert!(extract_docx_text(&full[..cut]).is_err(), "cut at {cut}");
        }
        // Flip bytes across the whole archive body: every outcome must be a
        // value (Ok or Err), never a panic.
        for offset in (0..full.len()).step_by(7) {
            let mut flipped = full.clone();
            flipped[offset] ^= 0xA5;
            let _ = extract_docx_text(&flipped);
        }
    }

    #[test]
    fn missing_main_part_is_an_error() {
        let bytes = zip_parts(&[("word/styles.xml", "<w:styles/>")]);
        let err = extract_docx_text(&bytes).unwrap_err();
        assert!(err.to_string().contains("word/document.xml"), "got: {err}");
    }

    #[test]
    fn malformed_auxiliary_part_does_not_lose_body() {
        let bytes = zip_parts(&[
            (MAIN_PART, &document(&p("Body survives."))),
            ("word/header1.xml", "<w:hdr <<< broken"),
        ]);
        assert_eq!(extract(&bytes), "Body survives.");
    }
}

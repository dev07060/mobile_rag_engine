/// Utility for extracting text from documents.
library;

import '../src/rust/api/document_parser.dart' as raw;

/// Utility class for parsing documents (PDF, DOCX, etc.).
///
/// Wraps the low-level Rust document parser functions.
class DocumentParser {
  DocumentParser._();

  /// User-facing message for PDFs that contain no extractable text.
  static const scannedPdfOcrRequiredMessage =
      '이 PDF는 텍스트를 추출할 수 없습니다.\n'
      '스캔본 또는 이미지 기반 PDF일 수 있어 OCR 처리가 필요합니다.';

  /// Returns true when a PDF extraction error indicates a scanned/image-only
  /// document — the kind OCR can recover.
  ///
  /// The Rust parser surfaces a below-threshold error for two distinct cases
  /// that share the same `"… fewer than N non-whitespace …"` prefix:
  ///   * scanned/image-only PDFs with no text layer — OCR helps;
  ///   * PDFs whose pages failed to extract (corrupt/unsupported content) —
  ///     OCR will *not* help.
  /// Only the first should drive the OCR-required message, so this keys on the
  /// scanned-specific marker rather than the shared prefix.
  static bool isOcrRequiredPdfExtractionError(Object error) {
    final message = error.toString();
    return message.contains('PDF text extraction returned fewer than') &&
        message.contains('scanned/image-only');
  }

  /// Convert known extraction failures into user-facing copy.
  static String userMessageForExtractionError(Object error) {
    if (isOcrRequiredPdfExtractionError(error)) {
      return scannedPdfOcrRequiredMessage;
    }
    return error.toString();
  }

  /// Extract text from PDF bytes.
  static Future<String> parsePdf(List<int> bytes) =>
      raw.extractTextFromPdf(fileBytes: bytes);

  /// Extract text from DOCX bytes.
  static Future<String> parseDocx(List<int> bytes) =>
      raw.extractTextFromDocx(fileBytes: bytes);

  /// Auto-detect document type and extract text.
  static Future<String> parse(List<int> bytes) =>
      raw.extractTextFromDocument(fileBytes: bytes);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() {
  group('DocumentParser extraction error helpers', () {
    test('classifies scanned/image-only PDF errors as OCR-required', () {
      const error =
          'Document extraction failed for "/tmp/scan.pdf": PDF text extraction '
          'returned fewer than 16 non-whitespace characters; PDF may be '
          'scanned/image-only';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isTrue);
      expect(
        DocumentParser.userMessageForExtractionError(error),
        DocumentParser.scannedPdfOcrRequiredMessage,
      );
      expect(
        DocumentParser.scannedPdfOcrRequiredMessage,
        '이 PDF는 텍스트를 추출할 수 없습니다.\n'
        '스캔본 또는 이미지 기반 PDF일 수 있어 OCR 처리가 필요합니다.',
      );
    });

    test('does NOT classify fully-failed (all pages) PDFs as OCR-required', () {
      // Every page failed to extract (corrupt/unsupported content), so no page
      // was readable and there is no scanned-layer evidence — OCR cannot fix
      // this. This is the only below-threshold case Rust emits WITHOUT the
      // scanned-specific marker, so the classifier must return false. A PDF
      // where some pages still parsed keeps the marker (see the mixed case).
      const error =
          'Document extraction failed for "/tmp/corrupt.pdf": PDF text '
          'extraction returned fewer than 16 non-whitespace characters; '
          '5 of 5 page(s) failed to extract (pages: [0, 1, 2, 3, 4])';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isFalse);
      expect(DocumentParser.userMessageForExtractionError(error), error);
    });

    test('classifies mixed scanned + corrupt PDF as OCR-required', () {
      // Regression guard for Finding #1: a scanned/image-only PDF that ALSO has
      // a corrupt page. Rust now appends the scanned/image-only marker after the
      // failed-page summary, so OCR guidance still fires for the recoverable
      // pages instead of dumping a raw error to the user.
      const error =
          'Document extraction failed for "/tmp/mixed.pdf": PDF text '
          'extraction returned fewer than 16 non-whitespace characters; '
          '1 of 5 page(s) failed to extract (pages: [3]); '
          'PDF may be scanned/image-only';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isTrue);
      expect(
        DocumentParser.userMessageForExtractionError(error),
        DocumentParser.scannedPdfOcrRequiredMessage,
      );
    });

    test('leaves unrelated extraction errors unchanged', () {
      const error = 'DOCX extraction failed: invalid zip archive';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isFalse);
      expect(DocumentParser.userMessageForExtractionError(error), error);
    });
  });
}

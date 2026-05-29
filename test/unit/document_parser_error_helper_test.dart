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

    test('does NOT classify page-extraction-failure PDFs as OCR-required', () {
      // Same below-threshold error family, but here individual pages failed to
      // extract (corrupt/unsupported content), which OCR cannot fix. This
      // message shares the "fewer than ... non-whitespace" prefix with the
      // scanned case, so the classifier must key on the scanned-specific
      // marker, not the shared prefix.
      const error =
          'Document extraction failed for "/tmp/broken.pdf": PDF text '
          'extraction returned fewer than 16 non-whitespace characters; '
          '3 of 5 page(s) failed to extract (pages: [1, 2, 3])';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isFalse);
      expect(DocumentParser.userMessageForExtractionError(error), error);
    });

    test('leaves unrelated extraction errors unchanged', () {
      const error = 'DOCX extraction failed: invalid zip archive';

      expect(DocumentParser.isOcrRequiredPdfExtractionError(error), isFalse);
      expect(DocumentParser.userMessageForExtractionError(error), error);
    });
  });
}

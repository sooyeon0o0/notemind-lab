import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notemind/core/document_import.dart';

void main() {
  test('PDF and text limits are distinct and case insensitive', () {
    validateDocumentFile('lecture.PDF', maxPdfBytes);
    expect(
      () => validateDocumentFile('lecture.pdf', maxPdfBytes + 1),
      throwsFormatException,
    );
    expect(
      () => validateDocumentFile('note.md', maxTextBytes + 1),
      throwsFormatException,
    );
    expect(() => validateDocumentFile('fake.docx', 10), throwsFormatException);
    expect(() => validateDocumentFile('empty.pdf', 0), throwsFormatException);
    expect(documentContentType('lecture.PDF'), 'application/pdf');
  });
  test('UTF-8 BOM and text import remain supported', () async {
    final chunks = await extractDocumentChunks(
      'note.md',
      Uint8List.fromList(utf8.encode('\uFEFF한글 수업 자료')),
      (_, _) {},
    );
    expect(chunks, ['한글 수업 자료']);
    await expectLater(
      extractDocumentChunks('note.txt', Uint8List.fromList([255]), (_, _) {}),
      throwsFormatException,
    );
  });
}

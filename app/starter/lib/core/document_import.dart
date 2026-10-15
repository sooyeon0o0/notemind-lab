// 구현할 때 필요한 import입니다. TODO를 채우면 경고가 사라집니다.
// ignore_for_file: unused_import
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'text_processing.dart';

const documentExtensions = ['txt', 'md', 'pdf'];
const maxPdfBytes = 20 * 1024 * 1024;
const maxTextBytes = 1024 * 1024;

String documentExtension(String name) => name.split('.').last.toLowerCase();

void validateDocumentFile(String name, int length) {
  final extension = documentExtension(name);
  if (!name.contains('.') || !documentExtensions.contains(extension)) {
    throw const FormatException('.txt, .md 또는 .pdf 파일을 선택하세요.');
  }
  final pdf = extension == 'pdf';
  if (length > (pdf ? maxPdfBytes : maxTextBytes)) {
    throw FormatException(
      pdf ? 'PDF는 20MB 이하로 선택하세요.' : '텍스트 파일은 1MB 이하로 선택하세요.',
    );
  }
  if (length == 0) throw const FormatException('빈 파일은 업로드할 수 없습니다.');
}

String documentContentType(String name) => switch (documentExtension(name)) {
  'pdf' => 'application/pdf',
  'md' => 'text/markdown',
  _ => 'text/plain',
};

/// PDF·텍스트 파일에서 글자를 추출해 검색용 청크 목록을 만듭니다.
/// 이미지로만 된 페이지는 OCR이 필요하므로 색인하지 않습니다.
Future<List<String>> extractDocumentChunks(
  String name,
  Uint8List bytes,
  void Function(double, String) progress,
) async {
  validateDocumentFile(name, bytes.length);
  if (documentExtension(name) != 'pdf') {
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    final chunks = chunkText(text);
    if (chunks.isEmpty) {
      throw const FormatException('파일에 읽을 수 있는 텍스트가 없습니다.');
    }
    if (chunks.length > 2000) {
      throw const FormatException('문서가 너무 깁니다. 여러 파일로 나눠주세요.');
    }
    return chunks;
  }

  progress(0.01, 'PDF 여는 중');
  await pdfrxFlutterInitialize();
  PdfDocument? document;
  try {
    document = await PdfDocument.openData(bytes);
    final pages = document.pages;
    if (pages.length > 500) {
      throw const FormatException('PDF는 500페이지 이하로 나눠주세요.');
    }
    final chunks = <String>[];
    for (final page in pages) {
      final text = (await page.loadStructuredText()).fullText;
      chunks.addAll(
        chunkText(text).map((part) => '[PDF ${page.pageNumber}페이지]\n$part'),
      );
      if (chunks.length > 2000) {
        throw const FormatException('문서가 너무 깁니다. 여러 파일로 나눠주세요.');
      }
      progress(
        0.01 + 0.07 * page.pageNumber / pages.length,
        'PDF 텍스트 추출 ${page.pageNumber} / ${pages.length}페이지',
      );
    } // for 끝
    if (chunks.isEmpty) {
      throw const FormatException(
        'PDF에 추출할 텍스트가 없습니다. '
        '스캔·이미지 PDF는 OCR로 텍스트를 추가한 뒤 업로드하세요.',
      );
    }
    return chunks;
  } on PdfPasswordException {
    throw const FormatException('암호로 잠긴 PDF입니다. 암호를 해제한 파일을 업로드하세요.');
  } on PdfException {
    throw const FormatException(
      'PDF를 읽을 수 없습니다. '
      '손상 여부를 확인하거나 PDF로 다시 저장해 주세요.',
    );
  } finally {
    await document?.dispose(); // 성공·실패와 관계없이 닫습니다.
  }
}

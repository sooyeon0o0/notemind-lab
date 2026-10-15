// 구현할 때 필요한 import입니다. TODO를 채우면 경고가 사라집니다.
// ignore_for_file: unused_import
import 'dart:convert';

/// 문서 전체를 요약해 달라는 요청인지 판별합니다.
/// 요약 요청이면 검색 없이 문서 앞부분을 근거로 사용합니다.
bool isDocumentOverviewRequest(String question) {
  final text = question.trim().replaceAll(RegExp(r'[.!?。]+$'), '');
  if (text == '이 자료의 핵심 내용을 설명해줘' || text == '중요한 개념을 예시와 함께 알려줘') {
    return true;
  }
  return RegExp(
    r'^(?:(?:이\s*)?(?:자료|문서|노트|PDF)(?:의|를|을)?\s*)?'
    r'(?:(?:전체|핵심)\s*(?:내용을?\s*)?)?'
    r'(?:요약|정리)(?:해\s*줘|해\s*주세요|해줄래|해|해주세요)?$',
    caseSensitive: false,
  ).hasMatch(text);
}

/// 텍스트를 글자(유니코드) 단위 청크로 나눕니다.
/// 임베딩 서버가 처리하기 좋은 크기(기본 320자, 겹침 48자)입니다.
List<String> chunkText(String text, {int size = 320, int overlap = 48}) {
  if (size < 1 || overlap < 0 || overlap >= size) {
    throw ArgumentError('Invalid chunk size/overlap');
  }
  final runes = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\u0000', '')
      .trim()
      .runes
      .toList();
  final chunks = <String>[];
  for (var start = 0; start < runes.length; start += size - overlap) {
    final end = (start + size).clamp(0, runes.length);
    final chunk = String.fromCharCodes(runes.sublist(start, end)).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    if (end == runes.length) break;
  }
  return chunks;
}

/// 스트리밍 응답(SSE)의 바이트 흐름에서 data 필드만 꺼냅니다.
Stream<String> sseData(Stream<List<int>> bytes) async* {
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield data.join('\n');
        data.clear();
      }
    } else if (line.startsWith('data:')) {
      var value = line.substring(5);
      if (value.startsWith(' ')) value = value.substring(1);
      data.add(value);
    }
  }
  if (data.isNotEmpty) yield data.join('\n');
}

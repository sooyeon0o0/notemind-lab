import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notemind/core/config.dart';
import 'package:notemind/core/text_processing.dart';
import 'package:notemind/data/inference.dart';
import 'package:notemind/data/models.dart';

void main() {
  test('answer provenance survives history and fallback requires completed no-evidence', () {
    const message = ChatMessage(
      id: 'id',
      role: 'assistant',
      content: '자료에 없습니다.',
      answerKind: 'no_evidence',
    );
    expect(
      ChatMessage.fromJson(message.toJson('conversation')).canAnswerGenerally,
      isTrue,
    );
    for (final status in ['generating', 'stopped', 'error']) {
      expect(message.copy(status: status).canAnswerGenerally, isFalse);
    }
    final general = message.copy(answerKind: 'general', content: '일반 답변');
    expect(
      ChatMessage.fromJson(general.toJson('conversation')).answerKind,
      'general',
    );
    expect(general.canAnswerGenerally, isFalse);
    expect(message.copy(answerKind: 'document').canAnswerGenerally, isFalse);
  });

  test('overview requests do not bypass search for topical questions', () {
    for (final question in [
      '이 자료의 핵심 내용을 설명해줘',
      '중요한 개념을 예시와 함께 알려줘',
      '이 문서를 요약해줘',
      '핵심 내용을 정리해 주세요.',
      '요약해줘',
    ]) {
      expect(isDocumentOverviewRequest(question), isTrue, reason: question);
    }
    for (final question in [
      '화성의 기온을 요약해줘',
      '발표 장소가 어디야?',
      '요약하지 말고 지구의 크기를 알려줘',
    ]) {
      expect(isDocumentOverviewRequest(question), isFalse, reason: question);
    }
    const source = SourceChunk('1', 'doc', 'note.pdf', 0, '자료', null);
    expect(SourceChunk.fromJson(source.toJson()).similarity, isNull);
  });
  test(
    'chunks preserve Korean and emoji and overlap without a trailing duplicate',
    () {
      final text = List.filled(100, '안녕👩‍💻 ').join();
      final chunks = chunkText(text, size: 40, overlap: 8);
      expect(chunks.first.runes.length, lessThanOrEqualTo(40));
      expect(chunks.any((s) => s.contains('\uFFFD')), isFalse);
      expect(chunkText('hello', size: 5, overlap: 2), ['hello']);
      expect(chunkText('   '), isEmpty);
      expect(
        () => chunkText('hello', size: 5, overlap: 5),
        throwsArgumentError,
      );
      final source = '가나다라마바사아자차카타파하';
      expect(chunkText(source, size: 5, overlap: 2), [
        '가나다라마',
        '라마바사아',
        '사아자차카',
        '차카타파하',
      ]);
    },
  );
  test('SSE handles split UTF8, comments, multiline and CRLF', () async {
    final raw = utf8.encode(
      ': ping\r\ndata: 안녕\r\ndata: 세계\r\n\r\ndata: [DONE]\n\n',
    );
    final events = await sseData(Stream.fromIterable(raw.map((b) => [b])))
        .toList();
    expect(events, ['안녕\n세계', '[DONE]']);
  });
  test('embedding order is restored and wrong dimensions fail', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'index': 1, 'embedding': List.filled(1024, 2.0)},
            {'index': 0, 'embedding': List.filled(1024, 1.0)},
          ],
        }),
        200,
      ),
    );
    final session = InferenceSession(const AppConfig(), client: client);
    final vectors = await session.embed(['a', 'b']);
    expect(vectors.first.first, 1);
    expect(vectors.last.first, 2);
    session.close();
    final bad = InferenceSession(
      const AppConfig(),
      client: MockClient(
        (_) async =>
            http.Response('{"data":[{"index":0,"embedding":[1]}]}', 200),
      ),
    );
    await expectLater(bad.embed(['a']), throwsFormatException);
    bad.close();
  });
  test('SSE refuses silently truncated answers', () async {
    final client = MockClient.streaming(
      (request, body) async => http.StreamedResponse(
        Stream.value(
          utf8.encode('data: {"choices":[{"delta":{"content":"답"}}]}\n\n'),
        ),
        200,
      ),
    );
    final session = InferenceSession(const AppConfig(), client: client);
    await expectLater(
      session.chat([]),
      emitsInOrder(['답', emitsError(isA<Exception>())]),
    );
    session.close();
  });
  test('cancel closes the transport and prevents future requests', () async {
    final client = TrackingClient();
    final session = InferenceSession(const AppConfig(), client: client);
    session.cancel();
    expect(client.closed, isTrue);
    await expectLater(
      session.embed(['test']),
      throwsA(isA<RequestCancelled>()),
    );
  });
  test(
    'a socket that ends quietly after cancel is still a stopped response',
    () async {
      final stream = StreamController<List<int>>();
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(stream.stream, 200),
      );
      final session = InferenceSession(const AppConfig(), client: client);
      final result = expectLater(
        session.chat([]),
        emitsError(isA<RequestCancelled>()),
      );
      await Future<void>.delayed(Duration.zero);
      session.cancel();
      await stream.close();
      await result;
    },
  );
}

class TrackingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
  @override
  void close() {
    closed = true;
  }
}

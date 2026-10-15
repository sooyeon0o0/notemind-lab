import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notemind/main.dart' as app;
import 'package:notemind/core/config.dart';
import 'package:notemind/data/repository.dart';
import 'package:notemind/features/controllers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real local stack: direct main, ingestion, citations, no-answer, stop and restore',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      expect(find.text('로그인'), findsNothing);
      await binding.takeScreenshot('01-main-direct');
      Future<void> waitFor(
        bool Function() condition, {
        int seconds = 90,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for app state');
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pump(const Duration(milliseconds: 300));
      }

      await waitFor(() => find.text('나만의 지식 서랍').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.NoteMindApp)),
      );
      final repo = container.read(repositoryProvider);
      final config = container.read(configProvider);
      const text =
          '이 문서는 테스트용 가상 수업 자료입니다. 파란별 프로젝트의 발표 장소는 미래관 402호입니다. 발표는 2026년 11월 20일 오후 2시에 시작합니다. 준비물은 Android APK와 README입니다.';
      final upload = container.read(uploadProvider.notifier);
      final uploadFuture = upload.upload(
        '발표_준비_노트.md',
        Uint8List.fromList(utf8.encode(text)),
      );
      await waitFor(() => !container.read(uploadProvider).busy);
      await uploadFuture;
      expect(container.read(uploadProvider).error, isNull);
      final docs = await container.read(documentsProvider.future);
      final doc = docs.firstWhere((d) => d.title == '발표_준비_노트.md');
      expect(doc.status, 'ready');
      expect(doc.chunkCount, greaterThan(0));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('02-documents');
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();
      final chat = container.read(chatProvider.notifier);
      chat.newChat(documentId: doc.id);
      await tester.pump();
      var streamingChanges = 0;
      final sub = container.listen(chatProvider, (before, after) {
        if (after.busy &&
            after.messages.isNotEmpty &&
            after.messages.last.content.isNotEmpty) {
          streamingChanges++;
        }
      });
      await tester.enterText(
        find.byKey(const Key('question')),
        '파란별 프로젝트의 발표 장소는 어디야?',
      );
      await tester.tap(find.byKey(const Key('send-stop')));
      await waitFor(() => !container.read(chatProvider).busy);
      final answered = container.read(chatProvider);
      expect(answered.error, isNull);
      expect(answered.messages.last.content, contains('402'));
      expect(answered.messages.last.content, contains('[1]'));
      expect(answered.messages.last.sources, isNotEmpty);
      expect(streamingChanges, greaterThan(2));
      final conversation = answered.conversationId!;
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03-rag-answer');
      final source = find.byType(ActionChip).first;
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(find.textContaining('청크 1'), findsOneWidget);
      await binding.takeScreenshot('04-source');
      Navigator.of(tester.element(find.textContaining('청크 1'))).pop();
      await tester.pumpAndSettle();
      chat.newChat(documentId: doc.id);
      final unknown = chat.send('해왕성의 대기 조성 비율과 달의 반지름은 얼마야?');
      await waitFor(() => !container.read(chatProvider).busy);
      await unknown;
      expect(container.read(chatProvider).error, isNull);
      expect(
        container.read(chatProvider).messages.last.content,
        contains('자료에 없'),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('05-no-evidence');
      expect(find.text('문서 기반'), findsNothing);
      expect(find.text('자유 대화'), findsNothing);
      expect(
        container.read(chatProvider).messages.last.answerKind,
        'no_evidence',
      );
      expect(find.byKey(const Key('general-answer')), findsOneWidget);
      final fallbackIds = container
          .read(chatProvider)
          .messages
          .map((m) => m.id)
          .toList();
      final fallbackConversation = container.read(chatProvider).conversationId!;
      await tester.ensureVisible(find.byKey(const Key('general-answer')));
      await tester.tap(find.byKey(const Key('general-answer')));
      await waitFor(() => !container.read(chatProvider).busy);
      expect(container.read(chatProvider).error, isNull);
      expect(container.read(chatProvider).messages.last.answerKind, 'general');
      expect(container.read(chatProvider).messages.last.sources, isEmpty);
      expect(
        container.read(chatProvider).messages.map((m) => m.id).toList(),
        fallbackIds,
      );
      expect(find.textContaining('업로드한 자료에 근거하지 않은 답변'), findsOneWidget);
      expect(find.byKey(const Key('general-answer')), findsNothing);
      await binding.takeScreenshot('21-general-answer');
      await chat.open({
        'id': fallbackConversation,
        'mode': 'rag',
        'document_id': doc.id,
      });
      await tester.pumpAndSettle();
      expect(container.read(chatProvider).messages.last.answerKind, 'general');
      expect(find.textContaining('업로드한 자료에 근거하지 않은 답변'), findsOneWidget);
      final again = chat.regenerate();
      await waitFor(() => !container.read(chatProvider).busy);
      await again;
      expect(container.read(chatProvider).messages.last.answerKind, 'general');
      expect((await repo.messages(fallbackConversation)).length, 2);
      final followup = chat.send('파란별 프로젝트의 발표 장소는 어디야?');
      await waitFor(() => !container.read(chatProvider).busy);
      await followup;
      expect(container.read(chatProvider).messages.last.answerKind, 'document');
      expect(
        container.read(chatProvider).messages.last.content,
        contains('402'),
      );
      expect(container.read(chatProvider).messages.last.sources, isNotEmpty);
      chat.newChat(documentId: doc.id);
      final missing = chat.send('컴퓨터 네트워크의 역사에 대해 아주 길게 30개 문단으로 자세히 설명해줘.');
      await waitFor(() => !container.read(chatProvider).busy);
      await missing;
      expect(
        container.read(chatProvider).messages.last.canAnswerGenerally,
        isTrue,
      );
      final generating = chat.answerFromGeneralKnowledge();
      await waitFor(
        () => container.read(chatProvider).messages.last.content.isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('send-stop')));
      await waitFor(() => !container.read(chatProvider).busy);
      await generating;
      expect(container.read(chatProvider).messages.last.status, 'stopped');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('06-stopped');
      final saved = await repo.messages(conversation);
      expect(saved.last.content, contains('402'));
      await chat.open({
        'id': conversation,
        'mode': 'rag',
        'document_id': doc.id,
      });
      await tester.pumpAndSettle();
      expect(container.read(chatProvider).messages.last.sources, isNotEmpty);
      await binding.takeScreenshot('07-restored');
      final originalIds = container
          .read(chatProvider)
          .messages
          .map((m) => m.id)
          .toList();
      final regenerate = chat.regenerate();
      await waitFor(() => !container.read(chatProvider).busy);
      await regenerate;
      expect(container.read(chatProvider).error, isNull);
      expect(
        container.read(chatProvider).messages.map((m) => m.id).toList(),
        originalIds,
      );
      expect((await repo.messages(conversation)).length, originalIds.length);
      sub.close();
      expect(tester.takeException(), isNull);
      // Failed embedding must produce a retryable document, never searchable partial chunks.
      final broken = AppConfig(
        chatUrl: config.chatUrl,
        embeddingUrl: 'http://127.0.0.1:1/v1',
        model: config.model,
        embeddingModel: config.embeddingModel,
        apiKey: config.apiKey,
      );
      await expectLater(
        repo.ingest(
          'retry-check.txt',
          Uint8List.fromList(utf8.encode(text)),
          broken,
          (_, _) {},
        ),
        throwsA(anything),
      );
      final failed = (await repo.documents()).firstWhere(
        (d) => d.title == 'retry-check.txt',
      );
      expect(failed.status, 'failed');
      await repo.retryDocument(failed, config, (_, _) {});
      expect(
        (await repo.documents()).firstWhere((d) => d.id == failed.id).status,
        'ready',
      );
      await repo.removeDocument(failed);
      // The app stays logged in for manual inspection after the run.
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

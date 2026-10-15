import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:notemind/main.dart' as app;
import 'package:notemind/core/config.dart';
import 'package:notemind/core/document_import.dart';
import 'package:notemind/data/repository.dart';
import 'package:notemind/features/controllers.dart';

import '../test/fixtures/pdf_bytes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('PDF native extraction, validation, Storage, retry and RAG', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    final client = Supabase.instance.client;
    final previousSession = client.auth.currentSession;
    final freshClient = SupabaseClient(
      AppConfig.defaultSupabaseUrl,
      AppConfig.defaultAnonKey,
    );
    try {
      final guestRepo = NoteRepository(freshClient);
      await Future.wait([guestRepo.documents(), guestRepo.conversations()]);
      expect(freshClient.auth.currentUser!.isAnonymous, isTrue);
      final guestId = freshClient.auth.currentUser!.id;
      await guestRepo.documents();
      expect(freshClient.auth.currentUser!.id, guestId);
      await client.auth.setSession(
        freshClient.auth.currentSession!.refreshToken!,
      );
      expect(find.text('로그인'), findsNothing);
      final chunks = await extractDocumentChunks(
        'study.PDF',
        studyPdf,
        (_, _) {},
      );
      expect(chunks.length, 2);
      expect(chunks.first, contains('[PDF 1페이지]'));
      expect(chunks.first, contains('미래관 402호'));
      expect(chunks.last, contains('[PDF 2페이지]'));
      Future<void> rejects(Uint8List bytes, String message) async {
        await expectLater(
          extractDocumentChunks('invalid.pdf', bytes, (_, _) {}),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      }

      await rejects(scanPdf, 'OCR');
      await rejects(lockedPdf, '암호');
      await rejects(longPdf, '500페이지');
      await rejects(Uint8List.fromList([1, 2, 3]), 'PDF를 읽을 수');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.NoteMindApp)),
      );
      final repo = container.read(repositoryProvider);
      final config = container.read(configProvider);
      final title = 'PDF_발표안내_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await repo.ingest(title, studyPdf, config, (_, _) {});
      final doc = (await repo.documents()).firstWhere((d) => d.title == title);
      expect(doc.status, 'ready');
      expect(doc.chunkCount, 2);
      expect(doc.path, endsWith('.pdf'));
      expect(
        await client.storage.from('documents').download(doc.path),
        studyPdf,
      );
      await repo.retryDocument(doc, config, (_, _) {});
      expect(
        (await repo.documents()).firstWhere((d) => d.id == doc.id).chunkCount,
        2,
      );
      container.invalidate(documentsProvider);
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('11-pdf-documents');
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();
      final chat = container.read(chatProvider.notifier);
      chat.newChat(documentId: doc.id);
      final sending = chat.send('파란별 프로젝트의 발표 장소는 어디야?');
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (container.read(chatProvider).busy) {
        if (DateTime.now().isAfter(deadline)) fail('PDF RAG timed out');
        await tester.pump(const Duration(milliseconds: 150));
      }
      await sending;
      final result = container.read(chatProvider);
      expect(result.error, isNull);
      expect(result.messages.last.content, contains('402'));
      expect(
        result.messages.last.sources.any(
          (s) => s.content.contains('[PDF 1페이지]'),
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('12-pdf-answer');
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('13-pdf-source');
      Navigator.of(tester.element(find.byType(SelectableText).first)).pop();
      await tester.pumpAndSettle();
      // The suggested overview has no topic keywords. It must still read the
      // only ready document and preserve both PDF pages as evidence.
      chat.newChat();
      final summary = chat.send('이 자료의 핵심 내용을 설명해줘');
      final summaryDeadline = DateTime.now().add(const Duration(seconds: 120));
      while (container.read(chatProvider).busy) {
        if (DateTime.now().isAfter(summaryDeadline)) {
          fail('PDF overview timed out');
        }
        await tester.pump(const Duration(milliseconds: 150));
      }
      await summary;
      final overview = container.read(chatProvider);
      expect(overview.error, isNull);
      expect(overview.messages.last.content, contains('402'));
      expect(overview.messages.last.content, contains('README'));
      expect(overview.messages.last.content, isNot(contains('자료에 없습니다')));
      expect(overview.messages.last.sources.length, 2);
      expect(
        overview.messages.last.sources.every((s) => s.similarity == null),
        isTrue,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('19-pdf-overview');
      expect(tester.takeException(), isNull);
    } finally {
      await freshClient.dispose();
      if (previousSession?.refreshToken != null) {
        await client.auth.setSession(previousSession!.refreshToken!);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}

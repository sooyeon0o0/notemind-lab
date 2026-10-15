import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notemind/main.dart';
import 'package:notemind/data/models.dart';
import 'package:notemind/data/repository.dart';

void main() {
  testWidgets('main appears immediately while storage is still connecting', (
    tester,
  ) async {
    final pending = Completer<List<NoteDocument>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_UnusedRepository()),
          documentsProvider.overrideWith((ref) => pending.future),
        ],
        child: const NoteMindApp(),
      ),
    );
    await tester.pump();
    expect(find.text('나만의 지식 서랍'), findsOneWidget);
    expect(find.text('노트 업로드'), findsOneWidget);
    expect(find.text('로그인'), findsNothing);
    expect(find.text('로그아웃'), findsNothing);
    expect(find.byKey(const Key('email')), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('문서 기반'), findsNothing);
    expect(find.text('자유 대화'), findsNothing);
    expect(find.text('노트와 대화해 보세요'), findsOneWidget);
    expect(find.text('일반 지식으로 답변받기'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _UnusedRepository implements NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

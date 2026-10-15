import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notemind/data/models.dart';
import 'package:notemind/data/repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NoteDocument document(String id, {String status = 'ready'}) =>
    NoteDocument(id, '$id.pdf', '$id/note.pdf', status, 9, 'model', null);

class OverviewRepository extends NoteRepository {
  OverviewRepository(super.client, this.docs);
  final List<NoteDocument> docs;
  @override
  Future<List<NoteDocument>> documents() async => docs;
}

void main() {
  test(
    'overview scopes to the selected document and marks partial input',
    () async {
      final client = SupabaseClient(
        'http://localhost:54321',
        'anon',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/chunks');
          expect(request.url.queryParameters['document_id'], 'eq.selected');
          expect(request.url.queryParameters['order'], 'position.asc.nullslast');
          expect(request.url.queryParameters['limit'], '9');
          return http.Response(
            jsonEncode(
              List.generate(
                9,
                (i) => {
                  'id': i,
                  'document_id': 'selected',
                  'position': i,
                  'content': 'section $i',
                },
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = OverviewRepository(client, [
        document('other'),
        document('selected'),
      ]);
      final result = await repo.overview(documentId: 'selected');
      expect(result.partial, isTrue);
      expect(result.sources.length, 8);
      expect(result.sources.every((s) => s.documentId == 'selected'), isTrue);
      expect(result.sources.last.position, 7);
    },
  );

  test(
    'overview does not silently choose another or unfinished document',
    () async {
      final client = SupabaseClient(
        'http://localhost:54321',
        'anon',
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected chunk fetch'),
        ),
      );
      addTearDown(client.dispose);
      final repo = OverviewRepository(client, [
        document('one'),
        document('two'),
        document('pending', status: 'processing'),
      ]);
      await expectLater(repo.overview(), throwsFormatException);
      expect((await repo.overview(documentId: 'missing')).sources, isEmpty);
      expect((await repo.overview(documentId: 'pending')).sources, isEmpty);
      expect(
        (await OverviewRepository(client, []).overview()).sources,
        isEmpty,
      );
    },
  );
}

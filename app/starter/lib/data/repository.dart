// 구현할 때 필요한 import입니다. TODO를 채우면 경고가 사라집니다.
// ignore_for_file: unused_import
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/document_import.dart';
import 'inference.dart';
import 'models.dart';
import 'study_session.dart';

final repositoryProvider = Provider<NoteRepository>((ref) {
  // 연결 설정에서 Supabase 주소·키를 바꾸면 새 클라이언트로 다시 만듭니다.
  ref.watch(configProvider.select((c) => (c.supabaseUrl, c.anonKey)));
  return NoteRepository(Supabase.instance.client);
});
final documentsProvider = FutureProvider<List<NoteDocument>>(
  (ref) => ref.watch(repositoryProvider).documents(),
);
final conversationsProvider = FutureProvider<List<Json>>(
  (ref) => ref.watch(repositoryProvider).conversations(),
);

class NoteRepository {
  NoteRepository(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;
  Future<List<NoteDocument>> documents() async {
    await ensureStudySession(client);
    return (await client
            .from('documents')
            .select()
            .order('created_at', ascending: false))
        .map(NoteDocument.fromJson)
        .toList();
  }

  Future<List<Json>> conversations() async {
    await ensureStudySession(client);
    return await client
        .from('conversations')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<List<ChatMessage>> messages(String id) async {
    await ensureStudySession(client);
    return (await client
            .from('messages')
            .select()
            .eq('conversation_id', id)
            .order('created_at', ascending: true))
        .map(ChatMessage.fromJson)
        .toList();
  }

  Future<void> saveMessage(ChatMessage message, String conversation) async {
    await ensureStudySession(client);
    await client.from('messages').upsert(message.toJson(conversation));
  }

  Future<String> createConversation(
    String title,
    bool rag, {
    String? documentId,
  }) async {
    await ensureStudySession(client);
    final id = const Uuid().v4();
    await client.from('conversations').insert({
      'id': id,
      'title': String.fromCharCodes(title.runes.take(50)),
      'mode': rag ? 'rag' : 'chat',
      'document_id': documentId,
    });
    return id;
  }

  Future<void> removeDocument(NoteDocument document) async {
    await ensureStudySession(client);
    await client.storage.from('documents').remove([document.path]);
    await client.from('documents').delete().eq('id', document.id);
  }

  Future<void> ingest(
    String name,
    Uint8List bytes,
    AppConfig config,
    void Function(double, String) progress, {
    NoteDocument? retry,
  }) async {
    final chunks = await extractDocumentChunks(name, bytes, progress);
    await ensureStudySession(client);
    final id = retry?.id ?? const Uuid().v4();
    final path = retry?.path ?? '$userId/$id/note.${documentExtension(name)}';
    final model = config.embeddingModel;
    var inserted = false;
    final session = InferenceSession(config);
    try {
      progress(0.09, '문서 준비 중');
      if (retry == null) {
        await client.from('documents').insert({
          'id': id,
          'title': String.fromCharCodes(name.runes.take(240)),
          'storage_path': path,
          'embedding_model': model,
        });
      } else {
        await client
            .from('documents')
            .update({
              'status': 'processing',
              'error': null,
              'embedding_model': model,
            })
            .eq('id', id);
      }
      inserted = true;
      await client.storage
          .from('documents')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: documentContentType(name),
              upsert: true,
            ),
          );

      final rows = <Json>[];
      for (var index = 0; index < chunks.length; index += 4) {
        final batch = chunks.sublist(
          index,
          (index + 4).clamp(0, chunks.length),
        );
        final vectors = await session.embed(batch);
        for (var i = 0; i < batch.length; i++) {
          rows.add({'content': batch[i], 'embedding': vectors[i]});
        }
        progress(
          0.1 + 0.8 * rows.length / chunks.length,
          '임베딩 ${rows.length} / ${chunks.length}',
        );
      }
      progress(0.95, '검색 가능한 문서로 저장 중');
      await client.rpc(
        'finish_document',
        params: {'p_document_id': id, 'p_chunks': rows},
      );
      progress(1, '문서 준비 완료');
    } catch (error) {
      if (inserted) {
        try {
          await client
              .from('documents')
              .update({'status': 'failed', 'error': friendlyError(error)})
              .eq('id', id);
        } catch (_) {
          // 원래 오류를 보존합니다. / 오류 상태 저장에 실패해도 원래 예외를 유지합니다.
        }
      }
      rethrow;
    } finally {
      session.close();
    }
  }

  Future<void> retryDocument(
    NoteDocument document,
    AppConfig config,
    void Function(double, String) progress,
  ) async {
    await ensureStudySession(client);
    final bytes = await client.storage
        .from('documents')
        .download(document.path);
    await ingest(document.title, bytes, config, progress, retry: document);
  }

  Future<({List<SourceChunk> sources, bool partial})> overview({
    String? documentId,
  }) async {
    final ready = (await documents())
        .where(
          (d) =>
              d.status == 'ready' && (documentId == null || d.id == documentId),
        )
        .toList();
    if (ready.isEmpty) return (sources: <SourceChunk>[], partial: false);
    if (ready.length > 1) {
      throw const FormatException(
        '요약할 문서를 골라주세요.'
        '문서함에서 해당 문서의 "이 노트에 질문하기"를 누르면 됩니다.',
      );
    }
    final doc = ready.single;
    const limit = 8;
    final rows = await client
        .from('chunks')
        .select('id, document_id, position, content')
        .eq('document_id', doc.id)
        .order('position', ascending: true)
        .limit(limit + 1);
    return (
      sources: rows
          .take(limit)
          .map(
            (row) => SourceChunk.fromJson({
              ...row,
              'title': doc.title,
              'similarity': null,
            }),
          )
          .toList(),
      partial: rows.length > limit,
    );
  }

  Future<List<SourceChunk>> search(
    List<double> vector,
    String model, {
    String? documentId,
  }) async {
    await ensureStudySession(client);
    final result = await client.rpc(
      'match_chunks',
      params: {
        'query_embedding': vector,
        'p_model': model,
        'match_threshold': 0.45,
        'match_count': 5,
        'p_document_id': documentId,
      },
    );
    return (result as List)
        .map((row) => SourceChunk.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}

String friendlyError(Object error) {
  if (error is AuthException) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message;
  }
  if (error is PostgrestException) {
    if (error.code == 'PGRST205') {
      return 'DB에서 요청한 테이블을 찾지 못했습니다. 앱의 테이블명과 DB 마이그레이션을 확인하세요. (PGRST205)';
    }
    return '데이터 저장·조회에 실패했습니다. 서버 연결과 DB 마이그레이션을 확인하세요. (${error.code ?? 'DB'})';
  }
  if (error is StorageException) {
    return '문서 파일 처리에 실패했습니다. 연결을 확인하고 다시 시도하세요.';
  }
  final text = error.toString().replaceFirst('Exception: ', '');
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('TimeoutException')) {
    return '서버에 연결할 수 없습니다. 연결 설정과 로컬 서버 상태를 확인하세요.';
  }
  return text;
}

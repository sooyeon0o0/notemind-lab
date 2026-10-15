typedef Json = Map<String, dynamic>;

class NoteDocument {
  const NoteDocument(
    this.id,
    this.title,
    this.path,
    this.status,
    this.chunkCount,
    this.model,
    this.error,
  );
  factory NoteDocument.fromJson(Json row) => NoteDocument(
    row['id'],
    row['title'],
    row['storage_path'],
    row['status'],
    row['chunk_count'],
    row['embedding_model'],
    row['error'],
  );
  final String id, title, path, status, model;
  final int chunkCount;
  final String? error;
}

class SourceChunk {
  const SourceChunk(
    this.id,
    this.documentId,
    this.title,
    this.position,
    this.content,
    this.similarity,
  );
  factory SourceChunk.fromJson(Json row) => SourceChunk(
    row['id'].toString(),
    row['document_id'],
    row['title'],
    row['position'],
    row['content'],
    (row['similarity'] as num?)?.toDouble(),
  );
  final String id, documentId, title, content;
  final int position;
  final double? similarity;
  Json toJson() => {
    'id': id,
    'document_id': documentId,
    'title': title,
    'position': position,
    'content': content,
    'similarity': similarity,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status = 'complete',
    this.sources = const [],
    this.answerKind = 'document',
  });
  factory ChatMessage.fromJson(Json row) => ChatMessage(
    id: row['id'],
    role: row['role'],
    content: row['content'],
    status: row['status'] == 'generating' ? 'stopped' : row['status'],
    answerKind: row['answer_kind'] ?? 'document',
    sources: (row['sources'] as List)
        .map((s) => SourceChunk.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
  final String id, role, content, status, answerKind;
  bool get canAnswerGenerally =>
      role == 'assistant' &&
      status == 'complete' &&
      answerKind == 'no_evidence';
  final List<SourceChunk> sources;
  ChatMessage copy({
    String? content,
    String? status,
    List<SourceChunk>? sources,
    String? answerKind,
  }) => ChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    status: status ?? this.status,
    sources: sources ?? this.sources,
    answerKind: answerKind ?? this.answerKind,
  );
  Json toJson(String conversationId) => {
    'id': id,
    'conversation_id': conversationId,
    'role': role,
    'content': content,
    'status': status,
    'answer_kind': answerKind,
    'sources': sources.map((s) => s.toJson()).toList(),
  };
}

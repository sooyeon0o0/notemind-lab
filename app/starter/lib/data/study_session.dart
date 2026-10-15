import 'package:supabase_flutter/supabase_flutter.dart';

final _pendingSessions = Expando<Future<void>>();

/// Keep each installation's session without asking students to register.
/// Share the first request so simultaneous reads/uploads create one user only.
Future<void> ensureStudySession(SupabaseClient client) async {
  if (client.auth.currentSession != null) return;
  final pending = _pendingSessions[client];
  if (pending != null) return pending;
  final request = _createSession(client);
  _pendingSessions[client] = request;
  try {
    await request;
  } finally {
    _pendingSessions[client] = null;
  }
}

Future<void> _createSession(SupabaseClient client) async {
  final response = await client.auth.signInAnonymously();
  if (response.session == null) {
    throw const FormatException('저장 공간을 준비하지 못했습니다. 다시 시도해 주세요.');
  }
}

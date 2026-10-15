import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConfig {
  const AppConfig({
    this.supabaseUrl = defaultSupabaseUrl,
    this.anonKey = defaultAnonKey,
    this.chatUrl = const String.fromEnvironment(
      'OPENAI_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/v1',
    ),
    this.embeddingUrl = const String.fromEnvironment(
      'EMBEDDING_BASE_URL',
      defaultValue: 'http://127.0.0.1:8001/v1',
    ),
    this.model = const String.fromEnvironment(
      'MODEL_ID',
      defaultValue: 'notemind-chat',
    ),
    this.embeddingModel = const String.fromEnvironment(
      'EMBEDDING_MODEL_ID',
      defaultValue: 'notemind-embedding',
    ),
    this.apiKey = const String.fromEnvironment('INFERENCE_API_KEY'),
  });
  // --dart-define 값은 연결 설정에 저장한 값이 없을 때만 쓰는 기본값입니다.
  static const defaultSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const defaultAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final String supabaseUrl, anonKey;
  final String chatUrl, embeddingUrl, model, embeddingModel, apiKey;
  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = AppConfig();
    return AppConfig(
      supabaseUrl: prefs.getString('supabaseUrl') ?? defaults.supabaseUrl,
      anonKey: prefs.getString('anonKey') ?? defaults.anonKey,
      chatUrl: prefs.getString('chatUrl') ?? defaults.chatUrl,
      embeddingUrl: prefs.getString('embeddingUrl') ?? defaults.embeddingUrl,
      model: prefs.getString('model') ?? defaults.model,
      embeddingModel:
          prefs.getString('embeddingModel') ?? defaults.embeddingModel,
      apiKey:
          await const FlutterSecureStorage().read(key: 'inferenceKey') ??
          defaults.apiKey,
    );
  }

  Future<void> save() async {
    for (final value in [supabaseUrl, chatUrl, embeddingUrl]) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty) {
        throw const FormatException('http(s)://로 시작하는 서버 주소를 입력하세요.');
      }
    }
    if (anonKey.trim().isEmpty) {
      throw const FormatException('Supabase 공개 키(anon key)를 입력하세요.');
    }
    if (model.trim().isEmpty || embeddingModel.trim().isEmpty) {
      throw const FormatException('모델 이름을 입력하세요.');
    }
    final prefs = await SharedPreferences.getInstance();
    // anon 키는 앱에 공개되는 키라서 일반 저장소에 둡니다.
    await prefs.setString('supabaseUrl', supabaseUrl);
    await prefs.setString('anonKey', anonKey);
    await prefs.setString('chatUrl', chatUrl);
    await prefs.setString('embeddingUrl', embeddingUrl);
    await prefs.setString('model', model);
    await prefs.setString('embeddingModel', embeddingModel);
    await const FlutterSecureStorage().write(
      key: 'inferenceKey',
      value: apiKey,
    );
  }
}

final initialConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final configProvider = NotifierProvider<ConfigController, AppConfig>(
  ConfigController.new,
);

class ConfigController extends Notifier<AppConfig> {
  @override
  AppConfig build() => ref.read(initialConfigProvider);
  Future<void> save(AppConfig config) async {
    await config.save();
    await connectSupabase(config);
    state = config;
  }
}

String? _connectedSupabase;

/// 설정의 주소·키로 Supabase에 연결합니다. 값이 바뀌면 기존 연결을 닫고 다시 만듭니다.
Future<void> connectSupabase(AppConfig config) async {
  final target = '${config.supabaseUrl}\n${config.anonKey}';
  if (_connectedSupabase == target) return;
  if (_connectedSupabase != null) await Supabase.instance.dispose();
  _connectedSupabase = null;
  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.anonKey,
  );
  _connectedSupabase = target;
}

/// 저장하기 전에 입력한 Supabase 주소·키가 맞는지 확인합니다. 로그인은 하지 않습니다.
Future<void> checkSupabase(AppConfig config, {http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    final http.Response response;
    try {
      response = await httpClient
          .get(
            Uri.parse(
              '${config.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/v1/health',
            ),
            headers: {'apikey': config.anonKey},
          )
          .timeout(const Duration(seconds: 10));
    } on Exception {
      // 주소가 틀렸거나 Supabase(Docker)가 꺼져 있으면 응답 자체가 없습니다.
      throw Exception('서버에 연결할 수 없습니다. Supabase(Docker)가 켜져 있는지 확인하세요.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('공개 키가 맞지 않습니다. (${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  } finally {
    if (client == null) httpClient.close();
  }
}

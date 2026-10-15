import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'data/repository.dart';
import 'features/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await AppConfig.load();
    // 공개 키가 없어도 앱을 열고, 연결 설정 탭에서 입력받습니다.
    await connectSupabase(config);
    runApp(
      ProviderScope(
        overrides: [initialConfigProvider.overrideWithValue(config)],
        child: NoteMindApp(needsSetup: config.anonKey.isEmpty),
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_outlined, size: 40),
                  const SizedBox(height: 24),
                  const Text(
                    'NoteMind 연결 준비',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(friendlyError(error)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const ink = Color(0xff172f29);
const green = Color(0xff245c46);
const paper = Color(0xfff7f8f2);
ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: green,
    brightness: Brightness.light,
    surface: paper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(primary: green, onSurface: ink),
    scaffoldBackgroundColor: paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xffdce3d9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xffdce3d9)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6),
      bodyMedium: TextStyle(fontSize: 14, height: 1.55),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xffdeebd6),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class NoteMindApp extends StatelessWidget {
  const NoteMindApp({super.key, this.needsSetup = false});

  /// Supabase 공개 키가 없으면 연결 설정 탭부터 엽니다.
  final bool needsSetup;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NoteMind',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: HomeScreen(initialTab: needsSetup ? 2 : 0),
  );
}

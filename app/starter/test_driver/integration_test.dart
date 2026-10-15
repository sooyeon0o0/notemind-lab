import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final folder = Directory('.runtime/screenshots')
            ..createSync(recursive: true);
          await File('${folder.path}/$name.png').writeAsBytes(bytes);
          return true;
        },
  );
}

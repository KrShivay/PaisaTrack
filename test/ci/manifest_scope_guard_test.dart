import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Manifest scope script passes on android/app/src/main/AndroidManifest.xml', () async {
    final result = await Process.run(
      'bash',
      ['scripts/check_manifest_scope.sh', 'android/app/src/main/AndroidManifest.xml'],
    );
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('Manifest scope check passed cleanly'));
  });

  test('Manifest scope script fails when SEND_SMS or WRITE_SMS is injected', () async {
    final tempDir = await Directory.systemTemp.createTemp('manifest_test');
    try {
      final tempManifest = File('${tempDir.path}/AndroidManifest.xml');
      await tempManifest.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECEIVE_SMS"/>
    <uses-permission android:name="android.permission.READ_SMS"/>
    <uses-permission android:name="android.permission.SEND_SMS"/>
</manifest>
''');

      final result = await Process.run(
        'bash',
        ['scripts/check_manifest_scope.sh', tempManifest.path],
      );
      expect(result.exitCode, 1);
      expect(result.stdout.toString(), contains('Forbidden SMS permission found'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

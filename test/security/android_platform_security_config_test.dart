import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android OS backup and device transfer are disabled', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    for (final domain in const [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ]) {
      expect(
        RegExp('<exclude domain="$domain" path="\\." \\/>').allMatches(rules),
        hasLength(2),
      );
    }
  });

  test('embedding model integrity pin uses SHA-256, not MD5', () {
    final source = File(
      'android/app/src/main/kotlin/com/paisatrack/intelligence/'
      'EmbedderBridge.kt',
    ).readAsStringSync();

    expect(source, contains('MessageDigest.getInstance("SHA-256")'));
    expect(
      source,
      contains(
        '89ad3c74175dd8caa398cc22b657296d'
        '94302d20c525c12b58b29420f7249749',
      ),
    );
    expect(source, isNot(contains('MessageDigest.getInstance("MD5")')));
  });
}

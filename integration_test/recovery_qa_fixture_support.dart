import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const recoveryQaManifestName = 't179a-recovery-qa-manifest.json';
const recoveryQaManifestVersion = 1;
const recoveryQaArchiveName = 't179a-synthetic-recovery.ptrack';

/// Deep equality for SHA-256 hash maps; `Map ==` is identity in Dart.
bool recoveryQaHashMapsEqual(
  Map<String, String> first,
  Map<String, String> second,
) {
  if (first.length != second.length) return false;
  return first.entries.every((entry) => second[entry.key] == entry.value);
}

Future<Map<String, String>> hashDatabaseFamily(File baseFile) async {
  final hashes = <String, String>{};
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final member = File('${baseFile.path}$suffix');
    if (await member.exists()) {
      hashes[p.basename(member.path)] = await sha256File(member);
    }
  }
  return hashes;
}

Future<String> sha256File(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

Future<void> writeRecoveryQaManifest(
  Directory directory,
  Map<String, Object?> manifest,
) async {
  final file = File(p.join(directory.path, recoveryQaManifestName));
  await file.writeAsString(jsonEncode(manifest), flush: true);
}

Future<Map<String, Object?>> readRecoveryQaManifest(
  Directory directory,
) async {
  final file = File(p.join(directory.path, recoveryQaManifestName));
  if (!await file.exists()) {
    throw StateError('Recovery QA prepare manifest is missing.');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic> ||
      decoded['version'] != recoveryQaManifestVersion ||
      decoded['archiveName'] != recoveryQaArchiveName) {
    throw StateError('Recovery QA prepare manifest is invalid.');
  }
  return decoded;
}

Map<String, String> readRecoveryQaHashMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw StateError('Recovery QA database hash manifest is invalid.');
  }
  return value.map((key, value) {
    if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('Recovery QA database hash manifest is invalid.');
    }
    return MapEntry(key, value);
  });
}

void emitRecoveryQaMarker(String name, Map<String, Object?> values) {
  // ignore: avoid_print
  print('$name ${jsonEncode(values)}');
}

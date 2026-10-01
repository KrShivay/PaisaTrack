import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/recovery_qa_fixture_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recovery_qa_manifest_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('compares recovery hash maps by entries', () {
    final expected = {'paisatrack.db': 'a' * 64, 'paisatrack.db-wal': 'b' * 64};

    expect(
      recoveryQaHashMapsEqual(
        {'paisatrack.db-wal': 'b' * 64, 'paisatrack.db': 'a' * 64},
        expected,
      ),
      isTrue,
    );
    expect(
      recoveryQaHashMapsEqual({'paisatrack.db': 'c' * 64}, expected),
      isFalse,
    );
    expect(
      recoveryQaHashMapsEqual({'paisatrack.db': 'a' * 64}, expected),
      isFalse,
    );
  });

  test('persists a versioned manifest and hashes each legacy database file',
      () async {
    final database = File('${directory.path}/paisatrack.db');
    final wal = File('${database.path}-wal');
    await database.writeAsString('synthetic encrypted database bytes');
    await wal.writeAsString('synthetic encrypted WAL bytes');

    final hashes = await hashDatabaseFamily(database);
    expect(hashes.keys, containsAll(['paisatrack.db', 'paisatrack.db-wal']));
    expect(hashes.values, everyElement(matches(RegExp(r'^[0-9a-f]{64}$'))));

    await writeRecoveryQaManifest(directory, {
      'version': recoveryQaManifestVersion,
      'archiveName': recoveryQaArchiveName,
      'legacyDatabaseFamilySha256': hashes,
      'archiveSha256': 'a' * 64,
    });
    final manifest = await readRecoveryQaManifest(directory);
    expect(
      readRecoveryQaHashMap(manifest['legacyDatabaseFamilySha256']),
      hashes,
    );
  });

  test('rejects absent, wrong-version, and malformed hash manifests', () async {
    await expectLater(
      readRecoveryQaManifest(directory),
      throwsA(isA<StateError>()),
    );

    await writeRecoveryQaManifest(directory, {
      'version': recoveryQaManifestVersion + 1,
      'archiveName': recoveryQaArchiveName,
    });
    await expectLater(
      readRecoveryQaManifest(directory),
      throwsA(isA<StateError>()),
    );

    expect(
      () => readRecoveryQaHashMap({'paisatrack.db': 'not-a-hash'}),
      throwsA(isA<StateError>()),
    );
  });
}

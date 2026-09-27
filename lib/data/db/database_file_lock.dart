import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const _databaseFileLockChannel = MethodChannel(
  'com.paisatrack/database_passphrase',
);

/// Serializes recovery activation and the background writer across isolates.
/// Android combines an in-process semaphore with an OS file lock: POSIX file
/// locks alone allow multiple isolates in the same process to acquire them.
Future<T> withDatabaseFileLock<T>(
  Directory directory,
  Future<T> Function() action,
) async {
  await directory.create(recursive: true);
  final lockFile = File(p.join(directory.path, '.paisatrack-database.lock'));
  if (Platform.isAndroid) {
    final token = await _databaseFileLockChannel.invokeMethod<String>(
      'acquireDatabaseFileLock',
      {'path': lockFile.path},
    );
    if (token == null || token.isEmpty) {
      throw StateError('Android did not return a database lock token');
    }
    try {
      return await action();
    } finally {
      await _databaseFileLockChannel.invokeMethod<void>(
        'releaseDatabaseFileLock',
        {'token': token},
      );
    }
  }

  final handle = await lockFile.open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.exclusive);
    try {
      return await action();
    } finally {
      await handle.unlock();
    }
  } finally {
    await handle.close();
  }
}

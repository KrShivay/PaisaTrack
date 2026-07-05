import 'dart:async';

import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

/// No-op/fake SMS source for tests that boot the app shell.
class FakeCapturedSmsSource implements CapturedSmsSource {
  const FakeCapturedSmsSource([this._stream = const Stream<RawSms>.empty()]);

  final Stream<RawSms> _stream;

  @override
  Stream<RawSms> messages() => _stream;
}

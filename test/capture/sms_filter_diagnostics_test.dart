import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/sms_filter_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.sms_diagnostics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('decodes content-free native counters', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'filterCounters');
      return <String, Object?>{
        'liveFilterRejected': 2,
        'batchFilterRejected': 3,
        'liveUnknownSender': 4,
        'batchUnknownSender': 5,
      };
    });

    final counters = await const PlatformSmsFilterDiagnostics(
      channel: channel,
    ).readCounters();

    expect(counters.liveFilterRejected, 2);
    expect(counters.batchFilterRejected, 3);
    expect(counters.liveUnknownSender, 4);
    expect(counters.batchUnknownSender, 5);
  });

  test('rejects malformed counters', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => <String, Object?>{
        'liveFilterRejected': -1,
        'batchFilterRejected': 0,
        'liveUnknownSender': 0,
        'batchUnknownSender': 0,
      },
    );

    await expectLater(
      const PlatformSmsFilterDiagnostics(channel: channel).readCounters(),
      throwsA(isA<FormatException>()),
    );
  });
}

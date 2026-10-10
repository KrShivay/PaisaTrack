import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';

import 'recovery_qa_fixture_support.dart';

const _probeChannel = MethodChannel(
  'com.paisatrack/recovery_qa_sms_identity',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('synthetic PDU and inbox row share sent-time identity with legacy alias',
      () async {
    await verifyRecoveryQaIdentity();

    final result = await _probeChannel.invokeMapMethod<String, Object?>(
      'runSyntheticProbe',
    );
    expect(result, isNotNull);
    expect(result!['acceptedByLiveReceiver'], isTrue);
    expect(result['acceptedByInboxReader'], isTrue);
    expect(result['senderMatchesFixture'], isTrue);
    expect(result['bodyMatchesFixture'], isTrue);
    expect(result['liveTimestampMatchesPdu'], isTrue);
    expect(result['idsMatch'], isTrue);
    expect(result['dateSentRequested'], isTrue);
    expect(result['legacyIdPresent'], isTrue);
    expect(result['legacyReceiptIdMatches'], isTrue);
    expect(result['pageHasMore'], isTrue);
    expect(result['nextCursorUsesReceivedDate'], isTrue);
    expect(result['nextCursorIdMatches'], isTrue);
    expect(result['sortOrderUsesReceiptDate'], isTrue);

    final liveTimestamp = result['liveTimestampEpochMillis'] as int;
    final inboxTimestamp = result['inboxTimestampEpochMillis'] as int;
    final expectedDifference = result['syntheticReceivedOffsetMillis'] as int;
    expect(inboxTimestamp - liveTimestamp, expectedDifference);

    emitRecoveryQaMarker('SMS_IDENTITY_QA_OBSERVED', {
      'acceptedByLiveReceiver': result['acceptedByLiveReceiver'],
      'acceptedByInboxReader': result['acceptedByInboxReader'],
      'idsMatch': result['idsMatch'],
      'dateSentRequested': result['dateSentRequested'],
      'pageHasMore': result['pageHasMore'],
      'nextCursorUsesReceivedDate': result['nextCursorUsesReceivedDate'],
      'sortOrderUsesReceiptDate': result['sortOrderUsesReceiptDate'],
      'timestampDifferenceMillis': inboxTimestamp - liveTimestamp,
    });
  });
}

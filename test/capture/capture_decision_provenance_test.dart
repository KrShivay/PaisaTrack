import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/capture_decision_provenance.dart';
import 'package:paisatrack/data/confidence_payload.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';

void main() {
  group('CaptureDecisionProvenance', () {
    test('writes and reads the current version without replacing fields', () {
      final payload = <String, Object?>{
        'parser': {'c': 0.91, 'src': 'template'},
        'category': {'c': 0.82, 'src': 'seed'},
      };

      CaptureDecisionProvenance.writeCurrent(
        payload,
        statusMode: CaptureDecisionStatusMode.policy,
        categorySource: 'rule',
      );

      final encoded = jsonEncode(payload);
      final provenance = CaptureDecisionProvenance.fromConfidenceJson(encoded);
      expect(
        provenance?.version,
        CaptureDecisionProvenance.currentVersion,
      );
      expect(provenance?.statusMode, CaptureDecisionStatusMode.policy);
      expect(provenance?.categorySource, 'rule');
      expect(parseConfidenceFromJson(encoded), 0.91);
      expect(
        TransactionConfidenceTrail.fromJson(encoded).category?.source,
        'seed',
      );
      expect(encoded, isNot(contains('raw_sms')));
    });

    test(
      'legacy rows remain readable and have no inferred decision version',
      () {
        const legacy = '{"parser":{"c":0.74,"src":"template"}}';

        expect(
          CaptureDecisionProvenance.versionFromConfidenceJson(legacy),
          isNull,
        );
        expect(parseConfidenceFromJson(legacy), 0.74);
        expect(
          TransactionConfidenceTrail.fromJson(legacy).parser?.confidence,
          0.74,
        );
      },
    );

    test('well-formed v1 decision metadata remains unversioned', () {
      const legacyV1 = '{"capture_decision":{"version":"capture-decision-v1",'
          '"status_mode":"policy","category_source":"rule"}}';
      expect(CaptureDecisionProvenance.fromConfidenceJson(legacyV1), isNull);
    });

    test('malformed and unsupported decision blocks remain unknown', () {
      expect(CaptureDecisionProvenance.versionFromConfidenceJson('{'), isNull);
      expect(
        CaptureDecisionProvenance.versionFromConfidenceJson(
          '{"capture_decision":{"version":"capture-decision-v2"}}',
        ),
        isNull,
      );
      expect(
        CaptureDecisionProvenance.versionFromConfidenceJson(
          '{"capture_decision":{"version":"capture-decision-v1","status_mode":"other"}}',
        ),
        isNull,
      );
    });
  });
}

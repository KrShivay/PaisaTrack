import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart'
    show FieldEvidence;
import 'package:paisatrack/features/transactions/detail/transaction_detail_evidence.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

const _sms = 'Debited INR 500 from SBI A/C xx1234';

FieldEvidence _ev(String field, int start, int end, {String? verbatim}) =>
    FieldEvidence(
      field: field,
      start: start,
      end: end,
      verbatim: verbatim ?? _sms.substring(start, end),
      extractor: 'regex',
    );

void main() {
  group('buildEvidenceSpans — null/empty rawSmsBody', () {
    testWidgets('shows purged message when rawSmsBody is null',
        (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(null, null, false, null)),
      );
      expect(find.text('Source message purged per retention policy'),
          findsOneWidget);
    });

    testWidgets('shows purged message when rawSmsBody is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans('', [], false, null)),
      );
      expect(find.text('Source message purged per retention policy'),
          findsOneWidget);
    });
  });

  group('buildEvidenceSpans — no evidence spans', () {
    testWidgets('shows FIELD EVIDENCE SPANS header', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [], false, null)),
      );
      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
    });

    testWidgets('renders full SMS as plain SelectableText', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [], false, null)),
      );
      expect(find.text(_sms), findsOneWidget);
    });

    testWidgets('shows header when evidence list is null', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, null, false, null)),
      );
      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
    });
  });

  group('buildEvidenceSpans — with spans', () {
    // "INR 500" starts at 8, ends at 15
    final amountSpan = _ev('amount', 8, 15);

    testWidgets('renders FIELD EVIDENCE SPANS header', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [amountSpan], false, 0.9)),
      );
      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
    });

    testWidgets('renders the highlighted verbatim text', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [amountSpan], false, 0.9)),
      );
      expect(find.text('INR 500'), findsOneWidget);
    });

    testWidgets('renders badge row with field and verbatim', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [amountSpan], false, 0.9)),
      );
      // Badge text includes field name and verbatim
      expect(
        find.textContaining('amount:'),
        findsOneWidget,
      );
    });

    testWidgets('span at start of string — no leading text', (tester) async {
      // span covering "Debited" at start
      final span = _ev('action', 0, 7);
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [span], false, 1.0)),
      );
      expect(find.text('Debited'), findsOneWidget);
    });

    testWidgets('span at end of string — no trailing text error',
        (tester) async {
      final end = _sms.length;
      // span covers last 7 chars "xx1234)"
      final span = _ev('account', end - 7, end);
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [span], false, 1.0)),
      );
      // just verify it renders without exception
      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
    });

    testWidgets('out-of-order spans are sorted by start', (tester) async {
      // Provide spans in reverse order — should still render cleanly
      final s1 = _ev('amount', 8, 15);
      final s2 = _ev('account', 30, 36, verbatim: 'xx1234');
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [s2, s1], false, 1.0)),
      );
      expect(find.text('INR 500'), findsOneWidget);
    });

    testWidgets('dark mode does not crash', (tester) async {
      await tester.pumpWidget(
        _wrap(buildEvidenceSpans(_sms, [amountSpan], true, 0.9)),
      );
      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
    });
  });
}

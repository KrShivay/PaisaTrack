import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/app.dart';

void main() {
  testWidgets('renders the app shell', (tester) async {
    await tester.pumpWidget(const PaisaTrackApp());

    expect(find.text('PaisaTrack'), findsOneWidget);
  });
}

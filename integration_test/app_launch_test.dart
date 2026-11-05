// Launch smoke test: the dev flavor starts (local-only mode when Firebase,
// RevenueCat and PostHog aren't configured) and lands on the welcome screen.
// CI runs this on an Android emulator and an iOS simulator.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snipfit/main_dev.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold start reaches the welcome screen', (tester) async {
    final started = DateTime.now();
    app.main();
    // The welcome animation loops forever, so poll instead of settling.
    for (var i = 0; i < 100 && find.text('Get started').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Get started'), findsOneWidget);
    debugPrint('cold start to first screen: ${DateTime.now().difference(started).inMilliseconds} ms');
  });
}

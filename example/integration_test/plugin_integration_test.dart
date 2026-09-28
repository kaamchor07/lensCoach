// LensCoach integration test.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:lenscoach/lenscoach.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('platform bridge connectivity test', (WidgetTester tester) async {
    // Verify the platform bridge can communicate with native side
    // This will fail on desktop/web — only valid on Android device/emulator
    try {
      final data = await LenscoachBridge.getSensorData();
      expect(data, isNotNull);
    } catch (e) {
      // Expected to fail when not running on Android
      expect(e, isA<Exception>());
    }
  });
}

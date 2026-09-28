import 'package:flutter_test/flutter_test.dart';
import 'package:lenscoach/lenscoach.dart';

void main() {
  testWidgets('LenscoachBridge exists', (WidgetTester tester) async {
    // Basic smoke test — verifies the bridge class is importable
    expect(LenscoachBridge, isNotNull);
  });
}

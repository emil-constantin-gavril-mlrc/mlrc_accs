import 'package:flutter_test/flutter_test.dart';
import 'package:screen_mirror/main.dart';

void main() {
  testWidgets('shows the watcher terminal dashboard', (tester) async {
    await tester.pumpWidget(const WatcherTerminalApp());

    expect(find.text('Event Stream Terminal'), findsOneWidget);
    expect(find.text('Start Transmitting'), findsOneWidget);
    expect(find.text('Start Receiving'), findsOneWidget);

    const showDebugPanel = bool.fromEnvironment(
      'SHOW_DEBUG_PANEL',
      defaultValue: false,
    );
    if (showDebugPanel) {
      expect(find.text('Debug Inspector Panel'), findsOneWidget);
      expect(find.text('Available MLRC peers'), findsOneWidget);
      expect(find.text('Current screen preview'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
    }
  });
}

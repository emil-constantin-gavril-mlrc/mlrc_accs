import 'dart:ui';

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

  testWidgets('compact dashboard tolerates zero-width startup layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(0, 800));
    await tester.pumpWidget(const WatcherTerminalApp());
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(320, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Event Stream Terminal'), findsOneWidget);
  });

  testWidgets('compact dashboard keeps the event log inside the scroll view', (
    tester,
  ) async {
    const showDebugPanel = bool.fromEnvironment(
      'SHOW_DEBUG_PANEL',
      defaultValue: false,
    );
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const WatcherTerminalApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Event Stream Terminal'), findsOneWidget);
    expect(find.text('Start Transmitting'), findsOneWidget);
    expect(find.text('Start Receiving'), findsOneWidget);
    if (showDebugPanel) {
      expect(find.text('Current screen preview'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Event Stream Terminal')).dy,
        lessThan(tester.getTopLeft(find.text('Current screen preview')).dy),
      );
    }

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(320, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

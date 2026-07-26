import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser.dart';
import 'package:flutter_muxpod/widgets/tmux_tiles.dart';

void main() {
  group('TmuxWindowTile', () {
    final window = TmuxWindow(index: 1, name: 'main', paneCount: 2);

    testWidgets('shows all actions and routes rename tap', (tester) async {
      var renamed = false;
      var resized = false;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TmuxWindowTile(
              window: window,
              isActive: false,
              onRename: () => renamed = true,
              onResize: () => resized = true,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Rename Window'), findsOneWidget);
      expect(find.text('Resize Window'), findsOneWidget);
      expect(find.text('Close Window'), findsOneWidget);

      await tester.tap(find.text('Rename Window'));
      await tester.pumpAndSettle();

      expect(renamed, isTrue);
      expect(resized, isFalse);
      expect(closed, isFalse);
    });

    testWidgets('no rename item when onRename is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TmuxWindowTile(
              window: window,
              isActive: false,
              onResize: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Rename Window'), findsNothing);
    });
  });
}

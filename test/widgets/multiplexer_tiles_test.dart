import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_window.dart';

import 'package:flutter_muxpod/widgets/multiplexer_tiles.dart';

void main() {
  group('MultiplexerSessionTile', () {
    final session = MultiplexerSession(name: 'dev', windowCount: 3);

    testWidgets('shows name, window count and folder icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerSessionTile(session: session, isActive: false),
          ),
        ),
      );

      expect(find.text('dev'), findsOneWidget);
      expect(find.text('3 windows'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('shows trailing and routes tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerSessionTile(
              session: session,
              isActive: true,
              onTap: () => tapped = true,
              trailing: const Icon(Icons.check),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.text('dev'));
      expect(tapped, isTrue);
    });
  });

  group('MultiplexerWindowTile', () {
    final window = MultiplexerWindow(index: 1, name: 'main', paneCount: 2);

    testWidgets('shows index, name, pane count and tab icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerWindowTile(window: window, isActive: false),
          ),
        ),
      );

      expect(find.text('1: main'), findsOneWidget);
      expect(find.text('2 panes'), findsOneWidget);
      expect(find.byIcon(Icons.tab), findsOneWidget);
    });

    testWidgets('shows all actions and routes rename tap', (tester) async {
      var renamed = false;
      var resized = false;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerWindowTile(
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
            body: MultiplexerWindowTile(
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
      expect(find.text('Resize Window'), findsOneWidget);
      expect(find.text('Close Window'), findsOneWidget);
    });

    testWidgets('no popup when all callbacks are null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerWindowTile(window: window, isActive: false),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('uses custom resize label when resizeLabel is provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerWindowTile(
              window: window,
              isActive: false,
              onResize: () {},
              resizeLabel: 'Resize Tab',
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Resize Tab'), findsOneWidget);
      expect(find.text('Resize Window'), findsNothing);
    });
  });

  group('MultiplexerPaneTile', () {
    final pane = MultiplexerPane(index: 0, id: '%0');

    testWidgets('shows title, index badge and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              subtitle: '120x40',
              isActive: false,
            ),
          ),
        ),
      );

      expect(find.text('Pane title'), findsOneWidget);
      expect(find.text('120x40'), findsOneWidget);
      // leading badge に pane.index が表示される
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('omits subtitle when null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              subtitle: null,
              isActive: false,
            ),
          ),
        ),
      );

      expect(find.text('Pane title'), findsOneWidget);
      // badge + title のみ（subtitle は null のため非表示）
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('shows popup actions and routes close tap', (tester) async {
      var resized = false;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              subtitle: '120x40',
              isActive: false,
              onResize: () => resized = true,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Resize Pane'), findsOneWidget);
      expect(find.text('Close Pane'), findsOneWidget);

      await tester.tap(find.text('Close Pane'));
      await tester.pumpAndSettle();

      expect(resized, isFalse);
      expect(closed, isTrue);
    });

    testWidgets('no resize item when onResize is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              isActive: false,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Resize Pane'), findsNothing);
      expect(find.text('Close Pane'), findsOneWidget);
    });

    testWidgets('no popup when all callbacks are null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              isActive: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('routes tap and long press', (tester) async {
      var tapped = false;
      var longPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPaneTile(
              pane: pane,
              paneTitle: 'Pane title',
              isActive: false,
              onTap: () => tapped = true,
              onLongPress: () => longPressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pane title'));
      expect(tapped, isTrue);

      await tester.longPress(find.text('Pane title'));
      expect(longPressed, isTrue);
    });
  });
}

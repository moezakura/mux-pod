import 'package:flutter/material.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/widgets/dialogs/pane_chooser_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 横並び 2 pane fixture（0 起点）
  const p1 = MultiplexerPane(
    index: 1,
    id: 'w1:p1',
    active: true,
    currentPath: '/home/user',
    left: 0,
    top: 0,
    width: 80,
    height: 24,
  );
  const p2 = MultiplexerPane(
    index: 2,
    id: 'w1:p2',
    left: 80,
    top: 0,
    width: 80,
    height: 24,
  );

  // 非 0 起点 × 複数 pane fixture（herdr 実測 x:26 / y:1・E12）
  const nonZeroOriginPanes = [
    MultiplexerPane(
      index: 1,
      id: 'w1:p1',
      left: 26,
      top: 1,
      width: 80,
      height: 24,
    ),
    MultiplexerPane(
      index: 2,
      id: 'w1:p2',
      left: 106,
      top: 1,
      width: 80,
      height: 24,
    ),
  ];

  Future<void> openDialog(
    WidgetTester tester, {
    required List<MultiplexerPane> panes,
    String? initialPaneId,
    String? Function(MultiplexerPane)? labelBuilder,
    required void Function(String paneId) onResize,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => PaneChooserDialog(
                    panes: panes,
                    initialPaneId: initialPaneId,
                    labelBuilder: labelBuilder,
                    onResize: onResize,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  bool isResizeEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Resize'),
    );
    return button.onPressed != null;
  }

  group('PaneChooserDialog', () {
    testWidgets('初期選択 = initialPaneId がリスト内に存在するとき', (tester) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p2',
        onResize: (_) {},
      );

      expect(find.text('Selected: Pane 2 (80x24)'), findsOneWidget);
      expect(isResizeEnabled(tester), isTrue);
    });

    testWidgets('initialPaneId 不在時はリスト内 active pane にフォールバック', (tester) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p9', // 存在しない id
        onResize: (_) {},
      );

      expect(find.text('Selected: Pane 1 (80x24)'), findsOneWidget);
      expect(isResizeEnabled(tester), isTrue);
    });

    testWidgets('active pane も存在しなければ panes.first にフォールバック', (tester) async {
      const inactive = [
        MultiplexerPane(
          index: 1,
          id: 'w1:p1',
          left: 0,
          top: 0,
          width: 80,
          height: 24,
        ),
        MultiplexerPane(
          index: 2,
          id: 'w1:p2',
          left: 80,
          top: 0,
          width: 80,
          height: 24,
        ),
      ];
      await openDialog(
        tester,
        panes: inactive,
        initialPaneId: 'w1:p9',
        onResize: (_) {},
      );

      expect(find.text('Selected: Pane 1 (80x24)'), findsOneWidget);
      expect(isResizeEnabled(tester), isTrue);
    });

    testWidgets('タップ選択 → Selected 更新 → Resize で onResize が発火する', (
      tester,
    ) async {
      String? resizedId;
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p1',
        onResize: (id) => resizedId = id,
      );

      // 初期は p1 が選択済み
      expect(find.text('Selected: Pane 1 (80x24)'), findsOneWidget);

      // p2 をタップして選択を切り替える
      await tester.tap(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected: Pane 2 (80x24)'), findsOneWidget);

      // Resize ボタンで onResize が選択中の paneId で発火
      await tester.tap(find.widgetWithText(FilledButton, 'Resize'));
      await tester.pumpAndSettle();
      expect(resizedId, 'w1:p2');
    });

    testWidgets('0 起点正規化: 非 0 起点 fixture（x:26 / y:1・E12）でもタイルが描画され選択できる', (
      tester,
    ) async {
      String? resizedId;
      await openDialog(
        tester,
        panes: nonZeroOriginPanes,
        initialPaneId: 'w1:p1',
        onResize: (id) => resizedId = id,
      );

      // 両タイルが find でき（画面内に描画され）、タップで選択可能
      expect(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p2')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected: Pane 2 (80x24)'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Resize'));
      await tester.pumpAndSettle();
      expect(resizedId, 'w1:p2');
    });

    testWidgets("空リスト: グリッド非表示・'Tap a pane to select' 非表示・Resize disabled", (
      tester,
    ) async {
      await openDialog(tester, panes: const [], onResize: (_) {});

      // グリッドタイルが存在しない（グリッド非表示）
      expect(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p1')),
        findsNothing,
      );
      // 未選択案内も空リストでは出さない
      expect(find.text('Tap a pane to select'), findsNothing);
      // Resize disabled
      expect(isResizeEnabled(tester), isFalse);
      // Cancel は有効のまま
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancel.onPressed, isNotNull);
    });

    testWidgets('ラベル注入: labelBuilder（cwd 表示）が Selected に反映される', (tester) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p1',
        labelBuilder: (pane) => pane.currentPath,
        onResize: (_) {},
      );

      // cwd がラベルとして表示される（'Pane N' ではなく）
      expect(find.text('Selected: /home/user (80x24)'), findsOneWidget);
      expect(find.text('Selected: Pane 1 (80x24)'), findsNothing);
    });

    testWidgets("ラベル注入: labelBuilder が null を返す場合は 'Pane N' にフォールバック", (
      tester,
    ) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p2',
        labelBuilder: (pane) => null,
        onResize: (_) {},
      );

      expect(find.text('Selected: Pane 2 (80x24)'), findsOneWidget);
    });

    testWidgets("ラベル注入: labelBuilder 未指定は 'Pane N'（index ベース）", (tester) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        initialPaneId: 'w1:p1',
        onResize: (_) {},
      );

      expect(find.text('Selected: Pane 1 (80x24)'), findsOneWidget);
    });

    testWidgets('グリッド内は index + WxH 形式で表示される', (tester) async {
      await openDialog(tester, panes: [p1, p2], onResize: (_) {});

      expect(find.text('1\n80x24'), findsOneWidget);
      expect(find.text('2\n80x24'), findsOneWidget);
    });

    testWidgets('サイズ不明 pane（width=0 / height=0）は「サイズ不明」と表示される', (tester) async {
      // サイズ不明 pane を先頭（left:0 / top:0）に置き、グリッドの clamp 計算
      // （最小サイズ 20x14）が画面外位置で破綻しない fixture にする。
      const unknownSize = MultiplexerPane(
        index: 3,
        id: 'w1:p3',
        left: 0,
        top: 0,
        width: 0,
        height: 0,
      );
      await openDialog(
        tester,
        panes: [unknownSize, p1, p2],
        initialPaneId: 'w1:p3',
        onResize: (_) {},
      );

      // グリッド内は index + 「サイズ不明」
      expect(find.text('3\nUnknown size'), findsOneWidget);
      // Selected 行も同様にフォールバック
      expect(find.text('Selected: Pane 3 (Unknown size)'), findsOneWidget);
      // サイズ不明でも選択・Resize は可能
      expect(isResizeEnabled(tester), isTrue);
    });
  });
}

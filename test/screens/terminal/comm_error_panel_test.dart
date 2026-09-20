import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/comm_error_panel.dart';

void main() {
  testWidgets(
    'narrow Japanese panel folds all details and scrolls long errors',
    (tester) async {
      var expanded = false;
      var retries = 0;
      var closes = 0;
      final details = List.generate(
        80,
        (i) => 'SshConnectionError: SocketException: connection refused ($i)',
      ).join('\n');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 296,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: StatefulBuilder(
                    builder: (context, setState) => CommErrorPanel(
                      title: '再接続に失敗しました',
                      body: 'サーバーとの接続が切断されました。',
                      detail: details,
                      expanded: expanded,
                      onToggleExpanded: () =>
                          setState(() => expanded = !expanded),
                      onRetry: () => retries++,
                      onClose: () => closes++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final collapsedHeight = tester
          .getSize(find.byType(CommErrorPanel))
          .height;
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(CommErrorPanel)).height,
        lessThanOrEqualTo(240),
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
      expect(
        tester.getSize(find.byType(CommErrorPanel)).height,
        collapsedHeight,
      );
      await tester.tap(find.text('今すぐ再接続'));
      await tester.tap(find.byIcon(Icons.close));
      expect(retries, 1);
      expect(closes, 1);
    },
  );
}

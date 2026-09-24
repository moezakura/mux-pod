import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('T15: herdr paste / 画像転送 / copy-mode 代替（Q-06/H7）', () {
    testWidgets('Cmd ダイアログの複数行送信は send-text で貼り付ける（Q-06）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      // SpecialKeysBar の Cmd から入力ダイアログを開き複数行を送信する。
      await tester.tap(find.text('Cmd'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'echo hi');
      await tester.tap(find.text('Execute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) => c.startsWith('herdr pane send-text w1:p1'),
        ),
        isTrue,
        reason: 'paste は PaneWriter.pasteText → send-text で送信されること（Q-06）',
      );

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('画像転送（SFTP アップロード + send-text でパス注入）', (tester) async {
      final image = FakeImageTransferNotifier()
        ..uploadResult = '/tmp/upload.png';
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        imageTransferNotifier: image,
        settle: false,
      );

      // SpecialKeysBar の画像ボタン → シートを閉じ → 状態を手動で進める。
      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(20, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      image.emit(const ImageTransferState(phase: ImageTransferPhase.picking));
      await tester.pump();
      image.emit(
        ImageTransferState(
          phase: ImageTransferPhase.confirming,
          pickedImageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
          pickedImageName: 'pixel.png',
          pendingRemotePath: '/tmp/pixel.png',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload Image'), findsOneWidget);
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SFTP アップロード（provider 側）完了後、パスを send-text で注入する。
      expect(
        client.execCommands.any(
          (c) =>
              c.startsWith('herdr pane send-text w1:p1') &&
              c.contains('/tmp/upload.png'),
        ),
        isTrue,
        reason: '画像転送は SFTP + send-text（パス送信）で行われること（Q-06）',
      );

      // SnackBar（Uploaded）の自動クローズまで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('Select モードは herdr では copy-mode を出さず pane read 履歴のみ', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'history content\n',
        },
        settle: false,
      );

      // 設定メニュー → 'Select Mode'（選択モードへ切替）。
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Select Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // herdr には copy-mode が無い（H7）: tmux copy-mode コマンドは出ない。
      expect(client.sendKeysCommands, isEmpty);
      // 履歴は pane read（既存）で取得する。要求行数はユーザー設定
      // scrollbackLines（既定 10000・バグ4）と整合する。
      expect(
        client.execCommands.any(
          (c) =>
              c.startsWith('herdr pane read w1:p1') &&
              c.contains('--lines 10000'),
        ),
        isTrue,
        reason: 'Select モードは herdr では pane read 履歴ベースのみ（H7）',
      );

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}

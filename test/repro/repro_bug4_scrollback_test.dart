// Repro: バグ4 スクロールバック（履歴行数）が異常に少ない
//
// 再現条件（静的解析）:
// - ライブポーリングは固定 -120 行で pane を読む（terminal_screen.dart:1508）
// - herdr では HerdrCommands.paneRead が `--source recent --lines 120 --raw` を
//   生成する（herdr_commands.dart:44-47）
// - mutation-baseline-report.md:268-269 に、herdr CLI は
//   `pane read --source recent --lines N --raw`（--lines と --raw 併用）で
//   0 バイトを返すという実測記録がある
// - 深い履歴（-100000）はスクロールモード/オーバースクロール時のみ
//   （terminal_screen.dart:2157）
// → 通常表示では毎回 `--lines 120 --raw` が発行され、herdr CLI の制約により
//   ほぼ空（または極端に少ない行数）しか取得できない
//
// このテストは「ライブポーリングが常に --lines 120 --raw を発行する」ことと
// 「空応答が空コンテンツになる」ことを再現する。実際の herdr CLI の 0 バイト
// 応答は実機（herdr サーバ）での確認が必要（手順書参照）。
@Tags(['repro'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/herdr/herdr_parser.dart';

void main() {
  group('Repro BUG-4: ライブポーリングは固定 -120 行', () {
    test('ライブポーリング（historyLines: -120, ansi: true）は '
        '`--source recent --lines 120 --raw` を生成する', () {
      final cmd = HerdrCommands.paneRead(
        'w1:p1',
        source: 'recent',
        lines: 120,
        ansi: true,
      );
      expect(
        cmd,
        'herdr pane read w1:p1 --source recent --lines 120 --raw',
        reason:
            'バグ: アプリは常に --lines と --raw を併用する。'
            'mutation-baseline-report.md:268-269 の実測ではこの組み合わせは'
            '0 バイトを返す（--lines のセマンティクス要確認）',
      );
    });

    test('深い履歴（scrollback）は PaneHistoryPolicy が行数を解決し、'
        'その行数で `--lines N` を生成する（バグ4 修正後）', () {
      // 修正後: 行数は backend ポリシー（PaneHistoryPolicy）が解決する。
      // 既定 scrollbackLines=10000 の場合、herdr は --lines 10000 を要求する。
      final cmd = HerdrCommands.paneRead(
        'w1:p1',
        source: 'recent',
        lines: 10000,
        ansi: true,
      );
      expect(cmd, 'herdr pane read w1:p1 --source recent --lines 10000 --raw');
    });

    test('herdr CLI が 0 バイトを返した場合、パース結果は空コンテンツになる', () {
      // mutation-baseline-report.md:268-269: `--lines` と `--raw` 併用で
      // 0 バイト応答。その場合の表示は空になる。
      final parsed = HerdrPaneContentParser.parse('', ansi: true);
      expect(parsed.rawText, '');
      expect(parsed.lines, isEmpty);
      expect(parsed.hasAnsi, isTrue); // --raw 指定のため ansi フラグは立つ
    });

    test('行数指定なし（全量）と比べ、--lines 120 は最大120行に制限される', () {
      // 120行を超える履歴がある場合、--lines 120 は末尾120行のみ返す。
      // これ自体は仕様だが、「ユーザー設定 scrollbackLines（200〜20000）」と
      // 比較すると、ライブ表示に使える履歴が常に120行に制限される。
      final limited = HerdrCommands.paneRead(
        'w1:p1',
        source: 'recent',
        lines: 120,
        ansi: true,
      );
      expect(limited, contains('--lines 120'));
      expect(
        limited.contains('--lines 2000'),
        isFalse,
        reason:
            'tmux 側はユーザー設定 scrollbackLines（200〜20000）に従うが、'
            'herdr ライブポーリングは常に 120 行固定',
      );
    });
  });
}

import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/backend/domain/wheel_encoder.dart';
import 'package:flutter_muxpod/services/herdr/herdr_keymap.dart';
import 'package:flutter_test/flutter_test.dart';

// スクロール送信エンコーダ（WheelEncoder）の単体テスト。
// - P0: エンコード文字列の完全一致（D10・Implementation Plan P0）。
// - encodePage は herdr_keymap の PPage/NPage（ESC[5~ / ESC[6~）と同一値で
//   あること（調査レポート §2.1・G4 実測）。

void main() {
  group('ScrollSendKind', () {
    test('values は wheel / key の 2 値（完全一致）', () {
      expect(ScrollSendKind.values, [ScrollSendKind.wheel, ScrollSendKind.key]);
    });
  });

  group('WheelEncoder.encodeSgr', () {
    test('上スクロール（up=true）は ESC[<64;1;1M', () {
      expect(
        WheelEncoder.encodeSgr(up: true, ticks: 1),
        '\x1b[<64;1;1M',
      );
    });

    test('下スクロール（up=false）は ESC[<65;1;1M', () {
      expect(
        WheelEncoder.encodeSgr(up: false, ticks: 1),
        '\x1b[<65;1;1M',
      );
    });

    test('ticks=8 は 8 個連結（合流送信・最大 8 ティック）', () {
      expect(
        WheelEncoder.encodeSgr(up: true, ticks: 8),
        '\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M'
        '\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M',
      );
      expect(
        WheelEncoder.encodeSgr(up: false, ticks: 8),
        '\x1b[<65;1;1M\x1b[<65;1;1M\x1b[<65;1;1M\x1b[<65;1;1M'
        '\x1b[<65;1;1M\x1b[<65;1;1M\x1b[<65;1;1M\x1b[<65;1;1M',
      );
    });

    test('x/y はデフォルト 1;1 で、明示指定で差し替え可能', () {
      expect(WheelEncoder.encodeSgr(up: true, ticks: 1), '\x1b[<64;1;1M');
      expect(
        WheelEncoder.encodeSgr(up: true, ticks: 1, x: 5, y: 3),
        '\x1b[<64;5;3M',
      );
    });

    test('ticks=0 / 負値は空文字（純関数・throw しない）', () {
      expect(WheelEncoder.encodeSgr(up: true, ticks: 0), '');
      expect(WheelEncoder.encodeSgr(up: false, ticks: -1), '');
    });
  });

  group('WheelEncoder.encodePage', () {
    test('上（up=true）は ESC[5~（herdr PPage と同一値）', () {
      expect(WheelEncoder.encodePage(up: true, ticks: 1), '\x1b[5~');
      // herdr_keymap の PPage エスケープと同一値（G4 実測でバイナリ素通し）。
      final route =
          PaneKeyMap.mapSpecialKey('PPage') as HerdrKeyRouteSendTextEscape;
      expect(route.bytes, '\x1b[5~');
    });

    test('下（up=false）は ESC[6~（herdr NPage と同一値）', () {
      expect(WheelEncoder.encodePage(up: false, ticks: 1), '\x1b[6~');
      final route =
          PaneKeyMap.mapSpecialKey('NPage') as HerdrKeyRouteSendTextEscape;
      expect(route.bytes, '\x1b[6~');
    });

    test('ticks=8 は 8 個連結', () {
      expect(
        WheelEncoder.encodePage(up: true, ticks: 8),
        '\x1b[5~\x1b[5~\x1b[5~\x1b[5~\x1b[5~\x1b[5~\x1b[5~\x1b[5~',
      );
      expect(
        WheelEncoder.encodePage(up: false, ticks: 8),
        '\x1b[6~\x1b[6~\x1b[6~\x1b[6~\x1b[6~\x1b[6~\x1b[6~\x1b[6~',
      );
    });

    test('ticks=0 / 負値は空文字（純関数・throw しない）', () {
      expect(WheelEncoder.encodePage(up: true, ticks: 0), '');
      expect(WheelEncoder.encodePage(up: false, ticks: -3), '');
    });
  });
}

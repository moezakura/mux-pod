// TerminalViewData.hyperlinks（copyWith センチネル）と
// paneHyperlinksEquals を検証する（herdr OSC 8 ハイパーリンク実験機能）。
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/screens/terminal/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _linkA = PaneHyperlinks(
  frameWidth: 80,
  frameHeight: 24,
  links: [
    PaneHyperlink(
      url: 'https://example.com/',
      ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 5)],
    ),
  ],
  rowFingerprints: {0: '9f1c000000000000'},
);

void main() {
  group('TerminalViewData.hyperlinks', () {
    test('既定は null（既存 tmux / caret 経路に影響しない）', () {
      const view = TerminalViewData();
      expect(view.hyperlinks, isNull);
    });

    test('copyWith 未指定なら現状維持', () {
      const view = TerminalViewData(hyperlinks: _linkA);
      final copied = view.copyWith(content: 'x');
      expect(copied.hyperlinks, same(_linkA));
    });

    test('copyWith(hyperlinks: null) で明示的にクリアできる', () {
      const view = TerminalViewData(hyperlinks: _linkA);
      final copied = view.copyWith(hyperlinks: null);
      expect(copied.hyperlinks, isNull);
    });

    test('copyWith(hyperlinks: value) で差し替えられる', () {
      const view = TerminalViewData(hyperlinks: _linkA);
      const other = PaneHyperlinks(frameWidth: 100, frameHeight: 30);
      final copied = view.copyWith(hyperlinks: other);
      expect(copied.hyperlinks, same(other));
    });

    test('caret と hyperlinks は独立して copyWith できる', () {
      const caret = PaneCaret(x: 1, y: 2, visible: true);
      const view = TerminalViewData(caret: caret, hyperlinks: _linkA);
      final copied = view.copyWith(hyperlinks: null);
      expect(copied.caret, same(caret));
      expect(copied.hyperlinks, isNull);
    });
  });

  group('paneHyperlinksEquals', () {
    test('同一インスタンスは値を比較せず true', () {
      expect(paneHyperlinksEquals(_linkA, _linkA), isTrue);
    });

    test('両方 null は true', () {
      expect(paneHyperlinksEquals(null, null), isTrue);
    });

    test('片方だけ null は false', () {
      expect(paneHyperlinksEquals(_linkA, null), isFalse);
      expect(paneHyperlinksEquals(null, _linkA), isFalse);
    });

    test('frameWidth/frameHeight/truncated の違いを検出する', () {
      const other = PaneHyperlinks(
        frameWidth: 81,
        frameHeight: 24,
        links: [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 5)],
          ),
        ],
        rowFingerprints: {0: '9f1c000000000000'},
      );
      expect(paneHyperlinksEquals(_linkA, other), isFalse);
    });

    test('links の中身（url・range）が同じなら別インスタンスでも true', () {
      const other = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 24,
        links: [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 5)],
          ),
        ],
        rowFingerprints: {0: '9f1c000000000000'},
      );
      expect(paneHyperlinksEquals(_linkA, other), isTrue);
    });

    test('range の範囲が違えば false', () {
      const other = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 24,
        links: [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 6)],
          ),
        ],
        rowFingerprints: {0: '9f1c000000000000'},
      );
      expect(paneHyperlinksEquals(_linkA, other), isFalse);
    });

    test('rowFingerprints の値が違えば false', () {
      const other = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 24,
        links: [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 5)],
          ),
        ],
        rowFingerprints: {0: 'ffffffffffffffff'},
      );
      expect(paneHyperlinksEquals(_linkA, other), isFalse);
    });

    test('links の件数が違えば false', () {
      const other = PaneHyperlinks(frameWidth: 80, frameHeight: 24);
      expect(paneHyperlinksEquals(_linkA, other), isFalse);
    });
  });
}

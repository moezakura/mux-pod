// PaneHyperlink 系の値オブジェクトと PaneFrame.toSnapshot() の伝搬を
// 検証する（herdr OSC 8 ハイパーリンク実験機能）。
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaneHyperlinkRange / PaneHyperlink / PaneHyperlinks', () {
    test('既定値は空のリンク一覧・フィンガープリント・truncated=false', () {
      const hyperlinks = PaneHyperlinks(frameWidth: 80, frameHeight: 24);
      expect(hyperlinks.links, isEmpty);
      expect(hyperlinks.rowFingerprints, isEmpty);
      expect(hyperlinks.truncated, isFalse);
    });

    test('値を保持する（行またぎリンクの複数 range を含む）', () {
      const hyperlinks = PaneHyperlinks(
        frameWidth: 120,
        frameHeight: 40,
        truncated: true,
        links: [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [
              PaneHyperlinkRange(row: 3, startCol: 10, endCol: 24),
              PaneHyperlinkRange(row: 4, startCol: 0, endCol: 5),
            ],
          ),
        ],
        rowFingerprints: {3: '9f1c000000000000', 4: '03ab000000000000'},
      );
      expect(hyperlinks.frameWidth, 120);
      expect(hyperlinks.frameHeight, 40);
      expect(hyperlinks.truncated, isTrue);
      expect(hyperlinks.links, hasLength(1));
      expect(hyperlinks.links.single.url, 'https://example.com/');
      expect(hyperlinks.links.single.ranges, hasLength(2));
      expect(hyperlinks.links.single.ranges.first.row, 3);
      expect(hyperlinks.links.single.ranges.first.startCol, 10);
      expect(hyperlinks.links.single.ranges.first.endCol, 24);
      expect(hyperlinks.rowFingerprints[3], '9f1c000000000000');
      expect(hyperlinks.rowFingerprints[4], '03ab000000000000');
    });
  });

  group('PaneFrame.hyperlinks / toSnapshot()', () {
    test('未指定なら null（既存 tmux / caret 経路に影響しない）', () {
      const frame = PaneFrame(content: 'hello');
      expect(frame.hyperlinks, isNull);
      final snapshot = frame.toSnapshot();
      expect(snapshot.hyperlinks, isNull);
      // 既存の項目（content/geometry/cursor/paneMode/hasAnsi/caret）は無変更。
      expect(snapshot.content, 'hello');
      expect(snapshot.caret, isNull);
    });

    test('hyperlinks が toSnapshot() でそのまま伝搬する', () {
      const hyperlinks = PaneHyperlinks(frameWidth: 80, frameHeight: 24);
      const frame = PaneFrame(content: 'hello', hyperlinks: hyperlinks);
      final snapshot = frame.toSnapshot();
      expect(snapshot.hyperlinks, same(hyperlinks));
    });

    test('caret と hyperlinks が両方指定されても互いに独立して伝搬する', () {
      const caret = PaneCaret(x: 1, y: 2, visible: true);
      const hyperlinks = PaneHyperlinks(frameWidth: 80, frameHeight: 24);
      const frame = PaneFrame(
        content: 'hello',
        caret: caret,
        hyperlinks: hyperlinks,
      );
      final snapshot = frame.toSnapshot();
      expect(snapshot.caret, same(caret));
      expect(snapshot.hyperlinks, same(hyperlinks));
    });
  });
}

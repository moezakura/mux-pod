// inventory: HERDR-FRAME-TEST-000
/// herdr_pane_frame_reader.dart のテスト（herdr OSC 8 ハイパーリンク実験
/// 機能）。
///
/// [HerdrHyperlinkReader] の fake を注入し、`PaneReadPurpose.live` の読込
/// でのみ呼ばれること（`PaneReadPurpose.scrollback` では呼ばれないこと）、
/// best-effort（例外は caret / content / geometry に影響させない）を検証する。
library;

import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_read.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

/// [HerdrAdapter.paneRead] の応答を差し込む fake。
class _FakeAdapter extends HerdrAdapter {
  _FakeAdapter() : super(FakeSshClient());

  HerdrPaneContent content = const HerdrPaneContent(
    lines: ['line1'],
    rawText: 'line1',
    hasAnsi: false,
  );

  @override
  Future<HerdrPaneContent> paneRead(
    String paneId, {
    String source = 'recent',
    int? lines,
    bool ansi = false,
    bool viaPersistent = false,
    Duration? timeout,
  }) async => content;
}

/// geometry を固定で返す fake（layout 解決は本テストの対象外）。
class _FakeLayoutResolver implements PaneLayoutResolver {
  PaneGeometry? geometry = const PaneGeometry(width: 100, height: 30);

  @override
  Future<PaneGeometry?> resolve(String paneId) async => geometry;
}

/// [HerdrHyperlinkReader] の fake。呼び出し回数・引数・戻り値・例外を
/// 差し替えられる。
class _FakeHyperlinkReader implements HerdrHyperlinkReader {
  int calls = 0;
  final List<String> paneIds = [];
  final List<int> colsSeen = [];
  final List<int> rowsSeen = [];
  PaneHyperlinks? result = const PaneHyperlinks(
    frameWidth: 100,
    frameHeight: 30,
  );
  Object? error;

  @override
  Future<PaneHyperlinks?> read({
    required String paneId,
    required int cols,
    required int rows,
  }) async {
    calls++;
    paneIds.add(paneId);
    colsSeen.add(cols);
    rowsSeen.add(rows);
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

void main() {
  group('通常表示のハイパーリンク', () {
    test('purpose == live のときだけ hyperlinkReader を呼ぶ', () async {
      final adapter = _FakeAdapter();
      final layout = _FakeLayoutResolver();
      final hyperlinkReader = _FakeHyperlinkReader();
      final frameReader = HerdrPaneFrameReader(
        adapter,
        layout,
        hyperlinkReader: hyperlinkReader,
      );

      final frame = await frameReader.read(
        const PaneFrameRequest(
          PaneReadRequest(
            paneId: 'w1:p1',
            purpose: PaneReadPurpose.live,
            maxLines: 120,
          ),
        ),
      );

      expect(hyperlinkReader.calls, 1);
      expect(hyperlinkReader.paneIds, ['w1:p1']);
      expect(hyperlinkReader.colsSeen, [100]);
      expect(hyperlinkReader.rowsSeen, [30]);
      expect(frame.hyperlinks, isNotNull);
      expect(frame.hyperlinks!.frameWidth, 100);
    });

    test('purpose == scrollback では hyperlinkReader を呼ばない', () async {
      final adapter = _FakeAdapter();
      final layout = _FakeLayoutResolver();
      final hyperlinkReader = _FakeHyperlinkReader();
      final frameReader = HerdrPaneFrameReader(
        adapter,
        layout,
        hyperlinkReader: hyperlinkReader,
      );

      final frame = await frameReader.read(
        const PaneFrameRequest(
          PaneReadRequest(
            paneId: 'w1:p1',
            purpose: PaneReadPurpose.scrollback,
            maxLines: 100000,
          ),
        ),
      );

      expect(hyperlinkReader.calls, 0);
      expect(frame.hyperlinks, isNull);
    });

    test(
      'hyperlinkReader 未注入では hyperlinks は null のまま（content/geometry は影響なし）',
      () async {
        final adapter = _FakeAdapter();
        final layout = _FakeLayoutResolver();
        final frameReader = HerdrPaneFrameReader(adapter, layout);

        final frame = await frameReader.read(
          const PaneFrameRequest(
            PaneReadRequest(
              paneId: 'w1:p1',
              purpose: PaneReadPurpose.live,
              maxLines: 120,
            ),
          ),
        );

        expect(frame.hyperlinks, isNull);
        expect(frame.content, 'line1');
      },
    );

    test(
      'hyperlinkReader が例外を投げても content/geometry/caret には影響しない（best-effort）',
      () async {
        final adapter = _FakeAdapter();
        final layout = _FakeLayoutResolver();
        final hyperlinkReader = _FakeHyperlinkReader()
          ..error = StateError('boom');
        final frameReader = HerdrPaneFrameReader(
          adapter,
          layout,
          hyperlinkReader: hyperlinkReader,
        );

        final frame = await frameReader.read(
          const PaneFrameRequest(
            PaneReadRequest(
              paneId: 'w1:p1',
              purpose: PaneReadPurpose.live,
              maxLines: 120,
            ),
          ),
        );

        expect(frame.hyperlinks, isNull);
        expect(frame.content, 'line1');
        expect(frame.geometry, isNotNull);
      },
    );

    test('geometry 未解決時は既定サイズ（80x24）で hyperlinkReader を呼ぶ', () async {
      final adapter = _FakeAdapter();
      final layout = _FakeLayoutResolver()..geometry = null;
      final hyperlinkReader = _FakeHyperlinkReader();
      final frameReader = HerdrPaneFrameReader(
        adapter,
        layout,
        hyperlinkReader: hyperlinkReader,
      );

      await frameReader.read(
        const PaneFrameRequest(
          PaneReadRequest(
            paneId: 'w1:p1',
            purpose: PaneReadPurpose.live,
            maxLines: 120,
          ),
        ),
      );

      expect(hyperlinkReader.colsSeen, [80]);
      expect(hyperlinkReader.rowsSeen, [24]);
    });

    test('geometry.width が 80 未満のときは 80 へ引き上げて hyperlinkReader を呼ぶ'
        '（caret の _fetchCaret と同じ下限を適用する）', () async {
      final adapter = _FakeAdapter();
      final layout = _FakeLayoutResolver()
        ..geometry = const PaneGeometry(width: 54, height: 30);
      final hyperlinkReader = _FakeHyperlinkReader();
      final frameReader = HerdrPaneFrameReader(
        adapter,
        layout,
        hyperlinkReader: hyperlinkReader,
      );

      await frameReader.read(
        const PaneFrameRequest(
          PaneReadRequest(
            paneId: 'w1:p1',
            purpose: PaneReadPurpose.live,
            maxLines: 120,
          ),
        ),
      );

      expect(hyperlinkReader.colsSeen, [80]);
    });

    test('geometry の width・height がともに 0 のときは hyperlinkReader を呼ばない'
        '（v0.7.5 で client が一度も attach していない間は rect/area が'
        '0x0 になる）', () async {
      final adapter = _FakeAdapter();
      final layout = _FakeLayoutResolver()
        ..geometry = const PaneGeometry(width: 0, height: 0);
      final hyperlinkReader = _FakeHyperlinkReader();
      final frameReader = HerdrPaneFrameReader(
        adapter,
        layout,
        hyperlinkReader: hyperlinkReader,
      );

      await frameReader.read(
        const PaneFrameRequest(
          PaneReadRequest(
            paneId: 'w1:p1',
            purpose: PaneReadPurpose.live,
            maxLines: 120,
          ),
        ),
      );

      expect(
        hyperlinkReader.calls,
        0,
        reason: '0x0 の geometry では helper を呼ばないこと（下限適用でマスクしない）',
      );
    });
  });
}

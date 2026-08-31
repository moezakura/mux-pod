// inventory: HERDR-CARET-SNAPSHOT-TEST-000
/// herdr_caret_snapshot.dart の単体テスト。
///
/// fromHelperJson（正常・(0,0) 正当・visible:false・cursor:null・破損 JSON・
/// cursor 非 object・範囲外座標・protocol 拒否・paneId 不一致・paneId 書式
/// 検証）と isValidPaneId を検証する。
library;

import 'dart:convert';

import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// helper stdout の JSON を組み立てる。
String helperJson({
  Object? cursor = const {'x': 5, 'y': 3, 'visible': true, 'shape': 0},
  int frameWidth = 80,
  int frameHeight = 24,
  int protocolVersion = 17,
  String paneId = 'w1:p1',
}) => jsonEncode({
  'cursor': cursor,
  'frameWidth': frameWidth,
  'frameHeight': frameHeight,
  'protocolVersion': protocolVersion,
  'paneId': paneId,
});

final fixedAt = DateTime(2026, 1, 1, 12, 0, 0);

void main() {
  group('fromHelperJson', () {
    test('正常: cursor 有りをパースする', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(),
        expectedPaneId: 'w1:p1',
        capturedAt: fixedAt,
      );
      expect(snap.x, 5);
      expect(snap.y, 3);
      expect(snap.visible, isTrue);
      expect(snap.shape, 0);
      expect(snap.frameWidth, 80);
      expect(snap.frameHeight, 24);
      expect(snap.protocolVersion, 17);
      expect(snap.paneId, 'w1:p1');
      expect(snap.capturedAt, fixedAt);
      expect(snap.hasPosition, isTrue);
      expect(snap.isHidden, isFalse);
    });

    test('(0, 0) は位置不明ではなく正当な座標として扱う', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(cursor: const {'x': 0, 'y': 0, 'visible': true, 'shape': 0}),
        expectedPaneId: 'w1:p1',
      );
      expect(snap.x, 0);
      expect(snap.y, 0);
      expect(snap.hasPosition, isTrue);
    });

    test('visible: false は非表示として扱う', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(
          cursor: const {'x': 1, 'y': 1, 'visible': false, 'shape': 0},
        ),
        expectedPaneId: 'w1:p1',
      );
      expect(snap.visible, isFalse);
      expect(snap.isHidden, isTrue);
    });

    test('cursor: null は非表示カーソル（x/y は null・visible false）', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(cursor: null),
        expectedPaneId: 'w1:p1',
      );
      expect(snap.x, isNull);
      expect(snap.y, isNull);
      expect(snap.visible, isFalse);
      expect(snap.shape, 0);
      expect(snap.hasPosition, isFalse);
      // frame 情報は通常どおり残る
      expect(snap.frameWidth, 80);
      expect(snap.frameHeight, 24);
    });

    test('破損 JSON は FormatException', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          'not json',
          expectedPaneId: 'w1:p1',
        ),
        throwsFormatException,
      );
    });

    test('JSON object でないものは FormatException', () {
      expect(
        () =>
            HerdrCaretSnapshot.fromHelperJson('[1,2]', expectedPaneId: 'w1:p1'),
        throwsFormatException,
      );
    });

    test('cursor が object / null 以外は FormatException', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(cursor: 5),
          expectedPaneId: 'w1:p1',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cursor'),
          ),
        ),
      );
    });

    test('範囲外座標（u16 超）は FormatException', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(
            cursor: const {
              'x': kHerdrCaretU16Max + 1,
              'y': 0,
              'visible': true,
              'shape': 0,
            },
          ),
          expectedPaneId: 'w1:p1',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('x'),
          ),
        ),
      );
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(
            cursor: const {'x': 0, 'y': -1, 'visible': true, 'shape': 0},
          ),
          expectedPaneId: 'w1:p1',
        ),
        throwsFormatException,
      );
    });

    test('u16 上限ちょうど（0xFFFF）は許容する', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(
          cursor: const {
            'x': kHerdrCaretU16Max,
            'y': kHerdrCaretU16Max,
            'visible': true,
            'shape': 0,
          },
        ),
        expectedPaneId: 'w1:p1',
      );
      expect(snap.x, kHerdrCaretU16Max);
      expect(snap.y, kHerdrCaretU16Max);
    });

    test('shape が u8 超は FormatException', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(
            cursor: const {
              'x': 0,
              'y': 0,
              'visible': true,
              'shape': kHerdrCaretShapeMax + 1,
            },
          ),
          expectedPaneId: 'w1:p1',
        ),
        throwsFormatException,
      );
    });

    test('protocolVersion 18 は拒否（17/20 のみ）', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(protocolVersion: 18),
          expectedPaneId: 'w1:p1',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('protocolVersion'),
          ),
        ),
      );
    });

    test('protocolVersion 20 は許容する', () {
      final snap = HerdrCaretSnapshot.fromHelperJson(
        helperJson(protocolVersion: 20),
        expectedPaneId: 'w1:p1',
      );
      expect(snap.protocolVersion, 20);
    });

    test('paneId 不一致は FormatException（stale 検出）', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(paneId: 'w1:p2'),
          expectedPaneId: 'w1:p1',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Pane id mismatch'),
          ),
        ),
      );
    });

    test('paneId が空は FormatException', () {
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(paneId: ''),
          expectedPaneId: '',
        ),
        throwsFormatException,
      );
    });

    test('paneId が 65 文字は FormatException', () {
      final longPaneId = 'a' * 65;
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(paneId: longPaneId),
          expectedPaneId: longPaneId,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('paneId'),
          ),
        ),
      );
    });

    test('paneId に制御文字が含まれる場合は FormatException', () {
      const ctlPaneId = 'w1:p\x01';
      expect(
        () => HerdrCaretSnapshot.fromHelperJson(
          helperJson(paneId: ctlPaneId),
          expectedPaneId: ctlPaneId,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('paneId'),
          ),
        ),
      );
    });
  });

  group('isValidPaneId', () {
    test('通常の paneId（w1:p1）は true', () {
      expect(HerdrCaretSnapshot.isValidPaneId('w1:p1'), isTrue);
      expect(HerdrCaretSnapshot.isValidPaneId('w12:p3'), isTrue);
    });

    test('空文字列は false', () {
      expect(HerdrCaretSnapshot.isValidPaneId(''), isFalse);
    });

    test('65 文字以上は false', () {
      expect(HerdrCaretSnapshot.isValidPaneId('a' * 64), isTrue);
      expect(HerdrCaretSnapshot.isValidPaneId('a' * 65), isFalse);
    });

    test('制御文字は false（0x20 未満・0x7E 超）', () {
      expect(HerdrCaretSnapshot.isValidPaneId('w1:p\x01'), isFalse);
      expect(HerdrCaretSnapshot.isValidPaneId('w1:p\x7F'), isFalse);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';

void main() {
  group('HerdrRowFingerprint (共有テストベクタ)', () {
    // Rust 側 tools/herdr-caret-helper/src/tracker.rs::row_fingerprint と
    // バイト単位で同じ値になることを、共通テストベクタで検証する。
    final vectorsFile = File(
      'tools/herdr-caret-helper/testdata/fingerprint_vectors.json',
    );

    test('共有テストベクタの全ケースで Rust 実装と同じ値を返す', () {
      final raw = vectorsFile.readAsStringSync();
      final vectors = jsonDecode(raw) as List<dynamic>;
      expect(vectors, isNotEmpty);

      for (final entry in vectors) {
        final map = entry as Map<String, dynamic>;
        final caseName = map['case'] as String;
        final displayText = map['displayText'] as String;
        final expected = map['fingerprint'] as String?;

        final actual = HerdrRowFingerprint.rowFingerprint(displayText);
        expect(
          actual,
          expected,
          reason: 'case "$caseName" の displayText=$displayText で不一致',
        );
      }
    });

    test('well-known FNV-1a-64 reference vectors と一致する', () {
      // http://www.isthe.com/chongo/tech/comp/fnv/（Rust 側テストと同じ参照値）。
      expect(
        HerdrRowFingerprint.fnv1a64Hex(utf8.encode('')),
        'cbf29ce484222325',
      );
      expect(
        HerdrRowFingerprint.fnv1a64Hex(utf8.encode('a')),
        'af63dc4c8601ec8c',
      );
      expect(
        HerdrRowFingerprint.fnv1a64Hex(utf8.encode('foobar')),
        '85944171f73967e8',
      );
    });

    test('末尾の半角スペースのみを除去し、除去後に空なら null', () {
      expect(HerdrRowFingerprint.rowFingerprint('   '), isNull);
      expect(HerdrRowFingerprint.rowFingerprint(''), isNull);
      expect(
        HerdrRowFingerprint.rowFingerprint('hello  '),
        HerdrRowFingerprint.rowFingerprint('hello'),
      );
      // タブは対象外（半角スペースのみ除去）。
      expect(
        HerdrRowFingerprint.rowFingerprint('hello\t'),
        isNot(HerdrRowFingerprint.rowFingerprint('hello')),
      );
    });
  });

  group('alignFrameRowToBodyLine', () {
    test('k=0・a=0 で末尾一致のとき frame 行と body 行が 1:1 対応する', () {
      // L=5, R=5, a=0, k=0 → r=i の恒等対応になる。
      for (var r = 0; r < 5; r++) {
        final i = alignFrameRowToBodyLine(
          frameRow: r,
          frameRows: 5,
          windowOffset: 0,
          bodyLineCount: 5,
          k: 0,
        );
        expect(i, r);
      }
    });

    test('範囲外（k による補正で本文行数を超える）は null', () {
      final i = alignFrameRowToBodyLine(
        frameRow: 0,
        frameRows: 3,
        windowOffset: 0,
        bodyLineCount: 5,
        k: 100,
      );
      expect(i, isNull);
    });
  });

  group('resolveHerdrHyperlinkAlignment（多数決）', () {
    test('出力が流れていない（k=0）とき、末尾一致から k=0 を採用する', () {
      final body = ['b0', 'b1', 'b2', 'b3', 'b4'];
      final frame = ['b0', 'b1', 'b2', 'b3', 'b4'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, 0);
    });

    test('本文読取後にk行分の出力が流れた場合、多数決で k を正しく推定する', () {
      // body 読取時点: a,b,c,d,e,f,g,h（L=8）。
      // その後 i,j が新たに流れ、frame（R=6,a=0）は e,f,g,h,i,j を表示する。
      // e,f,g,h は body 内で見つかるため、そこから k=2 が多数決で決まる。
      // i,j は body に無いため投票に寄与しない（マッチなし）。
      final body = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final frame = ['e', 'f', 'g', 'h', 'i', 'j'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, 2);
    });

    test('末尾の空行（null フィンガープリント）は投票対象から除外される', () {
      final body = ['b0', 'b1', 'b2', 'b3', 'b4'];
      // 末尾行は空行（フレームの末尾に空行が残っている状態を模す）。
      final frame = ['b0', 'b1', 'b2', 'b3', null];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      // 空でない行数は 4。4 行すべてが k=0 に投票し、閾値
      // （50%以上かつ min(3,4)=3以上）と 2 位無しの条件を満たす。
      expect(result, isNotNull);
      expect(result!.k, 0);
    });

    test('本文中に9回以上出現するフィンガープリントは投票に使わない', () {
      // 'rep' を body 中に 9 回置き、残り 1 行だけを一意な内容にする。
      final body = List<String>.filled(9, 'rep') + ['unique4'];
      // frame は 'rep' 1 行 + 'unique4' に対応する行の 2 行構成。
      // 'rep' は 9 回以上出現するため投票から除外され、'unique4' 側の
      // 1 票だけで多数決が行われる。
      final frame = ['rep', 'unique4'];

      // frame row 0 ('rep') は windowOffset=0, frameRows=2 のとき d=1。
      // frame row 1 ('unique4') は d=0。body の 'unique4' は index 9。
      // k = i - (L-1-d) = 9 - (9-0) = 0 （L=10）。
      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      // 'rep' 由来の（除外されなければ複数の）票が無いため、'unique4' の
      // 1 票のみが候補になる。非空行数2・min(3,2)=2 のため 1 票では
      // 閾値（top>=2）を満たさず、整列は失敗する。
      expect(result, isNull);
    });

    test('得票が僅少（空でない行数に対する閾値未達）のときは抑制される', () {
      // 非空行数2、うち1行だけ本文に一致 → top=1 < min(3,2)=2 で抑制。
      final body = ['x0', 'x1', 'match', 'x3'];
      final frame = ['match', 'nomatch'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('本文中の同一内容の複数出現から複数の k 候補が生じても、同点でなければ多数決で決まる', () {
      // body に同じ内容の行を異なる位置に2つ用意し、frame の当該行が
      // どちらの位置にもマッチする状況を作る。
      // body: ['same','x1','x2','same'] → 'same' は 2 回出現（9回未満なので
      // 投票対象）。frame 1 行だけが 'same' に一致すると、body 中の 2 つの
      // 出現それぞれから異なる k 候補に票が入る。
      final body = ['same', 'x1', 'x2', 'same'];
      final frame = ['same', 'x1', 'x2'];

      // frame row0='same' は body index0 と index3 の両方にマッチ →
      // 2 つの異なる k 候補にそれぞれ 1 票。
      // frame row1='x1' は body index1 にマッチ → その k に 1 票。
      // frame row2='x2' は body index2 にマッチ → その k に 1 票。
      // windowOffset=0, frameRows=3: d(r)=2-r → r0:d2,r1:d1,r2:d0。
      // L=4なので L-1-d: r0→1, r1→2, r2→3。
      // row0: i=0→k=0-1=-1、i=3→k=3-1=2。
      // row1: i=1→k=1-2=-1。
      // row2: i=2→k=2-3=-1。
      // k=-1 の得票: row0(i=0の分)+row1+row2 = 3。k=2 の得票: row0(i=3の分)=1。
      // 3 対 1 で同点にならず、k=-1 が採用される（同点ケースは次のテストで
      // 別構成により検証する）。
      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, -1);
    });

    test('候補の得票が完全に同数のときは全抑制する（同点ケース）', () {
      // frame の全ての非空行が、body 中で「異なる k」を指す 2 箇所に
      // ちょうど同数だけマッチする状況を作る。
      // body 全体を 2 行の繰り返し（'p','q'）にし、frame も 'p','q' の
      // 2 行にすると、'p' は body 中に複数出現し、それぞれ異なる k を
      // 指す票を生む。9 回未満に保つため body は 4 行構成とする。
      final body = ['p', 'q', 'p', 'q'];
      final frame = ['p', 'q'];

      // windowOffset=0, frameRows=2: d(r)=1-r → r0:d1,r1:d0。L=4→L-1-d:
      // r0(d=1)→2, r1(d=0)→3。
      // row0='p': body 'p' は index0,2 に出現 → k=0-2=-2, k=2-2=0。
      // row1='q': body 'q' は index1,3 に出現 → k=1-3=-2, k=3-3=0。
      // k=-2 の得票: row0(1)+row1(1)=2。k=0 の得票: row0(1)+row1(1)=2。
      // 同点のため抑制される。
      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('窓が本文の範囲から完全に外れている場合は整列失敗（null）', () {
      final body = ['b0', 'b1', 'b2'];
      final frame = ['nomatch0', 'nomatch1'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('フレームの空でない行が0件のときは null', () {
      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: ['b0', 'b1'],
        frameFingerprints: [null, null],
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('本文中に8回出現する行は投票に使われ、9回では除外される（同一構成・出現回数のみ変更）', () {
      // frame: 繰り返し行 'rep' が 3 行 + 末尾に一致する一意な行 'tailU'。
      // 'rep' は body 中で連続 8/9 回出現し、末尾一致（d=0 の行）の 'tailU' は
      // 常に k=0 に 1 票入る。
      //
      // 8 回（9回未満）: 投票対象になり、'rep' の対角上の一致から k=0 に
      // 追加で 3 票入って合計 4 票（他の候補は最大 3 票）になり、一意な最多
      // 得票として整列が成功する。
      // 9 回: 投票から完全除外され、'tailU' の 1 票だけでは 50% 閾値
      // （空でない行 4・2*1<4）を満たせず整列は失敗する。
      final frame = ['rep', 'rep', 'rep', 'tailU'];

      final body8 = List<String>.filled(8, 'rep') + ['tailU'];
      final result8 = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body8,
        frameFingerprints: frame,
        windowOffset: 0,
      );
      expect(result8, isNotNull);
      expect(result8!.k, 0);

      final body9 = List<String>.filled(9, 'rep') + ['tailU'];
      final result9 = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body9,
        frameFingerprints: frame,
        windowOffset: 0,
      );
      expect(result9, isNull);
    });

    test('50%閾値のちょうど境界: 空でない行8・得票3は抑制、空でない行6・得票3は採用', () {
      // 前半3行 'm0'/'m1'/'m2' は body の同じ位置と一致し（k=0 に3票）、
      // 残りはどの body 行とも一致しない一意な「雑音」フィンガープリント
      // （0票・ただし空でない行数には数える）。
      final body8 = ['m0', 'm1', 'm2', 'b3', 'b4', 'b5', 'b6', 'b7'];
      final frame8 = ['m0', 'm1', 'm2', 'n0', 'n1', 'n2', 'n3', 'n4'];
      final result8 = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body8,
        frameFingerprints: frame8,
        windowOffset: 0,
      );
      // 2*3=6 < 8 のため抑制される。
      expect(result8, isNull);

      final body6 = ['m0', 'm1', 'm2', 'b3', 'b4', 'b5'];
      final frame6 = ['m0', 'm1', 'm2', 'n0', 'n1', 'n2'];
      final result6 = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body6,
        frameFingerprints: frame6,
        windowOffset: 0,
      );
      // 2*3=6 >= 6 かつ min(3,6)=3 <= 3 のため採用される（k=0）。
      expect(result6, isNotNull);
      expect(result6!.k, 0);
    });

    test('min(3, 空でない行数) 条件のみで抑制される（空でない行4・得票2）', () {
      // 50%条件（2*2=4>=4）は満たすが、min(3,4)=3 に対して得票2は不足する。
      final body = ['m0', 'm1', 'b2', 'b3'];
      final frame = ['m0', 'm1', 'n0', 'n1'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('windowOffset（a）> 0 でも正しい k が採用される（スクロールモードの窓）', () {
      // a=10、本文50行、frame 5行が本文の index 37..41 に対応する構成で
      // k=2 が採用されることを検証する（窓が本文の末尾より手前にある場合）。
      final body = List<String>.generate(50, (i) => 'r$i');
      final frame = ['r37', 'r38', 'r39', 'r40', 'r41'];

      final result = resolveHerdrHyperlinkAlignment(
        bodyFingerprints: body,
        frameFingerprints: frame,
        windowOffset: 10,
      );

      expect(result, isNotNull);
      expect(result!.k, 2);
    });
  });

  group('resolveHerdrHyperlinkAlignedLinks（frameWidth 検証・整列・行単位の抑制の合成）', () {
    test('frameWidth が 0 以下（壊れたデータ）なら null（整列失敗。'
        'helper が実 pty サイズを優先するため「依頼幅との一致」は見ず、'
        'frameWidth の妥当性チェックのみ行う。fingerprint が一致していても frameWidth '
        'そのものが壊れていれば抑制する）', () {
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u')],
        },
        bodyFingerprints: ['line0'],
        frameFingerprints: ['line0'],
        frameWidth: 0,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('frameWidth が依頼幅（expectedWidth 相当）と違っても、fingerprint '
        'が一致していれば抑制されない'
        '（「依頼幅との一致」は見ない）', () {
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u')],
        },
        bodyFingerprints: ['line0'],
        frameFingerprints: ['line0'],
        frameWidth: 100,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.linksByBodyLine[0]!.single.url, 'u');
    });

    test('整列できない窓は null（整列失敗）', () {
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u')],
        },
        bodyFingerprints: ['line0'],
        frameFingerprints: ['completely-different'],
        frameWidth: 80,
        windowOffset: 0,
      );

      expect(result, isNull);
    });

    test('整列成功時、採用した k と本文行番号へ変換されたリンクを返す', () {
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [
            HerdrHyperlinkRange(startCol: 6, endCol: 9, url: 'https://x/'),
          ],
        },
        bodyFingerprints: ['click here for more'],
        frameFingerprints: ['click here for more'],
        frameWidth: 80,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, 0);
      expect(result.linksByBodyLine.keys, [0]);
      expect(result.linksByBodyLine[0]!.single.url, 'https://x/');
    });

    test('整列後に行単位でフィンガープリントが不一致ならその行のリンクだけ除外する', () {
      // row0-2 は本文と一致し、この3票（空でない行4に対して min(3,4)=3）で
      // 整列自体は成功する（k=0）。row3 は対応する本文行（'old-content'）と
      // 食い違う内容（別時刻に書き換わった想定）のため、row3 のリンクだけが
      // 行単位で除外される。
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u0')],
          3: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u3')],
        },
        bodyFingerprints: ['anchor0', 'anchor1', 'anchor2', 'old-content'],
        frameFingerprints: ['anchor0', 'anchor1', 'anchor2', 'new-content'],
        frameWidth: 80,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, 0);
      expect(result.linksByBodyLine.keys, [0]);
      expect(result.linksByBodyLine[0]!.single.url, 'u0');
    });

    test('窓が本文の範囲から一部外れる場合、範囲外に対応する行のリンクだけ除外する', () {
      // frameRows=4, windowOffset=0, bodyLineCount=3。
      // row1..3 は body の 'b0'/'b1'/'b2' と一致し、いずれも k=0 に投票する
      // （3票・空でない行4に対して min(3,4)=3 を満たし採用される）。
      // row0 は本文に無い一意な内容（投票に寄与しない）で、採用された k=0 の
      // もとでは i=-1（本文の範囲外）に対応づけられるため、row0 のリンクだけ
      // 結果から除外される。
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: {
          0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'out')],
          1: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u1')],
          2: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u2')],
          3: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u3')],
        },
        bodyFingerprints: ['b0', 'b1', 'b2'],
        frameFingerprints: ['zzz-no-match', 'b0', 'b1', 'b2'],
        frameWidth: 80,
        windowOffset: 0,
      );

      expect(result, isNotNull);
      expect(result!.k, 0);
      expect(result.linksByBodyLine.keys.toSet(), {0, 1, 2});
      expect(result.linksByBodyLine[0]!.single.url, 'u1');
      expect(result.linksByBodyLine[1]!.single.url, 'u2');
      expect(result.linksByBodyLine[2]!.single.url, 'u3');
    });
  });
  group('拒否された窓（truncated・links 空・rowHashes 空）', () {
    // helper は描画内容を拒否した窓を links 空・rowHashes 空・
    // truncated: true で返す。その窓は例外を出さず、リンクを一切出さない
    // （reader の _alignWindow と同じ組み替え: frameFingerprints は全て
    // null、frameLinksByRow は空）。
    test('フレーム側の指紋が全て null なら整列されずリンクは出ない', () {
      final result = resolveHerdrHyperlinkAlignedLinks(
        frameLinksByRow: const {},
        bodyFingerprints: ['b0', 'b1', 'b2'],
        frameFingerprints: List<String?>.filled(24, null),
        frameWidth: 80,
        windowOffset: 0,
      );

      expect(result == null || result.linksByBodyLine.isEmpty, isTrue);
    });
  });
}

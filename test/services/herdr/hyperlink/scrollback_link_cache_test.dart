/// scrollback_link_cache.dart のテスト。
library;

import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('初期状態は空', () {
    final cache = ScrollbackLinkCache();
    expect(cache.identity, isNull);
    expect(cache.generation, isNull);
    expect(cache.linksByBodyLine, isEmpty);
    expect(cache.lastK, isNull);
    expect(cache.lastFrameRows, isNull);
    expect(cache.hasFetched(0), isFalse);
    expect(cache.revision, 0);
  });

  test('applyWindowResult の frameRows が正の値なら lastFrameRows を更新する'
      '（helper が実 pty サイズを優先するため、次回の'
      '窓タイリング（R）の見積りに使う。lastK と同じ仕組み）', () {
    final cache = ScrollbackLinkCache();
    final idA = Object();
    cache.resetIfNeeded(identity: idA, generation: 1);

    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: 17,
    );
    expect(cache.lastFrameRows, 17);
    expect(cache.revision, 2); // resetIfNeeded(1) + この更新(1)

    // 同じ offsetFromBottom を使い回し、revision の増分を frameRows の
    // 変化だけに起因させる（offset の新規追加自体も changed に寄与する
    // ため）。0 以下や null は「分からなかった」として前回の値を保持する。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: 0,
    );
    expect(cache.lastFrameRows, 17);
    expect(cache.revision, 2); // 変化なし

    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: null,
    );
    expect(cache.lastFrameRows, 17);
    expect(cache.revision, 2); // 変化なし

    // 新しい値に変われば更新し revision も増える。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: 22,
    );
    expect(cache.lastFrameRows, 22);
    expect(cache.revision, 3);
  });

  test('lastFrameRows は resetIfNeeded・clear でリセットされる', () {
    final cache = ScrollbackLinkCache();
    final idA = Object();
    final idB = Object();
    cache.resetIfNeeded(identity: idA, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: 17,
    );
    expect(cache.lastFrameRows, 17);

    cache.resetIfNeeded(identity: idB, generation: 1);
    expect(cache.lastFrameRows, isNull);

    cache.resetIfNeeded(identity: idB, generation: 2);
    cache.applyWindowResult(
      generation: 2,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
      frameRows: 30,
    );
    expect(cache.lastFrameRows, 30);

    cache.clear();
    expect(cache.lastFrameRows, isNull);
  });

  test('resetIfNeeded は identity・generation のどちらかが変わったときだけ破棄する', () {
    final cache = ScrollbackLinkCache();
    final idA = Object();
    final idB = Object();

    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
    );
    // generation 未設定（null）のときの applyWindowResult は無視される
    // （resetIfNeeded を先に呼ぶのが前提のため、ここでは空のまま）。
    expect(cache.linksByBodyLine, isEmpty);

    cache.resetIfNeeded(identity: idA, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
      k: 2,
    );
    expect(cache.identity, same(idA));
    expect(cache.generation, 1);
    expect(cache.linksByBodyLine[0], isNotEmpty);
    expect(cache.hasFetched(0), isTrue);
    expect(cache.lastK, 2);

    // identity・generation とも同じなら破棄しない（冪等）。
    cache.resetIfNeeded(identity: idA, generation: 1);
    expect(cache.linksByBodyLine[0], isNotEmpty);

    // generation は同じだが identity だけが変わる
    // （controller の作り直し・再接続で番号が偶然一致する場合）
    // → 破棄する。
    cache.resetIfNeeded(identity: idB, generation: 1);
    expect(cache.identity, same(idB));
    expect(cache.generation, 1);
    expect(cache.linksByBodyLine, isEmpty);
    expect(cache.hasFetched(0), isFalse);
    expect(cache.lastK, isNull);

    // identity は同じで generation だけが変わる → 破棄する。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
    );
    cache.resetIfNeeded(identity: idB, generation: 2);
    expect(cache.identity, same(idB));
    expect(cache.generation, 2);
    expect(cache.linksByBodyLine, isEmpty);
  });

  test('resetIfNeeded は、別々に作られた同じ値の identity（record）では破棄しない'
      '（本番の HerdrTargetIdentity は呼び出しの'
      'たびに新しい record インスタンスが作られるため identical は使えない）', () {
    final cache = ScrollbackLinkCache();
    // 本番の HerdrTargetIdentity（herdr_types.dart）は
    // ({HerdrSnapshotCache cache, int epoch, String? paneId}) の record で、
    // HerdrController.captureIdentity() は呼び出しのたびに新しいインスタンス
    // を作る（内容が同じでも identical は false）。ここでは同じ特性
    // （内側の参照フィールド + スカラー値）を持つ record を都度新しく作って
    // 再現する。
    final sharedCacheRef = Object();
    ({Object cache, int epoch}) captureIdentity() =>
        (cache: sharedCacheRef, epoch: 1);

    final before = captureIdentity();
    final after = captureIdentity();
    // 別インスタンスだが値としては等しい（record の構造的等価性）。
    expect(identical(before, after), isFalse);
    expect(before == after, isTrue);

    cache.resetIfNeeded(identity: before, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
    );
    expect(cache.linksByBodyLine[0], isNotEmpty);

    // 別々に作られた同じ値の identity（`after`）で resetIfNeeded を呼んでも
    // 破棄しない（== で比較するため。identical だと本番では毎回破棄され
    // キャッシュが機能しなくなる）。
    cache.resetIfNeeded(identity: after, generation: 1);
    expect(
      cache.linksByBodyLine[0],
      isNotEmpty,
      reason: '同じ値の identity では破棄されないこと',
    );
  });

  test('revision は内容が実際に変わったときだけ増分する（表示側のメモ化キー。同じ結果の再適用では増やさない）', () {
    final cache = ScrollbackLinkCache();
    final idA = Object();
    expect(cache.revision, 0);

    // generation 未設定時の applyWindowResult は無視される（変化なし）。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: const {},
    );
    expect(cache.revision, 0);

    cache.resetIfNeeded(identity: idA, generation: 1); // 実際に切り替わった
    expect(cache.revision, 1);

    // identity・generation とも同じなら変化なし（冪等）。
    cache.resetIfNeeded(identity: idA, generation: 1);
    expect(cache.revision, 1);

    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
      k: 0,
    );
    expect(cache.revision, 2);

    // 同じ offset・同じ内容（値が等しい HerdrHyperlinkRange）・同じ k を
    // 再適用しても変化なし
    // （同じ結果を再適用したときは増やさない）。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
      k: 0,
    );
    expect(cache.revision, 2);

    // generation 不一致は無視される（変化なし）。
    cache.applyWindowResult(
      generation: 2,
      offsetFromBottom: 1,
      linksByBodyLine: const {},
    );
    expect(cache.revision, 2);

    // 別の窓の結果が追加で反映される（変化あり）。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 20,
      linksByBodyLine: {
        5: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'b')],
      },
      k: 0,
    );
    expect(cache.revision, 3);

    cache.clear(); // 内容があったので変化あり
    expect(cache.revision, 4);

    // 空の状態での clear は変化なし。
    cache.clear();
    expect(cache.revision, 4);
  });

  test('applyWindowResult は generation 不一致なら無視する', () {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: Object(), generation: 1);
    cache.applyWindowResult(
      generation: 2, // 古い/別の世代の結果
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
    );
    expect(cache.linksByBodyLine, isEmpty);
    expect(cache.hasFetched(0), isFalse);
  });

  test('clear は全内容を破棄する', () {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: Object(), generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
      k: 1,
    );

    cache.clear();

    expect(cache.identity, isNull);
    expect(cache.generation, isNull);
    expect(cache.linksByBodyLine, isEmpty);
    expect(cache.hasFetched(0), isFalse);
    expect(cache.lastK, isNull);
  });

  test('linksByBodyLine は unmodifiable view を返す', () {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: Object(), generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: const [HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'a')],
      },
    );
    expect(() => cache.linksByBodyLine[1] = const [], throwsUnsupportedError);
  });

  test('truncated の窓は取得済みにしない（再取得の対象に残す）が、リンクは取り込む', () {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: Object(), generation: 1);
    const range = HerdrHyperlinkRange(startCol: 0, endCol: 3, url: 'u');

    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 5,
      linksByBodyLine: const {
        2: [range],
      },
      truncated: true,
    );
    expect(cache.hasFetched(5), isFalse);
    expect(cache.linksByBodyLine[2], [range]);

    // 同じ offset が truncated でなく届けば取得済みになる。
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 5,
      linksByBodyLine: const {},
    );
    expect(cache.hasFetched(5), isTrue);
  });
}

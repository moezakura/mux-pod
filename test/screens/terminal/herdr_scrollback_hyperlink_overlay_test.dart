import 'package:flutter_muxpod/screens/terminal/widgets/herdr_scrollback_hyperlink_overlay.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// herdr_scrollback_hyperlink_overlay.dart のテスト。
///
/// [overlayHerdrHyperlinks] 自体（抑制ルールの適用結果・列→文字オフセット
/// 変換）は herdr_hyperlink_overlay_test.dart で検証済みのため、ここでは
/// [overlayScrollbackHyperlinks] のスナップショット照合ガード（表示側・identity と
/// generation の両方の照合）と [HerdrScrollbackHyperlinkMemo] のメモ化
/// 契約だけを対象にする。
void main() {
  final parser = AnsiParser();
  const bodyText = 'click here for more';

  List<ParsedLine> parsedLinesOf(String text) => parser.parseLines(text);

  ScrollbackLinkCache cacheWithLink({
    required Object identity,
    required int generation,
    String url = 'https://a/',
  }) {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: identity, generation: generation);
    cache.applyWindowResult(
      generation: generation,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: [HerdrHyperlinkRange(startCol: 6, endCol: 9, url: url)],
      },
    );
    return cache;
  }

  group('overlayScrollbackHyperlinks', () {
    test('cache が null なら重ねない', () {
      final bodyLines = parsedLinesOf(bodyText);
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: null,
        currentSnapshotIdentity: (identity: Object(), generation: 1),
      );
      expect(identical(result, bodyLines), isTrue);
    });

    test('cache.generation が未取得（null）なら重ねない', () {
      final bodyLines = parsedLinesOf(bodyText);
      final cache = ScrollbackLinkCache();
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: Object(), generation: 1),
      );
      expect(identical(result, bodyLines), isTrue);
    });

    test('currentSnapshotIdentity が null なら重ねない', () {
      final idA = Object();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(identity: idA, generation: 1);
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: null,
      );
      expect(identical(result, bodyLines), isTrue);
    });

    test(
      'cache.generation と currentSnapshotIdentity.generation が不一致なら重ねない（identity は一致）',
      () {
        final idA = Object();
        final bodyLines = parsedLinesOf(bodyText);
        // cache は generation 1 のスナップショットの結果を持つが、表示側は
        // 既に generation 2 へ切り替わっている（スナップショット差し替え後、
        // 古い世代の結果しかキャッシュに無い状態）。
        final cache = cacheWithLink(identity: idA, generation: 1);
        final result = overlayScrollbackHyperlinks(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: (identity: idA, generation: 2),
        );
        expect(identical(result, bodyLines), isTrue);
      },
    );

    test('generation は同じで identity が違う場合は重ねない（controller 再作成/再接続での番号衝突対策）', () {
      final idA = Object();
      final idB = Object();
      final bodyLines = parsedLinesOf(bodyText);
      // cache は identity=idA・generation=1 の結果を持つが、表示側は
      // 同じ generation 番号のまま identity だけが別オブジェクトへ
      // 変わっている（controller の作り直し・再接続で番号が偶然一致した
      // 場合を模す）。
      final cache = cacheWithLink(identity: idA, generation: 1);
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: idB, generation: 1),
      );
      expect(identical(result, bodyLines), isTrue);
    });

    test('identity・generation とも一致すれば重ねる', () {
      final idA = Object();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(
        identity: idA,
        generation: 1,
        url: 'https://example.com/',
      );
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: idA, generation: 1),
      );
      expect(identical(result, bodyLines), isFalse);
      expect(
        result[0].segments.where((s) => s.url != null).single.url,
        'https://example.com/',
      );
    });

    test('別々に作られた同じ値の identity（record。本番の HerdrTargetIdentity と同じ'
        '特性）でも重ねる', () {
      // 本番の HerdrController.captureIdentity() は呼び出しのたびに
      // 新しい record インスタンスを作る（内容が同じでも identical は
      // false）。cache 構築時と currentSnapshotIdentity で別々に作った
      // 同じ値の identity でも重ね合わせが働くことを確認する。
      final sharedCacheRef = Object();
      ({Object cache, int epoch}) captureIdentity() =>
          (cache: sharedCacheRef, epoch: 1);

      final cacheIdentity = captureIdentity();
      final currentIdentity = captureIdentity();
      expect(identical(cacheIdentity, currentIdentity), isFalse);
      expect(cacheIdentity == currentIdentity, isTrue);

      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(
        identity: cacheIdentity,
        generation: 1,
        url: 'https://example.com/',
      );
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: currentIdentity, generation: 1),
      );

      expect(identical(result, bodyLines), isFalse);
      expect(
        result[0].segments.where((s) => s.url != null).single.url,
        'https://example.com/',
      );
    });

    test('linksByBodyLine が空なら bodyLines をそのまま返す', () {
      final idA = Object();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = ScrollbackLinkCache();
      cache.resetIfNeeded(identity: idA, generation: 1); // 取得済みの窓はまだ無い
      final result = overlayScrollbackHyperlinks(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: idA, generation: 1),
      );
      expect(identical(result, bodyLines), isTrue);
    });
  });

  group('HerdrScrollbackHyperlinkMemo', () {
    test(
      '同じ入力（bodyLines identity・identity・generation・revision・currentIdentity・currentGeneration）なら同一インスタンスを返す',
      () {
        final idA = Object();
        final memo = HerdrScrollbackHyperlinkMemo();
        final bodyLines = parsedLinesOf(bodyText);
        final cache = cacheWithLink(identity: idA, generation: 1);
        final snapshotIdentity = (identity: idA, generation: 1);

        final first = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: snapshotIdentity,
        );
        final second = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: snapshotIdentity,
        );

        expect(identical(first, second), isTrue);
      },
    );

    test('cache.revision が変わる（新しい窓が届く）と再計算する', () {
      final idA = Object();
      final memo = HerdrScrollbackHyperlinkMemo();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(identity: idA, generation: 1);
      final snapshotIdentity = (identity: idA, generation: 1);

      final first = memo.overlay(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: snapshotIdentity,
      );

      // 同一 generation のまま、別の窓の結果が追加で届く
      // （ScrollbackLinkCache.revision がここで増分する）。
      cache.applyWindowResult(
        generation: 1,
        offsetFromBottom: 5,
        linksByBodyLine: {
          1: const [HerdrHyperlinkRange(startCol: 0, endCol: 2, url: 'c')],
        },
      );

      final second = memo.overlay(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: snapshotIdentity,
      );

      expect(identical(first, second), isFalse);
    });

    test('cache.identity と cache.generation が変わる（スナップショット差し替え）と再計算する', () {
      final idA = Object();
      final idB = Object();
      final memo = HerdrScrollbackHyperlinkMemo();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(identity: idA, generation: 1);

      final first = memo.overlay(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: idA, generation: 1),
      );

      cache.resetIfNeeded(identity: idB, generation: 2); // 破棄して切り替え

      final second = memo.overlay(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: (identity: idB, generation: 2),
      );

      expect(identical(first, second), isFalse);
      // generation 2 はまだ取得結果が無いので本文そのまま。
      expect(identical(second, bodyLines), isTrue);
    });

    test(
      'currentSnapshotIdentity.generation だけが変わる（キャッシュより新しい世代へ表示側が先行）と再計算する',
      () {
        final idA = Object();
        final memo = HerdrScrollbackHyperlinkMemo();
        final bodyLines = parsedLinesOf(bodyText);
        final cache = cacheWithLink(identity: idA, generation: 1);

        final first = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: (identity: idA, generation: 1),
        );
        expect(identical(first, bodyLines), isFalse); // 一致するので重ねられている

        // cache はまだ generation 1 のままだが、表示側は generation 2 へ
        // 進んだ（この時点からは重ねてはいけない）。
        final second = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: (identity: idA, generation: 2),
        );

        expect(identical(second, bodyLines), isTrue); // 重ねられなくなった
      },
    );

    test(
      'currentSnapshotIdentity.identity だけが変わる（generationを跨がない再接続）と再計算する',
      () {
        final idA = Object();
        final idB = Object();
        final memo = HerdrScrollbackHyperlinkMemo();
        final bodyLines = parsedLinesOf(bodyText);
        final cache = cacheWithLink(identity: idA, generation: 1);

        final first = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: (identity: idA, generation: 1),
        );
        expect(identical(first, bodyLines), isFalse); // 一致するので重ねられている

        // cache.generation は 1 のままだが、表示側の identity だけが
        // 別オブジェクトへ変わった（再接続。generation は跨がない）。
        final second = memo.overlay(
          bodyLines: bodyLines,
          parser: parser,
          cache: cache,
          currentSnapshotIdentity: (identity: idB, generation: 1),
        );

        expect(identical(second, bodyLines), isTrue); // 重ねられなくなった
      },
    );

    test('bodyLines が変わる（別インスタンス）と再計算する', () {
      final idA = Object();
      final memo = HerdrScrollbackHyperlinkMemo();
      final cache = cacheWithLink(
        identity: idA,
        generation: 1,
        url: 'https://example.com/',
      );
      final snapshotIdentity = (identity: idA, generation: 1);

      final first = memo.overlay(
        bodyLines: parsedLinesOf(bodyText),
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: snapshotIdentity,
      );
      final second = memo.overlay(
        bodyLines: parsedLinesOf(bodyText),
        parser: parser,
        cache: cache,
        currentSnapshotIdentity: snapshotIdentity,
      );

      expect(identical(first, second), isFalse);
      expect(
        second[0].segments.where((s) => s.url != null).single.url,
        'https://example.com/',
      );
    });

    test('別々に作られた同じ値の identity（record）でも重ねる（'
        'メモ化キーは == で比較するため再計算はしても結果は重なる）', () {
      final sharedCacheRef = Object();
      ({Object cache, int epoch}) captureIdentity() =>
          (cache: sharedCacheRef, epoch: 1);

      final memo = HerdrScrollbackHyperlinkMemo();
      final bodyLines = parsedLinesOf(bodyText);
      final cache = cacheWithLink(
        identity: captureIdentity(),
        generation: 1,
        url: 'https://example.com/',
      );

      final result = memo.overlay(
        bodyLines: bodyLines,
        parser: parser,
        cache: cache,
        // cache 構築時とは別インスタンスの identity（本番の getter が
        // 呼び出しのたびに新しい record を返すのと同じ状況）。
        currentSnapshotIdentity: (identity: captureIdentity(), generation: 1),
      );

      expect(identical(result, bodyLines), isFalse);
      expect(
        result[0].segments.where((s) => s.url != null).single.url,
        'https://example.com/',
      );
    });
  });
}

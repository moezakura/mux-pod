import 'dart:async';

import 'package:flutter/material.dart';

import 'ansi_display_model.dart';

/// スクロールドライバー（垂直スクロール所有と制御命令・P3-2）。
///
/// - 外部（親）から [ScrollController] が渡されていれば参照のみ・絶対に
///   dispose しない。未指定のときは内部生成し dispose 時に破棄する。
/// - スクロール命令 5 種（jumpToLineFromTop / scrollToBottom / followToBottom /
///   scrollToTop / scrollToCaret）は従来の `AnsiTextViewState` の実装を移設。
///   mounted ガードは [AnsiScrollDriverHost.isActive] を使用する。
class AnsiScrollDriver {
  /// スクロール計算に使う表示モデル（行高・パース済み行キャッシュ）。
  final AnsiDisplayModel content;

  /// State 側のホスト（mounted・外部 controller・パネル寸法・解決済みカーソル）。
  final AnsiScrollDriverHost host;

  ScrollController? _internalVerticalScrollController;

  AnsiScrollDriver({required this.content, required this.host});

  /// 外部 controller が渡されていない場合のみ内部で生成する。
  void attach() {
    if (host.externalVerticalScrollController == null) {
      _internalVerticalScrollController = ScrollController();
    }
  }

  /// 垂直スクロールコントローラー（外部優先）。
  ScrollController get controller =>
      host.externalVerticalScrollController ??
      _internalVerticalScrollController!;

  /// 内部生成時のみ破棄する（外部 controller は親所有）。
  void dispose() {
    _internalVerticalScrollController?.dispose();
  }

  /// 指定した行インデックスがビューポート最上部に来るよう即座にスクロールする。
  ///
  /// 履歴プリペンド後、「直前に最上部だった行」を同じ位置に留めるために使う
  /// （追加行数ぶん絶対位置で移動するので、途中位置へ飛ばない）。
  void jumpToLineFromTop(int lineIndex, [int attempt = 0]) {
    if (!host.isActive || !controller.hasClients) return;
    final pos = controller.position;
    final target = lineIndex * content.lineHeight;
    // 巨大コンテンツでは Sliver が末尾までレイアウトされるまで maxScrollExtent が
    // 小さいまま。現在の最大までジャンプして遅延ビルドを進め、ターゲットに届くまで
    // 数フレーム繰り返す。
    if (pos.maxScrollExtent + 1.0 < target && attempt < 60) {
      controller.jumpTo(pos.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => jumpToLineFromTop(lineIndex, attempt + 1),
      );
      return;
    }
    controller.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
  }

  /// 一番下までスクロール
  ///
  /// 完了（または中断）時に解決される Future を返す。呼び出し側は
  /// プログラマティックスクロール中の追従抑制解除タイミングに使える
  /// （fire-and-forget の既存呼び出しは変更なしで動作する）。
  Future<void> scrollToBottom() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.isActive || !controller.hasClients) {
        completer.complete();
        return;
      }
      completer.complete(
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    });
    return completer.future;
  }

  /// コンテンツ追従で最下部へジャンプする（自動スクロール・Issue #87）。
  ///
  /// アニメーションを伴わない即時ジャンプで、ポーリング更新ごとに
  /// 最下部ピン留め中の位置ズレを補正する。
  ///
  /// コンテンツ反映（ValueNotifier → 再構築 → レイアウト）がこの呼び出しの
  /// 後ろで行われるケースがあるため、maxScrollExtent が伸びている間は
  /// 数フレームだけ追試する（[jumpToLineFromTop] の遅延ビルド対策と同型）。
  void followToBottom([int attempt = 0]) {
    if (!host.isActive || !controller.hasClients) return;
    final pos = controller.position;
    final before = pos.maxScrollExtent;
    if (before > pos.pixels) {
      controller.jumpTo(before);
    }
    if (attempt >= 8) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.isActive || !controller.hasClients) return;
      final p = controller.position;
      // レイアウト遅延で max がまだ伸びている間、またはまだ最下部に
      // 届いていない間は追試する（バースト出力で追従が取りこぼされる
      // 事態を防ぐ・上限 6 フレーム）。
      if (p.maxScrollExtent != before || p.maxScrollExtent > p.pixels) {
        followToBottom(attempt + 1);
      }
    });
  }

  /// 一番上までスクロール
  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// カーソル位置までスクロール
  void scrollToCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.isActive) return;
      if (!controller.hasClients) return;

      final parsedLines = content.parsedLinesCache;
      if (parsedLines == null || parsedLines.isEmpty) return;

      // カーソル行インデックスを計算（build内と同じロジック）。
      // Phase 4: herdr caret が与えられた場合は caret.y を使う（位置不明・
      // 非表示は画面側で scrollToCaret を呼ばないため、ここでは単純に解決値）。
      final resolvedCaret = host.resolvedCaret;
      final int cursorLineIndex;
      if (parsedLines.length >= host.paneHeight) {
        cursorLineIndex =
            parsedLines.length - host.paneHeight + resolvedCaret.y;
      } else {
        cursorLineIndex = resolvedCaret.y;
      }

      // カーソル行のスクロールオフセット
      final targetOffset = cursorLineIndex * content.lineHeight;

      // ビューポート高さを考慮し、カーソル行が中央付近に来るよう調整
      final viewportHeight = controller.position.viewportDimension;
      final centeredOffset =
          targetOffset - (viewportHeight / 2) + (content.lineHeight / 2);

      // 有効範囲にクランプ
      final maxExtent = controller.position.maxScrollExtent;
      final clampedOffset = centeredOffset.clamp(0.0, maxExtent);

      controller.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
}

/// [AnsiScrollDriver] が State から読み取るホストインターフェース。
abstract class AnsiScrollDriverHost {
  /// 外部から渡された垂直スクロールコントローラー（なければ null）。
  ScrollController? get externalVerticalScrollController;

  /// ペインの文字高さ（`widget.paneHeight`）。
  int get paneHeight;

  /// 解決済みカーソル位置（`widget.caret` 反映）。
  ({int x, int y, bool draw}) get resolvedCaret;

  /// State が生きているか（= mounted）。
  bool get isActive;
}

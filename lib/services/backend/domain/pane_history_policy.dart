/// ペイン履歴取得のポリシー（backend 別）。
///
/// 従来は `TerminalScreen` が backend 分岐（`_deepHistoryLineCount()`）で
/// 行数を解決していた。ライブ窓・スクロールバック上限・取得戦略は
/// backend ごとに意味が異なるため、ポリシーとして分離する（バグ4 根本対応）。
library;

import 'multiplexer_backend.dart';

/// 履歴取得の戦略（どのトランスポートで取得するか）。
enum HistoryRetrievalStrategy {
  /// ライブポーリングと同じ持続的シェル（チャネル再利用・低遅延）。
  persistent,

  /// 一時チャネル（exec）で大量出力を取得する。
  ephemeral,
}

/// ペイン履歴取得のポリシー。
///
/// [liveTailLines]: ライブポーリングで取得する直近行数。
/// [scrollbackLimit]: スクロールバック取得の上限行数。
/// [scrollbackStrategy]: スクロールバック取得のトランスポート戦略。
class PaneHistoryPolicy {
  /// ライブポーリングの既定行数。
  static const int defaultLiveTailLines = 120;

  /// スクロールバックの既定上限。
  static const int defaultScrollbackLimit = 100000;

  /// スクロールバック上限の下限（設定値のクランプ用）。
  static const int minScrollbackLimit = 200;

  /// スクロールバック上限の上限（設定値のクランプ用）。
  static const int maxScrollbackLimit = 20000;

  final int liveTailLines;
  final int scrollbackLimit;
  final HistoryRetrievalStrategy scrollbackStrategy;

  const PaneHistoryPolicy({
    this.liveTailLines = defaultLiveTailLines,
    this.scrollbackLimit = defaultScrollbackLimit,
    this.scrollbackStrategy = HistoryRetrievalStrategy.ephemeral,
  });
}

/// backend 種別から [PaneHistoryPolicy] を解決する。
///
/// - tmux: ライブは persistent・スクロールバックは exec（capturePane）。
///   サーバ側 history-limit（setHistoryLimit = scrollbackLines）でクランプされる
///   ため、スクロールバックは大きな要求を出しサーバに委ねる。
/// - herdr: サーバ側に履歴上限の設定が無いため、要求行数 = scrollbackLines
///   （[PaneHistoryPolicy.minScrollbackLimit]..[maxScrollbackLimit] にクランプ）。
///   スクロールバックも persistent で統一する（`pane read --lines N` 単一経路）。
class PaneHistoryPolicyResolver {
  /// [configuredScrollbackLines]（ユーザー設定 scrollbackLines）から、
  /// [backend] に応じたポリシーを返す。
  static PaneHistoryPolicy forBackend(
    MultiplexerBackendKind backend, {
    int configuredScrollbackLines = 10000,
  }) {
    return switch (backend) {
      MultiplexerBackendKind.tmux => PaneHistoryPolicy(
          scrollbackStrategy: HistoryRetrievalStrategy.ephemeral,
        ),
      MultiplexerBackendKind.herdr => PaneHistoryPolicy(
          scrollbackLimit: configuredScrollbackLines.clamp(
            PaneHistoryPolicy.minScrollbackLimit,
            PaneHistoryPolicy.maxScrollbackLimit,
          ),
          scrollbackStrategy: HistoryRetrievalStrategy.persistent,
        ),
      MultiplexerBackendKind.unknown => const PaneHistoryPolicy(),
    };
  }
}

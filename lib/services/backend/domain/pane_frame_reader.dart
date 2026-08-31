/// ペイン表示フレーム（content + geometry + identity）の合成 domain。
///
/// 従来 `PaneContentReader.readPane` は content のみを返し、サイズ（geometry）
/// は表示層が backend 分岐で解決していた（`_backendKind == herdr` の直書き・
/// 診断専用 `cachedSnapshot` の表示利用）。content と layout を表示直前に
/// backend 非依存で合成する責務を [PaneFrameReader] に集約する
/// （Codex 根本設計レビュー・バグ1 根本対応）。
library;

import 'pane_content_reader.dart';
import 'pane_read.dart';

/// ペイン読み取り要求（content + geometry の合成に必要な情報）。
///
/// [PaneReadRequest] を拡張し、読み取り目的に応じた geometry 解決が
/// 必要なことを型で表す。
final class PaneFrameRequest {
  final PaneReadRequest read;
  const PaneFrameRequest(this.read);

  String get paneId => read.paneId;
  PaneReadPurpose get purpose => read.purpose;
}

/// 表示用のカーソル（caret）情報（Phase 4・herdr caret helper 由来）。
///
/// [x] / [y] は nullable にする（計画 L5: nullable snapshot）。
///
/// - `null` = 位置不明。non-null の正当な `(0, 0)` と区別するために必須。
///   helper が `cursor: null` を返した「非表示カーソル」の観測では位置が
///   分からないため、[visible] == false と合わせて [x] / [y] を null にする。
/// - 座標は 0-based の文字セル単位で、[frameWidth] / [frameHeight]（取得時点の
///   frame 寸法）に対する相対値。範囲外（frame を超える）座標は描画しない
///   （不正値・stale の誤表示を防ぐ）。
///
/// 表示層（画面）と domain（[PaneFrame]）をつなぐ小さな不変データであり、
/// backend（tmux / herdr）に依存しない。caret を持たない backend では null。
final class PaneCaret {
  /// カーソル X（0-based・文字セル単位）。不明なら null。
  final int? x;

  /// カーソル Y（0-based・文字セル単位）。不明なら null。
  final int? y;

  /// カーソルが表示中かどうか（false は非表示カーソルの観測）。
  final bool visible;

  /// DECSCUSR 相当のカーソル形状（u8）。
  final int shape;

  /// 取得時点の frame 幅（文字セル数・座標の検証用）。
  final int frameWidth;

  /// 取得時点の frame 高さ（文字セル数・座標の検証用）。
  final int frameHeight;

  const PaneCaret({
    this.x,
    this.y,
    this.visible = false,
    this.shape = 0,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  /// 位置が既知かどうか（描画・初回スクロールの判定に使う）。
  bool get hasPosition => x != null && y != null;

  @override
  String toString() {
    final pos = hasPosition ? '($x,$y)' : 'unknown';
    return 'PaneCaret($pos, visible=$visible, shape=$shape, '
        'frame=${frameWidth}x$frameHeight)';
  }
}

/// ペイン表示フレーム（content と geometry を合成した結果）。
final class PaneFrame {
  /// 表示用の生テキスト（ANSI エスケープ付きの場合あり）。
  final String content;

  /// ペインの文字セル単位のサイズ（不明なら null → 表示側は既定 80x24）。
  final PaneGeometry? geometry;

  /// カーソル X（0-based。不明なら 0）。
  final int cursorX;

  /// カーソル Y（0-based。不明なら 0）。
  final int cursorY;

  /// モード文字列（tmux copy-mode 等。無い backend は空文字）。
  final String paneMode;

  /// 内容が ANSI エスケープを含むかどうか。
  final bool hasAnsi;

  /// herdr カーソル情報（caret）。他 backend・未取得時は null
  /// （従来の cursorX/cursorY 契約へフォールバックする）。
  final PaneCaret? caret;

  const PaneFrame({
    required this.content,
    this.geometry,
    this.cursorX = 0,
    this.cursorY = 0,
    this.paneMode = '',
    this.hasAnsi = false,
    this.caret,
  });

  /// 共通 snapshot 形式へ変換する（表示コアはこの抽象に依存）。
  ///
  /// 既存の cursorX / cursorY 契約は維持し、[caret] は追加フィールドとして
  /// のみ伝搬する（既存 tmux 経路・テストは無影響）。
  MultiplexerPaneSnapshot toSnapshot() => MultiplexerPaneSnapshot(
    content: content,
    geometry: geometry,
    cursorX: cursorX,
    cursorY: cursorY,
    paneMode: paneMode,
    hasAnsi: hasAnsi,
    caret: caret,
  );
}

/// ペイン表示フレームの読み取り抽象。
///
/// content と layout（geometry）を合成して [PaneFrame] を返す。backend 差異
/// （tmux は poll で geometry 込み・herdr は content と snapshot layout を
/// 別々に取得）はこの抽象が吸収し、表示層は backend 非依存のまま
/// [PaneFrame.toSnapshot] を使う。
abstract interface class PaneFrameReader {
  Future<PaneFrame> read(PaneFrameRequest request);
}

/// pane ID から文字セル単位の geometry を解決する。
///
/// 別時刻の情報（snapshot layout）から解決するため、結果はあくまで
/// best-effort の表示用 geometry であり、表示対象の同一性（pane ID /
/// snapshot epoch / adapter identity）は解決側で照合する。
abstract interface class PaneLayoutResolver {
  Future<PaneGeometry?> resolve(String paneId);
}

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../providers/terminal_display_provider.dart'
    show terminalDisplayProvider;
import '../../../services/backend/domain/pane_frame_reader.dart' show PaneCaret;
import '../../../services/terminal/font_calculator.dart' show FontCalculator;
import '../widgets/ansi_terminal_model.dart' show TerminalMode;
import '../widgets/terminal_zoom.dart' show fitTerminalZoomFactor;
import 'terminal_input_mode.dart' show ScrollModeSource, TerminalBufferedUpdate;
import 'terminal_input_ports.dart'
    show TerminalScrollbackPort, TerminalTargetIdentityValidator;

/// ターミナルの「表示モード」状態の単一所有者（C7）。
///
/// `_terminalMode` / `_scrollModeSource` / `_isCopyModeDetected` / select 更新
/// バッファ 4 フィールド / zoom スケール / fit-zoom 退避値を所有する。モード
/// 遷移の「代入集合」は [applyXxx] で HEAD と厳密一致させ、リビルド通知
/// （`markNeedsBuild`）は呼び出し側（[TerminalInputCoordinator]）が 1 回行う。
class TerminalModeController {
  TerminalModeController({
    required this.ref,
    required this.scrollback,
    required this.validator,
  });

  final WidgetRef ref;
  final TerminalScrollbackPort scrollback;
  final TerminalTargetIdentityValidator validator;

  TerminalMode _mode = TerminalMode.normal;
  ScrollModeSource _source = ScrollModeSource.none;
  bool _isCopyModeDetected = false;

  // 選択状態保持用（スクロールモード中の更新抑制・C7）。
  String _bufferedContent = '';
  bool _hasBufferedUpdate = false;
  PaneCaret? _bufferedCaret;
  Object? _bufferedTargetIdentity;

  // ズームスケール / scrollSend 自動フィットズーム退避値。
  double _zoomScale = 1.0;
  double? _zoomBeforeScrollSend;

  // --- getters（root build / ui / session が読む） ---

  TerminalMode get mode => _mode;
  ScrollModeSource get source => _source;
  bool get isCopyModeDetected => _isCopyModeDetected;
  bool get hasBufferedUpdate => _hasBufferedUpdate;
  String get bufferedContent => _bufferedContent;
  double get zoomScale => _zoomScale;

  /// 表示中の実効ズーム倍率（永続 zoomFactor × ピンチ中のプレビュー _zoomScale）。
  double get effectiveZoom =>
      ref.read(settingsProvider).zoomFactor * _zoomScale;

  /// 実効ズームが等倍でない（インジケータ/リセットの活性判定）。
  bool get isZoomed => (effectiveZoom - 1.0).abs() > 0.005;

  // --- zoom ---

  /// AnsiTextView.onZoomChanged（HEAD `_zoomScale = scale` と同一）。
  void onZoomChanged(double scale) {
    _zoomScale = scale;
  }

  // --- モード遷移（代入集合は HEAD の各 setState と厳密一致・R1/R2） ---

  /// 通常モードへ（`_resetTerminalMode` / copy-mode 終了の正集合）。
  void applyNormal() {
    _mode = TerminalMode.normal;
    _source = ScrollModeSource.none;
    _isCopyModeDetected = false;
    _clearBuffer();
  }

  /// scrollSend モードへ（原子性契約 C1: mode と source を同時に設定）。
  void applyScrollSend() {
    _mode = TerminalMode.scrollSend;
    _source = ScrollModeSource.none;
    _isCopyModeDetected = false;
    _clearBuffer();
  }

  /// select モードへ（手動・copy-mode cancel 導線）。
  void applySelectManual() {
    _mode = TerminalMode.select;
    _source = ScrollModeSource.manual;
    _isCopyModeDetected = false;
    _clearBuffer();
  }

  /// select モードへ（スクロール上端からの深い履歴ロード専用・HEAD の
  /// `_loadDeepHistoryOnScroll` の setState と同一。copy-mode フラグとバッファは
  /// 触らない）。
  void applySelectForHistory() {
    _mode = TerminalMode.select;
    _source = ScrollModeSource.manual;
  }

  /// tmux copy-mode 自動検出（poll が呼ぶ・HEAD の setState と同一）。
  void applySelectTmux({required bool fromScrollSend}) {
    if (fromScrollSend) _isCopyModeDetected = true;
    _mode = TerminalMode.select;
    _source = ScrollModeSource.tmux;
  }

  /// tmux copy-mode 終了（poll が呼ぶ・HEAD の setState と同一。バッファは
  /// クリアせず、適用は呼び出し側の `onApplyBuffered` が行う）。
  void applyTmuxEnded() {
    _mode = TerminalMode.normal;
    _source = ScrollModeSource.none;
    _isCopyModeDetected = false;
  }

  /// バッファを明示的にクリアする（モード遷移で既に適用済み・過剰なら不要）。
  void clearBuffer() => _clearBuffer();

  // --- C7 選択バッファ（3 段契約） ---

  /// 1. session poll がバッファへ書き込む。
  void captureSelectUpdate({
    required String content,
    PaneCaret? caret,
    Object? targetIdentity,
  }) {
    _bufferedContent = content;
    _bufferedCaret = caret;
    _hasBufferedUpdate = true;
    _bufferedTargetIdentity = targetIdentity;
  }

  /// 2. session の apply 側が呼び、**破棄判定（identity 照合）は herdr API
  /// （validator）が行う**。不一致なら破棄して null を返す。
  TerminalBufferedUpdate? takeBufferedUpdate() {
    if (!_hasBufferedUpdate) return null;
    if (!validator.isCurrent(_bufferedTargetIdentity)) {
      _clearBuffer();
      return null;
    }
    final update = TerminalBufferedUpdate(
      content: _bufferedContent,
      caret: _bufferedCaret,
      targetIdentity: _bufferedTargetIdentity,
    );
    _clearBuffer();
    return update;
  }

  // --- scrollSend 自動フィットズーム（TERM-ZOOM-FIT-007/006） ---

  /// scrollSend モード突入時、設定 [autoFitZoomOnScrollSend] が ON かつ現在の
  /// ズームでターミナルが画面からはみ出している場合のみ缩小フィットをする。
  void applyScrollSendFitZoom() {
    final settings = ref.read(settingsProvider);
    if (!settings.autoFitZoomOnScrollSend) return;
    // 既に一時ズーム適用済みなら再適用しない（モード遷移の入れ子対策）。
    if (_zoomBeforeScrollSend != null) return;

    final display = ref.read(terminalDisplayProvider);
    final paneWidth = scrollback.displayedPaneWidth;
    final paneHeight = scrollback.displayedPaneHeight;
    if (display.screenWidth <= 0 || display.screenHeight <= 0) return;
    if (paneWidth <= 0 || paneHeight <= 0) return;

    // AnsiTextView と同一の baseFontSize を導出する（調整モード分岐・D12 準拠）。
    final double baseFontSize;
    if (settings.isAutoFit) {
      final calc = FontCalculator.calculate(
        screenWidth: display.screenWidth,
        paneCharWidth: paneWidth,
        fontFamily: settings.fontFamily,
        minFontSize: settings.minFontSize,
      );
      baseFontSize = calc.fontSize;
    } else {
      baseFontSize = settings.fontSize;
    }

    final fit = fitTerminalZoomFactor(
      screenWidth: display.screenWidth,
      screenHeight: display.screenHeight,
      paneCharWidth: paneWidth,
      paneHeight: paneHeight,
      baseFontSize: baseFontSize,
      charWidthRatio: FontCalculator.measureCharWidthRatio(settings.fontFamily),
      lineHeightRatio: FontCalculator.lineHeightRatio,
    );

    final current = settings.zoomFactor;
    // 現在より大きくならない（フィット目的は縮小のみ・拡大しない）。
    final target = math.min(current, fit);
    if ((target - current).abs() < 0.005) return; // 変化なし

    _zoomBeforeScrollSend = current;
    ref.read(settingsProvider.notifier).setZoomFactor(target);
  }

  /// scrollSend 自動フィットズームを適用前の値へ復元する。
  void restoreScrollSendZoom() {
    final saved = _zoomBeforeScrollSend;
    if (saved == null) return;
    _zoomBeforeScrollSend = null;
    ref.read(settingsProvider.notifier).setZoomFactor(saved);
  }

  void _clearBuffer() {
    _bufferedContent = '';
    _hasBufferedUpdate = false;
    _bufferedCaret = null;
    _bufferedTargetIdentity = null;
  }
}

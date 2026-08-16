import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal/font_calculator.dart';
import '../services/tmux/tmux_models.dart';

import 'settings_provider.dart';

// inventory: PROV-DISP-001
/// ターミナル表示状態
///
/// フォントサイズ、スクロール状態、ズーム状態を管理する。
class TerminalDisplayState {
  // inventory: PROV-DISP-002
  // inventory: LEGACY-0184
  /// ペインの横幅（文字数）
  final int paneWidth;

  // inventory: PROV-DISP-003
  // inventory: LEGACY-0185
  /// ペインの縦幅（行数）
  final int paneHeight;

  // inventory: PROV-DISP-004
  // inventory: LEGACY-0186
  /// 利用可能なスクリーン幅（ピクセル）
  final double screenWidth;

  // inventory: PROV-DISP-005
  // inventory: LEGACY-0187
  /// 利用可能なスクリーン高さ（ピクセル）
  final double screenHeight;

  // inventory: PROV-DISP-006
  // inventory: LEGACY-0188
  /// 計算されたフォントサイズ
  final double calculatedFontSize;

  // inventory: PROV-DISP-007
  // inventory: LEGACY-0189
  /// 水平スクロールが必要か
  final bool needsHorizontalScroll;

  // inventory: PROV-DISP-008
  // inventory: LEGACY-0190
  /// 水平スクロール位置
  final double horizontalScrollOffset;

  const TerminalDisplayState({
    this.paneWidth = 80,
    this.paneHeight = 24,
    this.screenWidth = 0.0,
    this.screenHeight = 0.0,
    this.calculatedFontSize = 14.0,
    this.needsHorizontalScroll = false,
    this.horizontalScrollOffset = 0.0,
  });

  // inventory: PROV-DISP-009
  // inventory: LEGACY-0191
  TerminalDisplayState copyWith({
    int? paneWidth,
    int? paneHeight,
    double? screenWidth,
    double? screenHeight,
    double? calculatedFontSize,
    bool? needsHorizontalScroll,
    double? horizontalScrollOffset,
  }) {
    return TerminalDisplayState(
      paneWidth: paneWidth ?? this.paneWidth,
      paneHeight: paneHeight ?? this.paneHeight,
      screenWidth: screenWidth ?? this.screenWidth,
      screenHeight: screenHeight ?? this.screenHeight,
      calculatedFontSize: calculatedFontSize ?? this.calculatedFontSize,
      needsHorizontalScroll:
          needsHorizontalScroll ?? this.needsHorizontalScroll,
      horizontalScrollOffset:
          horizontalScrollOffset ?? this.horizontalScrollOffset,
    );
  }

  // inventory: PROV-DISP-010
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalDisplayState &&
          runtimeType == other.runtimeType &&
          paneWidth == other.paneWidth &&
          paneHeight == other.paneHeight &&
          screenWidth == other.screenWidth &&
          screenHeight == other.screenHeight &&
          calculatedFontSize == other.calculatedFontSize &&
          needsHorizontalScroll == other.needsHorizontalScroll &&
          horizontalScrollOffset == other.horizontalScrollOffset;

  @override
  // inventory: LEGACY-0192
  int get hashCode => Object.hash(
    paneWidth,
    paneHeight,
    screenWidth,
    screenHeight,
    calculatedFontSize,
    needsHorizontalScroll,
    horizontalScrollOffset,
  );
}

// inventory: PROV-DISP-011
/// ターミナル表示状態を管理するNotifier
class TerminalDisplayNotifier extends Notifier<TerminalDisplayState> {
  @override
  // inventory: PROV-DISP-012
  // inventory: LEGACY-0193
  TerminalDisplayState build() => const TerminalDisplayState();

  // inventory: PROV-DISP-013
  // inventory: LEGACY-0194
  /// ペイン情報を更新
  ///
  /// ペイン選択時に呼び出し、フォントサイズを再計算する。
  void updatePane(TmuxPane pane) {
    // スクロール位置をリセット
    state = state.copyWith(
      paneWidth: pane.width,
      paneHeight: pane.height,
      horizontalScrollOffset: 0.0, // スクロール位置もリセット
    );
    // inventory: PROV-DISP-017
    _recalculateFontSize();
  }

  // inventory: PROV-DISP-014
  // inventory: LEGACY-0195
  /// スクリーン幅を更新
  ///
  /// LayoutBuilder から呼び出される。
  void updateScreenWidth(double width) {
    if (state.screenWidth == width) return; // 変更なしなら何もしない
    state = state.copyWith(screenWidth: width);
    _recalculateFontSize();
  }

  // inventory: PROV-DISP-015
  // inventory: LEGACY-0196
  /// スクリーンサイズを更新
  ///
  /// LayoutBuilder から幅と高さの両方を更新する。
  void updateScreenSize(double width, double height) {
    state = state.copyWith(screenWidth: width, screenHeight: height);
    _recalculateFontSize();
    // inventory: PROV-DISP-018
    _updateScrollRequirement();
  }

  // inventory: PROV-DISP-016
  // inventory: LEGACY-0197
  /// 水平スクロール位置を更新
  void updateHorizontalScrollOffset(double offset) {
    state = state.copyWith(horizontalScrollOffset: offset);
  }

  /// フォントサイズを再計算
  void _recalculateFontSize() {
    final settings = ref.read(settingsProvider);

    final result = FontCalculator.calculate(
      screenWidth: state.screenWidth,
      paneCharWidth: state.paneWidth,
      fontFamily: settings.fontFamily,
      minFontSize: settings.minFontSize,
    );

    state = state.copyWith(
      calculatedFontSize: result.fontSize,
      needsHorizontalScroll: result.needsScroll,
    );
  }

  /// 水平スクロールの必要性を更新
  void _updateScrollRequirement() {
    final settings = ref.read(settingsProvider);
    final terminalWidth = FontCalculator.calculateTerminalWidth(
      paneCharWidth: state.paneWidth,
      fontSize: state.calculatedFontSize,
      fontFamily: settings.fontFamily,
    );

    state = state.copyWith(
      needsHorizontalScroll: terminalWidth > state.screenWidth,
    );
  }

  // inventory: PROV-DISP-019
  // inventory: LEGACY-0198
  /// 設定変更時に再計算を強制
  void onSettingsChanged() {
    _recalculateFontSize();
  }
}

// inventory: PROV-DISP-020
/// ターミナル表示プロバイダー
final terminalDisplayProvider =
    NotifierProvider<TerminalDisplayNotifier, TerminalDisplayState>(
      () => TerminalDisplayNotifier(),
    );

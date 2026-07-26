import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal/font_calculator.dart';
import '../services/tmux/tmux_parser.dart';
import 'settings_provider.dart';

/// ターミナル表示状態
///
/// フォントサイズ、スクロール状態、ズーム状態を管理する。
class TerminalDisplayState {
  /// ペインの横幅（文字数）
  final int paneWidth;

  /// ペインの縦幅（行数）
  final int paneHeight;

  /// 利用可能なスクリーン幅（ピクセル）
  final double screenWidth;

  /// 利用可能なスクリーン高さ（ピクセル）
  final double screenHeight;

  /// 計算されたフォントサイズ
  final double calculatedFontSize;

  /// 水平スクロールが必要か
  final bool needsHorizontalScroll;

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
      needsHorizontalScroll: needsHorizontalScroll ?? this.needsHorizontalScroll,
      horizontalScrollOffset: horizontalScrollOffset ?? this.horizontalScrollOffset,
    );
  }

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

/// ターミナル表示状態を管理するNotifier
class TerminalDisplayNotifier extends Notifier<TerminalDisplayState> {

  @override
  TerminalDisplayState build() => const TerminalDisplayState();

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
    _recalculateFontSize();
  }

  /// スクリーン幅を更新
  ///
  /// LayoutBuilder から呼び出される。
  void updateScreenWidth(double width) {
    if (state.screenWidth == width) return; // 変更なしなら何もしない
    state = state.copyWith(screenWidth: width);
    _recalculateFontSize();
  }

  /// スクリーンサイズを更新
  ///
  /// LayoutBuilder から幅と高さの両方を更新する。
  void updateScreenSize(double width, double height) {
    state = state.copyWith(screenWidth: width, screenHeight: height);
    _recalculateFontSize();
    _updateScrollRequirement();
  }

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

  /// 設定変更時に再計算を強制
  void onSettingsChanged() {
    _recalculateFontSize();
  }
}

/// ターミナル表示プロバイダー
final terminalDisplayProvider =
    NotifierProvider<TerminalDisplayNotifier, TerminalDisplayState>(
  () => TerminalDisplayNotifier(),
);

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal/terminal_controller.dart';

/// ターミナル状態
class TerminalState {
  final MuxTerminalController? controller;
  final bool isInitialized;
  final int cols;
  final int rows;
  final String? title;

  const TerminalState({
    this.controller,
    this.isInitialized = false,
    this.cols = 80,
    this.rows = 24,
    this.title,
  });

  TerminalState copyWith({
    MuxTerminalController? controller,
    bool? isInitialized,
    int? cols,
    int? rows,
    String? title,
  }) {
    return TerminalState(
      controller: controller ?? this.controller,
      isInitialized: isInitialized ?? this.isInitialized,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      title: title ?? this.title,
    );
  }
}

/// ターミナルを管理するNotifier
class TerminalNotifier extends Notifier<TerminalState> {
  @override
  TerminalState build() {
    ref.onDispose(() {
      state.controller?.dispose();
    });
    return const TerminalState();
  }

  /// ターミナルを初期化
  void initialize({TerminalConfig config = const TerminalConfig()}) {
    // 既存のコントローラーがあれば破棄
    state.controller?.dispose();

    final controller = MuxTerminalController(config: config);
    state = TerminalState(
      controller: controller,
      isInitialized: true,
      cols: controller.cols,
      rows: controller.rows,
    );
  }

  /// データを書き込む
  void write(Uint8List data) {
    state.controller?.write(data);
  }

  /// 文字列を書き込む
  void writeString(String data) {
    state.controller?.writeString(data);
  }

  /// サイズを更新
  void updateSize(int cols, int rows) {
    state = state.copyWith(cols: cols, rows: rows);
  }

  /// タイトルを更新
  void updateTitle(String title) {
    state = state.copyWith(title: title);
  }

  /// ターミナルをクリア
  void clear() {
    state.controller?.clear();
  }

  /// コントローラーを破棄
  void disposeController() {
    state.controller?.dispose();
    state = const TerminalState();
  }
}

/// ターミナルプロバイダー
final terminalProvider = NotifierProvider<TerminalNotifier, TerminalState>(() {
  return TerminalNotifier();
});

import 'dart:async';

import '../../models/notification_rule.dart';
import 'notification_engine.dart';

/// ターミナル出力を監視して通知を発行するモニター
///
/// TerminalControllerに接続して出力を監視し、
/// NotificationEngineを使用してパターンマッチを行う。
class NotificationMonitor {
  NotificationMonitor({
    required NotificationEngine engine,
    required String connectionId,
    required String connectionName,
    this.sessionName,
    this.windowName,
    this.paneIndex,
  })  : _engine = engine,
        _connectionId = connectionId,
        _connectionName = connectionName;

  final NotificationEngine _engine;
  final String _connectionId;
  final String _connectionName;
  String? sessionName;
  String? windowName;
  int? paneIndex;

  /// 出力バッファ（行単位で処理するため）
  final StringBuffer _buffer = StringBuffer();

  /// 監視開始
  void start() {
    _engine.startSession(_connectionId);
  }

  /// 監視停止
  void stop() {
    _engine.endSession(_connectionId);
    _buffer.clear();
  }

  /// 出力を処理
  ///
  /// ターミナル出力を受け取り、行単位でパターンマッチングを行う。
  Future<List<NotificationEvent>> processOutput(String output) async {
    _buffer.write(output);

    // 行単位で処理
    final content = _buffer.toString();
    final lines = content.split('\n');

    // 最後の行は未完成の可能性があるので保持
    if (lines.length > 1) {
      _buffer.clear();
      _buffer.write(lines.last);

      // 完成した行を処理
      final events = <NotificationEvent>[];
      for (var i = 0; i < lines.length - 1; i++) {
        final line = _stripAnsiCodes(lines[i]);
        if (line.trim().isEmpty) continue;

        final lineEvents = await _engine.processOutput(
          text: line,
          connectionId: _connectionId,
          connectionName: _connectionName,
          sessionName: sessionName,
          windowName: windowName,
          paneIndex: paneIndex,
        );

        events.addAll(lineEvents);
      }

      return events;
    }

    return [];
  }

  /// ANSIエスケープコードを除去
  String _stripAnsiCodes(String text) {
    // ANSIエスケープシーケンスを除去する正規表現
    final ansiPattern = RegExp(r'\x1B\[[0-9;]*[A-Za-z]|\x1B\].*?\x07');
    return text.replaceAll(ansiPattern, '');
  }

  /// tmuxコンテキストを更新
  void updateContext({
    String? sessionName,
    String? windowName,
    int? paneIndex,
  }) {
    if (sessionName != null) this.sessionName = sessionName;
    if (windowName != null) this.windowName = windowName;
    if (paneIndex != null) this.paneIndex = paneIndex;
  }
}

/// NotificationMonitorのファクトリ
class NotificationMonitorFactory {
  NotificationMonitorFactory({
    required NotificationEngine engine,
  }) : _engine = engine;

  final NotificationEngine _engine;
  final Map<String, NotificationMonitor> _monitors = {};

  /// モニター作成または取得
  NotificationMonitor getOrCreate({
    required String connectionId,
    required String connectionName,
    String? sessionName,
    String? windowName,
    int? paneIndex,
  }) {
    return _monitors.putIfAbsent(connectionId, () {
      final monitor = NotificationMonitor(
        engine: _engine,
        connectionId: connectionId,
        connectionName: connectionName,
        sessionName: sessionName,
        windowName: windowName,
        paneIndex: paneIndex,
      );
      monitor.start();
      return monitor;
    });
  }

  /// モニター取得
  NotificationMonitor? get(String connectionId) {
    return _monitors[connectionId];
  }

  /// モニター削除
  void remove(String connectionId) {
    final monitor = _monitors.remove(connectionId);
    monitor?.stop();
  }

  /// 全モニター削除
  void clear() {
    for (final monitor in _monitors.values) {
      monitor.stop();
    }
    _monitors.clear();
  }
}

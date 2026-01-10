import 'dart:collection';

import 'package:flutter/foundation.dart';

/// アプリケーションエラーハンドラー
///
/// エラーのログ記録と報告を一元管理する。
class ErrorHandler {
  ErrorHandler._();

  static final ErrorHandler instance = ErrorHandler._();

  /// 最近のエラー履歴（最大100件）
  final Queue<ErrorRecord> _errorHistory = Queue();
  static const int _maxHistorySize = 100;

  /// エラーリスナー
  final List<void Function(ErrorRecord)> _listeners = [];

  /// エラーを報告
  void reportError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  }) {
    final record = ErrorRecord(
      error: error,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
      timestamp: DateTime.now(),
    );

    // 履歴に追加
    _errorHistory.addLast(record);
    if (_errorHistory.length > _maxHistorySize) {
      _errorHistory.removeFirst();
    }

    // デバッグログ
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════');
      debugPrint('ERROR [${record.context ?? 'Unknown'}]');
      debugPrint('Time: ${record.timestamp}');
      debugPrint('Error: $error');
      if (stackTrace != null) {
        debugPrint('Stack trace:');
        debugPrint(stackTrace.toString().split('\n').take(10).join('\n'));
      }
      if (extra != null && extra.isNotEmpty) {
        debugPrint('Extra: $extra');
      }
      debugPrint('═══════════════════════════════════════');
    }

    // リスナーに通知
    for (final listener in _listeners) {
      try {
        listener(record);
      } catch (e) {
        // リスナー内でのエラーは無視
        if (kDebugMode) {
          debugPrint('Error in error listener: $e');
        }
      }
    }

    // TODO: 将来的にCrashlyticsなどに送信
  }

  /// エラーリスナーを追加
  void addListener(void Function(ErrorRecord) listener) {
    _listeners.add(listener);
  }

  /// エラーリスナーを削除
  void removeListener(void Function(ErrorRecord) listener) {
    _listeners.remove(listener);
  }

  /// エラー履歴を取得
  List<ErrorRecord> get errorHistory => _errorHistory.toList();

  /// エラー履歴をクリア
  void clearHistory() {
    _errorHistory.clear();
  }

  /// 最新のエラーを取得
  ErrorRecord? get latestError =>
      _errorHistory.isNotEmpty ? _errorHistory.last : null;
}

/// エラー記録
class ErrorRecord {
  const ErrorRecord({
    required this.error,
    this.stackTrace,
    this.context,
    this.extra,
    required this.timestamp,
  });

  final Object error;
  final StackTrace? stackTrace;
  final String? context;
  final Map<String, dynamic>? extra;
  final DateTime timestamp;

  String get errorMessage => error.toString();

  String get shortStackTrace {
    if (stackTrace == null) return '';
    final lines = stackTrace.toString().split('\n');
    return lines.take(5).join('\n');
  }

  @override
  String toString() {
    return 'ErrorRecord(context: $context, error: $error, time: $timestamp)';
  }
}

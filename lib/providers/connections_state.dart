import 'connection.dart';

/// 接続一覧の状態
class ConnectionsState {
  final List<Connection> connections;
  final bool isLoading;
  final String? error;

  /// 読み込めなかった破損レコード一覧。
  final List<CorruptedConnection> corruptedRecords;

  /// ユーザー向けの非機密警告（マイグレーションや破損レカウント）。
  final String? warning;

  static const Object _kKeepSentinel = Object();

  const ConnectionsState({
    this.connections = const [],
    this.isLoading = false,
    this.error,
    this.corruptedRecords = const [],
    this.warning,
  });

  ConnectionsState copyWith({
    List<Connection>? connections,
    bool? isLoading,
    String? error,
    List<CorruptedConnection>? corruptedRecords,
    Object? warning = _kKeepSentinel,
  }) {
    return ConnectionsState(
      connections: connections ?? this.connections,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      corruptedRecords: corruptedRecords ?? this.corruptedRecords,
      warning: warning == _kKeepSentinel ? this.warning : warning as String?,
    );
  }
}

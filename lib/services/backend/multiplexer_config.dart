import 'backend_type.dart';

/// マルチプレクサ（backend）の接続設定。
///
/// どの backend を使うか（[backend]）と、必要に応じてその実行ファイルの
/// 絶対パス（[executablePath]）を保持する。
class MultiplexerConfig {
  /// 使用する backend。
  final BackendType backend;

  /// ユーザー指定の実行ファイルパス（null なら自動検出）。
  final String? executablePath;

  /// copyWith のクリア用センチネル。
  static const _kClearSentinel = Object();

  const MultiplexerConfig({
    required this.backend,
    this.executablePath,
  });

  /// tmux backend 用の簡易コンストラクタ。
  const MultiplexerConfig.tmux([String? executablePath])
      : this(
          backend: BackendType.tmux,
          executablePath: executablePath,
        );

  /// 部分的に値を更新したコピーを返す。
  ///
  /// [executablePath] に `null` を渡すと `executablePath` をクリアできる。
  MultiplexerConfig copyWith({
    BackendType? backend,
    Object? executablePath = _kClearSentinel,
  }) {
    return MultiplexerConfig(
      backend: backend ?? this.backend,
      executablePath: executablePath == _kClearSentinel
          ? this.executablePath
          : executablePath as String?,
    );
  }

  /// JSON としてシリアライズする。
  Map<String, dynamic> toJson() {
    return {
      'backend': backend.toJson(),
      'executablePath': executablePath,
    };
  }

  /// JSON から復元する。
  ///
  /// 未知の backend 文字列が与えられた場合は [FormatException] を投げる。
  factory MultiplexerConfig.fromJson(Map<String, dynamic> json) {
    final backendValue = json['backend'];
    if (backendValue is! String) {
      throw FormatException(
        'backend must be a string: ${json['backend']}',
      );
    }
    final backend = BackendType.fromJson(backendValue);
    return MultiplexerConfig(
      backend: backend,
      executablePath: json['executablePath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexerConfig &&
          runtimeType == other.runtimeType &&
          backend == other.backend &&
          executablePath == other.executablePath;

  @override
  int get hashCode => Object.hash(backend, executablePath);

  @override
  String toString() =>
      'MultiplexerConfig(backend: ${backend.name}, executablePath: $executablePath)';
}

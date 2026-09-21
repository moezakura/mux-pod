import 'dart:typed_data';

import '../backend/multiplexer_config.dart';

// inventory: SSH-003
/// SSH接続オプション
class SshConnectOptions {
  // inventory: SSH-004
  // inventory: LEGACY-0128
  /// パスワード認証時のパスワード
  final String? password;

  // inventory: SSH-005
  // inventory: LEGACY-0129
  /// 鍵認証時の秘密鍵（PEM形式）
  final String? privateKey;

  // inventory: SSH-006
  // inventory: LEGACY-0130
  /// 秘密鍵のパスフレーズ
  final String? passphrase;

  // inventory: SSH-007
  /// マルチプレクサ設定（nullなら自動検出）
  final MultiplexerConfig? multiplexer;

  // inventory: SSH-008
  // inventory: LEGACY-0132
  /// 接続タイムアウト（秒）
  final int timeout;

  // inventory: SSH-043
  /// 未知のホスト鍵を自動受け入れする（TOFU）。
  /// false の場合、未保存ホストは拒否する。
  final bool acceptNewHostKeys;

  SshConnectOptions({
    this.password,
    this.privateKey,
    this.passphrase,
    this.multiplexer,
    this.timeout = 30,
    this.acceptNewHostKeys = true,
  });
}

// inventory: SSH-009
/// シェルオプション
class ShellOptions {
  // inventory: SSH-010
  // inventory: LEGACY-0133
  /// ターミナルタイプ
  final String term;

  // inventory: SSH-011
  // inventory: LEGACY-0134
  /// カラム数
  final int cols;

  // inventory: SSH-012
  // inventory: LEGACY-0135
  /// 行数
  final int rows;

  const ShellOptions({
    this.term = 'xterm-256color',
    this.cols = 80,
    this.rows = 24,
  });
}

// inventory: SSH-013
/// SSH接続イベント
class SshEvents {
  // inventory: SSH-014
  // inventory: LEGACY-0136
  /// データ受信時
  final void Function(Uint8List data)? onData;

  // inventory: SSH-015
  /// 接続クローズ時
  final void Function()? onClose;

  // inventory: SSH-016
  /// エラー発生時
  final void Function(Object error)? onError;

  const SshEvents({this.onData, this.onClose, this.onError});

  // inventory: SSH-017
  // inventory: LEGACY-0137
  SshEvents copyWith({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    return SshEvents(
      onData: onData ?? this.onData,
      onClose: onClose ?? this.onClose,
      onError: onError ?? this.onError,
    );
  }
}

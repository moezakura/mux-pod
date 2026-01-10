/// Tmux Service Contract
///
/// tmuxセッション/ウィンドウ/ペイン操作のサービス層インターフェース。
/// SSHサービスに依存し、tmuxコマンドをラップする。

import 'dart:async';

import '../models/tmux.dart';

/// tmuxサービスインターフェース
abstract class TmuxService {
  /// セッション一覧取得
  Future<List<TmuxSession>> listSessions(String connectionId);

  /// ウィンドウ一覧取得
  Future<List<TmuxWindow>> listWindows({
    required String connectionId,
    required String sessionName,
  });

  /// ペイン一覧取得
  Future<List<TmuxPane>> listPanes({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
  });

  /// ペイン内容取得
  Future<List<String>> capturePane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  });

  /// キー送信
  Future<void> sendKeys({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    required String keys,
    bool literal = false,
  });

  /// ペイン選択
  Future<void> selectPane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  });

  /// ウィンドウ選択
  Future<void> selectWindow({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
  });

  /// セッション作成
  Future<void> newSession({
    required String connectionId,
    required String name,
  });

  /// セッション削除
  Future<void> killSession({
    required String connectionId,
    required String name,
  });

  /// ペインリサイズ
  Future<void> resizePane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    required int width,
    required int height,
  });

  /// tmuxインストール確認
  Future<bool> isTmuxInstalled(String connectionId);

  /// tmuxバージョン取得
  Future<String?> getTmuxVersion(String connectionId);
}

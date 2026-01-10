/// Storage Service Contract
///
/// データ永続化のサービス層インターフェース。
/// セキュアストレージと通常ストレージを統合。

import 'dart:async';

import '../models/connection.dart';
import '../models/app_settings.dart';

/// ストレージサービスインターフェース
abstract class StorageService {
  // === Connection ===

  /// 接続一覧取得
  Future<List<Connection>> getConnections();

  /// 接続取得
  Future<Connection?> getConnection(String id);

  /// 接続保存
  Future<void> saveConnection(Connection connection);

  /// 接続削除
  Future<void> deleteConnection(String id);

  /// パスワード保存（暗号化）
  Future<void> savePassword({
    required String connectionId,
    required String password,
  });

  /// パスワード取得
  Future<String?> getPassword(String connectionId);

  /// パスワード削除
  Future<void> deletePassword(String connectionId);

  // === Settings ===

  /// 設定取得
  Future<AppSettings> getSettings();

  /// 設定保存
  Future<void> saveSettings(AppSettings settings);

  /// 設定リセット
  Future<void> resetSettings();

  // === Migration ===

  /// データエクスポート（JSON形式）
  Future<String> exportData();

  /// データインポート（JSON形式）
  Future<void> importData(String json);

  /// 全データクリア
  Future<void> clearAll();
}

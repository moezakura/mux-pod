import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 汎用ストレージサービス
///
/// SharedPreferences を使用して非機密データを保存する。
/// - 接続メタデータ
/// - SSH鍵メタデータ
/// - 通知ルール
/// - アプリ設定
class StorageService {
  StorageService({
    SharedPreferences? prefs,
  }) : _prefs = prefs;

  SharedPreferences? _prefs;

  // === キー定義 ===
  static const String connectionsKey = 'connections';
  static const String sshKeysKey = 'ssh_keys';
  static const String notificationRulesKey = 'notification_rules';
  static const String appSettingsKey = 'app_settings';

  /// 初期化
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// SharedPreferences インスタンス取得
  SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError('StorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // === JSON保存・読み込み ===

  /// JSONオブジェクトを保存
  Future<bool> saveJson(String key, Map<String, dynamic> json) async {
    final encoded = jsonEncode(json);
    return prefs.setString(key, encoded);
  }

  /// JSONオブジェクトを読み込み
  Map<String, dynamic>? getJson(String key) {
    final encoded = prefs.getString(key);
    if (encoded == null) return null;
    return jsonDecode(encoded) as Map<String, dynamic>;
  }

  /// JSONリストを保存
  Future<bool> saveJsonList(String key, List<Map<String, dynamic>> list) async {
    final encoded = jsonEncode(list);
    return prefs.setString(key, encoded);
  }

  /// JSONリストを読み込み
  List<Map<String, dynamic>> getJsonList(String key) {
    final encoded = prefs.getString(key);
    if (encoded == null) return [];
    final decoded = jsonDecode(encoded) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  // === プリミティブ型 ===

  /// 文字列を保存
  Future<bool> setString(String key, String value) async {
    return prefs.setString(key, value);
  }

  /// 文字列を取得
  String? getString(String key) {
    return prefs.getString(key);
  }

  /// 整数を保存
  Future<bool> setInt(String key, int value) async {
    return prefs.setInt(key, value);
  }

  /// 整数を取得
  int? getInt(String key) {
    return prefs.getInt(key);
  }

  /// ブール値を保存
  Future<bool> setBool(String key, bool value) async {
    return prefs.setBool(key, value);
  }

  /// ブール値を取得
  bool? getBool(String key) {
    return prefs.getBool(key);
  }

  // === ユーティリティ ===

  /// キーを削除
  Future<bool> remove(String key) async {
    return prefs.remove(key);
  }

  /// すべてのデータをクリア
  Future<bool> clear() async {
    return prefs.clear();
  }

  /// キーが存在するか確認
  bool containsKey(String key) {
    return prefs.containsKey(key);
  }
}

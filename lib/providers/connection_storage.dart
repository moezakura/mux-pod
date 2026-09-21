import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/connection/connection_migration.dart';
import '../services/keychain/secure_storage.dart';
import 'connection.dart';
import 'connections_state.dart';

/// 接続レコードの永続化。
///
/// SecureStorage 読み書き、SharedPreferences からの引継ぎコピー、
/// ConnectionMigration 実行、破損レコード収集・警告文言の組み立てを担う。
/// JSON 変換・永続化の詳細だけを知る。アプリ内専用（internal）。
class ConnectionStorage {
  static const String storageKey = 'connections';

  /// 接続一覧を読み込み、ロード結果の [ConnectionsState] を返す。
  ///
  /// l10n はロード時点で解決した [AppLocalizations] を渡す（移譲元が
  /// [lookupL10n] の結果を resolve する現行挙動を維持）。
  Future<ConnectionsState> load(AppLocalizations l10n) async {
    developer.log('_loadConnections() started', name: 'ConnectionsProvider');
    try {
      final secure = SecureStorageService();
      String? jsonString = await secure.readValue(storageKey);

      // 古いSharedPreferencesからの移行
      SharedPreferences? prefs;
      var fromSharedPreferences = false;
      if (jsonString == null) {
        prefs = await SharedPreferences.getInstance();
        final sharedPrefsJson = prefs.getString(storageKey);
        if (sharedPrefsJson != null) {
          await secure.writeValue(storageKey, sharedPrefsJson);
          jsonString = sharedPrefsJson;
          fromSharedPreferences = true;
          developer.log(
            'Copied connections from SharedPreferences to secure storage for migration',
            name: 'ConnectionsProvider',
          );
        }
      }

      developer.log(
        'JSON from storage: ${jsonString != null ? 'exists' : 'null'}',
        name: 'ConnectionsProvider',
      );

      // 旧 tmuxPath から multiplexer へのマイグレーション
      final migrationResult = await ConnectionMigration.migrate(
        secure: secure,
        sourceJson: jsonString,
        l10n: l10n,
      );

      // SharedPreferences コピーは schema migration が成功してから削除
      if (fromSharedPreferences &&
          migrationResult.error == null &&
          migrationResult.json != null) {
        await prefs?.remove(storageKey);
        developer.log(
          'Removed migrated SharedPreferences copy',
          name: 'ConnectionsProvider',
        );
      }

      if (migrationResult.error != null && migrationResult.json == null) {
        developer.log(
          'Migration error: ${migrationResult.error}',
          name: 'ConnectionsProvider',
        );
        return ConnectionsState(
          error: migrationResult.error,
          warning: migrationResult.warning,
        );
      }

      jsonString = migrationResult.json;

      if (jsonString != null) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        final connections = <Connection>[];
        final corruptedRecords = <CorruptedConnection>[];

        for (final record in jsonList) {
          try {
            if (record is! Map<String, dynamic>) {
              throw FormatException('Record is not a JSON object');
            }
            connections.add(Connection.fromJson(record));
          } catch (e, stackTrace) {
            developer.log(
              'Corrupted connection record: $e',
              name: 'ConnectionsProvider',
              error: e,
              stackTrace: stackTrace,
            );
            final id = record is Map<String, dynamic>
                ? record['id'] as String?
                : null;
            corruptedRecords.add(
              CorruptedConnection(
                id: id,
                reason: l10n.connCorruptedRecordReason('$e'),
                rawJson: record is Map<String, dynamic> ? record : null,
              ),
            );
          }
        }

        developer.log(
          'Loaded ${connections.length} healthy and ${corruptedRecords.length} corrupted connection records from storage',
          name: 'ConnectionsProvider',
        );

        // 最終接続日時で並び替え（降順）
        connections.sort((a, b) {
          final aTime = a.lastConnectedAt ?? a.createdAt;
          final bTime = b.lastConnectedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });

        String? warning;
        if (corruptedRecords.isNotEmpty) {
          warning = l10n.connCorruptedWarning(corruptedRecords.length);
        }
        if (migrationResult.warning != null) {
          warning = warning == null
              ? migrationResult.warning
              : '$warning ${migrationResult.warning}';
        }

        developer.log(
          'State updated with ${connections.length} connections, ${corruptedRecords.length} corrupted records',
          name: 'ConnectionsProvider',
        );
        return ConnectionsState(
          connections: connections,
          corruptedRecords: corruptedRecords,
          warning: warning,
          error: migrationResult.error,
        );
      }

      developer.log(
        'No saved connections, initialized empty state',
        name: 'ConnectionsProvider',
      );
      return ConnectionsState(warning: migrationResult.warning);
    } catch (e, stackTrace) {
      developer.log(
        'Error loading connections: $e',
        name: 'ConnectionsProvider',
        error: e,
        stackTrace: stackTrace,
      );
      return ConnectionsState(error: e.toString());
    }
  }

  /// 接続一覧を SecureStorage へ保存する。
  Future<void> save(List<Connection> connections) async {
    final secure = SecureStorageService();
    final jsonList = connections.map((c) => c.toJson()).toList();
    await secure.writeValue(storageKey, jsonEncode(jsonList));
  }
}

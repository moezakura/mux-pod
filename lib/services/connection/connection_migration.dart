import 'dart:convert';

import '../backend/multiplexer_config.dart';
import '../keychain/secure_storage.dart';
import 'connection_storage_schema.dart';

/// 接続設定のマイグレーション結果。
class ConnectionMigrationResult {
  /// 最終的に読み込むべき JSON 文字列。
  final String? json;

  /// ユーザー向け警告（非機密）。
  final String? warning;

  /// ユーザー向けエラー（非機密）。
  final String? error;

  const ConnectionMigrationResult({this.json, this.warning, this.error});

  @override
  String toString() {
    return 'ConnectionMigrationResult(json: ${json != null ? '...' : null}, warning: $warning, error: $error)';
  }
}

/// 接続設定の旧 `tmuxPath` から `multiplexer` 形式へのマイグレーション。
///
/// `storageSchemaVersion == [ConnectionStorageSchema.current]` のレコードは
/// 新形式（downgrade 互換の `tmuxPath` を保持）として migration をスキップ
/// する。旧形式レコードのみを対象に、backup / rollback / recovery を持ち
/// 原子性を保つ。
class ConnectionMigration {
  static const String _storageKey = 'connections';
  static const String _backupKey = 'connections_backup_v2';

  ConnectionMigration._();

  /// [sourceJson] を `multiplexer` 形式にマイグレーションする。
  ///
  /// [secure] を使って backup / primary の読み書きを行う。
  /// [sourceJson] が null の場合は空の結果を返す。
  static Future<ConnectionMigrationResult> migrate({
    required SecureStorageService secure,
    required String? sourceJson,
  }) async {
    if (sourceJson == null) {
      // 古い backup が残っている場合は削除しておく
      await _deleteStaleBackup(secure);
      return const ConnectionMigrationResult(json: null);
    }

    // 1. read source（呼び出し側で読み込み済み）
    // 2. validate source
    List<dynamic>? sourceList;
    try {
      final decoded = jsonDecode(sourceJson);
      if (decoded is! List) {
        throw FormatException('Stored connections is not a JSON list');
      }
      sourceList = decoded;
    } catch (e) {
      // Source invalid; try backup
      return _recoverFromBackup(secure, e);
    }

    // マイグレーションが必要かチェック
    final needsMigration = _listNeedsMigration(sourceList);
    if (!needsMigration) {
      await _deleteStaleBackup(secure);
      return ConnectionMigrationResult(json: sourceJson);
    }

    // 3. write backup
    try {
      await secure.writeValue(_backupKey, sourceJson);
    } catch (e) {
      return ConnectionMigrationResult(
        json: sourceJson,
        error:
            'Failed to create backup before migration. Primary storage was not changed.',
        warning: 'Migration backup creation failed: $e',
      );
    }

    // 4. read-back validate backup
    final backupReadJson = await secure.readValue(_backupKey);
    if (backupReadJson == null ||
        !_jsonEquals(jsonDecode(backupReadJson), sourceList)) {
      return ConnectionMigrationResult(
        json: sourceJson,
        error:
            'Backup validation failed. Migration was not performed to avoid data loss.',
      );
    }

    // 5. migrate records
    List<Map<String, dynamic>> migratedList;
    try {
      migratedList = sourceList
          .map((record) => _migrateRecord(record as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Migration of a record failed; rollback and return source
      final rollbackError = await _rollback(secure, sourceJson);
      if (rollbackError != null) {
        return ConnectionMigrationResult(
          json: sourceJson,
          error:
              'Migration of a connection record failed and data rollback also failed. $rollbackError',
          warning: 'Original error: $e',
        );
      }
      return ConnectionMigrationResult(
        json: sourceJson,
        warning:
            'Migration of a connection record failed: $e. Original data preserved.',
      );
    }
    final migratedJson = jsonEncode(migratedList);

    // 6. write migrated primary
    try {
      await secure.writeValue(_storageKey, migratedJson);
    } catch (e) {
      final rollbackError = await _rollback(secure, sourceJson);
      if (rollbackError != null) {
        return ConnectionMigrationResult(
          json: sourceJson,
          error:
              'Failed to write migrated storage and data rollback also failed. $rollbackError',
          warning: 'Original error: $e',
        );
      }
      return ConnectionMigrationResult(
        json: sourceJson,
        warning:
            'Failed to write migrated storage: $e. Original data restored.',
      );
    }

    // 7. read-back validate primary
    final primaryReadJson = await secure.readValue(_storageKey);
    var primaryValid = false;
    if (primaryReadJson != null) {
      try {
        primaryValid = _jsonEquals(jsonDecode(primaryReadJson), migratedList);
      } catch (_) {
        primaryValid = false;
      }
    }
    if (primaryReadJson == null || !primaryValid) {
      final rollbackError = await _rollback(secure, sourceJson);
      if (rollbackError != null) {
        return ConnectionMigrationResult(
          json: sourceJson,
          error:
              'Migrated storage validation failed and data rollback also failed. $rollbackError',
        );
      }
      return ConnectionMigrationResult(
        json: sourceJson,
        error:
            'Migrated storage validation failed. Original data restored. Please check storage space or reinstall the app.',
      );
    }

    // 8. delete backup on success
    try {
      await secure.deleteValue(_backupKey);
    } catch (_) {
      // backup deletion failure is not critical
    }

    return ConnectionMigrationResult(json: primaryReadJson);
  }

  static bool _listNeedsMigration(List<dynamic> list) {
    for (final record in list) {
      if (record is Map<String, dynamic> &&
          !_isCurrentSchemaRecord(record) &&
          record.containsKey('tmuxPath')) {
        return true;
      }
    }
    return false;
  }

  /// [record] が現在スキーマ（`storageSchemaVersion == current`）かどうか。
  ///
  /// 現在スキーマのレコードは downgrade 互換の `tmuxPath` を含み得るため、
  /// `tmuxPath` の有無だけでは migration 要否を判定できない（G6 合意#4）。
  static bool _isCurrentSchemaRecord(Map<String, dynamic> record) {
    return record.containsKey('storageSchemaVersion') &&
        record['storageSchemaVersion'] == ConnectionStorageSchema.current;
  }

  static Map<String, dynamic> _migrateRecord(Map<String, dynamic> record) {
    // 現在スキーマのレコードは downgrade 互換の tmuxPath を保持するため変更しない。
    if (_isCurrentSchemaRecord(record)) {
      return record;
    }
    final newRecord = Map<String, dynamic>.of(record);
    final hasMultiplexer = newRecord.containsKey('multiplexer');
    if (newRecord.containsKey('tmuxPath')) {
      final tmuxPath = newRecord.remove('tmuxPath') as String?;
      if (!hasMultiplexer) {
        final executablePath = tmuxPath?.isNotEmpty == true ? tmuxPath : null;
        newRecord['multiplexer'] = MultiplexerConfig.tmux(
          executablePath,
        ).toJson();
      }
    }
    return newRecord;
  }

  /// primary に [sourceJson] を書き戻す。失敗したら backup を読み込んで
  /// primary を復旧する。それでも失敗したら非機密エラーメッセージを返す。
  static Future<String?> _rollback(
    SecureStorageService secure,
    String sourceJson,
  ) async {
    try {
      await secure.writeValue(_storageKey, sourceJson);
      return null;
    } catch (_) {
      // primary への source 復元に失敗したら backup から復旧を試みる
      final backupJson = await secure.readValue(_backupKey);
      if (backupJson != null) {
        try {
          await secure.writeValue(_storageKey, backupJson);
          return null;
        } catch (_) {}
      }
      return 'Failed to restore connection data from backup. Please check storage space or reinstall the app.';
    }
  }

  static Future<ConnectionMigrationResult> _recoverFromBackup(
    SecureStorageService secure,
    Object cause,
  ) async {
    final backupJson = await secure.readValue(_backupKey);
    if (backupJson != null) {
      try {
        final backupList = jsonDecode(backupJson) as List<dynamic>;
        if (backupList.isNotEmpty) {
          // Attempt to restore backup to primary
          try {
            await secure.writeValue(_storageKey, backupJson);
          } catch (e) {
            // Primary restore failed, but backup is still readable
            return ConnectionMigrationResult(
              json: backupJson,
              warning:
                  'Stored connections were invalid; using available backup. Error: $cause. Primary restore failed: $e',
            );
          }
          return ConnectionMigrationResult(
            json: backupJson,
            warning:
                'Stored connections were invalid; restored from backup. Error: $cause',
          );
        }
      } catch (_) {
        // backup is also invalid
      }
    }
    return ConnectionMigrationResult(
      error:
          'Stored connections are invalid and no usable backup is available. Please re-add your connections or clear app data.',
      warning: 'Original error: $cause',
    );
  }

  static Future<void> _deleteStaleBackup(SecureStorageService secure) async {
    try {
      final existing = await secure.readValue(_backupKey);
      if (existing != null) {
        await secure.deleteValue(_backupKey);
      }
    } catch (_) {
      // ignore
    }
  }

  static bool _jsonEquals(dynamic a, dynamic b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}

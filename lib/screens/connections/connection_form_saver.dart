import 'dart:developer' as developer;

import '../../providers/connection_provider.dart';
import '../../services/connection/proxy_config.dart' show ProxyConfig;
import '../../services/keychain/secure_storage.dart';
import 'connection_form_values.dart';

/// 接続設定の永続化（パスワード保存・[Connection] 構築・add/update）。
///
/// Riverpod には依存しない。[ConnectionsNotifier] は呼出元（State）が
/// `ref.read(connectionsProvider.notifier)` で取得して注入する。
class ConnectionSaver {
  const ConnectionSaver();

  Future<void> save({
    required String connectionId,
    required bool isEditing,
    required ConnectionFormValues values,
    required ConnectionsNotifier notifier,
  }) async {
    if (values.authMethod == 'password' && values.password.isNotEmpty) {
      developer.log(
        'Saving password to secure storage...',
        name: 'ConnectionForm',
      );
      final storage = SecureStorageService();
      await storage.savePassword(connectionId, values.password);
      developer.log('Password saved successfully', name: 'ConnectionForm');
    }

    final proxy = values.buildProxy();
    await _syncProxyCredentials(
      connectionId: connectionId,
      isEditing: isEditing,
      proxy: proxy,
      values: values,
      notifier: notifier,
    );

    final connection = Connection(
      id: connectionId,
      name: values.name,
      host: values.host,
      port: values.port,
      username: values.username,
      authMethod: values.authMethod,
      keyId: values.authMethod == 'key' ? values.keyId : null,
      multiplexer: values.buildMultiplexer(),
      proxy: proxy,
      keepAliveTimeoutSeconds: values.keepAliveTimeoutSecondsOrNull,
      deepLinkId: values.deepLinkIdOrNull,
      createdAt: isEditing
          ? notifier.getById(connectionId)?.createdAt ?? DateTime.now()
          : DateTime.now(),
    );
    developer.log(
      'Connection object created: ${connection.name}',
      name: 'ConnectionForm',
    );

    if (isEditing) {
      developer.log('Updating existing connection...', name: 'ConnectionForm');
      await notifier.update(connection);
      developer.log('Connection updated successfully', name: 'ConnectionForm');
    } else {
      developer.log('Adding new connection...', name: 'ConnectionForm');
      await notifier.add(connection);
      developer.log('Connection added successfully', name: 'ConnectionForm');
    }
  }

  /// ジャンプホスト認証情報の書き込みと掃除（MR-4・🤝2 orphan 対応）。
  ///
  /// - proxy 無効化 Save → 全 hop キー削除。
  /// - hop 数が減った Save → 減った分の index を削除（orphan 掃除）。
  /// - hop を key 認証へ切替 → 当該 hop のパスワードキー削除。
  /// - 編集時の空欄パスワード → 既存値維持（削除・上書きしない）。
  Future<void> _syncProxyCredentials({
    required String connectionId,
    required bool isEditing,
    required ProxyConfig? proxy,
    required ConnectionFormValues values,
    required ConnectionsNotifier notifier,
  }) async {
    final storage = SecureStorageService();
    if (proxy == null) {
      if (isEditing) {
        await storage.deleteProxyPassword(connectionId);
      }
      return;
    }

    // 編集時の旧設定（orphan 掃除・切替掃除の比較元）。
    final previous = isEditing ? notifier.getById(connectionId) : null;
    final previousProxy = previous?.proxy;
    final previousHops = previousProxy?.hops;
    final inputHops = values.proxyHops;

    for (var i = 0; i < proxy.hops.length; i++) {
      final hop = proxy.hops[i];
      if (hop.authMethod == 'password') {
        final password = i < inputHops.length ? inputHops[i].passwordText : '';
        if (password.isNotEmpty) {
          await storage.saveProxyPassword(connectionId, i, password);
        }
        // 空欄 = 既存値維持（削除しない）。
      } else {
        // key 認証へ切替 → 旧パスワードキーを掃除。
        final previousWasPassword =
            previousHops != null &&
            i < previousHops.length &&
            previousHops[i].authMethod == 'password';
        if (previousWasPassword) {
          await storage.deleteProxyPassword(connectionId, hopIndex: i);
        }
      }
    }

    // hop 縮小の orphan 掃除（🤝2）。
    final previousHopCount = previousHops?.length ?? 0;
    for (var i = proxy.hops.length; i < previousHopCount; i++) {
      await storage.deleteProxyPassword(connectionId, hopIndex: i);
    }
  }
}

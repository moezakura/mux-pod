import 'dart:developer' as developer;

import '../../providers/connection_provider.dart';
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

    final connection = Connection(
      id: connectionId,
      name: values.name,
      host: values.host,
      port: values.port,
      username: values.username,
      authMethod: values.authMethod,
      keyId: values.authMethod == 'key' ? values.keyId : null,
      multiplexer: values.buildMultiplexer(),
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
}

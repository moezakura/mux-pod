import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/connections/connections_screen.dart';
import '../screens/connections/connection_form_screen.dart';
import '../screens/terminal/terminal_screen.dart';
import '../screens/keys/keys_screen.dart';
import '../screens/keys/key_generate_screen.dart';
import '../screens/keys/key_import_screen.dart';
import '../screens/notifications/notification_rules_screen.dart';
import '../screens/settings/settings_screen.dart';

/// ルート名定義
abstract class AppRoutes {
  static const String connections = '/';
  static const String connectionForm = '/connection/:id';
  static const String connectionNew = '/connection/new';
  static const String terminal = '/terminal/:connectionId';
  static const String keys = '/keys';
  static const String keyGenerate = '/keys/generate';
  static const String keyImport = '/keys/import';
  static const String notifications = '/notifications';
  static const String settings = '/settings';
}

/// GoRouter プロバイダー
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.connections,
    routes: [
      // 接続一覧（ホーム）
      GoRoute(
        path: AppRoutes.connections,
        name: 'connections',
        builder: (context, state) => const ConnectionsScreen(),
      ),

      // 接続追加
      GoRoute(
        path: AppRoutes.connectionNew,
        name: 'connection-new',
        builder: (context, state) => const ConnectionFormScreen(),
      ),

      // 接続編集
      GoRoute(
        path: '/connection/:id',
        name: 'connection-edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ConnectionFormScreen(connectionId: id);
        },
      ),

      // ターミナル
      GoRoute(
        path: '/terminal/:connectionId',
        name: 'terminal',
        builder: (context, state) {
          final connectionId = state.pathParameters['connectionId']!;
          return TerminalScreen(connectionId: connectionId);
        },
      ),

      // SSH鍵一覧
      GoRoute(
        path: AppRoutes.keys,
        name: 'keys',
        builder: (context, state) => const KeysScreen(),
      ),

      // 鍵生成
      GoRoute(
        path: AppRoutes.keyGenerate,
        name: 'key-generate',
        builder: (context, state) => const KeyGenerateScreen(),
      ),

      // 鍵インポート
      GoRoute(
        path: AppRoutes.keyImport,
        name: 'key-import',
        builder: (context, state) => const KeyImportScreen(),
      ),

      // 通知ルール
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationRulesScreen(),
      ),

      // 設定
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 選択中接続IDを管理するNotifier
class SelectedConnectionIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) {
    state = id;
  }
}

/// 検索クエリを管理するNotifier
class ConnectionSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

/// 検索クエリプロバイダー
final connectionSearchProvider =
    NotifierProvider<ConnectionSearchNotifier, String>(() {
      return ConnectionSearchNotifier();
    });

/// ソートオプション
enum ConnectionSortOption {
  nameAsc,
  nameDesc,
  lastConnectedDesc,
  lastConnectedAsc,
  hostAsc,
  hostDesc,
}

/// ソートオプションを管理するNotifier
class ConnectionSortNotifier extends Notifier<ConnectionSortOption> {
  @override
  ConnectionSortOption build() => ConnectionSortOption.lastConnectedDesc;

  void setSort(ConnectionSortOption option) {
    state = option;
  }
}

/// ソートオプションプロバイダー
final connectionSortProvider =
    NotifierProvider<ConnectionSortNotifier, ConnectionSortOption>(() {
      return ConnectionSortNotifier();
    });

/// 現在選択中の接続IDプロバイダー
final selectedConnectionIdProvider =
    NotifierProvider<SelectedConnectionIdNotifier, String?>(() {
      return SelectedConnectionIdNotifier();
    });

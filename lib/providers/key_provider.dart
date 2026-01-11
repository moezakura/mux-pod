import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SSH鍵メタデータ
class SshKeyMeta {
  final String id;
  final String name;
  final String type; // 'rsa' | 'ed25519' | 'ecdsa'
  final String? publicKey;
  final bool hasPassphrase;
  final DateTime createdAt;
  final String? comment;

  const SshKeyMeta({
    required this.id,
    required this.name,
    required this.type,
    this.publicKey,
    this.hasPassphrase = false,
    required this.createdAt,
    this.comment,
  });

  SshKeyMeta copyWith({
    String? id,
    String? name,
    String? type,
    String? publicKey,
    bool? hasPassphrase,
    DateTime? createdAt,
    String? comment,
  }) {
    return SshKeyMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      publicKey: publicKey ?? this.publicKey,
      hasPassphrase: hasPassphrase ?? this.hasPassphrase,
      createdAt: createdAt ?? this.createdAt,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'publicKey': publicKey,
      'hasPassphrase': hasPassphrase,
      'createdAt': createdAt.toIso8601String(),
      'comment': comment,
    };
  }

  factory SshKeyMeta.fromJson(Map<String, dynamic> json) {
    return SshKeyMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      publicKey: json['publicKey'] as String?,
      hasPassphrase: json['hasPassphrase'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      comment: json['comment'] as String?,
    );
  }
}

/// 鍵一覧の状態
class KeysState {
  final List<SshKeyMeta> keys;
  final bool isLoading;
  final String? error;

  const KeysState({
    this.keys = const [],
    this.isLoading = false,
    this.error,
  });

  KeysState copyWith({
    List<SshKeyMeta>? keys,
    bool? isLoading,
    String? error,
  }) {
    return KeysState(
      keys: keys ?? this.keys,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// SSH鍵を管理するNotifier
class KeysNotifier extends Notifier<KeysState> {
  static const String _storageKey = 'ssh_keys_meta';

  @override
  KeysState build() {
    _loadKeys();
    return const KeysState(isLoading: true);
  }

  Future<void> _loadKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        final keys = jsonList
            .map((json) => SshKeyMeta.fromJson(json as Map<String, dynamic>))
            .toList();

        // 作成日時で並び替え（降順）
        keys.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        state = KeysState(keys: keys);
      } else {
        state = const KeysState();
      }
    } catch (e) {
      state = KeysState(error: e.toString());
    }
  }

  Future<void> _saveKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = state.keys.map((k) => k.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  /// 鍵を追加
  Future<void> add(SshKeyMeta key) async {
    final keys = [...state.keys, key];
    state = state.copyWith(keys: keys);
    await _saveKeys();
  }

  /// 鍵を削除
  Future<void> remove(String id) async {
    final keys = state.keys.where((k) => k.id != id).toList();
    state = state.copyWith(keys: keys);
    await _saveKeys();
  }

  /// 鍵を更新
  Future<void> update(SshKeyMeta key) async {
    final keys = state.keys.map((k) {
      return k.id == key.id ? key : k;
    }).toList();
    state = state.copyWith(keys: keys);
    await _saveKeys();
  }

  /// 鍵を取得
  SshKeyMeta? getById(String id) {
    try {
      return state.keys.firstWhere((k) => k.id == id);
    } catch (e) {
      return null;
    }
  }

  /// リロード
  Future<void> reload() async {
    state = state.copyWith(isLoading: true, error: null);
    await _loadKeys();
  }
}

/// SSH鍵プロバイダー
final keysProvider = NotifierProvider<KeysNotifier, KeysState>(() {
  return KeysNotifier();
});

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/keychain/secure_storage.dart';
import '../services/keychain/ssh_key_service.dart';

/// 鍵の由来を示すEnum
enum KeySource {
  generated, // アプリ内で生成
  imported, // ファイル/ペーストでインポート
}

/// SSH鍵メタデータ
class SshKeyMeta {
  final String id;
  final String name;
  final String type; // 'ed25519' | 'rsa-2048' | 'rsa-3072' | 'rsa-4096'
  final String? publicKey;
  final String? fingerprint; // SHA256フィンガープリント
  final bool hasPassphrase;
  final DateTime createdAt;
  final String? comment;
  final KeySource source; // 鍵の由来

  const SshKeyMeta({
    required this.id,
    required this.name,
    required this.type,
    this.publicKey,
    this.fingerprint,
    this.hasPassphrase = false,
    required this.createdAt,
    this.comment,
    this.source = KeySource.generated,
  });

  SshKeyMeta copyWith({
    String? id,
    String? name,
    String? type,
    String? publicKey,
    String? fingerprint,
    bool? hasPassphrase,
    DateTime? createdAt,
    String? comment,
    KeySource? source,
  }) {
    return SshKeyMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      publicKey: publicKey ?? this.publicKey,
      fingerprint: fingerprint ?? this.fingerprint,
      hasPassphrase: hasPassphrase ?? this.hasPassphrase,
      createdAt: createdAt ?? this.createdAt,
      comment: comment ?? this.comment,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'publicKey': publicKey,
      'fingerprint': fingerprint,
      'hasPassphrase': hasPassphrase,
      'createdAt': createdAt.toIso8601String(),
      'comment': comment,
      'source': source.name,
    };
  }

  factory SshKeyMeta.fromJson(Map<String, dynamic> json) {
    return SshKeyMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      publicKey: json['publicKey'] as String?,
      fingerprint: json['fingerprint'] as String?,
      hasPassphrase: json['hasPassphrase'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      comment: json['comment'] as String?,
      source: KeySource.values.firstWhere(
        (e) => e.name == (json['source'] as String?),
        orElse: () => KeySource.generated,
      ),
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

/// SSH鍵サービスプロバイダー
final sshKeyServiceProvider = Provider<SshKeyService>((ref) {
  return SshKeyService();
});

/// セキュアストレージプロバイダー
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

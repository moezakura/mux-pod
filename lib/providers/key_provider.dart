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
  final bool isAvailable; // 秘密鍵が復号可能か（false = 破損鍵）

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
    this.isAvailable = true,
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
    bool? isAvailable,
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
      isAvailable: isAvailable ?? this.isAvailable,
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
      'isAvailable': isAvailable,
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
      isAvailable: json['isAvailable'] as bool? ?? true,
    );
  }
}

/// 鍵一覧の状態
class KeysState {
  final List<SshKeyMeta> keys;
  final bool isLoading;
  final String? error;
  final List<SshKeyMeta> damagedKeys; // 破損鍵（モーダル表示用）

  const KeysState({
    this.keys = const [],
    this.isLoading = false,
    this.error,
    this.damagedKeys = const [],
  });

  KeysState copyWith({
    List<SshKeyMeta>? keys,
    bool? isLoading,
    String? error,
    List<SshKeyMeta>? damagedKeys,
  }) {
    return KeysState(
      keys: keys ?? this.keys,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      damagedKeys: damagedKeys ?? this.damagedKeys,
    );
  }
}

/// SSH鍵を管理するNotifier
class KeysNotifier extends Notifier<KeysState> {
  static const String _storageKey = 'ssh_keys_meta';

  bool _disposed = false;
  int _loadGeneration = 0;

  @override
  KeysState build() {
    ref.onDispose(() => _disposed = true);
    _loadKeys();
    return const KeysState(isLoading: true);
  }

  Future<void> _loadKeys() async {
    final generation = ++_loadGeneration;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || generation != _loadGeneration) return;
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        final keys = jsonList
            .map((json) => SshKeyMeta.fromJson(json as Map<String, dynamic>))
            .toList();

        // 作成日時で並び替え（降順）
        keys.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // 秘密鍵の可用性をチェック（破損鍵の検出）
        final storage = SecureStorageService();
        for (var i = 0; i < keys.length; i++) {
          final privateKey = await storage.getPrivateKey(keys[i].id);
          if (_disposed || generation != _loadGeneration) return;
          // 可用性は保存済み値ではなく、各ロード時の読み取り結果から上書きする
          keys[i] = keys[i].copyWith(isAvailable: privateKey != null);
        }

        final damagedKeys = keys.where((k) => !k.isAvailable).toList();
        if (_disposed || generation != _loadGeneration) return;
        state = KeysState(keys: keys, damagedKeys: damagedKeys);
      } else {
        if (_disposed || generation != _loadGeneration) return;
        state = const KeysState();
      }
    } catch (e) {
      if (!_disposed && generation == _loadGeneration) {
        state = KeysState(error: e.toString());
      }
    }
  }

  Future<void> _saveKeys() async {
    final prefs = await SharedPreferences.getInstance();
    // 作成日時で並び替え（降順）
    final keys = [...state.keys]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final jsonList = keys.map((k) => k.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  /// 鍵を追加
  Future<void> add(SshKeyMeta key) async {
    final keys = [...state.keys, key]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

/// 指定の鍵IDが破損鍵（秘密鍵を読み出せない）かどうかを返す。
bool isKeyDamaged(KeysState state, String? keyId) {
  if (keyId == null) return false;
  return state.keys.any((k) => k.id == keyId && !k.isAvailable);
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

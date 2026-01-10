# Research: Flutter Migration

**Feature**: 001-flutter-migration
**Date**: 2026-01-11

## Executive Summary

MuxPodをReact Native (Expo)からFlutterへ移行するための技術調査結果。dartssh2 + xterm.dartの組み合わせが最適であり、Pure Dart実装でネイティブ依存を完全排除可能。

---

## 1. SSH接続 (dartssh2)

### Decision
**dartssh2 2.13+** を採用。Pure Dart実装でネイティブ依存なし。

### Rationale
- TerminalStudio がアクティブにメンテナンス
- xterm.dart と同一チームで開発、連携良好
- パスワード認証 + RSA/Ed25519鍵認証対応
- PTY（256色対応）、キープアライブ内蔵

### Key Patterns

**パスワード認証:**
```dart
final socket = await SSHSocket.connect(host, port);
final client = SSHClient(
  socket,
  username: username,
  onPasswordRequest: () => password,
);
await client.authenticated;
```

**公開鍵認証:**
```dart
final client = SSHClient(
  socket,
  username: username,
  identities: [...SSHKeyPair.fromPem(privateKeyPem)],
);
```

**シェル起動（PTY付き）:**
```dart
final shell = await client.shell(
  pty: SSHPtyConfig(
    width: 80,
    height: 24,
    term: 'xterm-256color',
  ),
);
```

**特殊キー送信:**
```dart
shell.write(Uint8List.fromList([0x1B]));       // ESC
shell.write(Uint8List.fromList([0x03]));       // Ctrl+C
shell.write(Uint8List.fromList([0x1B, 0x5B, 0x41])); // 矢印キー（上）
```

### Alternatives Considered
- **ssh2** (Dart): 4年間更新なし、ネイティブ依存あり → 却下
- **WebSocket Proxy**: サーバー設置必要、設計思想に反する → 却下

---

## 2. ターミナルエミュレーション (xterm.dart)

### Decision
**xterm 4.0+** を採用。dartssh2との統合が良好。

### Rationale
- 60fps レンダリング
- ANSI 256色 + トゥルーカラー対応
- CJK文字・絵文字対応
- クロスプラットフォーム

### Key Patterns

**TerminalView統合:**
```dart
late final terminal = Terminal();

TerminalView(
  terminal: terminal,
  theme: TerminalThemes.defaultTheme,
  autoResize: true,
)
```

**SSH出力接続:**
```dart
// リモート出力 → Terminal
shell.stdout.listen((data) {
  terminal.write(utf8.decode(data));
});

// ユーザー入力 → リモート
terminal.onOutput = (String output) {
  shell.write(utf8.encode(output));
};
```

**リサイズ同期:**
```dart
terminal.onResize = (w, h) {
  session.setPtySize(columns: w, rows: h);
};
```

### Alternatives Considered
- 自前実装: 複雑すぎる → 却下
- react-native-terminal: RN依存 → 却下

---

## 3. 状態管理 (Riverpod)

### Decision
**flutter_riverpod + riverpod_annotation (codegen)** を採用。

### Rationale
- AsyncNotifierProvider で非同期操作を自然に扱える
- .family で接続ごとの独立した状態管理
- autoDispose でメモリリーク防止
- DI が容易でテスタビリティ向上

### Key Patterns

**SSH接続コントローラー:**
```dart
@riverpod
class SshConnectionController extends _$SshConnectionController {
  @override
  FutureOr<SshConnection> build(String connectionId) async {
    ref.onDispose(() => _cleanup());
    return await _establishConnection(connectionId);
  }

  Future<void> disconnect() async {
    state = const AsyncValue.loading();
    await _client?.close();
    state = AsyncValue.error('Disconnected', StackTrace.current);
  }
}

// 使用: ref.watch(sshConnectionControllerProvider(connId))
```

**Provider構成:**
```
基盤層:   sshConnectionProvider (family)
          ↓ 依存
ドメイン層: tmuxSessionsProvider, terminalProvider
          ↓ 依存
UI層:     selectedPaneProvider (StateProvider)
```

### Alternatives Considered
- **Provider**: シンプルだが複雑な非同期に弱い → 却下
- **BLoC**: ボイラープレート多い → 却下
- **GetX**: 設計思想が異なる → 却下

---

## 4. セキュアストレージ

### Decision
- **機密データ**: flutter_secure_storage（秘密鍵、パスワード）
- **非機密データ**: shared_preferences（接続設定メタデータ）

### Rationale
- flutter_secure_storage: Android Keystore / iOS Keychain 使用、暗号化保証
- shared_preferences: 高速、設定値に適切
- expo-secure-store と同等のセキュリティレベル

### Key Patterns

**秘密鍵保存:**
```dart
final storage = FlutterSecureStorage();
await storage.write(key: 'ssh_key_$id', value: privateKeyPem);
```

**バイオメトリック認証:**
```dart
final storage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
);
```

**接続設定保存:**
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('connections', jsonEncode(connections));
```

### Migration Strategy (RN → Flutter)
1. expo-secure-store からデータをJSON形式でエクスポート
2. flutter_secure_storage に再暗号化して保存
3. キー名規則を維持（`ssh_key_${id}`, `password_${id}`）

**注意**: 暗号化実装が異なるため、直接互換性なし。ユーザーは初回起動時に再設定が必要になる可能性あり。

### Alternatives Considered
- **flutter_keychain**: 低レベルすぎる → 却下
- **biometric_storage**: flutter_secure_storageで十分 → 不要

---

## 5. ナビゲーション

### Decision
**go_router** を採用。

### Rationale
- 宣言的ルーティング
- Deep link 対応
- Navigator 2.0 ベース
- Riverpod との統合良好

### Key Patterns

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => ConnectionsScreen()),
    GoRoute(
      path: '/terminal/:connectionId',
      builder: (_, state) => TerminalScreen(
        connectionId: state.pathParameters['connectionId']!,
      ),
    ),
    GoRoute(path: '/keys', builder: (_, __) => KeysScreen()),
    GoRoute(path: '/settings', builder: (_, __) => SettingsScreen()),
  ],
);
```

---

## 6. データモデル (Freezed)

### Decision
**freezed + json_serializable** を採用。

### Rationale
- イミュータブルクラス自動生成
- copyWith 自動生成
- JSON シリアライズ対応
- パターンマッチング対応

### Key Patterns

```dart
@freezed
class Connection with _$Connection {
  const factory Connection({
    required String id,
    required String name,
    required String host,
    @Default(22) int port,
    required String username,
    required AuthMethod authMethod,
    String? keyId,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}
```

---

## 7. 依存パッケージ一覧

### Core
| パッケージ | バージョン | 用途 |
|-----------|-----------|------|
| dartssh2 | ^2.13.0 | SSH接続 |
| xterm | ^4.0.0 | ターミナルエミュレーション |
| flutter_riverpod | ^2.5.0 | 状態管理 |
| riverpod_annotation | ^2.3.0 | Riverpod codegen |
| go_router | ^14.0.0 | ルーティング |

### Storage
| パッケージ | バージョン | 用途 |
|-----------|-----------|------|
| flutter_secure_storage | ^9.2.0 | 暗号化ストレージ |
| shared_preferences | ^2.3.0 | 設定保存 |

### Model/Codegen
| パッケージ | バージョン | 用途 |
|-----------|-----------|------|
| freezed | ^2.5.0 | イミュータブルモデル |
| json_serializable | ^6.8.0 | JSONシリアライズ |
| freezed_annotation | ^2.4.0 | Freezed アノテーション |

### Testing
| パッケージ | バージョン | 用途 |
|-----------|-----------|------|
| flutter_test | (SDK) | ウィジェットテスト |
| mockito | ^5.4.0 | モック生成 |
| build_runner | ^2.4.0 | コード生成 |

---

## 8. Constitution Check (Post-Research)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | Dart strict mode + Freezed |
| II. KISS & YAGNI | ✅ PASS | 既存機能のみ移植 |
| III. Test-First | ✅ PASS | mockito + flutter_test |
| IV. Security-First | ✅ PASS | flutter_secure_storage + biometric |
| V. SOLID | ✅ PASS | Riverpod DI + サービス層分離 |
| VI. DRY | ✅ PASS | Freezed codegen |
| Prohibited Naming | ✅ PASS | ドメイン名で命名 |

---

## References

- [dartssh2 - pub.dev](https://pub.dev/packages/dartssh2)
- [xterm.dart - pub.dev](https://pub.dev/packages/xterm)
- [Riverpod 公式ドキュメント](https://riverpod.dev/docs/)
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- [go_router](https://pub.dev/packages/go_router)
- [freezed](https://pub.dev/packages/freezed)

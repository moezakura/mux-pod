# Data Model: Flutter Migration

**Feature**: 001-flutter-migration
**Date**: 2026-01-11

## Entity Overview

```
┌─────────────┐     ┌───────────┐     ┌─────────────┐
│ Connection  │────▷│  SSHKey   │     │ AppSettings │
└──────┬──────┘     └───────────┘     └─────────────┘
       │
       │ 1:N (runtime)
       ▼
┌─────────────┐
│ TmuxSession │
└──────┬──────┘
       │ 1:N
       ▼
┌─────────────┐
│ TmuxWindow  │
└──────┬──────┘
       │ 1:N
       ▼
┌─────────────┐     ┌──────────────────┐
│  TmuxPane   │◁────│ NotificationRule │
└─────────────┘     └──────────────────┘
```

---

## 1. Connection

SSH接続設定を表すエンティティ。

```dart
@freezed
class Connection with _$Connection {
  const factory Connection({
    required String id,              // UUID
    required String name,            // 表示名 (e.g., "Production AWS")
    required String host,            // ホスト名 or IP
    @Default(22) int port,           // SSHポート
    required String username,        // SSHユーザー名
    required AuthMethod authMethod,  // 認証方法
    String? keyId,                   // SSH鍵ID（key認証時）
    @Default(30) int timeout,        // 接続タイムアウト秒
    @Default(60) int keepAliveInterval, // Keepalive間隔秒
    String? icon,                    // カスタムアイコン
    String? color,                   // カード色（hex）
    @Default([]) List<String> tags,  // タグ
    DateTime? lastConnected,         // 最終接続日時
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}

@freezed
class AuthMethod with _$AuthMethod {
  const factory AuthMethod.password() = PasswordAuth;
  const factory AuthMethod.key() = KeyAuth;
}
```

### Validation Rules
- `name`: 1-50文字、空白不可
- `host`: 有効なホスト名/IPv4/IPv6
- `port`: 1-65535
- `username`: 1-32文字
- `timeout`: 5-120秒
- `keepAliveInterval`: 0（無効）または 10-300秒

### Storage
- **非機密**: SharedPreferences (JSON)
- **パスワード**: flutter_secure_storage (暗号化)

---

## 2. SSHKey

SSH鍵ペアを表すエンティティ。

```dart
@freezed
class SSHKey with _$SSHKey {
  const factory SSHKey({
    required String id,              // UUID
    required String name,            // 表示名
    required KeyType type,           // 鍵タイプ
    int? bits,                       // RSAの場合: 2048, 4096等
    required String fingerprint,     // SHA256フィンガープリント
    required String publicKey,       // 公開鍵（表示・エクスポート用）
    @Default(false) bool encrypted,  // パスフレーズ保護
    @Default(false) bool isDefault,  // デフォルト鍵
    required DateTime createdAt,
    DateTime? lastUsed,
  }) = _SSHKey;

  factory SSHKey.fromJson(Map<String, dynamic> json) =>
      _$SSHKeyFromJson(json);
}

enum KeyType { rsa, ed25519, ecdsa }
```

### Validation Rules
- `name`: 1-50文字
- `bits` (RSA): 2048, 3072, 4096のいずれか
- `fingerprint`: SHA256:... 形式

### Storage
- **メタデータ**: SharedPreferences (JSON)
- **秘密鍵**: flutter_secure_storage (暗号化、キー: `ssh_private_key_${id}`)

---

## 3. TmuxSession

リモートサーバー上のtmuxセッションを表すエンティティ（ランタイムのみ）。

```dart
@freezed
class TmuxSession with _$TmuxSession {
  const factory TmuxSession({
    required String name,            // セッション名
    required DateTime created,       // 作成日時
    required bool attached,          // アタッチ状態
    required int windowCount,        // ウィンドウ数
    @Default([]) List<TmuxWindow> windows, // ウィンドウ一覧
  }) = _TmuxSession;
}
```

### State Transitions
```
[Not Exists] ──create──▷ [Detached] ◁──detach── [Attached]
                              │                      ▲
                              └───────attach─────────┘
                              │
                           kill-session
                              │
                              ▼
                        [Not Exists]
```

---

## 4. TmuxWindow

tmuxウィンドウを表すエンティティ（ランタイムのみ）。

```dart
@freezed
class TmuxWindow with _$TmuxWindow {
  const factory TmuxWindow({
    required int index,              // ウィンドウインデックス
    required String name,            // ウィンドウ名
    required bool active,            // アクティブ状態
    required int paneCount,          // ペイン数
    @Default([]) List<TmuxPane> panes, // ペイン一覧
  }) = _TmuxWindow;
}
```

---

## 5. TmuxPane

tmuxペインを表すエンティティ（ランタイムのみ）。

```dart
@freezed
class TmuxPane with _$TmuxPane {
  const factory TmuxPane({
    required int index,              // ペインインデックス
    required String id,              // ペインID (%0, %1, etc.)
    required bool active,            // アクティブ状態
    required String currentCommand,  // 実行中コマンド
    required String title,           // ペインタイトル
    required int width,              // 幅（列数）
    required int height,             // 高さ（行数）
    required int cursorX,            // カーソルX位置
    required int cursorY,            // カーソルY位置
  }) = _TmuxPane;
}
```

---

## 6. NotificationRule

通知ルールを表すエンティティ。

```dart
@freezed
class NotificationRule with _$NotificationRule {
  const factory NotificationRule({
    required String id,              // UUID
    required String name,            // ルール名
    @Default(true) bool enabled,     // 有効/無効

    // ターゲット
    required String connectionId,    // 対象接続
    String? sessionName,             // 対象セッション（null=全て）
    int? windowIndex,                // 対象ウィンドウ
    int? paneIndex,                  // 対象ペイン

    // 条件
    required NotificationCondition condition,

    // アクション
    @Default(NotificationAction.inApp) NotificationAction action,
    String? soundName,               // サウンド名（sound時）

    // 制御
    @Default(NotificationFrequency.always) NotificationFrequency frequency,
    @Default(5000) int throttleMs,   // 最小通知間隔

    DateTime? lastTriggered,
    required DateTime createdAt,
  }) = _NotificationRule;

  factory NotificationRule.fromJson(Map<String, dynamic> json) =>
      _$NotificationRuleFromJson(json);
}

@freezed
class NotificationCondition with _$NotificationCondition {
  const factory NotificationCondition.text({
    required String text,
    @Default(false) bool caseSensitive,
  }) = TextCondition;

  const factory NotificationCondition.regex({
    required String pattern,
    @Default('') String flags,
  }) = RegexCondition;

  const factory NotificationCondition.idle({
    required int durationMs,
  }) = IdleCondition;

  const factory NotificationCondition.activity() = ActivityCondition;

  factory NotificationCondition.fromJson(Map<String, dynamic> json) =>
      _$NotificationConditionFromJson(json);
}

enum NotificationAction { inApp, sound, vibrate }
enum NotificationFrequency { always, oncePerSession, oncePerMatch }
```

### Validation Rules
- `name`: 1-50文字
- `throttleMs`: 1000-60000ms
- `pattern` (regex): 有効な正規表現

### Storage
- SharedPreferences (JSON)

---

## 7. AppSettings

アプリケーション設定を表すエンティティ。

```dart
@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(DisplaySettings()) DisplaySettings display,
    @Default(TerminalSettings()) TerminalSettings terminal,
    @Default(SshSettings()) SshSettings ssh,
    @Default(SecuritySettings()) SecuritySettings security,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}

@freezed
class DisplaySettings with _$DisplaySettings {
  const factory DisplaySettings({
    @Default(14) int fontSize,       // 10-24
    @Default(FontFamily.jetBrainsMono) FontFamily fontFamily,
    @Default(ColorTheme.dracula) ColorTheme colorTheme,
    TerminalColors? customColors,
  }) = _DisplaySettings;

  factory DisplaySettings.fromJson(Map<String, dynamic> json) =>
      _$DisplaySettingsFromJson(json);
}

@freezed
class TerminalSettings with _$TerminalSettings {
  const factory TerminalSettings({
    @Default(2000) int scrollbackLimit, // 1000-10000
    @Default(false) bool bellSound,
    @Default(true) bool bellVibrate,
  }) = _TerminalSettings;

  factory TerminalSettings.fromJson(Map<String, dynamic> json) =>
      _$TerminalSettingsFromJson(json);
}

@freezed
class SshSettings with _$SshSettings {
  const factory SshSettings({
    @Default(60) int keepAliveInterval, // 0=off, 10-300秒
    @Default(false) bool compressionEnabled,
    @Default(22) int defaultPort,
    @Default('') String defaultUsername,
  }) = _SshSettings;

  factory SshSettings.fromJson(Map<String, dynamic> json) =>
      _$SshSettingsFromJson(json);
}

@freezed
class SecuritySettings with _$SecuritySettings {
  const factory SecuritySettings({
    @Default(true) bool useSecureEnclave,
    @Default(false) bool lockOnBackground,
    @Default(false) bool biometricUnlock,
  }) = _SecuritySettings;

  factory SecuritySettings.fromJson(Map<String, dynamic> json) =>
      _$SecuritySettingsFromJson(json);
}

enum FontFamily { jetBrainsMono, firaCode, meslo, hackGen, plemolJP }
enum ColorTheme { dracula, solarized, monokai, nord, custom }
```

---

## 8. TerminalColors

ターミナルカラーテーマを表すエンティティ。

```dart
@freezed
class TerminalColors with _$TerminalColors {
  const factory TerminalColors({
    required String background,      // hex (#RRGGBB)
    required String foreground,
    required String cursor,
    required String selection,
    required String black,
    required String red,
    required String green,
    required String yellow,
    required String blue,
    required String magenta,
    required String cyan,
    required String white,
    required String brightBlack,
    required String brightRed,
    required String brightGreen,
    required String brightYellow,
    required String brightBlue,
    required String brightMagenta,
    required String brightCyan,
    required String brightWhite,
  }) = _TerminalColors;

  factory TerminalColors.fromJson(Map<String, dynamic> json) =>
      _$TerminalColorsFromJson(json);
}
```

---

## Storage Summary

| Entity | Storage | Key Pattern |
|--------|---------|-------------|
| Connection (metadata) | SharedPreferences | `connections` (JSON array) |
| Connection (password) | flutter_secure_storage | `password_${connectionId}` |
| SSHKey (metadata) | SharedPreferences | `ssh_keys` (JSON array) |
| SSHKey (private key) | flutter_secure_storage | `ssh_private_key_${keyId}` |
| NotificationRule | SharedPreferences | `notification_rules` (JSON array) |
| AppSettings | SharedPreferences | `app_settings` (JSON object) |
| TmuxSession/Window/Pane | Memory only | - |

---

## Code Generation Commands

```bash
# Freezed/JSON Serializable 生成
dart run build_runner build --delete-conflicting-outputs

# Watch モード
dart run build_runner watch
```

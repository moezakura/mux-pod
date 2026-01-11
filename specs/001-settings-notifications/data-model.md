# Data Model: Settings and Notifications

**Feature**: 001-settings-notifications
**Date**: 2026-01-11

## 1. Entities

### 1.1 AppSettings

アプリケーション全体の設定を保持するエンティティ。

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| darkMode | bool | true | ダークモード有効 |
| fontSize | double | 14.0 | ターミナルフォントサイズ（pt） |
| fontFamily | String | "JetBrains Mono" | ターミナルフォントファミリー |
| requireBiometricAuth | bool | false | 生体認証必須 |
| enableNotifications | bool | true | 通知有効 |
| enableVibration | bool | true | バイブレーション有効 |
| scrollbackLines | int | 10000 | スクロールバック行数 |

**Validation Rules**:
- fontSize: 10.0 <= value <= 20.0
- fontFamily: 許可リスト ["JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono"]

**Storage**: SharedPreferences
- Key prefix: `settings_`
- 各フィールドは個別キーで保存

### 1.2 NotificationRule

通知ルールを表すエンティティ。

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | String | UUID | ルール一意識別子 |
| name | String | required | ルール表示名 |
| pattern | String | required | マッチパターン |
| isRegex | bool | false | 正規表現として扱う |
| enabled | bool | true | ルール有効 |
| caseSensitive | bool | false | 大文字小文字区別 |
| sound | String? | null | サウンドファイル名 |
| vibrate | bool | true | バイブレーション有効 |
| priority | NotificationPriority | normal | 通知優先度 |
| targetSession | String? | null | 対象セッション（nullで全て） |
| rateLimitSeconds | int | 5 | 同一ルール通知間隔（秒） |
| createdAt | DateTime | now | 作成日時 |
| lastMatchedAt | DateTime? | null | 最終マッチ日時 |

**Validation Rules**:
- name: 1文字以上
- pattern: 1文字以上、isRegex=trueの場合は有効な正規表現
- rateLimitSeconds: 0 <= value <= 3600

**Storage**: SharedPreferences
- Key: `notification_rules`
- Format: JSON配列

### 1.3 NotificationPriority (Enum)

通知の優先度を表す列挙型。

| Value | Index | Description |
|-------|-------|-------------|
| low | 0 | 低優先度 |
| normal | 1 | 通常優先度 |
| high | 2 | 高優先度 |
| urgent | 3 | 緊急（最高優先度） |

### 1.4 ThemeMode (Flutter標準)

テーマモードを表す列挙型（Flutter標準）。

| Value | Description |
|-------|-------------|
| system | システム設定に従う |
| light | ライトモード |
| dark | ダークモード |

**Mapping**:
- AppSettings.darkMode = true → ThemeMode.dark
- AppSettings.darkMode = false → ThemeMode.light
- 拡張: darkMode を themeMode (String) に変更検討

## 2. State Classes

### 2.1 NotificationState

通知プロバイダーの状態を表すクラス。

| Field | Type | Description |
|-------|------|-------------|
| rules | List\<NotificationRule\> | 全ルールリスト |
| recentEvents | List\<NotificationEvent\> | 最近の通知イベント |
| globalEnabled | bool | グローバル通知有効 |
| isLoading | bool | 読み込み中フラグ |
| error | String? | エラーメッセージ |

## 3. Relationships

```
┌──────────────────┐
│   AppSettings    │
│                  │
│  - fontSize      │
│  - fontFamily    │
│  - darkMode      │
│  - enableVibrate │
└──────────────────┘
         │
         │ references
         ▼
┌──────────────────┐
│ NotificationRule │
│                  │
│  - vibrate       │ ← AppSettings.enableVibration がグローバル設定
│  - priority      │
│  - enabled       │
└──────────────────┘
         │
         │ generates
         ▼
┌──────────────────┐
│NotificationEvent │
│                  │
│  - rule          │
│  - matchResult   │
│  - timestamp     │
└──────────────────┘
```

## 4. State Transitions

### 4.1 NotificationRule Lifecycle

```
[Create] ──► [Enabled] ◄──► [Disabled]
                │
                ▼
           [Delete]
```

### 4.2 Settings Change Flow

```
User Action ──► Provider Method ──► SharedPreferences ──► State Update ──► UI Rebuild
```

## 5. Font Options

### 5.1 Available Font Sizes

| Value (pt) | Use Case |
|------------|----------|
| 10 | 高密度表示 |
| 12 | コンパクト |
| 14 | 標準（デフォルト） |
| 16 | 読みやすい |
| 18 | 大きめ |
| 20 | 最大 |

### 5.2 Available Font Families

| Font | Package | Notes |
|------|---------|-------|
| JetBrains Mono | google_fonts | デフォルト、リガチャ対応 |
| Fira Code | google_fonts | 人気のコーディングフォント |
| Source Code Pro | google_fonts | Adobe製 |
| Roboto Mono | google_fonts | Android標準 |

## 6. Theme Options

| Option | ThemeMode | AppSettings.darkMode |
|--------|-----------|---------------------|
| Dark | ThemeMode.dark | true |
| Light | ThemeMode.light | false |
| System | ThemeMode.system | (要拡張) |

**Note**: System対応には AppSettings を拡張して themeMode フィールドを追加する必要がある。初期実装では Dark/Light のみをサポート。

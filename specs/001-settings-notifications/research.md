# Research: Settings and Notifications

**Feature**: 001-settings-notifications
**Date**: 2026-01-11

## 1. 既存実装の調査

### 1.1 設定プロバイダー (settings_provider.dart)

**現状**:
- `AppSettings` クラスに全設定を保持
- `SettingsNotifier` でSharedPreferencesへの保存/読み込み実装済み
- 既存メソッド: `setDarkMode()`, `setFontSize()`, `setFontFamily()`, `setEnableVibration()` 等

**Decision**: 既存のSettingsNotifierメソッドをそのまま活用
**Rationale**: 既に必要な機能が実装されている
**Alternatives**: なし（再実装は不要）

### 1.2 通知プロバイダー (notification_provider.dart)

**現状**:
- `NotificationState` で状態管理
- `NotificationNotifier` にCRUD操作実装済み: `addRule()`, `removeRule()`, `updateRule()`, `toggleRule()`
- `NotificationEngine` で永続化処理実装済み

**Decision**: 既存のNotificationNotifierメソッドをUI層から呼び出す
**Rationale**: 既にルールの永続化機能が完備されている
**Alternatives**: なし

### 1.3 テーマ管理 (app_theme.dart, main.dart)

**現状**:
- `AppTheme.dark` と `AppTheme.light` が定義済み（ただしlightはdarkと同一）
- `AppTheme.getThemeMode()` メソッド存在
- `main.dart` では `ThemeMode.dark` がハードコードされている

**Decision**: `MyApp`をConsumerWidgetに変更し、settingsProviderからテーマを取得
**Rationale**: 動的テーマ切り替えには状態管理との連携が必要
**Alternatives**:
- InheritedWidgetで独自実装 → 却下（Riverpod既存）
- MaterialApp.router使用 → 却下（過剰な変更）

## 2. UI実装パターン

### 2.1 ダイアログ実装

**Decision**: FlutterのAlertDialog + SimpleDialogOptionを使用
**Rationale**: Material Design準拠、Flutter標準
**Alternatives**:
- BottomSheet → 却下（選択肢少数のため過剰）
- カスタムダイアログ → 却下（KISS原則）

### 2.2 フォントサイズ選択

**Decision**: RadioListTileリストのAlertDialog
**選択肢**: 10, 12, 14, 16, 18, 20pt（デフォルト14）
**Rationale**: 一般的なコードエディタの設定範囲

### 2.3 フォントファミリー選択

**Decision**: RadioListTileリストのAlertDialog
**選択肢**: JetBrains Mono, Fira Code, Source Code Pro, Roboto Mono
**Rationale**: プログラミングフォントとして人気のある4種

### 2.4 テーマ選択

**Decision**: RadioListTileリストのAlertDialog
**選択肢**: Dark, Light, System
**Rationale**: 一般的なアプリの3パターン

## 3. 外部リンク

### 3.1 url_launcher使用

**Decision**: url_launcherパッケージを使用
**Rationale**: Flutter公式推奨、クロスプラットフォーム対応
**Alternatives**:
- android_intent → Android専用のため却下
- webview → 過剰（単純なURL起動）

**実装**:
```dart
import 'package:url_launcher/url_launcher.dart';

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

## 4. 通知ルール画面の改善

### 4.1 ルールリスト表示

**Decision**: `ref.watch(notificationProvider).rules` を監視してListView.builderで表示
**Rationale**: Riverpodの標準パターン

### 4.2 スワイプ削除

**Decision**: Dismissibleウィジェットを使用
**Rationale**: Flutter標準、ユーザー馴染みのあるUX
**確認ダイアログ**: 削除前に確認ダイアログを表示

### 4.3 ルール編集

**Decision**: 既存の_RuleFormDialogを拡張、ruleIdがある場合は編集モード
**Rationale**: 新規/編集で同一フォームを再利用（DRY原則）

## 5. 依存関係

### 5.1 追加パッケージ

| パッケージ | 用途 | 状態 |
|-----------|------|------|
| url_launcher | 外部URL起動 | 追加必要 |
| google_fonts | フォント選択 | 既存 |
| shared_preferences | 設定保存 | 既存 |

### 5.2 pubspec.yaml確認

```yaml
dependencies:
  url_launcher: ^6.2.0  # 追加
```

## 6. テスト戦略

### 6.1 Widgetテスト

- settings_screen_test.dart: ダイアログ表示、設定変更
- notification_rules_screen_test.dart: ルールリスト、CRUD操作

### 6.2 モック

- SharedPreferencesはモック使用
- NotificationEngineはモック使用

## まとめ

- 既存のプロバイダー機能は十分であり、新規実装は不要
- UI層からプロバイダーメソッドを呼び出す実装が主
- url_launcherパッケージの追加が必要
- テーマ切り替えのためmain.dartの軽微な変更が必要

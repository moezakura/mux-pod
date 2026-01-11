# MuxPod

AndroidスマートフォンからSSH経由でリモートサーバーのtmuxセッション・ウィンドウ・ペインを閲覧・操作するFlutterアプリ。

## 主要機能

- SSH直接接続（サーバー側はsshdのみで動作）
- tmuxセッション/ウィンドウ/ペインのナビゲーション
- ANSIカラー対応ターミナル表示
- 特殊キー入力（ESC/CTRL/ALT等）
- 通知ルール（パターンマッチで通知）
- SSH鍵管理（flutter_secure_storage対応）
- 折りたたみデバイス対応

## 技術スタック

- Flutter 3.24+ / Dart 3.x
- flutter_riverpod (状態管理)
- dartssh2 (SSH接続)
- xterm (ターミナル表示)
- flutter_secure_storage (セキュアストレージ)
- shared_preferences (設定保存)

## 開発コマンド

```bash
flutter run             # 開発実行
flutter run -d android  # Android実機/エミュレータ
flutter analyze         # 静的解析
flutter test            # テスト実行
flutter build apk       # APKビルド
```

## ドキュメント

- @/docs/tmux-mobile-design-v2.md - 詳細設計書
- @/docs/coding-conventions.md - コーディング規約
- @/docs/ui-guidelines.md - UI/UXガイドライン
- @/docs/screens/ - 画面デザイン
- @/docs/logo/logo.svg - ロゴ

## ディレクトリ構成

```
muxpod/
├── lib/
│   ├── main.dart           # エントリーポイント
│   ├── providers/          # Riverpod providers
│   ├── screens/            # 画面
│   │   ├── connections/    # 接続管理
│   │   ├── terminal/       # ターミナル
│   │   ├── keys/           # SSH鍵管理
│   │   ├── notifications/  # 通知ルール
│   │   └── settings/       # 設定
│   ├── services/           # ビジネスロジック
│   │   ├── ssh/            # SSH接続
│   │   ├── tmux/           # tmux操作
│   │   ├── terminal/       # ターミナル制御
│   │   ├── keychain/       # 鍵管理
│   │   └── notification/   # 通知エンジン
│   ├── theme/              # テーマ・デザイン
│   └── widgets/            # 共通ウィジェット
├── android/                # Androidネイティブ設定
├── ios/                    # iOSネイティブ設定
└── test/                   # テスト
```

## 主要な型

```dart
class Connection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
}

class TmuxSession {
  final String name;
  final List<TmuxWindow> windows;
}

class TmuxWindow {
  final int index;
  final String name;
  final List<TmuxPane> panes;
}

class TmuxPane {
  final int index;
  final String id;
  final bool active;
}
```

## セキュリティ

- SSH鍵: flutter_secure_storage（暗号化）
- パスワード: flutter_secure_storage（暗号化）
- 生体認証対応（local_auth）

## Active Technologies
- Dart 3.10+ / Flutter 3.24+ + dartssh2 (SSH), xterm (ターミナル表示), flutter_riverpod (状態管理)
- flutter_secure_storage (SSH鍵/パスワード), shared_preferences (接続設定)
- cryptography, pointycastle (SSH鍵生成)
- flutter_local_notifications, url_launcher (設定/通知)

## Recent Changes
- 001-ssh-terminal-integration: SSH接続・tmuxアタッチ・キー送信の実装
- 003-ssh-key-management: Ed25519/RSA鍵生成・インポート・管理機能
- 001-settings-notifications: 設定画面・通知ルールCRUD・テーマ切替

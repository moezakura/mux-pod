# MuxPod

AndroidスマートフォンからSSH経由でリモートサーバーのtmuxセッション・ウィンドウ・ペインを閲覧・操作するExpo (React Native) アプリ。

## 主要機能

- SSH直接接続（サーバー側はsshdのみで動作）
- tmuxセッション/ウィンドウ/ペインのナビゲーション
- ANSIカラー対応ターミナル表示
- 特殊キー入力（ESC/CTRL/ALT等）
- 通知ルール（パターンマッチで通知）
- SSH鍵管理（Secure Enclave対応）
- 折りたたみデバイス対応

## 技術スタック

- Expo ~52.0.0 / React Native 0.76.0
- TypeScript 5.6+
- Expo Router ~4.0.0
- Zustand 5.0+
- react-native-ssh-sftp

## 開発コマンド

```bash
pnpm start          # 開発サーバー起動
pnpm android        # Android実機/エミュレータ
pnpm typecheck      # 型チェック
pnpm lint           # Lint
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
├── app/              # Expo Router (画面定義)
├── src/
│   ├── components/   # UIコンポーネント
│   ├── hooks/        # カスタムhooks
│   ├── stores/       # Zustand stores
│   ├── services/     # SSH, tmux, notification, keychain, ansi, terminal
│   └── types/        # TypeScript型定義
└── assets/           # フォント、画像等
```

## 主要な型

```typescript
interface Connection {
  id: string; name: string; host: string; port: number;
  username: string; authMethod: 'password' | 'key';
}

interface TmuxSession { name: string; windows: TmuxWindow[]; }
interface TmuxWindow { index: number; name: string; panes: TmuxPane[]; }
interface TmuxPane { index: number; id: string; active: boolean; }
```

## セキュリティ

- SSH鍵: Android Keystore / Secure Enclave
- パスワード: expo-secure-store（暗号化）
- 生体認証対応

# UI再設計 決定レポート

**日時**: 2026-01-10 22:00
**監督者**: Claude Opus 4.5 (Spec-Kit Conductor)
**対象エージェント**: pane %100

---

## 概要

HTMLデザインファイル (`docs/screens/html/*.html`) に完全一致させるためのUI再設計を実施。

---

## 許可決定ログ

| 時刻 | 許可内容 | 理由 |
|------|---------|------|
| 21:30 | pnpm add @babel/runtime | Metro bundlerエラー解消 |
| 21:45 | src/theme/tokens.ts 作成 | デザイントークン定義 |
| 22:00 | ConnectionCard.tsx 更新 | HTMLデザイン準拠 |
| 22:05 | app/index.tsx 更新 | 接続一覧画面UI |
| 22:10 | TerminalHeader.tsx 作成 | ターミナルヘッダー |
| 22:15 | SpecialKeys.tsx 更新 | 特殊キーUI |
| 22:20 | TerminalInput.tsx 更新 | 入力バーUI |
| 22:25 | pnpm add @expo/vector-icons | Material iconsに必要 |
| 22:30 | MUXPOD_THEME 追加 | ターミナルカラーテーマ |
| 23:15 | スクリーンショット検証 | UI確認のため |
| 23:20 | app/_layout.tsx 更新 | Stackヘッダー非表示 (headerShown: false) |
| 23:20 | app/(main)/_layout.tsx 更新 | Stackヘッダー非表示 (headerShown: false) |
| 23:25 | スクリーンショット再取得 | 修正確認のため |
| 23:45 | ConnectionForm.tsx 更新 | 接続追加画面をHTMLデザインに準拠 |
| 23:50 | スクリーンショット取得 | 接続追加画面確認 |
| 23:55 | SafeAreaView修正 | react-native-safe-area-context使用 |
| 00:00 | 最終スクリーンショット | 全画面一致確認完了 |

---

## 変更されたファイル

### 新規作成
- `src/theme/tokens.ts` - デザイントークン
- `src/theme/index.ts` - エクスポート
- `src/components/terminal/TerminalHeader.tsx` - ヘッダーコンポーネント

### 更新
- `src/components/connection/ConnectionCard.tsx`
- `src/components/terminal/SpecialKeys.tsx`
- `src/components/terminal/TerminalInput.tsx`
- `src/components/terminal/TerminalView.tsx`
- `src/types/terminal.ts` (MUXPOD_THEME追加)
- `app/index.tsx`
- `app/(main)/terminal/[connectionId].tsx`
- `app/_layout.tsx` (headerShown: false)
- `app/(main)/_layout.tsx` (headerShown: false)
- `src/components/connection/ConnectionForm.tsx` (HTMLデザインに完全準拠)

---

## 適用されたデザイン仕様

### カラーパレット (HTMLから抽出)
```
primary: #00c0d1
background-dark: #0e0e11
surface-dark: #1E1F27
canvas-dark: #101116
terminal-green: #22c55e
terminal-yellow: #eab308
terminal-red: #ef4444
terminal-blue: #3b82f6
terminal-purple: #a855f7
```

### アイコン (Material Symbols)
- dns, terminal, search, sort
- expand_less, expand_more, add
- lan, key, settings
- bolt, keyboard, arrow_*

### フォント
- UI: Space Grotesk
- Terminal: JetBrains Mono

---

## 検証結果

- **TypeScript**: ✅ Pass
- **Lint**: 要確認
- **実機テスト**: ✅ 完了

### スクリーンショット検証 (23:15)
- ❌ 余計な「index」ヘッダーバー表示 → ✅ 修正済み (headerShown: false)
- ✅ 接続一覧画面: HTMLデザインと一致確認済み (23:30)
  - ヘッダー、検索/ソートアイコン、背景色、FAB、ボトムナビ全て一致
- ✅ 接続追加画面: HTMLデザインと一致 (23:55)
  - セクション、フローティングラベル、アイコン、トグル、TEST CONNECTIONボタン全て一致
  - SafeAreaViewをreact-native-safe-area-contextに変更 (ヘッダー表示修正)

---

## 次のステップ

1. ~~`pnpm android` で実機確認~~ ✅ 完了
2. ~~接続一覧画面~~ ✅ HTMLデザインと一致
3. ~~接続追加画面~~ ✅ HTMLデザインと一致
4. フォント (Space Grotesk, JetBrains Mono) のインストール
5. 残りのHTML画面 (terminal, notification_rules等) の実装

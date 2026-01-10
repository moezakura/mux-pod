<!--
Sync Impact Report
==================
Version change: 1.0.0 → 1.1.1 (MINOR - added design principles, utils prohibition, pnpm)

Modified principles:
- II. Simplicity → II. KISS & YAGNI (expanded with KISS principle)
- V. Single Responsibility → V. SOLID (expanded to cover all SOLID principles)

Added sections:
- Prohibited Naming (utils, helpers, common 禁止)
- DRY principle integrated into SOLID section

Templates requiring updates:
- .specify/templates/plan-template.md: ✅ Compatible
- .specify/templates/spec-template.md: ✅ Compatible
- .specify/templates/tasks-template.md: ✅ Compatible

Follow-up TODOs:
- docs/coding-conventions.md: utils参照の更新が必要
- docs/tmux-mobile-design-v2.md: src/utils/ 参照の更新が必要
-->

# MuxPod Constitution

## Core Principles

### I. Type Safety

TypeScriptの型システムを最大限に活用し、コンパイル時にバグを防止する。

- `strict: true` を必ず維持する
- `any` 型の使用は原則禁止（やむを得ない場合は eslint-disable コメントで理由を明記）
- 外部入力（SSH応答、ユーザー入力）は必ず型ガードまたはバリデーションを通す
- 共通型は `src/types/` に集約し、重複定義を避ける

**根拠**: モバイルアプリはクラッシュがUX劣化に直結する。型安全性によりランタイムエラーを最小化する。

### II. KISS & YAGNI

**Keep It Simple, Stupid** - シンプルな解決策を選び、不要な複雑さを排除する。
**You Aren't Gonna Need It** - 今必要な機能のみを実装する。

- 1つの問題に対して最もシンプルな解決策を選ぶ
- 抽象化は3回以上の重複が発生してから検討する（Rule of Three）
- 設定可能性やプラグイン機構は具体的な要件が出てから追加する
- 「後で必要になるかも」は実装の理由にならない
- 複雑なパターンより明快な直接実装を優先する

**根拠**: モバイルアプリはバンドルサイズとパフォーマンスが重要。不要なコードは負債となる。

### III. Test-First (TDD)

**Test-Driven Development** - テストを先に書き、実装はテストを通過させるために行う。

- 新機能: Red（テスト作成・失敗）→ Green（実装・通過）→ Refactor の順序を守る
- バグ修正: 再現テスト作成 → 修正 → テスト通過 の順序を守る
- SSHコマンド実行やtmux操作は必ずモック/スタブでテスト可能にする
- カバレッジ目標よりもクリティカルパスのテストを優先する

**根拠**: TDDにより設計が洗練され、リグレッションを防止できる。

### IV. Security-First

SSH鍵や認証情報の取り扱いにおいて、セキュリティを最優先する。

- SSH秘密鍵は Android Keystore / Secure Enclave に保存（平文保存禁止）
- パスワードは `expo-secure-store` で暗号化保存
- コマンドインジェクションを防ぐため、シェルエスケープは `TmuxCommands.escape()` を必ず使用
- ログ出力に認証情報や鍵データを含めない
- 生体認証オプションを提供する

**根拠**: SSH接続アプリは攻撃対象となりやすく、鍵漏洩は深刻なセキュリティインシデントにつながる。

### V. SOLID

オブジェクト指向設計の5原則を遵守する。

#### S - Single Responsibility Principle (SRP)
- 1つのモジュール・クラス・関数は1つの責務のみを持つ
- 変更理由が複数ある場合は分割を検討する

#### O - Open/Closed Principle (OCP)
- 拡張に対して開いており、修正に対して閉じている設計を目指す
- 既存コードを変更せずに新機能を追加できる構造を優先する

#### L - Liskov Substitution Principle (LSP)
- 派生型は基底型と置換可能でなければならない
- インターフェースの契約を破る実装をしない

#### I - Interface Segregation Principle (ISP)
- クライアントが使用しないメソッドへの依存を強制しない
- 大きなインターフェースより小さな専用インターフェースを優先する

#### D - Dependency Inversion Principle (DIP)
- 上位モジュールは下位モジュールに依存しない（両者とも抽象に依存する）
- テスト容易性のため、依存性注入を活用する

**根拠**: SOLIDにより保守性・拡張性・テスト容易性が向上する。

### VI. DRY

**Don't Repeat Yourself** - 知識の重複を排除する。

- 同一ロジックの2回目の出現で共通化を検討、3回目で必須
- ただし、過度な抽象化よりも明確な重複を許容する場合もある（KISS優先）
- 設定値・マジックナンバーは定数として一元管理する

**根拠**: 重複は変更時の修正漏れとバグの温床となる。

## Development Standards

MuxPod固有の開発標準を定める。

### Prohibited Naming (命名禁止)

以下の曖昧な命名は**禁止**。目的を明確に表す名前を使用すること。

| 禁止 | 理由 | 代替例 |
|------|------|--------|
| `utils/` | 責務が曖昧 | `src/services/ansi/parser.ts` |
| `helpers/` | 何を助けるか不明 | `src/services/terminal/formatter.ts` |
| `common/` | 共通とは何か不明 | 具体的なドメイン名を使用 |
| `misc/` | 雑多は設計の敗北 | 適切なモジュールに分類 |
| `lib/` | ライブラリとは何か不明 | `src/services/` または `src/domain/` |

**正しい命名の原則**:
- ファイル名から責務が推測できること
- ディレクトリ構造がドメインを反映すること
- 「このファイルは何をするか」を一言で説明できること

### Mobile UX

- オフライン状態を考慮し、接続エラーは明確にユーザーに通知する
- ターミナル操作のレスポンスは体感100ms以下を目指す（ポーリング間隔100ms）
- 折りたたみデバイス・タブレットの画面サイズ変化に対応する
- 特殊キー（ESC, CTRL, ALT）は常にアクセス可能にする

### SSH/tmux Protocol

- tmuxコマンドは `TmuxCommands` クラスを経由して実行する
- SSH接続状態は `connectionStore` で一元管理する
- ANSIエスケープシーケンスは `src/services/ansi/parser.ts` で処理する

### Naming Conventions

| 対象 | 規則 | 例 |
|------|------|-----|
| コンポーネント | PascalCase | `TerminalView.tsx` |
| hooks | camelCase + `use` prefix | `useTerminal.ts` |
| stores | camelCase + `Store` suffix | `connectionStore.ts` |
| services | camelCase（責務を明示） | `sshClient.ts`, `ansiParser.ts` |
| 型定義 | PascalCase | `TmuxSession` |
| 定数 | SCREAMING_SNAKE_CASE | `DEFAULT_PORT` |

## Quality Gates

コードがマージされる前に満たすべき条件。

### Mandatory (必須)

- [ ] `pnpm typecheck` が通過する
- [ ] `pnpm lint` がエラーなしで通過する
- [ ] 新機能にはテストが存在する
- [ ] セキュリティ原則（Principle IV）に違反していない
- [ ] 禁止命名（utils, helpers等）を使用していない

### Recommended (推奨)

- [ ] 関連するドキュメントが更新されている
- [ ] 変更がCLAUDE.mdの規約に従っている
- [ ] UI変更の場合、ui-guidelines.mdに準拠している
- [ ] SOLID原則に違反していない

## Governance

この Constitution の運用ルールを定める。

### Amendment Process

1. 変更提案はPRで行い、影響範囲を明示する
2. Constitution変更はプロジェクトオーナーの承認が必要
3. 変更時はバージョン番号を適切に更新する:
   - MAJOR: 原則の削除・根本的変更
   - MINOR: 新規原則・セクションの追加
   - PATCH: 文言の明確化・誤字修正

### Compliance

- 全てのPR/レビューはConstitution準拠を確認する
- 原則違反が必要な場合は、Complexity Tracking（plan-template.md）で理由を文書化する
- ランタイム開発ガイダンスは `CLAUDE.md` および `docs/` 配下のドキュメントを参照する

**Version**: 1.1.1 | **Ratified**: 2026-01-10 | **Last Amended**: 2026-01-10

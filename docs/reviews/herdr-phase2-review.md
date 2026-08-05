# Herdr Backend Phase 2 Review Report

## レビュー対象

- **対象ブランチ**: `feat/support-hardr`
- **対象機能**: Herdr backend phase 2（Connection migration + UI + foundation）
- **元計画**: Contract v2（`/tmp/implement/mux-pod/_contract_v2.md`）/ Implement DAG（`/tmp/implement/mux-pod/_dag.md`）
- **調査レポート**: `https://md-server.mox.run/d7288186-1835-45ea-8822-02663d1948c4/investigation-report-herdr-backend/`（要認証のため、ローカル Contract v2 を参照）
- **最終検証日**: 2026-06-11

## Round 1: タスク境界レビュー

| # | タスク | 担当ファイル集合 | 判定 | 証拠 | 指摘 | 修正 |
|---|---|---|---|---|---|---|
| 1 | 契約先行: backend domain/adapter | `lib/services/backend/backend_type.dart`, `lib/services/backend/multiplexer_config.dart`, `lib/services/backend/backend_adapter.dart` | **Pass** | `make analyze` 通過、`test/services/backend/*_test.dart` 通過 | なし | — |
| 2 | Connection schema migration / recovery | `lib/providers/connection_provider.dart`, `lib/services/connection/connection_migration.dart`, `test/providers/connection_provider_test.dart` | **Pass with correction** | migration テスト全通過 | `_resolveMultiplexer` 経由の `tmuxPath` 互換パラメータが public API に残存していた | `Connection` から deprecated な `tmuxPath` コンストラクタ/copyWith/getter を削除、内部 migration ロジックは `fromJson` に集約 |
| 3 | UI: connection form multiplexer path + widget test | `lib/screens/connections/connection_form_screen.dart`, `test/screens/connections/connection_form_screen_test.dart` | **Pass** | ウィジェットテスト全通過、Herdr 文字列不在をアサート | なし | — |
| 4a | Transport core: SshConnectOptions / SshClient / executor / resolver | `lib/services/ssh/ssh_client.dart`, `lib/services/tmux/ssh_tmux_command_executor.dart`, `lib/services/tmux/tmux_executable_resolver.dart` | **Pass with correction** | 既存 tmux テスト全通過 | `SshConnectOptions.tmuxPath` / `SshClient.userTmuxPath` / `TmuxExecutableResolver.detect(userTmuxPath)` / `SshTmuxCommandExecutor(userTmuxPath)` 等の非推奨エイリアスが残存していた | これらの deprecated パラメータ・ゲッターを削除 |
| 4b | Consumer wiring: 全 SshConnectOptions 作成箇所 | `lib/providers/notification_panes_provider.dart`, `lib/screens/connections/connections_screen.dart`, `lib/screens/home_screen.dart`, `lib/screens/terminal/terminal_screen.dart`, `test/helpers/fake_ssh_notifier.dart` | **Pass** | `grep SshConnectOptions` ですべて `multiplexer` 使用を確認、`flutter test` 通過 | なし | — |

## Round 2: 結線・回帰レビュー

### 実行コマンドと結果

| コマンド | 結果 |
|---|---|
| `make analyze` | `No issues found!` |
| `make test` | `All tests passed!`（`+570` 前後） |
| 対象テスト `test/screens/connections/connection_migration_e2e_test.dart` | `+1: All tests passed!` |

### 追加確認事項

| 観点 | 方法 | 結果 |
|---|---|---|
| 旧 `tmuxPath` 残存検索 | `grep -R "tmuxPath\|userTmuxPath" lib/` | lib 内の public API からは削除済。残る `tmuxPath` は JSON migration 時の内部読み込み、または `TmuxCommandExecutor.tmuxPath`（解決済みパス）のみ |
| 全 `SshConnectOptions` 生成箇所の再検索 | `grep -R "SshConnectOptions(" lib/` | 全箇所で `multiplexer: connection.multiplexer` を使用。Terminal 経路も含む |
| Herdr 非表示の否定テスト | `test/screens/connections/connection_form_screen_test.dart` `does not contain Herdr or herdr text` | Pass |
| rollback / recovery 故障注入 | `test/providers/connection_provider_test.dart` `rolls back when primary read-back validation fails`, `recovery from invalid source using stale backup` | Pass |
| custom tmux path 接続と再接続 | `test/services/tmux/tmux_executable_resolver_test.dart`, `test/services/tmux/ssh_tmux_command_executor_test.dart` | Pass |
| Tmux parity | 既存 tmux 系テスト全件通過 | Pass |
| migration E2E（旧 JSON → 起動 → 編集 → 保存 → 再起動読込） | 新規 `test/screens/connections/connection_migration_e2e_test.dart` | Pass |

### 指摘と対応

| 指摘 | 重要度 | 対応 |
|---|---|---|
| Contract v2 では `tmuxPath` / `userTmuxPath` が削除対象だったが、実装では `@Deprecated` 互換エイライスとして残っていた | HIGH | **解決**: `Connection` / `SshConnectOptions` / `SshClient` / `TmuxExecutableResolver` / `SshTmuxCommandExecutor` / `test/helpers/fake_ssh_client.dart` から deprecated API を削除。古い JSON 形式の読み込みは `Connection.fromJson` / `ConnectionMigration` 内部で維持 |
| Contract Pattern Map では `TmuxBackend` を `BackendAdapter` の alias/export としていたが、実装では独立した interface だった | MEDIUM | **解決**: `lib/services/tmux/tmux_backend.dart` で `typedef TmuxBackend = BackendAdapter;` とし、`SshClient implements BackendAdapter` に整理。`TmuxInputTransport` は tmux 固有の入力能力として維持 |
| D7（migration E2E）が単体テストのみで一気通貫検証されていなかった | MEDIUM | **解決**: `test/screens/connections/connection_migration_e2e_test.dart` を追加し、旧 JSON 保存 → 起動マイグレーション → 編集画面 → 保存 → 新 Provider 再起動読込 を検証 |
| `docs/herdr-inventory/` が未追跡のまま残っている | LOW | **記録**: 調査アーティファクトとしてコミット対象外。必要に応じて別途整理 |

## 総合判定

**Pass with corrections**

- すべての HIGH/MEDIUM 指摘は解決済み。
- D1〜D7 は満たされている。
- D8（2-round レビュー記録）は本レポートで対応。

## 残存未対応

- `docs/herdr-inventory/` の整理（意図的に未追跡として残置）

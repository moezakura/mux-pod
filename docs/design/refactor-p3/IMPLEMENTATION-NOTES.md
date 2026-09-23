# P3 実装ノート（設計書からの差分・レビュー記録）

P3（lib/screens の 500 行超 8 ファイルの責務ベース再設計）の実装時に、
設計書と異なった点、および独立レビューで記録された非ブロッキング指摘を残す。

## 実装が設計書と異なる点（いずれも挙動・公開 API に影響なし）

1. **connections: 操作オブジェクトの戻り値型**
   - 設計書（connections-screen.md §3.7）は `ConnectionSessionOperations` が
     domain 型（`List<MultiplexerSession>` 等）を返すと記載。
   - 実装は生型（`List<TmuxSession>` / `HerdrSnapshot` 等）を返し、
     `ConnectionCardState` が `toDomain` / `toDomainSessions` で変換してから
     `updateSessionsFromDomain` を呼ぶ。
   - 設計意図（operations は ref 非依存・provider 同期は State 骨格が実施）は
     満たしている。実装側の doc にも「生データと同じ形状で返す」と明記。

2. **markdown: static ScrollKey の実装形**
   - 設計書（shell-and-panes.md v3）は「中立 const への委譲 getter」と記載。
   - 実装は `static const Key rawScrollKey = MarkdownScrollKeys.rawScrollKey;`
     とし、HEAD と同じ **const 宣言**を維持（他ライブラリの const は const 文脈
     で参照可能なため、getter より API 忠実度が高い）。

3. **デッドコード削除（ユーザー承認済み）**
   - `home_screen.dart` の `_TerminalTab` / `_TerminalTabState` /
     `_EmptySessionsView` / `_SessionCard`（計 540 行）は HEAD で
     インスタンス化ゼロのため削除（案A・ユーザー承認）。
   - 専用 l10n キー 4 本（homeActiveSessions 等）は生成物のため残置。
     未使用でも `flutter analyze` 警告は出ない（実測）。

## 独立レビューの記録

| レビュー | 対象 | 判定 | 主な非ブロッキング指摘 |
|---|---|---|---|
| review-a | connections / ansi / navigation | OK | §3.7 の型契約乖離（文書側・上記 1 で記録）/ `_EagerScaleGestureRecognizer` の private 維持確認 / `connection_tile.dart`（HEAD から未使用）は将来の掃除候補 / 行数マージン（ansi 490・card 476） |
| review-b | form / browser / dashboard / shell / notification / markdown | OK | static ScrollKey の const 復元（上記 2 で対応）/ `ConnectionFormValues.port` の `tryParse ?? 22`（validator ゲート済みで到達不能）/ `use_build_context_synchronously` の ignore は HEAD 由来 / listen ガード順序の微差（外部観測差なし）/ 未使用 l10n キー 4 本の残置 |

## 既知の循環参照（P3 対象外・現状維持）

`screens` 配下の相互循環は P3 で解消済み（`dag-verification.md`）。
以下は生成物または P3 対象外で残存する既知の循環。

1. `lib/l10n/app_localizations*.dart` — gen-l10n 生成物（編集禁止）。
2. `lib/services/backend/domain/pane_content_reader.dart` ⇄ `pane_frame_reader.dart`
   — P3 対象外（P1 完了領域）。将来の整理候補。
3. `lib/services/ssh/ssh_client.dart` → （export）`ssh_factory.dart` →
   （import）`ssh_client.dart` — P1 以前からの互換 re-export 形式。将来の整理候補。

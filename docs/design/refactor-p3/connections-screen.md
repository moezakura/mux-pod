# P3 責務ベース再設計 — connections_screen.dart（1702行）

## v3 改訂サマリ（ユーザー指摘「相互循環参照が発生する構造が間違っている」対応・タスク#13）

**背景（実測）**: lib/screens の **10 ファイル SCC**（connections_screen / dashboard / home / keys / notifications / settings×4 / terminal）の原因は `home_screen.dart`（L28-35）所有の `CurrentTabNotifier` / `currentTabProvider` への**逆参照 3 本**（`connections_screen.dart` L10 / `keys_screen.dart` L9 / `settings_search_field.dart` L6 の `import '../home_screen.dart'`）。SCC シミュレーション（付録・スクリプト実測）で**逆辺 3 本を除去すると lib/screens の循環が完全消滅**（1 本ずつの除去では消えないことを実証）。

- **必須A（中立モジュール direct import）**: `connection_list_screen.dart` は `currentTabProvider` を home シム（`home_screen.dart`）経由で import せず、**中立モジュール `lib/navigation/current_tab_provider.dart`（shell 設計が新設）から直接 import** する。connections 配下の**全ファイルは `home_screen.dart` を import しない**（v2 の「home/home_tab_provider.dart 直接 import」案を中立モジュール案へ格上げ）。
- **必須B（実装順序の解決）**: v2 §8-5「home_tab_provider.dart の新設タイミング」は**解決済み**——実装順序「① shell 設計が中立モジュールを新設（= home 逆辺 3 本の除去が先）→ ② その後に connections を改修」を強制。常に SCC 消滅状態で実装が進む。
- **必須C（import 辺リスト）**: 「改修後の connections サブツリー import 辺リスト（ファイル→ファイル）」を §2.4 に新設。**逆向き辺（card→shell 等）が存在しない**ことを明示。特に **`connection_card ⇄ connection_sessions_panel` の型依存はなし**（panel は props 受領のみ・card を import しない）。
- その他（素の public 昇格・500行未満・合成・part/mixin なし・既存テスト差分ゼロ・シム方式）は v1/v2 から維持。
- **実装時ゲート（§7 に追加）**: ① grep で connections 配下に `home_screen.dart` の import が存在しないこと ② §付録の SCC チェックスクリプトで lib/screens の SCC 消滅を再検証。

---

## v2 改訂サマリ（critique §1・§6 対応・タスク#7）

- **必須1（private のまま移動 → 素の public 化）**: 「private のまま別ファイルへ移動」という全記述を削除。Dart の可視性規則（`_` シンボル＝同一ライブラリ＝同一ファイル内のみ参照可）に抵触しコンパイル不能のため、別ファイルへ移す **9 シンボル**（`ConnectionCard` / `ConnectionCardState` / `SearchField` / `SortOptionTile` / `NewSessionDialog` / `CardHeader` / `ExpandedSessionsPanel` / `SessionRow` / `showSortDialog`）を**素の public に昇格**。`@internal` は**使用しない**（P2 実績ゼロ＝`rg "@internal" lib/` 0 件、critique §5.2 の lint 警告リスク回避）。public 化しても外部影響はゼロ（元々 private で外部参照なし・§1.5 実測）。§2/§3/§4 に import 構成を明記。
- **必須2（operations の受渡契約）**: `ConnectionSessionOperations` の各メソッドの戻り値型（`Future<SshClient>` / `Future<List<MultiplexerSession>>`）と、「**State 骨格（ConnectionCardState）がその戻り値を `ref.read(activeSessionsProvider.notifier).updateSessionsFromDomain(...)` に渡す**」契約を §3.7/§5 に明記。operations は ref 非依存のまま（critique §1.2）。
- **推奨1（導出所有者の確定）**: `liveWindowCounts`（L1337-1340）と `statusColor`（L623-637）の導出所有者を**呼出側 State（ConnectionCardState）に確定**。view（CardHeader / ExpandedSessionsPanel / SessionRow）へは導出済みの値をプロパティで渡す。理由: provider watch を view 側に置くと `ConnectionCardState` の setState 再構築と二重の再構築源になる（critique §1.3）。
- **推奨2（循環 import 対策）**: `currentTabProvider` は home シム（`home_screen.dart`）経由の import をやめ、shell 設計の新設 `home/home_tab_provider.dart` を**直接 import** する代替に変更（critique §1.4・§5.5・§6）。実装順序と検証手順を §6-6 に明記。**→ v3 で「home 名前空間にも依存しない中立モジュール `lib/navigation/current_tab_provider.dart`」へ格上げ（下記 v3 サマリ必須A・SCC 実測に基づく）**。
- **推奨3（シェル行数の双値化）**: `connection_list_screen.dart` の見積を **~430（超過時は §6-7 の states 分離で ~330）** に双値化（critique §1.5）。
- 設計原則（全ファイル 500 行未満・合成・part/mixin なし・既存テスト差分ゼロ）は変更なし。

---

- 対象: `lib/screens/connections/connections_screen.dart`（作業ツリー・HEAD 同一・実測 1702 行）
- 出発点: HEAD a86fbdd（P2 完了状態）。`git diff HEAD -- lib/screens/` は空（BRIEF 要件確認済み）。
- 方針: P2 と同一の compat re-export 方式。「公開 API 維持」「既存テスト差分ゼロ」「1ファイル=1責務・500行未満」「合成 + 単一状態所有者」。
- 行番号の基準: 作業ツリー実ファイル（= HEAD）。

---

## 1. 現状分析（事実）

### 1.1 1ファイルに同居する責務と行範囲（実測）

| 責務 | 行範囲 | 実測行数 | 主メンバ |
|---|---|---|---|
| ① 検索バー表示状態（Notifier） | 1-42 | 42 | `_SearchVisibleNotifier`（L29）/ `_searchVisibleProvider`（L37） |
| ② 画面シェル（一覧 Scaffold・AppBar・FAB・状態分岐・CRUD 導線） | 44-592 | 549 | `ConnectionsScreen` |
| ③ 接続カード（Widget 定義） | 593-611 | 19 | `_ConnectionCard` |
| ④ カード状態（表示骨格・展開・SSH 操作・セッション表示） | 612-1468 | **857** | `_ConnectionCardState` |
| ⑤ 検索フィールド | 1469-1556 | 88 | `_SearchField` + `_SearchFieldState` |
| ⑥ ソートタイル | 1557-1591 | 35 | `_SortOptionTile` |
| ⑦ 新規セッション名入力ダイアログ | 1592-1702 | 111 | `_NewSessionDialog` + `_NewSessionDialogState` |

BRIEF 記載の境界（29 / 44-593 / 593-612 / 612-1469 / 1469-1556 / 1557-1591 / 1592-1702）は実測と一致（`_ConnectionCardState` は L612-1468 の 857 行 =「約860行」）。

### 1.2 `ConnectionsScreen`（ConsumerWidget・L44-592）の内部

| メンバ | 行 | 行数 | 内容 |
|---|---|---|---|
| `sshClientFactory`（final フィールド） | L45 | 1 | `Future<SshClient> Function(Connection)?`。テスト3本が注入 |
| `build` | L50-78 | 28 | CustomScrollView（SliverAppBar + SliverPadding + SliverList）+ FAB |
| `_buildAppBar` | L80-168 | 90 | SliverAppBar（検索欄・アクション3ボタン=検索/ソート/設定） |
| `_openSettings` | L170-174 | 5 | `currentTabProvider.setTab(3)` |
| `_showSortDialog` | L175-289 | 115 | showModalBottomSheet + `_SortOptionTile`×6 |
| `_buildFAB` | L290-301 | 12 | `heroTag: 'fab_add_connection'`（L293） |
| `_buildBody` | L302-353 | 52 | 状態分岐（loading/error/empty/noResults/リスト）→ `ValueKey(connection.id)` + `RepaintBoundary` + `_ConnectionCard`（L332） |
| `_buildNoResultsState` | L354-417 | 64 | 検索0件ビュー |
| `_buildErrorState` | L418-441 | 24 | エラービュー（reload ボタン） |
| `_buildEmptyState` | L442-494 | 53 | 空ビュー |
| `_addConnection` | L495-507 | 13 | ConnectionFormScreen へ push |
| `_editConnection` | L508-526 | 19 | ConnectionFormScreen(connectionId) へ push |
| `_deleteConnection` | L527-565 | 39 | 確認ダイアログ → `SecureStorageService().deletePassword(id)` → `connectionsProvider.notifier.remove(id)` → `context.mounted` ガードで SnackBar |
| `_connectToServer` | L566-592 | 27 | `updateLastConnected` → `touchSession`（sessionName non-null 時）→ TerminalScreen へ push |

### 1.3 `_ConnectionCardState`（L612-1468・857行）の内部

| メンバ | 行 | 行数 | 内容 |
|---|---|---|---|
| 状態フィールド | L613-619 | 7 | `_isExpanded` / `_isLoadingSessions` / `_sessions`（List\<TmuxSession>）/ `_sessionError` / `_herdrSnapshot`（HerdrSnapshot?） |
| `build` | L622-798 | 177 | コンテナ + カードヘッダー（InkWell：status icon stack 40×40・名前・host•username・破損キー警告 + バッジ・展開アイコン）+ 展開時 `_buildExpandedContent`。`ref.watch(activeSessionsProvider)`（L626）/ `ref.watch(keysProvider)`（L633）/ `isKeyDamaged`（L634） |
| `_backendKind` getter | L799-805 | 7 | `connection.multiplexer.backend` → tmux / herdr |
| `_toggleExpand` | L806-822 | 17 | `setState` で展開反転、展開時に herdr=`_herdrSnapshot==null` / tmux=`_sessions.isEmpty` なら `_fetchSessions` |
| `_connectSsh` | L823-859 | 37 | factory 分岐（L827）/ SecureStorageService から privateKey・passphrase・password を取得し `SshClient.connect(lightweight: true, l10n: ...)` |
| `_fetchSessions` | L860-902 | 43 | setState(loading) → `_connectSsh` → herdr: snapshot / tmux: `_reloadSessions` → mounted ガード → setState → `updateSessionsFromDomain` → catch → finally `client?.disconnect()` |
| `_reloadSessions` | L903-924 | 22 | `tmuxFacade.listSessions` → mounted → setState → `updateSessionsFromDomain`（tmux） |
| `_killSession`（tmux） | L925-984 | 60 | 確認ダイアログ（`_isLoadingSessions` ガード）→ `_connectSsh` → `tmuxFacade.killSession` → **同一接続で `_reloadSessions(client)`** → SnackBar（connSessionKilled） |
| `_killHerdrWorkspace` | L985-1059 | 75 | workspaceId null/empty ガード（SnackBar connCannotCloseWorkspace）→ 確認ダイアログ（連鎖 close 警告・R2）→ `_connectSsh` → `HerdrAdapter(client).workspaceClose(id)` → `snapshot()` → mounted → setState → `updateSessionsFromDomain` → SnackBar（connWorkspaceClosed） |
| `_buildExpandedContent` | L1060-1082 | 23 | backend 分岐で domain セッション一覧を組み立て |
| `_buildDomainExpandedContent` | L1083-1244 | 162 | 'ACTIVE SESSIONS' ヘッダー + リロードボタン（`_isLoadingSessions` で disable）+ loading/エラー/空/セッション行 4 分岐 + New Session/Workspace ボタン + Divider + Edit/Delete ボタン行 |
| `_showNewSessionDialog` | L1245-1271 | 27 | 既存名取得 → `showDialog<String>`（`_NewSessionDialog`）→ herdr: `_createHerdrWorkspace` / tmux: `widget.onConnect(sessionName)` |
| `_createHerdrWorkspace` | L1272-1318 | 47 | `_connectSsh` → `workspaceCreate(label)` → `snapshot()` → mounted → setState → `updateSessionsFromDomain` → SnackBar（connWorkspaceCreated） |
| `_buildDomainSessionItems` | L1319-1448 | 130 | セッション行（terminal icon・名前・`connWindowsCount`・Attached/Detached バッジ・Kill ボタン）。`liveWindowCounts` は provider 最新 window 数優先（L1337-1340） |
| `_buildDamagedKeyBadge` | L1449-1468 | 20 | 破損キーバッジ |

### 1.4 状態・リソース所有権インベントリ（実測）

| リソース | 所有者 | 生成 | 破棄 | 備考 |
|---|---|---|---|---|
| `_isExpanded` / `_isLoadingSessions` / `_sessions` / `_sessionError` / `_herdrSnapshot` | `_ConnectionCardState` | フィールド初期値 | State 破棄（明示 dispose なし） | `setState` でのみ更新 |
| `TextEditingController _controller` | `_SearchFieldState` | `initState`（L1490） | `dispose`（L1504） | `didUpdateWidget`（L1494-1502）に「initialValue が空になったら clear」分岐 |
| `GlobalKey<FormState> _formKey` | `_NewSessionDialogState` | フィールド（L1602） | — | `_submit`（L1638）で validate |
| `TextEditingController _nameController` | `_NewSessionDialogState` | `initState`（L1608・デフォルト名 `session-N`） | `dispose`（L1613） | — |
| `SshClient` | 各 async メソッドのローカル変数 | `_connectSsh` | `finally { await client?.disconnect(); }` | 4 メソッドで同一パターン |
| `ref.watch` | `_ConnectionCardState.build` | — | Riverpod | `activeSessionsProvider` / `keysProvider` |
| `ref.read` | `_ConnectionCardState` / `ConnectionsScreen` | — | Riverpod | `connectionsProvider` / `activeSessionsProvider` 等 |
| `Timer` / `StreamSubscription` / `FocusNode` / `ScrollController` / `ref.listen` | **なし（実測 0 件）** | — | — | `rg` で確認済み。`FocusNode` は Framework 内部（autofocus）のみ |

### 1.5 呼出元・import（rg 実測）

**import 元**（パスを維持する必要あり）:
- `lib/screens/home_screen.dart:19`（`import 'connections/connections_screen.dart';`）→ L52 `ConnectionsScreen()`（const・引数なし）
- テスト 3 本（下記）→ `package:flutter_muxpod/screens/connections/connections_screen.dart` + `home: ConnectionsScreen(sshClientFactory: ...)`

**本ファイルの import**（実測・全 21 本）:
`dart:developer` / `material` / `flutter_riverpod` / `google_fonts` / `../../providers/active_session_provider.dart` / `../../providers/connection_provider.dart` / `../../providers/key_provider.dart` / `../home_screen.dart` / `../../l10n/l10n_ext.dart` / `../../services/backend/backend_type.dart` / `../../services/backend/domain/multiplexer_backend.dart` / `.../multiplexer_session.dart` / `../../services/herdr/herdr_adapter.dart` / `.../herdr_models.dart` / `.../herdr_to_domain.dart` / `../../services/keychain/secure_storage.dart` / `../../services/ssh/ssh_client.dart` / `../../services/tmux/tmux_facade.dart` / `.../tmux_models.dart` / `.../tmux_to_domain.dart` / `../../theme/design_colors.dart` / `connection_form_screen.dart` / `../terminal/terminal_screen.dart`

**参照される外部 API**（移設先ファイルの依存として維持）:
- `connectionsProvider` / `filteredConnectionsProvider` / `connectionSearchProvider` / `connectionSortProvider`（`connection_provider.dart` compat → `connections_notifier` / `connection_selectors` / `connection_ui_state`）
- `activeSessionsProvider`（`getSessionsForConnection` / `touchSession` / `updateSessionsFromDomain`）
- `keysProvider` / `isKeyDamaged`（`key_provider.dart`）
- `currentTabProvider`（`home_screen.dart` L28-35 定義 — **本ファイル→home_screen の逆参照（import '../home_screen.dart' L10）が lib/screens 10ファイル SCC の原因の 1 つ（v3 実測）**。v3 では「connections 配下は `home_screen.dart` を import せず、中立モジュール `lib/navigation/current_tab_provider.dart`（shell 設計が新設）を直接 import」に変更（§2.4 import 辺リスト・§6-6））
- `tmuxFacade.listSessions / killSession`、`HerdrAdapter`（snapshot / workspaceCreate / workspaceClose）、`SecureStorageService`、`SshClient`、`TmuxSession`、domain 変換（`toDomain` / `toDomainSessions`）

### 1.6 既存テストが固定している挙動（実測・テスト名単位）

対象 3 ファイル（`test/screens/connections/`・rg `connections_screen` による特定）。**すべて `ConnectionsScreen(sshClientFactory: ...)` を `home:` に置き、`_StaticConnectionsNotifier extends ConnectionsNotifier`（build のみ override）と `_EmptyActiveSessionsNotifier extends ActiveSessionsNotifier`（build のみ override）で provider を差し替える**。

※同ディレクトリの `connections_screen_immediate_reflect_test.dart`（254 行）は**notifier レベル**のテスト（コメント冒頭「Widget-level testing of ConnectionsScreen is out of scope」・import は connection_provider / secure_storage のみ・rg 実測で connections_screen.dart を**コード参照ゼロ**。`ConnectionsScreen` のヒットはコメント 2 箇所のみ）→ 本設計の分割対象外。`test/screens/terminal/terminal_screen_contract_test.dart` も実測で connections_screen / ConnectionsScreen を参照しない（rg 0 件）ため対象外（検証計画 §7 に反映）。

#### connections_screen_session_kill_test.dart（103 行・1 本）
- テスト名: `'TERM-CRUD session kill confirms, executes kill-session, and reloads'`
- 固定する挙動:
  1. カード名 `'Test Server'` タップ → 展開 → `'mysession'` 表示（`list-sessions` fixture → `_sessions` 反映）
  2. `find.byTooltip('Kill session')`（= connKillSessionTooltip）タップ → ダイアログ `'Kill Session'`（connKillSessionTitle）+ `find.widgetWithText(TextButton, 'Kill')`（connKill）。**この時点で kill-session コマンドが未発行**（確認前は発行しない）
  3. `'Kill'` タップ後: `execCommands` 内で `kill-session ... -t mysession` が発行され、**その後に `list-sessions`（reload）が再来する**（`kill < reload` のインデックス順序検証 = 同一接続での kill→reload 並び）
  4. `'Session mysession killed'`（connSessionKilled）SnackBar 表示・`'mysession'` 消滅・`'other'` 表示（2 回目の list-sessions 出力反映）

#### connections_screen_herdr_test.dart（395 行・4 本）
- テスト名 1: `'herdr connection expands to a session list with workspace operations enabled (T16/Q-05)'`
  - 展開 → `'lab-ws1'` + `'1 windows'`（connWindowsCount(1)）+ `'Attached'`（connAttached、findsOneWidget=バッジ重複なし）+ `'New Workspace'`（connNewWorkspace）+ `find.byTooltip('Kill workspace')`（connKillWorkspaceTooltip）
  - `herdr api snapshot` コマンド発行検証
  - `'lab-ws1'` タップ → **TerminalScreen 遷移**。`pump()` + `pump(400ms)` + `pump(200ms)`（**pumpAndSettle 不使用**=TerminalScreen のライブポーリングが回り続けるため）
  - `'Not connected — viewing only'` なし + `find.byType(SpecialKeysBar)` あり
- テスト名 2: `'herdr New Workspace creates a workspace via workspace create and refreshes the list (T16/Q-05)'`
  - `'New Workspace'` タップ → `_NewSessionDialog` の `find.byType(TextField)` に `'api'` 入力 → `'Create'`（connCreate・FilledButton）タップ
  - `herdr workspace create` かつ `'api'` を含むコマンド発行検証
  - **2 回目の snapshot（execOutputQueues FIFO）** → `'api'` + `'lab-ws1'` 両表示
- テスト名 3: `'herdr Kill Workspace confirms the chain close and closes the workspace (T16/Q-05)'`
  - `find.byTooltip('Kill workspace')` タップ → `'Close Workspace?'`（connCloseWorkspaceTitle）+ `textContaining('All tabs and panes in this workspace')`（connCloseWorkspaceMessage・R2 連鎖警告）
  - `'Cancel'`（connCancel）→ **workspace close 未発行**の検証
  - 再タップ → `'Close'`（connClose）→ `herdr workspace close w1` 発行検証 → `'lab-ws1'` 消滅（**kill 後の snapshot は workspaces 空**）
- テスト名 4: `'tmux connection keeps the existing session UI unchanged'`
  - tmux backend 展開 → `'mysession'` + `'New Session'`（connNewSession）+ `find.byTooltip('Kill session')` 維持

#### connections_screen_damaged_key_test.dart（167 行・2 本・locale ja）
- テスト名 1: `'shows damaged key badge for connection using a broken key'`
  - 鍵メタに `broken-key-id` があり秘密鍵なし（破損）→ ヘッダーに `Icons.warning_amber`（findsWidgets）+ バッジ `'破損した鍵を使用中'`（connDamagedKeyBadge）
- テスト名 2: `'does not show damaged key badge for healthy key connection'`
  - 秘密鍵あり（`privatekey_healthy-key-id: 'K'`）→ バッジ `findsNothing`

**固定される構造まとめ**: カード名タップで展開・セッション行表示・tooltip 文言（'Kill session'/'Kill workspace'）・ダイアログタイトル/ボタン文言・「確認前にコマンド未発行」「kill→reload 同一接続」の非同期並び・New ダイアログの TextField+Create・TerminalScreen 遷移・破損キーバッジ。Widget 型指定は `TextField` / `TerminalScreen` / `SpecialKeysBar` / `TextButton`・`FilledButton` のみ（private 型 `_ConnectionCard` 等はテスト非参照）。

---

## 2. 目標構成

**全体方針（P2 と同一）**: 元ファイル `connections_screen.dart` は公開 API 安定供給のため thin re-export シムとして存続。実装は責務単位の **8 ファイル**へ分割（下表 #2-9）。**v2 変更（critique §1.1・必須1）: private のまま別ファイルへ移す設計は Dart の可視性規則（`_` 接頭辞シンボルは同一ライブラリ=同一ファイル内のみ参照可能）に抵触しコンパイル不能。別ファイルへ移す 9 シンボルはすべて「素の public」へ昇格する**。`@internal` は使用しない（P2 で使用実績ゼロ＝`rg "@internal" lib/` 0 件・critique §5.2 の lint 警告リスク回避）。昇格しても外部への影響はゼロ（元々 private・ファイル外参照なし・§1.5 実測）。識別子・ツリー形状は現行どおり。

| # | ファイル | 責務（1文） | 公開シンボル（v2: 素の public 昇格） | 推定行数 | 依存先・import 構成 |
|---|---|---|---|---|---|
| 1 | `lib/screens/connections/connections_screen.dart`（存続・シム） | 既存公開面の安定供給（`ConnectionsScreen`） | `ConnectionsScreen`（export） | ~20 | `export 'connection_list_screen.dart'` のみ |
| 2 | `lib/screens/connections/connection_list_screen.dart` | サーバ一覧画面シェル（AppBar・検索/ソート導線・FAB・状態分岐・CRUD・接続遷移 + `_SearchVisibleNotifier`） | `ConnectionsScreen` | **~430（超過時 §6-7 の states 分離で ~330）** | **import**: `connection_sort_sheet.dart` / `connection_search_field.dart` / `connection_card.dart`、**中立モジュール `lib/navigation/current_tab_provider.dart`**（currentTabProvider・shell 設計が新設。**`home_screen.dart` は import しない**・v3 必須A）、`connection_form_screen.dart`、`terminal_screen.dart`、providers、theme、l10n |
| 3 | `lib/screens/connections/connection_sort_sheet.dart` | ソート選択 UI（モーダルシート + タイル） | `SortOptionTile` / `showSortDialog`（public 昇格） | ~135 | import: `connection_ui_state`（connectionSortProvider / ConnectionSortOption）・`design_colors`・`l10n`。**シェルから import される** |
| 4 | `lib/screens/connections/connection_search_field.dart` | 検索テキストフィールド（IME・controller 所有） | `SearchField`（+ `SearchFieldState`・public 昇格） | ~100 | import: `design_colors`・`l10n`。**シェルから import される** |
| 5 | `lib/screens/connections/connection_card.dart` | 接続カード（widget + **単一状態所有者** State 骨格） | `ConnectionCard` / `ConnectionCardState`（public 昇格） | ~310 | **import**: `connection_card_header.dart` / `connection_sessions_panel.dart` / `connection_session_operations.dart` / `connection_new_session_dialog.dart`、providers（active_session / keys）、l10n。**シェルから import される** |
| 6 | `lib/screens/connections/connection_card_header.dart` | カードヘッダー表示（status アイコン・接続情報・破損キー警告 + バッジ・展開アイコン） | `CardHeader` / `DamagedKeyBadge`（public 昇格） | ~150 | import: `design_colors`・`l10n`。**カード State から import される**。provider watch なし（導出値はプロパティ受領・§5） |
| 7 | `lib/screens/connections/connection_sessions_panel.dart` | 展開パネル（セッション一覧・ロード/エラー/空分岐・New ボタン・Edit/Delete・セッション行） | `ExpandedSessionsPanel` / `SessionRow`（public 昇格） | ~300 | import: `multiplexer_session` / `active_sessions_state` / `design_colors` / `l10n`。**カード State から import される** |
| 8 | `lib/screens/connections/connection_session_operations.dart` | マルチプレクサ操作（SSH 接続・snapshot/listSessions・kill/close/create・domain 変換）の協調オブジェクト | `ConnectionSessionOperations`（public 昇格・ref 非依存） | ~210 | import: `ssh_client`・`secure_storage`・`tmux_facade`・`herdr_adapter`・`herdr_to_domain`・`tmux_to_domain`・domain モデル・`l10n`。**カード State から import される** |
| 9 | `lib/screens/connections/connection_new_session_dialog.dart` | 新規セッション/workspace 名入力ダイアログ（validator・既定名生成） | `NewSessionDialog`（public 昇格） | ~115 | import: `design_colors`・`l10n`。**カード State から import される** |

**合計 ~1,770 行**（現行 1,702 に対し +4%。P2 の critique 指摘（+17%）を踏まえ、部品化による import/doc 追加を最小化した控えめな見積）。**各ファイル 500 行未満を数値で保証**: 最長は `connection_list_screen.dart`（~430・v2 双値）と `connection_sessions_panel.dart`（~300）。§3 の移動マッピングの行数合計が根拠（シェル = 549 − ソート 115 = 434 → **初期値 ~430。実装が 450 行を超えた時点で `_buildNoResultsState`（L354-417・64行）と `_buildEmptyState`（L442-494・53行）を `connection_list_states.dart` へ切り出すと ~330 へ戻る**。パネル = 23+162+130+20 = 335 に import を乗せても 500 未満。）。

**依存グラフ（一方向・循環なし・v3）**:
```
[シム] connections_screen.dart ──export──▶ connection_list_screen.dart（ConnectionsScreen）
        （import 由来の public シンボルは再 export されない = Dart 仕様。ConnectionCard 等の
          public 昇格分がシム経由で外部へ漏れることはない）
              ▲                                   │
              │ import（home 逆辺なし・現行どおり）│ import（home 経由なし）
    home_screen.dart（IndexedStack で build）      ▼
    ConnectionsScreen ──import──▶ connection_sort_sheet / connection_search_field /
                                  connection_card → card_header / sessions_panel /
                                                   session_operations / new_session_dialog
    connection_list_screen ──import──▶ [中立モジュール] lib/navigation/current_tab_provider.dart
                                        （home_screen.dart に非依存・shell 設計が新設）
    （connections 配下の全ファイルは providers / services / theme / l10n / navigation のみ参照。
       home_screen.dart への逆参照は存在しない＝SCC 原因の home 逆辺 3 本のうち 1 本を除去）
```
- `connection_session_operations` は **ref 非依存**（SshClient と値・l10n を引数で受け取る協調オブジェクト）。ライフサイクル・ref 同期・UI はカード State が所有（§5）。戻り値の受渡契約は §3.7/§5 に明記（v2 必須2）。
- **v3 の構造修正（ユーザー指摘対応）**: 現行循環（connections_screen ↔ home_screen）は `home_screen.dart` 所有の `CurrentTabNotifier`/`currentTabProvider`（L28-35）への逆参照が原因（§付録・SCC 実測）。v3 では **`currentTabProvider` を中立モジュール `lib/navigation/current_tab_provider.dart` から直接 import** し、connections 配下は `home_screen.dart` を**一切 importしない**（§2.4 import 辺リスト・§6-6 に実装順序）。

### 2.4 改修後の connections サブツリー import 辺リスト（ファイル→ファイル・v3 必須C）

改修後の connections 配下（シム + 新規 8 ファイル + 既存 connection_form_screen.dart）の import/export 辺を**全列挙**する。送信元→送信先の一方向のみで、**逆向き辺（card→shell 等）は存在しない**。

| # | 送信元 | 送信先 | 種別・用途（実測/設計根拠） |
|---|---|---|---|
| 1 | `connections_screen.dart`（シム） | `connection_list_screen.dart` | **export**（ConnectionsScreen 供給のみ。import ではなく供給辺＝循環を作らない） |
| 2 | `connection_list_screen.dart` | `connection_sort_sheet.dart` | import（`showSortDialog` / `SortOptionTile` を参照） |
| 3 | `connection_list_screen.dart` | `connection_search_field.dart` | import（`SearchField` を参照） |
| 4 | `connection_list_screen.dart` | `connection_card.dart` | import（`ConnectionCard` を SliverList で build） |
| 5 | `connection_list_screen.dart` | **中立モジュール `lib/navigation/current_tab_provider.dart`** | import（`currentTabProvider` のみ・`_openSettings` の setTab(3) 用。**home_screen.dart 経由ではない**） |
| 6 | `connection_list_screen.dart` | `connection_form_screen.dart` | import（push 遷移。既存・P3 対象#3 の相手） |
| 7 | `connection_list_screen.dart` | `terminal_screen.dart` | import（push 遷移。既存・P4 対象外の相手） |
| 8 | `connection_card.dart` | `connection_card_header.dart` | import（`CardHeader` / `DamagedKeyBadge` を build） |
| 9 | `connection_card.dart` | `connection_sessions_panel.dart` | import（`ExpandedSessionsPanel` / `SessionRow` を build） |
| 10 | `connection_card.dart` | `connection_session_operations.dart` | import（`ConnectionSessionOperations` を合成・戻り値受領） |
| 11 | `connection_card.dart` | `connection_new_session_dialog.dart` | import（`NewSessionDialog` を showDialog で表示） |
| 12 | `connection_card_header.dart` → **（なし）** | — | providers/services/theme/l10n のみ参照。**connections 内へ逆辺なし** |
| 13 | `connection_sessions_panel.dart` → **（なし）** | — | **props 受領のみ。`connection_card.dart` を import しない**（card ⇄ panel の型依存なし） |
| 14 | `connection_session_operations.dart` → **（なし）** | — | services/domain モデル/l10n のみ参照（ref 非依存）。逆辺なし |
| 15 | `connection_new_session_dialog.dart` → **（なし）** | — | design_colors / l10n のみ参照。逆辺なし |
| 16 | `connection_form_screen.dart` → **（なし）** | — | `import 'connections_screen.dart'` は**実測 0 件**（既存 grep） |

**逆向き辺の不在（明示）**:
- `connection_card.dart → connection_list_screen.dart`（シェル）: **なし**（シェルがカードを import する一方向のみ）。
- `connection_sessions_panel.dart` / `connection_card_header.dart` / `connection_session_operations.dart` / `connection_new_session_dialog.dart` → `connection_card.dart`: **なし**（すべて props / 引数で値を受領し、カード State やシェルへはコールバックで値を返すのみ。**card ⇄ sessions_panel の型依存なし = panel は `List<MultiplexerSession>` 等の値型とコールバックのみをプロパティに持つ**）。
- connections 配下の全ファイル → `home_screen.dart`: **なし**（v3 必須A・home 逆辺から除外）。
- connections 配下の全ファイル → `connections_screen.dart`（シム）: **なし**（シムは export される側であり、配下から import されない）。

---

## 3. 移動マッピング

凡例: 【移動】= 新ファイルへ移設（移動のみ・ロジック変更なし）/【残】= 元ファイル（シムに吸収される実装先）に残す。

### 3.1 connections_screen.dart → connection_list_screen.dart（シェル）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| import 群 | 各新ファイルへ配分 | 【移動】 | シェルは `dart:developer` / material / riverpod / google_fonts / providers(connection, active_session? 不要)/ l10n_ext / theme / **`connection_sort_sheet.dart`・`connection_search_field.dart`・`connection_card.dart`（public シンボル参照のための import）** / connection_form_screen / terminal_screen を維持。**`currentTabProvider` は `home_screen.dart` を import せず、中立モジュール `lib/navigation/current_tab_provider.dart` を直接 import（v3 必須A・§6-6）** |
| `_SearchVisibleNotifier` / `_searchVisibleProvider`（L1-42） | connection_list_screen.dart | 【移動】 | **定義と使用が同一ファイル内で完結**するため private のままで可（外部参照ゼロ・rg 確認済み。critique §1.6 の良い点どおり） |
| `ConnectionsScreen` クラス全体（L44-592） | connection_list_screen.dart | 【移動】 | `sshClientFactory`（L45）・`build`（L50-78）・`_buildAppBar`（L80-168）・`_openSettings`（L170-174）・`_buildFAB`（L290-301）・`_buildBody`（L302-353）・`_buildNoResultsState`（L354-417）・`_buildErrorState`（L418-441）・`_buildEmptyState`（L442-494）・`_addConnection`（L495-507）・`_editConnection`（L508-526）・`_deleteConnection`（L527-565）・`_connectToServer`（L566-592）を**そのまま写経** |

### 3.2 connections_screen.dart → connection_sort_sheet.dart（ソート UI）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `_showSortDialog`（L175-289） | connection_sort_sheet.dart（**public トップレベル関数 `showSortDialog(BuildContext, WidgetRef)` へ昇格**） | 【移動】 | 呼出はシェル `_buildAppBar` の `IconButton.onPressed: () => showSortDialog(context, ref)`。**シェル側が `connection_sort_sheet.dart` を import**。private のままの関数移設は可視性規則で**不可**（v2 必須1） |
| `_SortOptionTile`（L1557-1591） | connection_sort_sheet.dart（**public `SortOptionTile` へ昇格**） | 【移動】 | プロパティ 4 つ（title/option/currentOption/onTap）不変・同ファイル内で `showSortDialog` から使用 |
| l10n キー: connSortTitle / connSortNameAsc / connSortNameDesc / connSortLastConnectedDesc / connSortLastConnectedAsc / connSortHostAsc / connSortHostDesc | — | 参照維持 | 移設先で使用 |

### 3.3 connections_screen.dart → connection_search_field.dart（検索フィールド）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `_SearchField`（L1469-1483） | connection_search_field.dart（**public `SearchField` へ昇格**） | 【移動】 | プロパティ 3 つ（initialValue/onChanged/onClear）不変。**呼出はシェル `_buildAppBar`（`connection_search_field.dart` を import）** |
| `_SearchFieldState`（L1484-1556） | connection_search_field.dart（public `SearchFieldState`） | 【移動】 | `initState`（controller 生成 L1490）・`didUpdateWidget`（L1494-1502 の「initialValue が空なら clear」分岐を**そのまま維持**）・`dispose`（L1504）・`build`（autofocus: true L1525・suffix clear ボタン=_controller.text 依存 L1542） |
| 検索配線（L114-122: provider への onChanged/onClear） | connection_list_screen.dart `_buildAppBar` | 【残】 | `setQuery` / `clear` / `_searchVisibleProvider.hide` の順序維持 |

### 3.4 connections_screen.dart → connection_card.dart（カード状態所有者）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `_ConnectionCard`（L593-611） | connection_card.dart（**public `ConnectionCard` へ昇格**） | 【移動】 | コンストラクタ（connection / sshClientFactory / onConnect / onEdit / onDelete）不変。**呼出はシェル `_buildBody`（`connection_card.dart` を import）** |
| `_ConnectionCardState`（L612-1468） | connection_card.dart（public `ConnectionCardState extends ConsumerState<ConnectionCard>`） | 【移動】 | **単一状態所有者は State のまま**（§5）。フィールド・build 骨格・`_backendKind`・`_toggleExpand`・async 骨格 4 本・`_showNewSessionDialog` を移設 |
| フィールド 5 種（L613-619） | connection_card.dart（State） | 【移動・残】 | §5 の状態所有権表どおり |
| `build`（L622-798） | connection_card.dart（State） | 【移動】 | ヘッダー部分（L644-784 付近の status icon / Connection Info / Expand Icon）を `CardHeader(...)` 呼び出しに置換、展開部は `ExpandedSessionsPanel(...)` 呼び出しに置換。**statusColor 導出（L623-637）と `liveWindowCounts`（L1337-1340 相当）は State で行い、値をプロパティで渡す**（v2 推奨1・§5）。**生成される Widget ツリー（テキスト・tooltip・アイコン・ボタン）は現行と同一** |
| `_backendKind`（L799-805） | connection_card.dart（State） | 【移動】 | — |
| `_toggleExpand`（L806-822） | connection_card.dart（State） | 【移動】 | 「展開時のみ fetch（herdr: `_herdrSnapshot==null` / tmux: `_sessions.isEmpty`・`_isLoadingSessions` ガード）」を維持 |
| `_buildExpandedContent`（L1060-1082） | connection_sessions_panel.dart | 【移動】 | backend 分岐の domain 変換は **State 側**で行い、`ExpandedSessionsPanel` へは domain 一覧を渡す（v2 推奨1） |
| `_showNewSessionDialog`（L1245-1271） | connection_card.dart（State） | 【移動】 | 既存名取得 → `NewSessionDialog` 呼び出し → herdr: 骨格 / tmux: `widget.onConnect(sessionName)` の分岐を維持 |

### 3.5 connections_screen.dart → connection_sessions_panel.dart（表示部品群）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `_buildDomainExpandedContent`（L1083-1244） | connection_sessions_panel.dart（**public `ExpandedSessionsPanel`** StatelessWidget へ） | 【移動】 | 引数をプロパティ化: sessions / isLoading / sessionError / backendKind / isHerdr / l10n / onReload（`_fetchSessions`・`_isLoadingSessions` で disable）/ onNewSession / onEdit / onDelete。**分岐順（loading→error→empty→行）とボタン文言・tooltip は現行どおり** |
| `_buildDomainSessionItems`（L1319-1448） | connection_sessions_panel.dart（**public `SessionRow`** へ1行単位で） | 【移動】 | 引数をプロパティ化: session / windowCount / isAttached→color / onTap / onKill（`_isLoadingSessions` で disable）/ isHerdr による tooltip 分岐。**`liveWindowCounts` の計算（L1337-1340）は呼出側 State が行い、解決済み windowCount を渡す**（v2 推奨1・critique §1.3）。`onTap: widget.onConnect(session.name, sessionId: session.id)`（L1383）はコールバック受け渡し |
| `_buildDamagedKeyBadge`（L1449-1468） | **connection_card_header.dart（public `DamagedKeyBadge`）** | 【移動】 | バッジ単体 StatelessWidget。**v2 で配置先を header 側に確定**（破損キー警告アイコン + バッジはヘッダー内の Connection Info 領域 L695-708 に同居するため。呼出は `CardHeader` 内） |
| `_buildExpandedContent`（L1060-1082） | connection_sessions_panel.dart | 【移動】 | 「backend に応じ domain セッション一覧を組み立て」は **State 側**で行い `ExpandedSessionsPanel(sessions: ...)` へ渡す（`_herdrSnapshot?.toDomainSessions()` / `_sessions.map((s) => s.toDomain())` の分岐は現行どおり） |

### 3.6 connections_screen.dart → connection_card_header.dart（ヘッダー表示）

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `build` 内ヘッダー部（L644-784 付近: InkWell > Row > status icon stack / Connection Info / 破損キー警告 + Expand Icon） | connection_card_header.dart（**public `CardHeader`** StatelessWidget へ） | 【移動】 | プロパティ化: connection / isExpanded / isConnected / statusColor / hasDamagedKey / onTap / l10n。**`statusColor` 導出（L623-637: hasActiveSessions→success / lastConnectedAt→orange / muted の3分岐）は呼出側 State（ConnectionCardState）に確定**（v2 推奨1・critique §1.3）。State が `ref.watch(activeSessionsProvider)` / `ref.watch(keysProvider)` → `isKeyDamaged` の判定を行い、導出済みの statusColor / hasDamagedKey / isConnected を CardHeader へ渡す。**CardHeader 内に provider watch を持たせない**（State の setState 再構築と二重の再構築源になるのを防ぐ） |
| `_buildDamagedKeyBadge`（L1449-1468） | connection_card_header.dart（public `DamagedKeyBadge`・§3.5 参照） | 【移動】 | `CardHeader` 内から使用 |
| `_backendKind` の使用箇所 | — | 各ファイルで必要に応じ値を渡す | tooltip 分岐は panel / header が引数 `isHerdr` で受ける |

### 3.7 connections_screen.dart → connection_session_operations.dart（操作協調・v2 戻り値契約）

**受渡契約（v2 必須2・critique §1.2）**: `ConnectionSessionOperations` の各メソッドは **ref を持たず、戻り値で結果を返す**。State 骨格（ConnectionCardState）がその戻り値を受領し、**`ref.read(activeSessionsProvider.notifier).updateSessionsFromDomain(connectionId: ..., connectionName: ..., host: ..., sessions: <戻り値>, backend: <backend>)` に渡す**。operations は `updateSessionsFromDomain` を**直接呼ばない**（ref 依存が漏れない）。

| 現行メンバ（行） | 移動先（戻り値型） | 種別 | 備考 |
|---|---|---|---|
| `_connectSsh`（L823-859） | `Future<SshClient> connect({required Connection connection, Future<SshClient> Function(Connection)? factory, required AppLocalizations l10n})` | 【移動】 | factory 分岐（L827）・SecureStorage 読み出し（L831-852 の key/password 分岐）・`connect(lightweight: true, l10n: ...)`（L854-859）を写経。**`factory` と `connection` は呼び出し時引数**（現行の `widget.` ライブ参照と等価）。戻り値は接続済み `SshClient`（骨格が `finally { await client?.disconnect(); }` する） |
| `_fetchSessions`（L860-902）の取得部 | `Future<List<MultiplexerSession>> fetchSessions(SshClient client, {required MultiplexerBackendKind backend})` | 【移動】 | herdr: `HerdrAdapter(client).snapshot()` → `toDomainSessions()` / tmux: `tmuxFacade.listSessions` → `toDomain()`。**State 骨格は setState(loading) → ops 呼出 → mounted ガード → setState → `updateSessionsFromDomain(sessions: 戻り値)` → catch/finally** を保持 |
| `_reloadSessions`（L903-924） | 上記 `fetchSessions` の tmux 分岐に統合 | 【移動】 | `tmuxFacade.listSessions` + domain 変換。provider 同期は State 骨格 |
| `_killSession`（L925-984） | `Future<List<MultiplexerSession>> killSessionAndReload(SshClient client, String sessionName)`（kill → **同一接続で `fetchSessions` 相当の reload を await 順に実行**し domain 一覧を返す） | 【移動】 | 確認ダイアログ（connKillSessionTitle/Message・Kill/Cancel）は **State 骨格**（UI 責務）。**kill→reload の連続発行を operations 内で await 順（unawaited 禁止）で担保＝テストのインデックス順序検証を固定**。`_isLoadingSessions` ガード（L953）と失敗時 setState(error) は骨格 |
| `_killHerdrWorkspace`（L985-1059） | `Future<List<MultiplexerSession>> closeWorkspace(SshClient client, String workspaceId)`（`workspaceClose` → `snapshot()` → domain 一覧を返す） | 【移動】 | workspaceId null/empty ガード（L987-999・SnackBar connCannotCloseWorkspace）と連鎖 close 確認ダイアログ（L1001-1024）は骨格。close→snapshot は operations 内で順序維持 |
| `_createHerdrWorkspace`（L1272-1318） | `Future<List<MultiplexerSession>> createWorkspace(SshClient client, String label)`（`workspaceCreate` → `snapshot()` → domain 一覧を返す） | 【移動】 | — |

### 3.8 connections_screen.dart → connection_new_session_dialog.dart

| 現行メンバ（行） | 移動先 | 種別 | 備考 |
|---|---|---|---|
| `_NewSessionDialog`（L1592-1600） | connection_new_session_dialog.dart（**public `NewSessionDialog` へ昇格**） | 【移動】 | `existingSessionNames` 不変。**呼出はカード State（`connection_card.dart` が import）** |
| `_NewSessionDialogState`（L1601-1702） | connection_new_session_dialog.dart（public `NewSessionDialogState`） | 【移動】 | `_formKey` / `_nameController`（initState L1608 デフォルト名 `session-N`）/ `dispose`（L1613）/ `_generateDefaultName`（L1616-1623）/ `_validateSessionName`（L1625-1637: 空・`^[a-zA-Z0-9_.-]+$`・重複の3分岐）/ `_submit`（L1638-1642 `_formKey.validate()` → pop 値返却）/ `build`（autofocus・FilledButton 'Create' = connCreate）を**そのまま写経** |

### 3.9 元ファイル connections_screen.dart（シム化）

- 全ロジックを上記 8 ファイルへ移動後、ロジックなしの thin re-export に置換（P2 の `connection_provider.dart` と同型）。doc comment に実装先を明記。
- 例:
```dart
/// P3: 実装は connection_list_screen.dart へ移動（責務ベース分割）。
/// 公開面（ConnectionsScreen）を安定供給する compat layer（ロジックなし）。
/// 注: ConnectionCard 等の public 昇格シンボルは import 経由のため再 export されない
///（Dart は import を再 export しない）→ シム経由で外部へ漏れない。
library;
export 'connection_list_screen.dart';
```
- 注意: シムは `export 'connection_list_screen.dart';`（全体）でよい。`show ConnectionsScreen` でも可（§8 未確定点 1）。**v2: import 由来の public 昇格シンボル（ConnectionCard 等）は export されないため、共用の公開面は `ConnectionsScreen` のみに保たれる**。

---

## 4. 公開 API 維持表

| シンボル | 種別 | 現行 export 元 | 維持方法 | import 元（rg 実測・不変） |
|---|---|---|---|---|
| `ConnectionsScreen`（public Widget） | 公開 API（維持対象） | `connections_screen.dart` | シム（§3.9）が `export 'connection_list_screen.dart'` で継続供給。コンストラクタ `const ConnectionsScreen({super.key, this.sshClientFactory})` は実装先で不変 | `home_screen.dart`（L19 import・L52 `const ConnectionsScreen()`）、テスト3本（`home: ConnectionsScreen(sshClientFactory: ...)` = session_kill 1 / herdr 4 / damaged_key 2） |
| `sshClientFactory`（プロパティ） | 公開 API（維持対象） | 同上 | 実装先 `ConnectionsScreen` のフィールドとして維持 | テスト3本（上記） |
| `_SearchVisibleNotifier` / `_searchVisibleProvider` | private（維持） | 同上 | 定義・使用が同一ファイル（connection_list_screen.dart）内で完結。private のまま移設可 | なし |
| `ConnectionCard` / `ConnectionCardState` / `SearchField`（+ `SearchFieldState`） / `SortOptionTile` / `NewSessionDialog`（+ `NewSessionDialogState`） / `CardHeader` / `ExpandedSessionsPanel` / `SessionRow` / `DamagedKeyBadge` / `ConnectionSessionOperations` / `showSortDialog` | **新規 public（v2: private → 素の public 昇格）** | 元 private（外部未公開） | 各実装ファイルで public として定義。**シム（`export 'connection_list_screen.dart'`）経由でも外部へ漏れない**（Dart は import を再 export しない。connection_list_screen はこれらを import するのみ）。維持対象の公開 API ではない（元々 private・ファイル外参照ゼロ） | なし（rg 実測: 本ファイル外で参照ゼロ。settings/category_list_view.dart の `_SearchFieldHeaderDelegate` は別物） |

**根拠（rg 実測）**: `rg "ConnectionsScreen\("` のヒットは home_screen L52 とテスト 7 箇所のみ。`rg "_ConnectionCard|_SearchField|_SortOptionTile|_NewSessionDialog"` の本ファイル外ヒットは settings/category_list_view.dart の同名異物（`_SearchFieldHeaderDelegate`）のみ。**public 昇格の 9 シンボルの衝突**: `rg` で lib/test に同名定義なし（付録・実測）。→ **シム化により呼出元・テストの import パスと呼出形状が一切変わらない**。

---

## 5. 状態所有権表

設計原則 6（破棄責任を持つ所有者を 1 つ）に基づく。**現行に存在しないもの**（Timer / StreamSubscription / FocusNode / ScrollController / ref.listen）は新設しない。

| 状態 / リソース | 所有者（1つ） | 生成 | 破棄 | 更新通知経路 | 現行（HEAD）との一致点 |
|---|---|---|---|---|---|
| `_isExpanded` / `_isLoadingSessions` / `_sessions` / `_sessionError` / `_herdrSnapshot` | `ConnectionCardState`（connection_card.dart・移動後も State が唯一所有者） | フィールド初期値（L613-619） | State 破棄（明示 dispose なし＝現行どおり） | `setState` のみ。非同期経路は各骨格の `if (!mounted) return;`（L873 / L892 / L905 / L951 / L964 etc.）ガード後に setState | 生成位置・dispose なし・mounted ガード箇所を全て維持 |
| `SshClient`（各操作の一時オブジェクト） | 各 async 骨格のローカル変数 | `connection_session_operations.connect(...)` | 各骨格の `finally { await client?.disconnect(); }` | なし | 4 経路（fetch / kill / closeWorkspace / createWorkspace）すべて `finally` disconnect を維持 |
| `TextEditingController _controller` | `_SearchFieldState` | `initState`（現行 L1490） | `dispose`（現行 L1504） | `build` 内 `_controller.text`（suffix 表示）・`didUpdateWidget` の clear 分岐（L1494-1502） | initState→didUpdateWidget→dispose の順序・条件をそのまま移設 |
| `GlobalKey<FormState> _formKey` | `_NewSessionDialogState` | フィールド（L1602） | —（ダイアログ破棄時 GC） | `_submit` の `_formKey.currentState!.validate()` | そのまま移設 |
| `TextEditingController _nameController` | `_NewSessionDialogState` | `initState`（L1608） | `dispose`（L1613） | `_submit` で `Navigator.pop(値)` | デフォルト名生成 `_generateDefaultName`（session-N）とともにそのまま移設 |
| `ref.watch/read`（providers） | 各 widget / State（Riverpod が破棄管理） | — | — | `connectionsProvider` / `filteredConnectionsProvider` / `connectionSearchProvider` / `connectionSortProvider` / `activeSessionsProvider` / `keysProvider` / `_searchVisibleProvider` / `currentTabProvider` | provider 名・呼出形式不変 |
| `updateSessionsFromDomain` 同期 | `ConnectionCardState` 骨格（v2 必須2） | — | — | **受渡契約**: operations の戻り値 `List<MultiplexerSession>`（tmux: `fetchSessions` / herdr: `closeWorkspace`・`createWorkspace` の snapshot 由来）を骨格が受領し、`ref.read(activeSessionsProvider.notifier).updateSessionsFromDomain(connectionId: ..., connectionName: ..., host: ..., sessions: <戻り値>, backend: <backend>)` に渡す（L897-901 / L918-923 / L1046-1052 / L1308-1314 相当・4 経路すべて）。**operations は ref を持たず `updateSessionsFromDomain` を直接呼ばない** | **4 経路すべて State 骨格が行う**（operations は ref 非依存） |
| 導出値 `statusColor`（L623-637）・`liveWindowCounts`（L1337-1340） | **ConnectionCardState（v2 推奨1・単一所有者）** | State の build 内で `ref.watch(activeSessionsProvider)` / `ref.watch(keysProvider)` 結果から毎ビルド導出 | State 破棄 | `CardHeader` / `ExpandedSessionsPanel` / `SessionRow` へ**導出済みの値**をプロパティで受け渡し（view 側に provider watch を持たせない＝二重再構築源を作らない・critique §1.3） | 現行では build（L626 `activeSessions` / L634 `isKeyDamaged`）と `_buildDomainSessionItems`（L1337-1340）で State 内導出・同一 |
| 一時的なダイアログ結果（確認） | 各 async 骨格のローカル値 | `showDialog<bool>` | 消費 | `confirmed != true || !mounted` ガード（L951 / L1015） | 確認→操作の順序・ガードを維持 |

**非同期経路のライフサイクル（削除・kill・herdr 系）を整理**:

| 経路 | 開始点 | 確認ダイアログ | コマンド順序（テスト固定） | 成功時 | 失敗時 | 終了 |
|---|---|---|---|---|---|---|
| `_deleteConnection`（シェル・L527-565） | `onDelete`（カード→シェル） | connDeleteConfirmTitle/Message → 消去 | SecureStorage delete → `remove(id)` | `context.mounted` で SnackBar（connDeletedMessage） | —（try/catch なし・現行どおり） | — |
| `_killSession`（tmux・L925-984） | Kill ボタン（`onPressed: _isLoadingSessions ? null : () => _killSession(session)`・L1423-1424） | 確認 → Kill | **kill →（同一接続で）list-sessions reload** | setState + updateSessionsFromDomain + SnackBar | setState(`_sessionError`) | `finally disconnect` |
| `_killHerdrWorkspace`（L985-1059） | Kill workspace ボタン | id ガード → 連鎖警告 → Close | **workspace close w1 → snapshot** | setState + updateSessionsFromDomain + SnackBar | 同上 | `finally disconnect` |
| `_createHerdrWorkspace`（L1272-1318） | New Workspace → ダイアログ → Create | —（ダイアログで名前返却） | **workspace create api → snapshot** | 同上 | 同上 | `finally disconnect` |
| `_fetchSessions`（L860-902） | 展開・リロード | — | snapshot（herdr）/ list-sessions（tmux） | setState + updateSessionsFromDomain | 同上 | `finally disconnect` |

→ 分割後もこの表の「開始点・確認・コマンド順・成功/失敗・終了」を State 骨格（UI・ライフサイクル）と operations（プロトコル実行）の境界に 1:1 写経する。**テストが固定するのは kill→reload の同一接続連続性と確認前のコマンド未発行**であり、いずれも State 骨格の呼出順序と operations 内の await 順で担保される。

---

## 6. リスクと対策

| # | リスク | 回帰シナリオ | 対策 | 検出テスト |
|---|---|---|---|---|
| 1 | **kill→reload の並び崩れ**（同一接続性） | operations 化で `unawaited` 化・別接続化されると `execCommands` の `kill < reload` 順序検証が失敗 | operations の `killSessionAndReload` 内で `await tmuxFacade.killSession(...)` → `await reloadSessions(client)` の順を保証。写経表（§3.7・§5）を実装時チェックリスト化 | session_kill_test（`kill` / `reload` インデックス検証） |
| 2 | **確認前にコマンド発行** | State 骨格のガード順序が変わると確認キャンセル時にも kill/close が発行される | `confirmed != true || !mounted` ガード・`execCommands` 未発行検証の維持 | session_kill_test / herdr_test#3（Cancel 後の未発行検証） |
| 3 | **ワークスペース操作 UI の消失**（T16/Q-05） | パネル部品化で New Workspace / Kill workspace tooltip が消える | `_buildDomainExpandedContent` の New ボタン・`_SessionRow` の Kill ボタン（backend 分岐 tooltip）を現行文言のまま移設 | herdr_test#1/#2/#3/#4 |
| 4 | **破損キーバッジの消失/誤表示** | keysProvider 判定・バッジ表示の移設ミス | `ref.watch(keysProvider)` → `isKeyDamaged` 判定は State（ConnectionCardState）で行い、`CardHeader` へ `hasDamagedKey` を渡す。バッジ文言（connDamagedKeyBadge）不変・`DamagedKeyBadge` の配置先を header 側に確定（§3.5/3.6） | damaged_key_test 2 本 |
| 5 | **TerminalScreen 遷移の破壊** | onConnect コールバック配線ミスでカードのセッション行タップ遷移が消える | `CardHeader` / `SessionRow` は onTap をコールバックで受け取り、シェル `_connectToServer`（updateLastConnected→touchSession→push）を不変 | herdr_test#1（pump 遷移 + SpecialKeysBar + 'Not connected' なし） |
| 6 | **循環 import（home 逆辺による lib/screens 10 ファイル SCC）** | 現行は `home_screen.dart`（L28-35）所有の `CurrentTabNotifier`/`currentTabProvider` への逆参照 **3 本**（connections_screen.dart L10 / keys_screen.dart L9 / settings_search_field.dart L6）が lib/screens の **10 ファイル SCC** の原因（§付録・スクリプト実測）。接続リスト側シムと home 側シムの相互参照が現行より深くなるリスクがあった | **v3 対策（ユーザー指摘対応・タスク#13）: `currentTabProvider` を home シム（home_screen.dart）経由で import せず、shell 設計が新設する中立モジュール `lib/navigation/current_tab_provider.dart` を直接 import する**。connections 配下の**全ファイルは `home_screen.dart` を import しない**（§2.4 import 辺リスト）。**実装順序（必須B）: ① shell 設計が中立モジュールを新設（= home 逆辺 3 本を除去、この時点で SCC 消滅）→ ② その後に connections を改修（§2.4 の辺リストどおり）→ ③ 両シム化完了後に `flutter analyze` + SCC スクリプトで確認**。中立モジュールの正確なパスはリーダー確定（§8-7）。 | **grep ゲート**: `rg "import.*home_screen" lib/screens/connections/` = 0 件。**SCC スクリプト**（付録）: home 逆辺 3 本除去で SCC 消滅を再検証 |
| 7 | **行数見積の上振れ（シェル ~430 が 500 超）** | 実装で import/doc/クラス境界が増え 450+ 行になり「500 未満」違反 | **v2 双値化（critique §1.5）: 初期値を ~430 とし、シェルが 450 行を超えた時点で即座に `_buildNoResultsState`（L354-417・64行）と `_buildEmptyState`（L442-494・53行）を `connection_list_states.dart` へ切り出して ~330 へ戻す**（切出しは同シンボル public 化 + shell からの import のみで追加リスクなし） | 実装中に `wc -l` で各ファイルを監視 |
| 8 | **`_SearchField` の didUpdateWidget 分岐喪失** | 検索バーを閉じる（`hide()` + `clear()`）際の `_controller.clear()` が動かなくなる | `didUpdateWidget`（L1494-1502）をそのまま移設（現行仕様。テストはこの分岐を固定していない=ステルス回帰のため明記） | 新規テスト候補（§7） |
| 9 | **repo 編集禁止の順守** | 設計中に誤ってファイルを触る | 書き込みは `/tmp/p3-design/` のみ。`git diff HEAD -- lib/ test/` で空を確認済み | — |
| 10 | **IME の挙動・スクロールレイアウト** | autofocus（SearchField L1525・NewSessionDialog L1653）・suffix アイコン・アニメーション | TextField の autofocus / controller / decoration を現行どおり移設。リビルド範囲の変更なし（部品化は同型 Widget 生成） | なし（既存テストは IME を固定しない。動作確認は手動 + 新規テスト） |
| 11 | **public 昇格による API 面の拡大（v2 新設）** | 9 シンボルが public になり、将来誤用される・シム経由で漏れる懸念 | Dart は未使用 public に警告を出さない（lint リスクなし）。シムは import を再 export しないため外部へ漏れない（§3.9）。doc comment に「feature 内部利用（P3 分割用 public 化）」を明記し意図を残す。`flutter analyze` で警告が追加されないことを確認 | `flutter analyze` |

---

## 7. 検証計画

実装フェーズ（この設計書は読み取り専用・実装ではない）で実行するコマンド:

```bash
# 1. 整形（diff なし）
dart format --output=none --set-exit-if-changed .

# 2. 静的解析
flutter analyze

# 3. 対象テスト（本設計の回帰ゲート・差分ゼロの前提）
flutter test test/screens/connections/connections_screen_session_kill_test.dart
flutter test test/screens/connections/connections_screen_herdr_test.dart
flutter test test/screens/connections/connections_screen_damaged_key_test.dart
# 参考（v2 実測・対象外の確認）: immediate_reflect_test は notifier レベル（connections_screen.dart コード参照ゼロ）
#         terminal_screen_contract_test も connections_screen 非参照（rg 0 件）→ 分割の影響なし
# 4. 全体（repro タグ除外）
flutter test --exclude-tags=repro

# 5. 既存テスト差分ゼロの確認（テストを書き換えない）
git diff HEAD -- test/   # 空であること

# 6. プロトコル生成チェック（変更禁止対象の保全）
dart tool/generate_herdr_protocols.dart --check

# 7. 500行未満の機械確認
wc -l lib/screens/connections/connection_*.dart

# 8. v3 ゲート: connections 配下から home_screen.dart への逆辺がゼロ
rg "import.*home_screen" lib/screens/connections/   # 0 件であること

# 9. v3 ゲート: lib/screens の SCC 消滅を再検証（付録のスクリプト）
python3 /tmp/p3-design/scc_check3.py   # 「home 逆辺 3 本除去後の SCC = なし」を再現
```

**新規テスト追加（任意・回帰強化）候補**:
- `SearchField` の didUpdateWidget clear 分岐（検索を開いて入力→閉じるでクリアされ、再度開いたとき空になる）
- tmux `_killSession` 相当（`ConnectionCardState`）の確認キャンセル時未発行（session_kill_test 相当の tmux 版は Kill 実装が既にあるため、Cancel ケースのみ追加）
- `ConnectionSessionOperations` 単体（FakeSshClient を直接渡し、kill→reload の await 順・workspace close→snapshot 順を**戻り値 `List<MultiplexerSession>` まで**コマンドログで検証）

---

## 8. 未確定点

1. **シムの export 形式**: `export 'connection_list_screen.dart';`（全体）か `export '...' show ConnectionsScreen;`（明示）か。v2 では public 昇格シンボルが import 由来のためどちらでも外部へ漏れない（挙動差なし）。P2 の `connection_provider.dart` は全体 export を採用 → 合わせるのが無難（チーム方針依存）。
2. **~~private 部品の internal 化の是非~~（v2 で解決済み）**: 素の public 化で確定（@internal 不使用・P2 実績ゼロ・critique §2.5/§5.2）。テストから直接参照されない（§1.6 実測）ため public 化による影響なし。
3. **operations オブジェクトの生成/受け渡し形式**: `late final` フィールド生成（P2 の notifier/orchestrator と同型）か、呼び出し時生成か。SSH 接続は毎回行うため**呼び出し時引数渡しが現行の `widget.` ライブ参照と等価**で安全と考える（§3.7 に明記済み）が、実装者の好みに依存。
4. **シェル 500 行超過時の避難先ファイル名**: `connection_list_states.dart`（ロード/エラー/空/0件ビュー）か、`connection_app_bar.dart`（AppBar のみ）か。450 行を超えた場合のみ選択（§6-7・v2 双値）。
5. **~~`home_tab_provider.dart` の新設タイミング~~（v3 で解決済み）**: 中立モジュール（helper `lib/navigation/current_tab_provider.dart` 等）が**先に新設**され、その後 connections を改修する実装順序を §6-6 に明記（必須B）。
6. その他: ユーザー判断が必要な本質的選択肢なし。
7. **中立モジュールの正確なパス（v3・リーダー調整事項）**: 本設計は `lib/navigation/current_tab_provider.dart` を前提とするが、shell 設計（shell-and-panes.md §2.1）は `screens/home/home_tab_provider.dart` を提案している。**home 名前空間への依存を避ける中立化を優先する場合は `lib/navigation/` 配下に置き、shell 設計書とパスを統一する必要がある**（どちらでも import 先 1 行が変わるのみで、SCC 消滅の効果は同じ。リーダーが一本化する）。

---

## 付録: 事実と推測の区別

### 事実（コード・rg・テスト読了で確認済み）
- 全クラス・メンバの行番号（§1.1〜§1.3）。BRIEF の境界と実測一致。
- Timer / StreamSubscription / FocusNode / ScrollController / ref.listen がファイル内に存在しない（rg 0 件）。
- `ConnectionsScreen` の import 元 = home_screen.dart + テスト 3 本のみ。`sshClientFactory` はテスト 3 本が注入。
- テスト 3 本の固定事項（§1.6・テスト名・find 条件・コマンド順序検証）は全テストファイルの読了に基づく。
- 循環 import（connections_screen ↔ home_screen）は現行で存在する事実。`currentTabProvider` は home_screen.dart L35 定義（v2 でも同一）。
- fake 構成: `_StaticConnectionsNotifier`（build のみ）/ `_EmptyActiveSessionsNotifier`（build のみ）/ `FakeSshClient`（SshClient 継承・execCommands/execOutputs/execOutputQueues 提供）/ `FakeSshNotifier` / `FakeSettingsNotifier` / `FakeTmuxNotifier`（herdr・damaged_key のみ）。
- **v2 追加実測 1**: public 昇格 9 シンボル + `DamagedKeyBadge` / `ConnectionSessionOperations` / `ConnectionListScreen` 等の候補名は lib/test に同名定義なし（`rg` 衝突ゼロ・名前安全）。
- **v2 追加実測 2**: `@internal` は lib/ 全体で 0 件（P2 実装実績ゼロ・critique §5.2 の指摘どおり）。
- **v2 追加実測 3**: `connections_screen_immediate_reflect_test.dart` は notifier レベル（import は connection_provider / secure_storage・コード参照ゼロ・`ConnectionsScreen` ヒットはコメント 2 箇所のみ）→ 分割対象外。`terminal_screen_contract_test.dart` は connections_screen / ConnectionsScreen 非参照（rg 0 件）→ 対象外。
- **v3 追加実測 1（SCC）**: lib/screens 53 ファイルの import/export 辺をスクリプトで抽出し Tarjan で SCC を計算 → **現状 SCC size 10**（下記リスト）を再現。
  - SCC 構成: `connections_screen.dart` / `dashboard_screen.dart` / `home_screen.dart` / `keys_screen.dart` / `notification_panes_screen.dart` / `settings/category_list_view.dart` / `settings/master_detail_view.dart` / `settings/settings_screen.dart` / `settings/widgets/settings_search_field.dart` / `terminal_screen.dart`
- **v3 追加実測 2（逆辺）**: home を import する screens ファイル = **3 本**（`connections_screen.dart` L10 / `keys_screen.dart` L9 / `settings_search_field.dart` L6）。home 逆辺 **3 本を全除去すると SCC 完全消滅**（0 件）。**1 本ずつの除去では SCC は残る**（3 本全部の除去が必要）ことを実証。→ 本設計の対象 `connections_screen.dart` の home 逆辺除去は、SCC 消滅のための必要かつ十分な集合（3 本）の一部。
- **v3 追加実測 3（既存）**: `lib/navigation/` ディレクトリは**現時点で未存在**（shell 設計が新設予定）。`currentTabProvider`/`CurrentTabNotifier` は `home_screen.dart` L28-35 に定義（移設前）。
- **v3 追加実測 4（subtree 辺）**: connections 配下から `home_screen.dart` を import するファイルは設計上の改修後 0 件（現行は connections_screen.dart L10 の 1 件）。`connection_form_screen.dart` は現行も connections_screen.dart を import しない（grep 0 件）。

### 推測・設計判断（要実装確認）
- 推定行数（§2）は現行実測行からの概算。特にシェル ~430→~330・パネル ~300 は実装時に ±20% 変動し得る（§6-7 双値で対応）。
- 部品化（`CardHeader` 等）が Widget ツリー形状を変えないことは、テストが「テキスト・tooltip・アイコン・指定型（TextField/TerminalScreen/TextButton/FilledButton/SpecialKeysBar）のみ」を検証することから低位リスクと判断（テストから直接観測できない範囲は推測）。
- v3 の中立モジュール（`lib/navigation/current_tab_provider.dart`）直接 import は shell 設計の新設タイミングに依存する（SCC 消滅には home 逆辺 3 本の全除去が必須）。**実装順序の 3 段階（① 中立モジュール新設 → ② connections 改修 → ③ 両シム化）を省略せず守ること**（推測・要リーダー調整）。
- operations を ref 非依存にする判断（§3.7）は「状態所有権の単一化（State のみが ref と mounted を扱う）」に基づく設計判断。
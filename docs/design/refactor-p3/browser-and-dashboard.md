# P3 設計 v2: `file_browser_screen.dart` + `dashboard_screen.dart` 責務ベース再設計

- 担当: p3-browser-designer（タスク#4 → #10 v2改訂）
- 対象: `lib/screens/file_browser/file_browser_screen.dart`（983 行）/ `lib/screens/dashboard/dashboard_screen.dart`（503 行）
- 制約: **設計のみ・読み取り専用**。リポジトリ編集なし。成果物は本ファイルのみ。
- 基準: HEAD（P2 完了・`git diff HEAD -- lib/screens/` が空であることを確認済み）。行番号は作業ツリー実ファイル = HEAD。v2 の行番号はすべて `awk`/`grep` 実測。
- 前提: P1/P2 設計書と `critique.md`（§4・§6）を読了。方針（①1ファイル=1責務 ②合成優先 ③part/mixin/private基底禁止 ④公開API維持 ⑤挙動不変 ⑥状態所有権の単一化 ⑦テストが固定するツリー形状の実測）を適用。

---

## v2 改訂サマリ（critique §4・§6 の必須 3 点 + 推奨）

| # | 変更 | 根拠（critique） |
|---|---|---|
| v2-1 | **【必須】3 view を「private のまま移動」から素の public ウィジェット化へ変更**。`_FileBrowserAppBar`→`FileBrowserAppBar`（public `ConsumerWidget`）・`_FileBrowserBody`→`FileBrowserBody`（public `StatelessWidget` + コールバック/props）・`_FileBrowserUploadTransferPanel`→`FileBrowserUploadPanel`（public `ConsumerWidget`）。呼出元 `file_browser_screen.dart` が import する構成と、各 view の `ref` 受け渡し方法を §2.1/§2.4 に明記。`@internal` は用いず素の public（critique 5.2 の「@internal 実績ゼロ・lint リスク」を踏まえる） | 4.1（重大・1.1 と同型） |
| v2-2 | **【必須】`runFileBrowserUpload` のシグネチャを `Future<void> runFileBrowserUpload(BuildContext context, WidgetRef ref, String remoteDir)` に確定**。`!mounted`→`context.mounted` 置換箇所を列挙。**事実訂正**: critique は「5 箇所 L274/279/303/323/359」とするが、実測は **4 箇所 L274/L278/L303/L323**（L279 は L278 の誤記・L359 は `        ),`（SnackBar の閉じ括弧）で mounted チェックは存在しない）。§3.1/§3.3 に実測を記載 | 4.2（重大） |
| v2-3 | **【必須】`FileBrowserDownloadFlow` は `BuildContext` を保持しない**。`attach(WidgetRef ref, {onPhaseChanged})` + 全 context 依存メソッドは `BuildContext` を**引数で都度受ける**。listen コールバック（flow 内）→ State の `_onDownloadPhaseChanged(phase)` → State が自身の `context` を flow メソッドへ渡す、という context 経路を §5 に図示。`_sheetOpen` は flow 内 private bool・`dispose()` で破棄 | 4.3（重大） |
| v2-4 | **【推奨】転送中パネルの命名を `FileBrowserUploadPanel` に**（`_buildTransferPanel` は upload 専用。download の進捗は既存 `showTransferProgressSheet` の別経路である実測を反映） | 4.4（中・軽微） |
| v2-5 | **【推奨】dashboard の `_navigateToTerminal` は `touchSession` → `Navigator.push` の順序を維持**（connections 側の `updateLastConnected→touchSession→push` と同型）。§3.2 に注意書き | 4.6（中・軽微） |
| v2-6 | **【事実訂正】v1 §2.4 の `_buildAppBar` 内 `ref.watch(fileTransferProvider)` を行 190 と誤記 → 実測 L168 に訂正**。`ref.read` は L204（toggleShowHidden）/L219（setSort）。critique 4.1 の実測と一致 | 4.1 |
| v2-7 | 検証計画に upload パネルの「under 時キャンセル」テスト（`file_browser_upload_test.dart` L211-）を重点追加 | critique §7 |

---

## 1. 現状分析（事実）

### 1.1 `file_browser_screen.dart`（983 行・cwd 実測）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 1-27 | imports | import 14 ファイル | 27 |
| 29-38 | `FileBrowserScreen`（公開 `ConsumerStatefulWidget`） | 画面エントリーポイント。`connectionId` / `paneId` | 10 |
| 39-978 | `_FileBrowserScreenState`（private State） | **全てを兼務** | ~940 |
| 978-983 | `_SortSelection`（private） | ソートメニュー値オブジェクト（`option` + `isDirectionToggle`） | 6 |

`_FileBrowserScreenState` 内部の責務（39-978）:

| 責務 | メンバー（行番号実測） | 行数 |
|---|---|---|
| **A. ライフサイクル + ダウンロード位相リスナー** | fields `_downloadFlowSub` (43-46) / `_sheetOpen` (48)、`initState` (58-84: postFrame で `initialize` + `ref.listenManual` で DownloadState 位相遷移監視)、`dispose` (86-90: sub close) | ~50 |
| **B. 画面合成ルート（build）** | `build` (93-131): Scaffold + RefreshIndicator + CustomScrollView + PathBar + 転送パネル + Body + FAB(新規フォルダ) | ~39 |
| **C. AppBar（通常 + 選択モード）** | `_buildAppBar` (133-264: 通常 AppBar のアップロード/隠しファイル/ソートメニュー + 選択モード AppBar の件数/一括DL/解除)、`_sortOptionLabel` (967-977)、`_SortSelection` (978-983)。**ref 実測: `ref.watch(fileTransferProvider)` L168、`ref.read(fileBrowserProvider.notifier).toggleShowHidden` L204、`setSort` L219**（v2-6 訂正） | ~145 |
| **D. アップロード導線** | `_handleUpload` (266-388: FilePicker → prepare → 衝突確認ループ → start → 結果 SnackBar → refresh)。**実測: `!mounted` 4 箇所 L274/278/303/323、`ref.read(fileTransferProvider…)` 6 箇所 L276/280/295/296/297/324、`ScaffoldMessenger.of(context)` 7 箇所 L282/306/334/341/349/362/372、`ref.read(fileBrowserProvider.notifier).refresh()` L385** | ~123 |
| **E. 転送中パネル（upload 専用）** | `_buildTransferPanel` (390-453: 全体カウンタ + TransferProgressRow 行 + キャンセル)。**ref 実測: `cancelAll` L428 / `cancelFile` L446 → ConsumerWidget 必須** | ~64 |
| **F. 一覧ボディ** | `_buildBody` (454-585: loading / error / empty / SliverList + 親ディレクトリ「..」行)、`_buildFileListTile` (586-601)。**ref 実測: error 再試行 `refresh` L509、親ディレクトリ `navigateUp` L564** | ~148 |
| **G. エントリ操作ディスパッチ** | `_handleEntryTap` (602-620: dir→navigate / md→preview / 他→menu)、`_openMarkdownPreview` (621-646)、`_toMbCeil` (647-651)、`_showActionMenu` (701-730: open/rename/delete/download) | ~80 |
| **H. 複数選択モード状態** | `_selectMode` (51) / `_selectedEntries` (53-55)、`_handleLongPress` (652-664)、`_handleSelectionTap` (665-677)、`_exitSelectionMode` (678-687)、`_canSelect` (688-692)、`_handleBatchDownload` (693-700) | ~50 |
| **I. ダウンロード位相ハンドラ + ダイアログ収集** | `_handleDownload` (731-743)、`_handleAwaitingOverwrite` (744-757、`_collectOverwriteDecisions(context)` L745・`!mounted` L746)、`_showDownloadProgressSheet` (758-771、`showTransferProgressSheet(context)` L761)、`_collectOverwriteDecisions` (772-796、`showOverwriteConfirmDialog(context,…)` L779-780) | ~60 |
| **J. ファイル操作ダイアログ 3 種** | `_showRenameDialog` (797-855)、`_showDeleteConfirmDialog` (856-907)、`_showCreateDirectoryDialog` (908-966) | ~170 |

**状態/リソース所有権インベントリ（file_browser）**:

| リソース | 現在の所有者 | 生成 | 破棄 | 更新通知経路 |
|---|---|---|---|---|
| `ProviderSubscription<DownloadState>? _downloadFlowSub` (43-46) | State | `initState` (`ref.listenManual`, 58-84) | `dispose` (`close`, 86-90) | listen コールバック → `_handleAwaitingOverwrite` / `_showDownloadProgressSheet` |
| `bool _sheetOpen` (48) | State | 初期値 `false` | `_showDownloadProgressSheet` の `whenComplete` で `false` | 位相リスナーからの呼び出し経路 |
| `bool _selectMode` (51) + `Set<FileEntry> _selectedEntries` (53-55) | State | 初期値 | フォルダ移動・解除ボタンで clear | `setState` + `_buildAppBar` / `_buildBody` へ伝播 |
| TextEditingController（rename/新規フォルダ） | ダイアログローカル | `showDialog` 前 | `showDialog` 後（await 完了後 `dispose`） | — |

**呼出元（rg 実測）**:
- `FileBrowserScreen` 参照: `lib/screens/terminal/terminal_screen.dart:7643`（`builder: (context) => FileBrowserScreen(connectionId:, paneId:)`）＋ テスト 5 本（下記）。import パスは 1 本のみ: `terminal_screen.dart:76` / テスト 5 本の `package:flutter_muxpod/screens/file_browser/file_browser_screen.dart`。
- `markdown_preview_screen.dart` 呼出: `file_browser_screen.dart:20`（import）・`_openMarkdownPreview` で `MarkdownPreviewScreen(connectionId:, entry:)` を push（621-646）。テスト: `markdown_preview_screen_test.dart` / `file_browser_markdown_flow_test.dart`。
- `connection_form_screen.dart` は**dashboard 側**から: `dashboard_screen.dart:12`。

**関連テスト（rg 実測・ファイル名と該当テスト名）**:

| テストファイル | テスト名（testWidgets 実測） | 固定している挙動 |
|---|---|---|
| `test/screens/file_browser/file_browser_multi_select_test.dart`（10 本） | ファイル長押しで選択モード突入 / タップでトグル / 選択モードはファイルのみ Checkbox / 選択 0 件では一括DL 無効 / 解除ボタンで終了 / ディレクトリ・symlink 長押しは従来メニュー / 一括DL 完了 / 選択モード中のディレクトリタップはナビゲート+解除 ほか | `find.byType(Checkbox)`、`byTooltip('Sort')` / `'Batch download'` / `'Clear selection'`、`_'N selected'` テキスト、`find.byType(FileBrowserScreen)` からの l10n、`fileBrowserProvider.notifier.navigatedPaths`、一括DL は保存先ピッカー 1 回・`closeCalls==0` |
| `test/screens/file_browser/file_browser_markdown_flow_test.dart`（8 本） | .md タップでプレビュー遷移 / 20MB 超は警告のみ / 非 md はメニュー / ディレクトリ開く / .md の open で遷移 / .md 長押しは選択 ほか | `find.byType(MarkdownPreviewScreen)`（遷移有無）、`find.ancestor(of: text, matching: byType(ListTile))` + `byIcon(Icons.more_vert)` のメニューボタン、`find.byType(Checkbox)` 4 個、SFTP `openedPaths`、`maxPreviewBytes` 閾値 |
| `test/screens/file_browser/file_browser_download_flow_test.dart`（7 本） | 単一DL（tmp→Save-As）/ Save-As キャンセル / 一括DL 順次 / 衝突→Overwrite / applyToAll / listen 導線で一括DL / 件数把握 ほか | `_downloadFlowSub` 経由の位相駆動（`awaitingOverwrite` → 基盤ダイアログ → `downloading` → 進捗シート）、`find.text('Overwrite')` / `'Apply to all'`、`byTooltip('Batch download')`、`DownloadPhase` 遷移・`completedCount`・tmp 削除・`closeCalls==0` |
| `test/screens/file_browser/file_browser_upload_test.dart`（6 本。特に L211-「転送中: 進捗パネルとキャンセルボタンが表示される」） | アップロードボタン表示 / 単一成功 / 衝突→上書き / リネーム / キャンセル / 転送中パネルとキャンセル ほか | `byTooltip('アップロード')`、転送中パネル `find.text('すべてキャンセル')` + `'big.bin'` の行、成功 SnackBar 文言、`openedFiles` 内容 |
| `test/screens/terminal/terminal_screen_contract_test.dart`（4 本中 1 本） | TERM-FILE-001 opens the file browser for the active pane | `find.byTooltip('File Browser')` → push 後 `find.byType(FileBrowserScreen)` |
| その他関連 | `test/widgets/file_action_menu_test.dart`、`test/screens/file_browser/transfer_progress_sheet_test.dart` | FileActionMenu（既抽出）・進捗シート（既抽出）を直接検証。対象 2 ファイルとは無関係 |

### 1.2 `dashboard_screen.dart`（503 行・cwd 実測）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 1-14 | imports | material / riverpod / google_fonts / providers（active_session・connection・key・session_history）/ l10n（app_localizations を**直接** import・`_formatRelativeTime` の型用）/ connection_form / terminal | 14 |
| 16-182 | `DashboardScreen`（公開 `ConsumerWidget`） | ダッシュボード画面全体: build（20-98: Scaffold + CustomScrollView + SliverAppBar + セクションヘッダ + 一覧/空状態 + FAB add）、`_buildEmptyState` (99-136)、`_navigateToTerminal` (137-162: **L145 の `touchSession` → L151 の `Navigator.of(context).push(TerminalScreen…)`**)、`_removeFromHistory` (164-173)、`_addNewConnection` (174-181: ConnectionFormScreen push) | ~166 |
| 182-503 | `_SessionHistoryCard`（private `ConsumerWidget`） | セッション履歴カード 1 枚分: build（194-466: Dismissible(swipe 削除) + 破損キー解決 + アイコン/名前/ホスト・相対時刻/ウィンドウ件数/バッジ）、`_formatRelativeTime` (468-485: 純関数)、`_buildDamagedKeyBadge` (486-503)。`ref.watch(connectionsProvider)` L200 / `ref.watch(keysProvider)` L208 | ~321 |

**状態/リソース所有権インベントリ（dashboard）**: Controller / FocusNode / Timer / StreamSubscription / ScrollController / GlobalKey / TextEditingController は**皆無**。`DashboardScreen` も `_SessionHistoryCard` も `ConsumerWidget`（無状態）。`Dismissible(key: Key(session.key))` のみがキーを持つ（テスト固定対象外・可視）。

**呼出元（rg 実測）**:
- `DashboardScreen` 参照: `lib/screens/home_screen.dart:54`（`IndexedStack` の中央タブ）+ テスト 2 本。import: `home_screen.dart:20` / テスト 2 本の `package:flutter_muxpod/screens/dashboard/dashboard_screen.dart`。
- `connection_form_screen.dart` 呼出: `dashboard_screen.dart:12`（`_addNewConnection` で push）。**他に `connections_screen.dart:25`・テスト 3 本**からも import（P3 タスク #1/#3 の対象領域・本ファイルでは触らない）。

**関連テスト（rg 実測）**:

| テストファイル | テスト名（testWidgets 実測） | 固定している挙動 |
|---|---|---|
| `test/screens/dashboard/dashboard_screen_herdr_workspace_test.dart`（1 本） | herdr/tmux session cards both show chevron_right with no workspace actions | `find.text('Herdr Server: lab-ws1')` / `'Tmux Server: main'`、`find.byIcon(Icons.chevron_right)` 2 個（両カードの trailing が chevron_right）、`'Workspace actions'` tooltip なし、`Icons.more_vert` なし |
| `test/screens/dashboard/dashboard_screen_damaged_key_test.dart`（1 本） | shows damaged key badge for session using a broken key | `find.text('Damaged key in use')` 1 個、`find.byIcon(Icons.warning_amber)` あり。`connectionsProvider` / `activeSessionsProvider` の override（`_StaticConnectionsNotifier` / `_StaticActiveSessionsNotifier`）で provider 構造に依存 |

---

## 2. 目標構成（全ファイル 500 行未満・数値保証）

大きな方針: **両画面とも「公開 Widget は元ファイルに残し、公開（素の public）の子 Widget＋協調オブジェクトを新規ファイルへ抽出」する構成ルート型**。P2 の `resize_dialog.dart` は公開シンボル移設 + thin re-export だったが、本件は **公開 Widget が元パスに残るため thin re-export は不要**（P2 `skeys.md` の「組成ルート State を元ファイルに残す」方式に同一）。`part` / `mixin` / private 基底クラスは不使用。

### 2.1 file_browser（6 ファイル：改修 1 + 新規 5）

| ファイル | 1 文責務 | 公開面（v2: 素の public 化） | 依存先 | 推定行数（根拠） |
|---|---|---|---|---|
| `lib/screens/file_browser/file_browser_screen.dart`（改修） | **画面の合成ルート（facade）**: `FileBrowserScreen` + `_FileBrowserScreenState`。State は責務 A（ライフサイクル+ダウンロード位相リスナー登録）・B（build 配線）・G（エントリ操作ディスパッチ）・H（選択モード状態）を保持し、C/D/E/F/I/J を協調オブジェクトへ委譲。**新規 5 ファイルを import**（下記 §2.4）| `FileBrowserScreen`（現行と完全同一コンストラクタ） | `file_browser_app_bar.dart` / `file_browser_body.dart` / `file_browser_download_flow.dart` / `file_browser_upload_flow.dart` / `file_browser_dialogs.dart` / 既存 widgets（path_bar・file_list_tile・file_action_menu・transfer_progress_sheet） / markdown_preview_screen / providers | ~330 |
| `lib/screens/file_browser/file_browser_app_bar.dart`（新規） | **AppBar（通常 + 選択モード）とソートメニュー**. 責務 C を **`FileBrowserAppBar`（public `ConsumerWidget`）** として移設。`_SortSelection` / `_sortOptionLabel` は同ファイル内 **private** で同居 | `FileBrowserAppBar`（public・呼出元が import） | file_browser_provider / file_transfer_provider / l10n / design_colors / google_fonts | ~155 |
| `lib/screens/file_browser/file_browser_body.dart`（新規） | **一覧ボディ**: loading / error / empty / SliverList（親ディレクトリ行 + FileListTile 配線）。責務 F を **`FileBrowserBody`（public `StatelessWidget` + props/コールバック）** として移設 | `FileBrowserBody`（public・呼出元が import） | file_browser_provider（`FileBrowserState` 型のみ）/ file_list_tile / l10n / design_colors | ~170 |
| `lib/screens/file_browser/file_browser_download_flow.dart`（新規） | **ダウンロード位相の協調オブジェクト**: `FileBrowserDownloadFlow`. 責務 I を State から移設し、`_downloadFlowSub` と `_sheetOpen` の**単一所有者**。`attach(WidgetRef, {onPhaseChanged})` / `dispose()` / `startBatch(entries, context)` / `startSingle(entry)` / `handleAwaitingOverwrite(context)` / `showProgressSheet(context)` / `collectOverwriteDecisions(context)` | `FileBrowserDownloadFlow`（public・無状態クラス） | download_provider / batch_destination_picker_provider / overwrite_confirm_dialog / transfer_progress_sheet | ~150 |
| `lib/screens/file_browser/file_browser_upload_flow.dart`（新規） | **アップロード導線 + upload 中パネル**: 責務 D を **`runFileBrowserUpload(BuildContext, WidgetRef, String)`（public トップレベル関数）**、責務 E を **`FileBrowserUploadPanel`（public `ConsumerWidget`）** として移設 | `runFileBrowserUpload` / `FileBrowserUploadPanel`（public） | file_transfer_provider / file_picker / overwrite_confirm_dialog / file_browser_provider（成功後 refresh）/ transfer_progress_row / l10n / design_colors | ~200 |
| `lib/screens/file_browser/file_browser_dialogs.dart`（新規） | **ファイル操作ダイアログ 3 種**: 責務 J を `showRenameDialog` / `showDeleteConfirmDialog` / `showCreateDirectoryDialog`（public トップレベル関数）として移設 | 3 関数（public） | file_browser_provider / l10n（l10n_ext）/ design_colors | ~180 |

**500 行未満の根拠（数値）**: 各部分の実測行数をそのまま移設 + 移動に伴うインターフェース境界（doc/imports）を ~10-30 行計上。最大は `file_browser_screen.dart` ~330 / `file_browser_upload_flow.dart` ~200 でいずれも 500 未満。**合計推定 ≈ 330+155+170+150+200+180 = 1,185 行**（現行 983 から +20.5%）。P2 実績（合計 ≈7,310 vs 6,247 = +17%）と同水準。

### 2.2 dashboard（2 ファイル：改修 1 + 新規 1）

| ファイル | 1 文責務 | 公開面 | 依存先 | 推定行数（根拠） |
|---|---|---|---|---|
| `lib/screens/dashboard/dashboard_screen.dart`（改修） | **ダッシュボード画面の合成ルート**: `DashboardScreen`（build・一覧/空状態・ナビゲーション・履歴削除・新規接続）。`_SessionHistoryCard` 呼出部分を `session_history_card.dart` の public widget へ差し替え | `DashboardScreen`（現行と完全同一） | session_history_provider / active_session_provider / connection_form_screen / terminal_screen / `session_history_card.dart` / l10n / design_colors | ~180（16-182 ≈ 166 + 差し替え配線 ~10 + imports/doc ~5）|
| `lib/screens/dashboard/session_history_card.dart`（新規） | **セッション履歴カード 1 枚分**: 責務 `_SessionHistoryCard`（182-503）を `SessionHistoryCard`（**public `ConsumerWidget`**）として移設。破損キー解決・Dismissible swipe 削除・相対時刻・バッジを保持 | `SessionHistoryCard`（public） | connection_provider / key_provider / active_session_provider（ActiveSession 型）/ l10n（app_localizations 直接 import を維持）/ design_colors / google_fonts | ~330（182-503 ≈ 321 + doc/imports ~10）|

**500 行未満の根拠**: 最大は `session_history_card.dart` ~330（現行 321 の純移設）。`dashboard_screen.dart` ~180。**合計 ≈ 510**（現行 503 から +1.4%）。

### 2.3 依存グラフ（一方向・循環なし）

```
dashboard_screen.dart ─→ session_history_card.dart
                     ↘ connection_form_screen.dart / terminal_screen.dart（変化なし）

file_browser_screen.dart ─→ file_browser_app_bar.dart       (FileBrowserAppBar)
                       ├→ file_browser_body.dart            (FileBrowserBody)
                       ├→ file_browser_download_flow.dart   (FileBrowserDownloadFlow)
                       ├→ file_browser_upload_flow.dart     (runFileBrowserUpload / FileBrowserUploadPanel)
                       ├→ file_browser_dialogs.dart         (show*Dialog ×3)
                       ├→ markdown_preview_screen.dart（遷移先・変化なし）
                       └→ widgets/(path_bar|file_list_tile|file_action_menu|transfer_progress_sheet)（既存）
file_browser_upload_flow.dart → widgets/file_transfer/transfer_progress_row.dart（既存）
file_browser_download_flow.dart → widgets/dialogs/overwrite_confirm_dialog.dart, widgets/file_browser/transfer_progress_sheet.dart
```

**import 構成（v2-1 の明記）**: 新規 5 ファイルは **`file_browser_screen.dart` を import しない**（逆向き依存の禁止）。`file_browser_screen.dart` は新規 5 ファイルの public シンボルを import する。新規ファイル同士は import しない（`upload_flow` は `download_flow` を参照しない・`dialogs` は他を参照しない）。すべて provider/services への一方向 import。

### 2.4 子 Widget / 関数の配線契約（v2・シグネチャ指定）

```dart
// file_browser_app_bar.dart
// 公開（呼出元が import する）。ref は ConsumerWidget が保持するため呼出元からの受け渡し不要。
class FileBrowserAppBar extends ConsumerWidget {
  const FileBrowserAppBar({
    super.key,
    required this.state,              // FileBrowserState（root の ref.watch 値）
    required this.isDark,
    required this.colorScheme,
    required this.selectMode,
    required this.selectedCount,
    required this.onUpload,           // void Function()（root が state.currentPath を閉包）
    required this.onToggleShowHidden, // void Function()
    required this.onSort,             // void Function(SortOption option, {required bool ascending})
    required this.onBatchDownload,    // void Function()
    required this.onExitSelection,    // void Function()
  });
  @override
  Widget build(BuildContext context, WidgetRef ref);
  // build(): 通常/選択モードの SliverAppBar を返す（現行 _buildAppBar 133-264 を無改変移設）。
  // 転送中判定は build 内で ref.watch(fileTransferProvider) する（現行 L168。ConsumerWidget 必須）。
  // 隠しファイルトグル/ソートは ref.read(fileBrowserProvider.notifier)（現行 L204/L219）を build 内で使用。
}
// _SortSelection（private）と _sortOptionLabel（private 関数）は本ファイル内に同居。外部公開しない。

// file_browser_body.dart
// 公開。ref 不要（provider 依存はすべてコールバック/props 化）。StatelessWidget。
class FileBrowserBody extends StatelessWidget {
  const FileBrowserBody({
    super.key,
    required this.state,             // FileBrowserState
    required this.isDark,
    required this.selectMode,
    required this.selectedEntries,
    required this.onRetry,           // void Function()（error 時 refresh。root が ref.read を閉包）
    required this.onNavigateUp,      // void Function()（親ディレクトリ「..」。root が ref.read を閉包）
    required this.onEntryTap,        // void Function(FileEntry)
    required this.onEntryLongPress,  // void Function(FileEntry)
    required this.onEntryMenu,       // void Function(FileEntry)
  });
  @override
  Widget build(BuildContext context);
  // build(): 現行 _buildBody 454-585 + _buildFileListTile 586-601 を移設。
  // 選択可否/トグルの判断は onEntryTap / onEntryLongPress のクロージャ（root State 側）に集約。
  // ref.read は L509(refresh) / L564(navigateUp) の 2 箇所のみで、いずれも onRetry / onNavigateUp に置換。
}

// file_browser_upload_flow.dart
// 公開トップレベル関数。v2-2 でシグネチャ確定。
Future<void> runFileBrowserUpload(BuildContext context, WidgetRef ref, String remoteDir);
// 公開ウィジェット。ref は ConsumerWidget が保持。転送行キャンセル（現行 L428 cancelAll / L446 cancelFile）に必要。
class FileBrowserUploadPanel extends ConsumerWidget {
  const FileBrowserUploadPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref); // 現行 _buildTransferPanel 390-453 を移設
}

// file_browser_download_flow.dart
// 公開クラス。context を保持しない（v2-3）。
class FileBrowserDownloadFlow {
  FileBrowserDownloadFlow();
  void attach(WidgetRef ref, {required void Function(DownloadPhase phase) onPhaseChanged});
  void dispose();                                    // sub.close・_sheetOpen 破棄
  Future<void> startBatch(List<FileEntry> entries, BuildContext context);
  Future<void> startSingle(FileEntry entry);
  Future<void> handleAwaitingOverwrite(BuildContext context);
  void showProgressSheet(BuildContext context);
  Future<Map<String, OverwriteChoice>?> collectOverwriteDecisions(BuildContext context);
  bool _sheetOpen = false;                           // flow 内 private bool（v2-3）
  ProviderSubscription<DownloadState>? _sub;         // flow 内 private
}

// file_browser_dialogs.dart
Future<void> showRenameDialog(BuildContext context, WidgetRef ref, FileEntry entry);
Future<void> showDeleteConfirmDialog(BuildContext context, WidgetRef ref, FileEntry entry);
Future<void> showCreateDirectoryDialog(BuildContext context, WidgetRef ref);
```

**重要な配線事実（行番号根拠・v2-6）**: 現行 `_buildAppBar` は関数内で `ref.watch(fileTransferProvider)` を呼ぶ（**実測 L168**。v1 の「L190」は誤記）。したがって `FileBrowserAppBar` は **ConsumerWidget** でなければ転送中のアップロード無効化（L188-195）が機能しない。root の `build` も同 provider を watch（L95）して転送パネル表示（L96-99）を判定するため、**同じ provider を 2 箇所で watch する**（Riverpod では正常。HEAD は State 全体の 1 回再構築、v2 では AppBar の独立再構築が加わる点のみ差。表示・無効化の挙動は不変）。`FileBrowserUploadPanel` は `ref.read(fileTransferProvider.notifier)`（L428/446）を使うため **ConsumerWidget 必須**。

### 2.5 共通化の検討（「過剰抽象化はしない」の判断）

file_browser（一覧+選択+多状態）と dashboard（カード+破損キー+swipe削除）は「SliverList + 非同期状態」を共有するが、**共通 abstract は設けない**。理由（事実）:
- 状態モデルが非互換: `FileBrowserState`（currentPath/entries/isLoading/error/sort…）と `sessionHistoryProvider`（`List<ActiveSession>`）で、一覧は「ファイル行」・dashboard は「カード+破損キー付加+swipe」。
- 状態遷移も非対称: file_browser は loading/error/empty + 選択モード + pull-to-refresh、dashboard は空状態のみ（loading/error 分岐なし・RefreshIndicator なし）。
- 共通化を強行すると `AsyncSliverList<T>` のような汎用抽象 = **grab-bag / over-abstraction**（critique の忌避対象）になり、2 箇所しか消費者がいない。
- 既に物理的に共通化済みの部品: `TransferProgressRow`、`DesignColors`、`l10n_ext` はそのまま共有で再利用。新規抽象は不要。

---

## 3. 移動マッピング

### 3.1 file_browser_screen.dart（983 → ~330）

| 現行メンバー（行） | 移動先 | 移動の種類 |
|---|---|---|
| `FileBrowserScreen` (29-38) | **残す**（file_browser_screen.dart） | — |
| `_downloadFlowSub` (43-46) / `_sheetOpen` (48) | `file_browser_download_flow.dart` の `FileBrowserDownloadFlow` へ移動 | 状態移設（所有者変更・§5） |
| `_selectMode` (51) / `_selectedEntries` (53-55) | **残す**（State が所有者） | — |
| `initState` (58-84) | **残す**（postFrame の initialize）。`ref.listenManual` 部分のみ `flow.attach(ref, onPhaseChanged: _onDownloadPhaseChanged)` へ置換 | 配線変更 |
| `dispose` (86-90) | **残す**（`flow.dispose()` 呼出へ置換） | 配線変更 |
| `build` (93-131) | **残す**。slivers 内 `_buildAppBar`→`FileBrowserAppBar(...)`、`_buildBody`→`FileBrowserBody(...)`、転送パネル→`FileBrowserUploadPanel()` へ差し替え | 配線変更のみ（ツリー形状は維持: RefreshIndicator + CustomScrollView + FAB 等） |
| `_buildAppBar` (133-264) / `_sortOptionLabel` (967-977) | `file_browser_app_bar.dart`（`FileBrowserAppBar` として public 化 / private 補助関数は同ファイル内 private） | **移動 + public 化** |
| `_SortSelection` (978-983) | `file_browser_app_bar.dart` 内 **private のまま** | 移動のみ |
| `_handleUpload` (266-388) | `file_browser_upload_flow.dart` の `runFileBrowserUpload(BuildContext, WidgetRef, String)` | **移動 + シグネチャ変更（v2-2）** |
| `_buildTransferPanel` (390-453) | `file_browser_upload_flow.dart` の `FileBrowserUploadPanel`（public ConsumerWidget） | **移動 + public 化 + 命名変更（v2-4）** |
| `_buildBody` (454-585) | `file_browser_body.dart` の `FileBrowserBody`（public StatelessWidget） | **移動 + public 化** |
| `_buildFileListTile` (586-601) | `file_browser_body.dart` の `FileBrowserBody` 内部へ | 移動のみ |
| `_handleEntryTap` (602-620) | **残す**（ディスパッチの要） | — |
| `_openMarkdownPreview` (621-646) / `_toMbCeil` (647-651) | **残す**（`widget.connectionId` 依存・MarkdownPreviewScreen 遷移を画面が担う） | — |
| `_handleLongPress` (652-664) / `_handleSelectionTap` (665-677) / `_exitSelectionMode` (678-687) / `_canSelect` (688-692) | **残す**（選択状態の所有者=State） | — |
| `_handleBatchDownload` (693-700) | **残す**（`flow.startBatch(entries, context)` へ委譲） | 配線変更 |
| `_showActionMenu` (701-730) | **残す**（rename/delete → dialogs 関数へ委譲・download → flow） | 配線変更 |
| `_handleDownload` (731-743) | `file_browser_download_flow.dart` の `flow.startSingle(entry)` へ | 移動 + 委譲 |
| `_handleAwaitingOverwrite` (744-757) | `file_browser_download_flow.dart` へ（`handleAwaitingOverwrite(BuildContext)`） | 移動のみ |
| `_showDownloadProgressSheet` (758-771) | `file_browser_download_flow.dart` へ（`showProgressSheet(BuildContext)`・`_sheetOpen` と共に） | 移動のみ |
| `_collectOverwriteDecisions` (772-796) | `file_browser_download_flow.dart` へ（`collectOverwriteDecisions(BuildContext)`） | 移動のみ |
| `_showRenameDialog` (797-855) / `_showDeleteConfirmDialog` (856-907) / `_showCreateDirectoryDialog` (908-966) | `file_browser_dialogs.dart` のトップレベル関数へ | 移動のみ（`context` / `FileEntry` / `ref` を引数で受ける） |
| **新規**: `_onDownloadPhaseChanged(DownloadPhase)` | file_browser_screen.dart に**新設**（State が context を flow に渡す経路・§5） | 新規小メソッド |

### 3.2 dashboard_screen.dart（503 → ~180 + 330）

| 現行メンバー（行） | 移動先 | 移動の種類 |
|---|---|---|
| `DashboardScreen` (16-182) | **残す**（build・empty・nav・remove・add すべて） | — |
| `_navigateToTerminal` (137-162) | **残す**。**注意（v2-5）: `touchSession`（L145）→ `Navigator.push`（L151）の順序を厳守**。`touchSession` は `activeSessionsProvider` の状態を先に更新し、その後 TerminalScreen を push する（connections の `updateLastConnected→touchSession→push` と同型）。順序入替は「開いたセッションの lastAccessed が更新されない」回帰を招く | 残す + 順序注意 |
| `_removeFromHistory` (164-173) / `_addNewConnection` (174-181) | **残す** | — |
| `_SessionHistoryCard` (182-503) | `session_history_card.dart` の `SessionHistoryCard`（public `ConsumerWidget`）へ | **移動 + public 化** |
| `_formatRelativeTime` (468-485) / `_buildDamagedKeyBadge` (486-503) | `session_history_card.dart` 内に同居 | 移動のみ |

### 3.3 `runFileBrowserUpload` の置換リスト（v2-2・実測）

`_handleUpload`（266-388）を `runFileBrowserUpload(BuildContext context, WidgetRef ref, String remoteDir)` へ移す。`State.mounted` → `context.mounted` の置換は**実測 4 箇所**:

| 実測行 | 現行 | 置換後 |
|---|---|---|
| 274 | `if (!mounted \|\| files.isEmpty) return;` | `if (!context.mounted \|\| files.isEmpty) return;` |
| 278 | `if (!mounted) return;` | `if (!context.mounted) return;` |
| 303 | `if (!mounted) return;` | `if (!context.mounted) return;` |
| 323 | `if (!mounted) return;` | `if (!context.mounted) return;` |

**事実訂正（critique §4.2 との差異）**: critique は「5 箇所（L274/279/303/323/359）」とするが、`awk` 実測では `_handleUpload` 内の `!mounted` は **L274/L278/L303/L323 の 4 箇所**。L279 に mounted チェックはなく（実測 L278 が正）、L359 は `        ),`（SnackBar の閉じ括弧）であり mounted チェックは存在しない（`backgroundColor: DesignColors.error,` は L357）。**実装時は実測 4 箇所を置換する**。

その他の実測（移動先の `WidgetRef` 使用箇所・`ScaffoldMessenger` 使用箇所）:
- `ref.read(fileTransferProvider…)`: L276 / L280 / L295 / L296 / L297 / L324（計 6）
- `ScaffoldMessenger.of(context).showSnackBar`: L282 / L306 / L334 / L341 / L349 / L362 / L372（計 7）
- `ref.read(fileBrowserProvider.notifier).refresh()`: L385

→ `ref` を 6 箇所 + 1 箇所で使うため、**引数の `WidgetRef ref` は必須**。移動先ファイル先頭に `// ignore_for_file: use_build_context_synchronously` を維持（現行 file スコープの ignore を踏襲）。

---

## 4. 公開 API 維持表

| シンボル / パス | 現行の公開面 | 維持方法（根拠） |
|---|---|---|
| `FileBrowserScreen({required String connectionId, String? paneId})` | コンストラクタ 2 引数 | **元ファイル `file_browser_screen.dart` にそのまま残す**（thin re-export 不要）。呼出元 `terminal_screen.dart:7643`・テスト 5 本の import パス 6 箇所がすべて `screens/file_browser/file_browser_screen.dart` で無変更（rg 実測） |
| `markdown_preview_screen.dart` import (`file_browser_screen.dart:20`) | 相対 import | 元ファイルに残るため行のまま維持。MarkdownPreviewScreen 自体は P3 別タスク対象（#6）・本設計では触らない |
| `DashboardScreen()` | const コンストラクタ 0 引数 | **元ファイル `dashboard_screen.dart` にそのまま残す**。呼出元 `home_screen.dart:54`・テスト 2 本の import パス 3 箇所すべて無変更（rg 実測） |
| `dashboard_screen.dart:12` の `connection_form_screen.dart` import | 相対 import | 残る（`_addNewConnection` が元ファイルに残るため） |
| 新規公開面（追加のみ・既存を壊さない） | **`FileBrowserAppBar` / `FileBrowserBody` / `FileBrowserUploadPanel` / `FileBrowserDownloadFlow` / `runFileBrowserUpload` / `showRenameDialog` / `showDeleteConfirmDialog` / `showCreateDirectoryDialog` / `SessionHistoryCard`** | 新規ファイルの **素の public** シンボル。既存公開 API の変更なし。名前衝突なし（rg 実測: 同一名の既存シンボルなし）。`@internal` は付与しない（critique 5.2 の lint リスク回避・doc comment で「file_browser 内部用」を明記） |

**thin re-export シム不要の理由**: 公開 Widget（`FileBrowserScreen` / `DashboardScreen`）が元パスに残るため、原則④の import パス維持は自動達成。P2 の `resize_dialog.dart` が re-export だったのは**公開シンボル全移設**を選んだため。

---

## 5. 状態所有権表（v2-3 で context 方針を確定）

| リソース | 所有者（1 つ） | 生成 | 破棄 | 更新通知経路 | HEAD との整合 |
|---|---|---|---|---|---|
| `_downloadFlowSub`（ProviderSubscription） | `FileBrowserDownloadFlow` | `attach(ref, onPhaseChanged:)` 内で `ref.listenManual`（=現行 initState の登録タイミングを踏襲） | `dispose()` で `close`（=現行 dispose を踏襲） | 位相遷移時のみ `onPhaseChanged(next.phase)` を呼ぶ → State へ通知 | `initState → attach`、`dispose → dispose` と呼出順序が HEAD と同一 |
| `_sheetOpen`（bool・flow 内 private） | `FileBrowserDownloadFlow` | 初期値 `false` | **`dispose()` で破棄**（bool のため明示リセットは不要・sub close と同時に所有者消滅） | 位相リスナー → `showProgressSheet(context)` 呼出時にガード | 現行 L758-771 のロジックを移設 |
| `BuildContext`（ダウンロード位相処理） | **保持しない**（v2-3） | — | — | `handleAwaitingOverwrite(BuildContext)` / `showProgressSheet(BuildContext)` / `collectOverwriteDecisions(BuildContext)` / `startBatch(entries, BuildContext)` の**メソッド引数**で都度受ける | `context` は State の `context`（下図） |
| **flow → State の context 経路（新設）** | `_FileBrowserScreenState._onDownloadPhaseChanged(phase)` | `initState` の attach で渡す | — | 下図のとおり | 現行 listen コールバックの switch を State メソッドへ移設 |
| `_selectMode`（bool） | `_FileBrowserScreenState` | 初期値 `false` | フォルダ移動・解除ボタン・一括DL 後で `false` | `setState` → `FileBrowserAppBar` / `FileBrowserBody` へ props 伝播 | 現状維持 |
| `_selectedEntries`（Set\<FileEntry\>） | `_FileBrowserScreenState` | 初期値 `{}` | `_exitSelectionMode` で clear・一括DL 後に clear | `setState` → `FileBrowserAppBar`（件数・一括DL 有効/無効）へ伝播 | 現状維持 |
| TextEditingController（rename / 新規フォルダ） | 各ダイアログ関数内ローカル | show 前 | await 完了後（現行と同位置） | — | 現状維持（移動のみ） |

### 5.1 listen コールバック → State への context 経路（v2-3 の図示）

```
[initState]
  _downloadFlow = FileBrowserDownloadFlow()
    ..attach(ref, onPhaseChanged: _onDownloadPhaseChanged);

[FileBrowserDownloadFlow.attach(WidgetRef ref, {onPhaseChanged})]
  _sub = ref.listenManual<DownloadState>(downloadProvider, (prev, next) {
    if (prev?.phase == next.phase) return;   // 位相遷移のみ（現行 L70 相当・`!mounted` は L68）
    onPhaseChanged(next.phase);              // ← flow は context を持たず、位相のみ State へ返す
  });

[State._onDownloadPhaseChanged(DownloadPhase phase)]      ← 新設・State が所有
  if (!mounted) return;                                    // context 使用前の安全確認
  switch (phase) {
    case DownloadPhase.awaitingOverwrite:
      _downloadFlow.handleAwaitingOverwrite(context);      // ← State の context を引数で渡す
    case DownloadPhase.downloading:
    case DownloadPhase.exporting:
      _downloadFlow.showProgressSheet(context);            // ← 同上
    default: break;
  }

[FileBrowserDownloadFlow.handleAwaitingOverwrite(BuildContext context)]
  ... showOverwriteConfirmDialog(context, ...)             // context は保持せず都度受ける
[FileBrowserDownloadFlow.showProgressSheet(BuildContext context)]
  if (_sheetOpen) return;
  _sheetOpen = true;
  showTransferProgressSheet(context).whenComplete(() => _sheetOpen = false);
```

- **flow は `BuildContext` フィールドを持たない**。`_sub`・`_sheetOpen` のみを保持し、`dispose()` で `_sub.close()` する。
- **context 経路**: `flow 内 listen コールバック → onPhaseChanged(phase) → State._onDownloadPhaseChanged → State.context → flow の各メソッド引数`。dispose 後に flow から context を触る経路は存在しない（State の `!mounted` と各 await 後の `context.mounted` でガード）。
- 副次: `startBatch(entries, context)` は State の `_handleBatchDownload` が `context` を渡す（現行 L697 の `if (dest == null || !mounted)` 相当は `!context.mounted` へ）。

**dispose / didUpdateWidget / build の呼出順序（HEAD 一致の保証）**:
- file_browser: `initState`（postFrame で `initialize` → **`flow.attach(ref, onPhaseChanged:)`**）→ `build`（子 widget props 配線）→ `dispose`（**`flow.dispose()`**）→ `super.dispose()`。HEAD の「postFrame initialize・initState 内 listenManual・dispose 先頭で sub close」を関数分割しただけなので順序不変。
- dashboard: 双方 ConsumerWidget のため dispose 対象なし。`DashboardScreen.build` で `SessionHistoryCard(session:, onTap:, onRemove:)` を生成する配線に変わるだけ。

---

## 6. リスクと対策

| # | リスク | 影響 | 対策 | 検出（既存/新規テスト) |
|---|---|---|---|---|
| 0 | **子 Widget の public 化漏れ / 配線契約欠落**（AppBar の `ref.watch(fileTransferProvider)` L168、UploadPanel の ref L428/446） | コンパイル不能・転送中アップロード無効化・転送パネル表示が壊れる | §2.4 の契約どおり `FileBrowserAppBar` / `FileBrowserUploadPanel` を **ConsumerWidget**、`FileBrowserBody` をコールバック props の **StatelessWidget** にする。`file_browser_screen.dart` から public import。`flutter analyze` が未定義シンボル・引数不足を検出 | `file_browser_upload_test.dart`（転送中パネル+キャンセル）、`file_browser_multi_select_test.dart` |
| 1 | **ダウンロード位相リスナーの登録/解除タイミングずれ**（`_downloadFlowSub`） | `awaitingOverwrite` ダイアログや進捗シートが出ない/消えない | `attach` は `initState` 内・`dispose()` は `dispose` 内で呼ぶ規約。位相遷移ガードを維持。State 側 `_onDownloadPhaseChanged` の `!mounted` と flow メソッド await 後の `context.mounted` を維持 | `file_browser_download_flow_test.dart`（listen 導線・applyToAll 等 7 本） |
| 2 | **AppBar/本体の widget 化による rebuild 範囲・ツリー形状変化** | Checkbox / tooltip / ListTile / SliverAppBar の検出失敗 | `FileBrowserAppBar` は public ConsumerWidget 化するが、`SliverAppBar`・各 `IconButton` tooltip・`PopupMenuButton<_SortSelection>`・`Checkbox` を**同一ツリー位置・同一 key/props** に維持（現行 `_buildAppBar` の戻りをそのまま build に渡す） | `file_browser_multi_select_test.dart`（byType(Checkbox)・byTooltip） |
| 3 | **`runFileBrowserUpload` の `mounted` 判定**（`WidgetRef` 引数漏れ・置換漏れ） | アップロード完了後の SnackBar / refresh が dispose 後実行 or コンパイル不能 | シグネチャを `(BuildContext, WidgetRef, String)` に固定。`!mounted`→`context.mounted` を**実測 4 箇所（L274/278/303/323）**置換（§3.3）。移動先に `use_build_context_synchronously` ignore を維持 | `file_browser_upload_test.dart`（6 本の導線 + L211- のパネル） |
| 4 | **ダイアログ関数化による `context` / `l10n` / `ref` の取り回し誤り** | ダイアログ内容・SnackBar 文言の変化 | 引数は `BuildContext` + `WidgetRef` + `FileEntry`。文言・アイコン・DesignColors は現行コードを逐語移設 | `file_browser_markdown_flow_test.dart`・既存 SnackBar 文言テスト |
| 5 | **dashboard カード移設で provider 参照漏れ**（connectionsProvider L200 / keysProvider L208） | 破損キーバッジ・ケバブ非表示に回帰 | `SessionHistoryCard` を `ConsumerWidget` にし、現行 build 194-466 を無改変移設 | `dashboard_screen_damaged_key_test.dart`・`herdr_workspace_test.dart` |
| 6 | **`_selectMode`/`_selectedEntries` の setState スコープ**（Body が props で受けるため） | 選択モード UI が即時更新されない | Body には選択モード/選択集合/コールバックを props で毎回渡す。State の setState → Body 再構築 | `file_browser_multi_select_test.dart` |
| 7 | **`find.byType(FileBrowserScreen)` の祖先検索**（test L209 / markdown_flow L115） | l10n 解決用に FileBrowserScreen 要素が必要 | `FileBrowserScreen` は元ファイルに残るため `byType` 解決は不変 | 両テストの `tester.element(...)` 呼出 |
| 8 | **`Dismissible(key: Key(session.key))` の引き継ぎ漏れ** | swipe 削除の state 管理が崩れる | カードの `key: Key(session.key)` を維持 | 既存テストは Dismissible を直接検証しない。新規 widget テストでキー維持を回帰担保可 |
| 9 | **行数超過**（推定が外れた場合） | 500 未満を満たさないファイルが出る | 「超過分離スロット」: file_browser_screen.dart が 400 超 → `_handleEntryTap`/`_openMarkdownPreview`/`_showActionMenu` を `file_browser_actions.dart` へ。upload_flow が 300 超 → `FileBrowserUploadPanel` を `file_browser_upload_panel.dart` へ分離 | `wc -l` による検証 |
| 10 | **アップロード成功後に `fileBrowserProvider.refresh()` を呼ぶ導線**（現行 L385） | 一覧反映漏れ | `runFileBrowserUpload` の完了処理（done 有り → refresh）を逐語移設 | `file_browser_upload_test.dart` |
| 11 | **dashboard `touchSession` → `push` の順序入替**（v2-5） | 開いたセッションの lastAccessed が更新されない | `_navigateToTerminal`（137-162）の順序を厳守（L145 `touchSession` 後に L151 `push`） | 既存テストに直接のナビテストなし。新規 widget テストで provider 更新順を回帰担保可 |

---

## 7. 検証計画

1. `dart format --output=none --set-exit-if-changed .`（書式差分ゼロ）
2. `flutter analyze`（未使用 import / 公開面の不整合 / cycle import / ConsumerWidget 化漏れを検出）
3. `flutter test --exclude-tags=repro`（全テスト。特に以下を重点実行）
   - `test/screens/file_browser/file_browser_multi_select_test.dart` / `markdown_flow_test.dart` / `download_flow_test.dart` / `upload_test.dart` / `transfer_progress_sheet_test.dart`
   - **`file_browser_upload_test.dart` の「転送中: 進捗パネルとキャンセルボタンが表示される」（L211-）を重点に含める**（critique §7 推奨）
   - `test/screens/terminal/terminal_screen_contract_test.dart`（TERM-FILE-001: FileBrowserScreen push）
   - `test/screens/dashboard/dashboard_screen_herdr_workspace_test.dart` / `dashboard_screen_damaged_key_test.dart`
   - `test/widgets/file_action_menu_test.dart`（既抽出 widget が壊れないこと）
4. `git diff HEAD -- test/` が**空**であることを確認（テスト差分ゼロ）
5. `dart tool/generate_herdr_protocols.dart --check`（生成物不変）
6. `make build-apk` は本チェックアウトでは keystore 欠落で署名段階までしか走らないため、コンパイル成功（`flutter build apk --release` の前半）までを代替確認するか、`flutter analyze` + テストで十分とする（AGENTS.md 記載の環境制約）。
7. 追加（任意・新規テスト可）: `FileBrowserDownloadFlow` の位相遷移ユニットテスト・`SessionHistoryCard` の widget テスト・`_navigateToTerminal` の touchSession 順序テストを新規追加してもよい（回帰テスト・既存は無変更）。

---

## 8. 未確定点

1. **`SessionHistoryCard` の公開範囲**: public 化するが `@internal` 注記を付けるか。→ **v2 判断: 素の public（`@internal` は付与しない）**。critique 5.2 が「@internal 昇格は実績ゼロ・lint リスク」を指摘しているため、doc comment で「dashboard 画面内部用」と明記するに留める。critic の最終判断があれば従う。
2. ~~`FileBrowserDownloadFlow` の `context` 受け渡し~~ → **v2-3 で確定**: flow は context を保持せず、全 context 依存メソッドが引数で受ける。listen コールバックは `onPhaseChanged(phase)` で State へ位相のみ通知し、State が自身の `context` を渡す（§5.1）。未確定ではない。
3. **新規ファイルの配置**: すべて既存ディレクトリ直下（`lib/screens/file_browser/`・`lib/screens/dashboard/`）に置く案。`widgets/` サブディレクトリへの移動は既存プライベート widget と混ざるため不可と判断。異論あれば要相談。
4. **`FileBrowserBody` を ConsumerWidget にするか StatelessWidget（コールバック）にするか**: v2 は **StatelessWidget + コールバック**を採用（body 内の provider 参照は refresh/navigateUp の 2 箇所のみで、いずれも callback 化が自然）。critic に異論があれば ConsumerWidget へ変更可（その場合 `FileBrowserBody` が `ref.read(fileBrowserProvider.notifier).refresh()/navigateUp()` を直接呼ぶ）。

# P4 設計書（v2）: ui 領域（terminal_screen.dart）

- 担当: p4-ui-designer ／ 対象: `lib/screens/terminal/terminal_screen.dart`（9,529 行・HEAD bff0c13）
- v2 改訂日: 2025-09-23 ／ v1: 2025-09-23
- v2 根拠: `/tmp/p4-design/arbitration.md` 全章 + `/tmp/p4-design/critique.md` §2/§4/§5/§10

---

## 0. v2 改訂サマリ（v1 からの変更）

| # | 変更点 | 内容 |
|---|---|---|
| 1 | **シム/root State を <500 行に保証** | セレクタ起動（tmux `_show*Selector` / `_selectorContextOf`）を新規 `selector_launch.dart` へ、resize 実行（`_handleResizePane` / `_handleResizeWindow`）は session-runtime へ明渡し。root State の残置インベントリを §2 に定義し、**行数合計 ≈450** を §2 で数値見積り |
| 2 | **`_PaneLayoutPainter` は新ファイル内 private のまま** | typedef 案を取り下げ。`pane_layout_painter.dart` 内で private 定義・同ファイル内 `PaneIndicatorShell` から使用。runtimeType `'_PaneLayoutPainter'` を維持（herdr テスト 7+ 箇所保護） |
| 3 | **C5 を自領域所有** | `_HerdrLabelInputDialog` を ui の `herdr_label_input_dialog.dart`（素の public `HerdrLabelInputDialog`）へ一本化。herdr_crud → ui の一方向 import（両方 public 化禁止） |
| 4 | **C3/C4 の残置を取り下げ** | `_showHerdr{Workspace,Tab,Pane}Selector` / `_showHerdrResizePaneChooser` / `_herdrSelectorContext` は herdr（`herdr_selectors.dart` / `herdr_resize.dart`）所有へ明渡し |
| 5 | **G5/G6 を session-runtime に明渡し** | `_handleFileBrowser` / `_handleImageTransfer` / `_injectImagePath` / `_ensureImageTransferListener` / `_ensureDownloadListener` は session-runtime（`terminal_transfer_flow.dart`）。ui は `download_snackbar_display.dart`（純関数）+ コールバック配線（`onFileBrowser` / `onDownloadNotify` 等）のみ |
| 6 | **`pane_layout_visualizer` を必須 2 分割** | `pane_layout_painter.dart`（Painter 群 + `PaneIndicatorShell` ≈ 290 行）と `pane_layout_visualizer.dart`（`PaneLayoutVisualizer` ≈ 320 行） |
| 7 | **dispose を仲裁 §4 フェーズ表に整合** | §4 に P0-P9 表を掲載し、ui の破棄はすべて「Widget State 自身の dispose（unmount 時）」で完結・root の P0-P9 に ui 由来の破棄物なし、を明記 |
| 8 | **検証計画へ SCC>=2 検証を追加** | `/tmp/p3-design/scc_verify_v3.py` 相当を新設ファイルグラフへ適用。シム（terminal_screen.dart）への**逆 import 禁止**と env 相互 import 禁止を検証 |

---

## 1. 現状分析（事実）

### 1-1. ui 領域の実測メンバ（行番号・v2 の帰属を含む）

`_TerminalScreenState`（L460-7885）内の ui 担当メンバ（v2 確定後）:

| 行範囲 | メンバ | 行数 | v2 帰属 |
|---|---|---|---|
| 3351-3608 | `build()` | 258 | root（表示ツリーは `terminal_view_shell.dart` へ・root は合成のみ ≈90 行） |
| 4343-4446 | `_buildErrorOverlay` | 104 | ui → terminal_overlays.dart |
| 4447-4609 | `_buildBreadcrumbHeader` | 163 | ui → terminal_breadcrumb.dart |
| 4607-4630 | `_tmuxToBreadcrumb` | 24 | ui → terminal_breadcrumb.dart |
| 4632-4660 | `_herdrToBreadcrumb` | 29 | **ui**（仲裁 C6）→ terminal_breadcrumb.dart `buildHerdrBreadcrumb`。herdr は `HerdrDisplayData` 提供のみ |
| 4664-4730 | `_showHerdrWorkspaceSelector` | 67 | **herdr（仲裁 C3）** — ui 残置取り下げ |
| 4731-4817 | `_showHerdrTabSelector` | 87 | **herdr（C3）** |
| 4818-4930 | `_showHerdrPaneSelector` | 113 | **herdr（C3）** |
| 4931-4942 | `_herdrSelectorContext` | 12 | **herdr（C3）** |
| 5147-5172 | `_showSessionSelector` | 26 | ui → selector_launch.dart |
| 5175-5245 | `_showWindowSelector` | 71 | ui → selector_launch.dart |
| 5251-5258 | `_selectorContextOf` | 8 | ui → selector_launch.dart |
| 5274-5314 | `_showMultiplexerSheet` | 41 | ui → selector_launch.dart |
| 5315-5327 | `_closeSelectorThen` | 13 | ui → selector_launch.dart（200ms 維持） |
| 5329-5423 | `_showPaneSelector` | 95 | ui → selector_launch.dart |
| 5425-5436 | `_buildPaneLayoutVisualizer` | 12 | ui → selector_launch.dart（アダプタ） |
| 5683-5715 | `_showResizePaneChooser` | 33 | ui → selector_launch.dart（表示のみ・`onResize` は session の `_handleResizePane` をコールバック受領） |
| 5716-5753 | `_showHerdrResizePaneChooser` | 38 | **herdr（仲裁 C4）** |
| 5754-5773 | `_showResizeWindowChooser` | 20 | ui → selector_launch.dart（`onResize` は session の `_handleResizeWindow`） |
| 5869-5954 | `_handleResizePane` | 86 | **session-runtime（仲裁 G1-G4）** — ui は `onResize` コールバックを渡すのみ |
| 6232-6299 | `_handleResizeWindow` | 68 | **session-runtime（仲裁 G4）** |
| 6390-6455 | `_buildBreadcrumbItem` | 66 | ui → terminal_breadcrumb.dart |
| 6456-6471 | `_buildBreadcrumbSeparator` | 16 | ui → terminal_breadcrumb.dart |
| 6472-6675 | `_showTerminalMenu` | 204 | ui → terminal_menu.dart |
| 7282-7297 | `_buildConnectionIndicator` | 16 | ui → terminal_overlays.dart |
| 7298-7332 | `_buildLatencyIndicator` | 35 | ui → terminal_overlays.dart |
| 7333-7427 | `_buildReconnectingIndicator` | 95 | ui → terminal_overlays.dart |
| 7558-7578 | `_ensureDownloadListener` | 21 | **session-runtime（仲裁 G6）**。ui は `download_snackbar_display.dart` 純関数を提供 |
| 7579-7721 | 転送系（`_ensureImageTransferListener` / `_handleFileBrowser` / `_handleImageTransfer` / `_injectImagePath`） | 143 | **session-runtime（仲裁 G5）** |
| 7804-7868 | `_buildPaneIndicatorShell` | 65 | ui → pane_layout_painter.dart（`PaneIndicatorShell`・`_PaneLayoutPainter` と同ファイル） |
| 7869-7883 | `_buildTmuxPaneIndicator` | 15 | ui → selector_launch.dart（`onTap` → `showPaneSelector`） |

末尾トップレベル（L7885-9529）:

| 行範囲 | シンボル | 行数 | v2 帰属 |
|---|---|---|---|
| 7885-7992 | `_PaneLayoutPainter` | 108 | ui → pane_layout_painter.dart（**private のまま**・同ファイル内使用） |
| 7993-8306 | `_PaneLayoutVisualizer` + State | 314 | ui → pane_layout_visualizer.dart（public `PaneLayoutVisualizer`） |
| 8307-8419 | `_SplitRightIconPainter` / `_SplitDownIconPainter` | 113 | ui → pane_layout_painter.dart（public。Visualizer が import） |
| 8420-8691 | `_InputDialogContent` + State | 272 | ui → input_dialog_content.dart（public） |
| 8692-8823 | `_HerdrLabelInputDialog` + State | 132 | **ui（仲裁 C5）** → herdr_label_input_dialog.dart（public `HerdrLabelInputDialog`・herdr_crud が import・**両方 public 化禁止**） |
| 8824-9109 | `_ResizeWindowChooserDialog` + State | 286 | ui → resize_window_chooser_dialog.dart（`_buildPaneLayoutPreview` 8990-9040 を含む） |
| 9047-9058 | `buildInputDialogContentForTesting` | 12 | ui → input_dialog_content.dart（`@visibleForTesting` 維持） |
| 9060-9098 | `_findTmuxPaneIn` / `_tmuxPaneLabelFor` / `_tmuxPaneSubtitleFor` | 39 | ui → tmux_pane_label.dart |
| 9100-9108 | `_tmuxWindowOf` | 9 | ui → tmux_pane_label.dart |
| 9110-9190 | `_SelectorContext` / `_isCurrentSession/Window/Pane` | 81 | ui → selector_sheet.dart |
| 9204-9263 | `_MultiplexerSelectorSheet` / `_SelectorContent` | 60 | ui → selector_sheet.dart |
| 9264-9418 | `_MultiplexerSelectorSheetState` | 155 | ui → selector_sheet.dart |
| 9419-9471 | `_DisconnectedBanner` | 53 | ui → terminal_overlays.dart |
| 9472-9529 | `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` | 58 | ui → download_snackbar_display.dart（公開維持・シム export） |

### 1-2. 起動元・State フィールド依存（v1 実測のまま・帰属更新済み）

- build → `_showTerminalMenu`（設定 IconButton）/ `_showPaneSelector`（tmux インジケータ）/ herdr インジケータの `onTap` は**herdr の `_showHerdrPaneSelector` へコールバック接続**。
- ブレッドクラム → tmux 3 セレクタ（ui selector_launch）/ herdr 3 セレクタ（herdr）。
- セレクタ内 headerActions → `_showResizePaneChooser` / `_showResizeWindowChooser`（ui・`onResize`=session コールバック）／ herdr mutation（herdr）。
- ui が読む root state フィールド: `_terminalMode` / `_zoomScale`/`_isZoomed`/`_effectiveZoom` / `_sshState` / `_inputQueue.length` / `_backendKind` / `_can*` getters / `_isConnecting` / `_connectionError` / `_latencyNotifier`（read）/ `_herdrDisplayNotifier`（read）/ `_herdrPaneIndicatorNotifier`（read）/ `_viewNotifier`（read）/ `_keyOverlayState`（渡し）/ `_ansiTextViewKey`（menu resetZoom）/ `_scrollToBottomKey`（シート後 show）。**書込は `_savedCommandInput`（C8: view-input へ譲渡のため ui は撤回）を除き存在しない**（v1 の「保管」記述は撤回）。

### 1-3. 担当領域を固定するテスト（v1 実測のまま・変更なし）

`terminal_screen_contract`（TERM-DIALOG-002..006・TERM-FILE-001）/ `terminal_screen_remaining_contracts`（TERM-CRUD-003・TERM-RESIZE-004..007・TERM-DIALOG-008..011・セレクタ群・H-1・mutation UI tooltips）/ `terminal_download_snackbar`（6 本）/ `terminal_download_summary`（7 本）/ `widgets/input_dialog_test`（9 本）/ `terminal_screen_herdr_test`（paneIndicatorPainter L45・runtimeType 固定）/ `terminal_screen_herdr_mutation_ui_test`（ValueKey `terminal-pane-layout-*`・`terminal-split-right-*`・`terminal-split-down-*`・'New Tab'/'Create'・条件3/10・N-T1〜N-T4）/ `terminal_screen_follow_scroll`（FAB・Icons.settings）。詳細は v1 §1-4 と同一（全件保持）。

---

## 2. 目標構成（500 行制約・root State 残置インベントリ含む）

### 2-1. 新規/変更ファイル一覧

| ファイル | 責務（1文） | 見積り行数 | 公開シンボル |
|---|---|---|---|
| `terminal_screen.dart`（シム+root State） | 公開 API re-export・協調オブジェクトの合成と結線のみ | **≈450（§2-2 で内訳）** | `TerminalScreen` / `ScrollModeSource` / `HerdrSyncTargetPolicy` / `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` の **export 1 経路** |
| `terminal_view_shell.dart` | build の表示ツリー本体（ConsumerWidget・自身で Provider watch） | ≈300 | `TerminalViewShell`（props: 表示データ+コールバック 20 前後） |
| `terminal_breadcrumb.dart` | ブレッドクラム描画と入力変換（C6 含む） | ≈280 | `BreadcrumbData` / `TerminalBreadcrumbHeader` / `buildTmuxBreadcrumb` / `buildHerdrBreadcrumb` / `BreadcrumbItem` / `BreadcrumbSeparator` |
| `terminal_menu.dart` | ターミナルメニュー BottomSheet | ≈210 | `TerminalMenu.show` |
| `terminal_overlays.dart` | エラー/再接続/レイテンシ/未接続バナー | ≈250 | `ErrorOverlay` / `ReconnectingIndicator` / `LatencyIndicator` / `ConnectionIndicator` / `DisconnectedBanner` |
| `selector_sheet.dart` | 共通 1 段セレクタシート（widget 層のみ） | ≈330 | `MultiplexerSelectorSheet` / `SelectorContent` / `SelectorContext` / `isCurrentSession/Window/Pane` |
| `selector_launch.dart` | セレクタ/チューザーの表示起動コーディネータ（遷移のみ・実行はコールバック） | ≈380 | `showMultiplexerSheet` / `closeSelectorThen` / `showSessionSelector` / `showWindowSelector` / `showPaneSelector` / `showResizePaneChooser` / `showResizeWindowChooser` / `buildPaneLayoutVisualizer` アダプタ / `buildTmuxPaneIndicator` アダプタ |
| `pane_layout_painter.dart` | **Painter 群 + ミニマップシェル（必須分離 ①）** | ≈290 | `_PaneLayoutPainter`（**private**） / `SplitRightIconPainter` / `SplitDownIconPainter` / `PaneIndicatorShell` |
| `pane_layout_visualizer.dart` | 分割プレビュー widget（必須分離 ②） | ≈320 | `PaneLayoutVisualizer` |
| `input_dialog_content.dart` | Enter=改行/CtrlCmd+Enter=送信の入力シート | ≈230 | `InputDialogContent` / `buildInputDialogContentForTesting` |
| `herdr_label_input_dialog.dart` | herdr rename/create 共用ラベル入力（C5・public 単一） | ≈140 | `HerdrLabelInputDialog` |
| `resize_window_chooser_dialog.dart` | Resize Window 選択ダイアログ | ≈290 | `ResizeWindowChooserDialog` |
| `tmux_pane_label.dart` | tmux pane 表示名/サブタイトル/引き当て | ≈70 | `findTmuxPaneIn` / `tmuxPaneLabelFor` / `tmuxPaneSubtitleFor` / `tmuxWindowOf` |
| `download_snackbar_display.dart` | Download SnackBar 仕様の純関数 | ≈90 | `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` |

全ファイル <500 行を **wc -l ゲートで必須検証**（§7）。依存方向: すべて **一方向**（シム ← ui。ui → シム逆 import 禁止。herdr → ui の `selector_launch`/`selector_sheet`/`herdr_label_input_dialog`/`download_snackbar_display` は一方向可。`pane_layout_visualizer.dart` → `pane_layout_painter.dart` のみで逆辺なし）。

### 2-2. root State 残置インベントリ（仲裁 §2 の限定スコープ + 行数見積り）

残置するのは**これのみ**:

| 残置要素 | 内容 | 見積り行数 |
|---|---|---|
| import / export | ui 14 ファイル + 領域 3 bundle + P2/P3 必要分 + **4 公開シンボルの export** | 25 |
| `TerminalScreen` widget クラス | コンストラクタ 12 引数 + doc（現 L379-458 維持） | 80 |
| State フィールド | GlobalKey × 3 / `_terminalScrollController` / `_isDisposed` / ProviderSubscription × 4（`_sshSubscription`/`_tmuxSubscription`/`_settingsSubscription`/`_networkSubscription`）/ C9 の `_pendingTargetIdentity` / `_pendingCaret` | 30 |
| `initState` | observer 登録 / scrollController listener / `postFrame` で領域 controller を attach（`_setupListeners` 等は session へ委譲） | 20 |
| `didChangeAppLifecycleState` / `didChangeMetrics` | session（`_pausePolling`/`_scheduleBackgroundRestore`/`_resumePolling`）へ委譲 | 50 |
| `deactivate` | session へ委譲（`_restoreResizedWindows` は session G2・contract 表に明記） | 15 |
| `dispose` | **P0-P9 フェーズ統括**（§4 参照・各領域 controller の分割呼出順を明記） | 70 |
| テストフック forwarding | 6 本（tmux/view）+ herdr 10 本 = 16 × 2-3 行 | 45 |
| `build`（残り） | `TerminalViewShell` への合成 + コールバック結線のみ（表示ツリーは shell へ） | 90 |
| クラス境界・ドキュメント・余白 | — | 25 |
| **合計** | | **≈450** |

- **root State 合計 ≈450 行 < 500**（実測保証: 実装時の `wc -l lib/screens/terminal/terminal_screen.dart` で判定）。マージン 50 行。
- 超過時のフォールバックスロット（事前定義）: 残置 build 結線（≈90 行）を `terminal_root_bindings.dart` へ、またはテストフック forwarding（≈45 行）を `terminal_test_hooks.dart` へ分離。見積りでは不要。
- **残置しないもの**: セレクタ起動・`_selectorContextOf` → selector_launch.dart／resize 実行（`_handleResizePane`/`_handleResizeWindow` 含む G1-G4）→ session-runtime／`_showHerdr*Selector`・`_showHerdrResizePaneChooser` → herdr／転送系（G5/G6）→ session-runtime／`_savedCommandInput` → view-input（C8）。

---

## 3. 移動マッピング（v2）

| 既存メンバ（行） | 移動先 | 種別 |
|---|---|---|
| `build`（3351-3608） | root 残置（合成のみ）＋表示ツリーは `TerminalViewShell` | 改造 |
| `_buildErrorOverlay`（4343-4446） | terminal_overlays.dart `ErrorOverlay` | 移動+public 化 |
| `_buildConnectionIndicator`（7282-7297）/ `_buildLatencyIndicator`（7298-7332）/ `_buildReconnectingIndicator`（7333-7427） | terminal_overlays.dart | 移動+public 化 |
| `_DisconnectedBanner`（9419-9471） | terminal_overlays.dart | 移動+public 化 |
| `_BreadcrumbData`（348-377）`_buildBreadcrumbHeader`（4447-4609）`_tmuxToBreadcrumb`（4607-4630）`_herdrToBreadcrumb`（4632-4660）`_buildBreadcrumbItem`（6390-6455）`_buildBreadcrumbSeparator`（6456-6471） | terminal_breadcrumb.dart | 移動+public 化（C6） |
| `_showTerminalMenu`（6472-6675） | terminal_menu.dart | 移動+コールバック化 |
| `_PaneLayoutPainter`（7885-7992） | pane_layout_painter.dart（**private のまま・同ファイル内使用**） | 移動（改名なし・runtimeType 維持） |
| `_SplitRightIconPainter`（8307-8364）/ `_SplitDownIconPainter`（8365-8419） | pane_layout_painter.dart（public） | 移動+public 化 |
| `_buildPaneIndicatorShell`（7804-7868） | pane_layout_painter.dart `PaneIndicatorShell` | 移動+public 化 |
| `_PaneLayoutVisualizer`+State（7993-8306・`_buildPaneContent` 8194-8278 含む） | pane_layout_visualizer.dart（public・ValueKey 不変） | 移動+public 化 |
| `_InputDialogContent`+State（8420-8691）`buildInputDialogContentForTesting`（9047-9058） | input_dialog_content.dart | 移動+public 化 |
| `_HerdrLabelInputDialog`+State（8692-8823） | herdr_label_input_dialog.dart `HerdrLabelInputDialog`（C5・public 単一） | 移動+public 化 |
| `_ResizeWindowChooserDialog`+State（8824-9109・`_buildPaneLayoutPreview` 8990-9040 含む） | resize_window_chooser_dialog.dart | 移動+public 化 |
| `_showSessionSelector`（5147-5172）/ `_showWindowSelector`（5175-5245）/ `_showPaneSelector`（5329-5423）/ `_selectorContextOf`（5251-5258）/ `_showMultiplexerSheet`（5274-5314）/ `_closeSelectorThen`（5315-5327）/ `_buildPaneLayoutVisualizer`（5425-5436）/ `_showResizePaneChooser`（5683-5715）/ `_showResizeWindowChooser`（5754-5773）/ `_buildTmuxPaneIndicator`（7869-7883） | selector_launch.dart | 移動（表示のみ・実行はコールバック） |
| `_MultiplexerSelectorSheet`（9204-9247）/ `_SelectorContent`（9251-9263）/ `_MultiplexerSelectorSheetState`（9264-9418）/ `_SelectorContext`（9110-9137）/ `_isCurrentSession`（9149-9171）/ `_isCurrentWindow`（9178-9187）/ `_isCurrentPane`（9189-9190） | selector_sheet.dart | 移動+public 化 |
| `_findTmuxPaneIn`（9060-9074）/ `_tmuxPaneLabelFor`（9076-9089）/ `_tmuxPaneSubtitleFor`（9091-9098）/ `_tmuxWindowOf`（9100-9108） | tmux_pane_label.dart | 移動 |
| `DownloadSnackBarDisplay`（9472-9485）/ `downloadSnackBarDisplay`（9487-9529） | download_snackbar_display.dart | 移動（シム export 1 経路） |
| `_showHerdr{Workspace,Tab,Pane}Selector`（4664-4930）/ `_herdrSelectorContext`（4931-4942） | **herdr**（herdr_selectors.dart） | 明渡し（C3・ui 残置取り下げ） |
| `_showHerdrResizePaneChooser`（5716-5753） | **herdr**（herdr_resize.dart） | 明渡し（C4） |
| `_handleResizePane`（5869-5954）/ `_handleResizeWindow`（6232-6290） | **session-runtime**（G1-G4） | 明渡し（ui は `onResize` 受領のみ） |
| `_ensureDownloadListener`（7558-7578）/ `_ensureImageTransferListener`（7579-7637）/ `_handleFileBrowser`（7638）/ `_handleImageTransfer` / `_injectImagePath`（7692-7721） | **session-runtime**（terminal_transfer_flow.dart） | 明渡し（G5/G6。ui は純関数 + コールバックのみ） |

---

## 4. インターフェース契約 + dispose フェーズ表（仲裁 §4 準拠）

### 4-1. ui が他領域から受ける props / コールバック

| ui 側 | 受ける props / コールバック | 接続先 |
|---|---|---|
| `TerminalViewShell`（root build から） | `sshState` / `canSendSpecialKey` / `canSendText` / `canFocusDirection` / `terminalMode` / notifiers（view/herdrDisplay/herdrPaneIndicator/latency）/ `onMenuOpen`(_showTerminalMenu)/ `onFileBrowser`(session G5)/ `onInput?(view-input)` / FAB 操作 | root 結線 |
| build → AnsiTextView / SpecialKeysBar / KeyOverlayWidget | 既存 18 props・`onKeyInput` 等 | view-input |
| `TerminalMenu.show` | `mode`（normal/scrollSend/select）/ `_exitToNormalMode` / `_enterScrollSendMode` / `_enterSelectMode` / `_showDisconnectConfirmation` / `onResetZoom`（settingsProvider + `_ansiTextViewKey.resetZoom`）/ `onSheetClosed`(→`_scrollToBottomKey.show`) | view-input / session-runtime |
| selector_launch 系（`showSessionSelector` 等） | `tmuxState` / `capabilities`（canResize etc.）/ `onSessionSelected`(`_selectSession`) / `onWindowSelected`(`_selectWindow`) / `onPaneSelected`(`_selectPane`) / `onSplitRequested`(`_splitPane`) / `onResizePane`(session `_handleResizePane`) / `onResizeWindow`(session `_handleResizeWindow`) / `onKillPane` / `onKillWindow` / `onRenameWindow` / `onCreateWindow` / `onSheetClosed` | root 結線（同一の callback 束をシートへ接続） |
| `PaneIndicatorShell` | `panes` / `activePaneId` / `onTap`（tmux=`showPaneSelector` / herdr=herdr の `_showHerdrPaneSelector`） | root / herdr |
| `PaneLayoutVisualizer` | `panes` / `activePaneId` / `onPaneSelected` / `onSplitRequested` | selector_launch（sheet top） |
| `InputDialogContent` | `initialValue`(`_savedCommandInput`→view-input C8) / `onValueChanged` / `onSend`(`_sendMultilineText`) | view-input |
| `HerdrLabelInputDialog` | `title` / `labelText` / `hintText` / `initialValue` / `confirmLabel` / `allowEmpty` | **herdr_crud が import**（一方向） |
| `ResizeWindowChooserDialog` | `windows` / `activeWindowIndex` / `onResize`(`_handleResizeWindow`=session) | selector_launch / session |
| `downloadSnackBarDisplay(l10n, state, prevPhase)` | 純関数・状態なし | session `_ensureDownloadListener`（**session → ui の一方向 import**） |

### 4-2. ui が他領域へ提供する API

- `DownloadSnackBarDisplay` / `downloadSnackBarDisplay`（公開・シム export 1 経路）。
- 各 Widget クラス（描画・状態機械 UI）＋ `buildInputDialogContentForTesting`（`@visibleForTesting`）。
- `showMultiplexerSheet` / `closeSelectorThen`（200ms・`mux-sel-*` Key・文言は不変）— herdr セレクタも本 API を一方向 import して使用。

### 4-3. dispose フェーズ表（仲裁 §4 の master 順序・今回の呼出位置を明記）

| フェーズ | 内容（HEAD L3293-3345 順） | root の呼出 | **ui の破棄物/呼出位置** |
|---|---|---|---|
| P0 | `_isDisposed = true` | root | なし |
| P1 | herdr bridge.reset（先頭） | `herdr.disposeBridge()` | なし |
| P2 | removeObserver / Wakelock 解除 | root | なし |
| P3 | ProviderSubscription 4 本 + transfer 2 本（`_downloadSub`/`_imageTransferSub` 含む） | `session.closeSubscriptions()`（G5/G6 の subscription も root ④ 経由で close） | なし（`_downloadSub` は session 所有） |
| P4 | poll / tree タイマー停止 | `session.disposePollers()` | なし |
| P5 | scrollSend / keyOverlay タイマー（`_keyOverlayState.dispose()` 含む） | `view.disposeTimers()` | なし（key overlay は view-input 所有） |
| P6 | autoResize / background タイマー | `session.disposeResizeTimers()` | なし |
| P7 | herdr cache / identity / resolved target の null 化 | `herdr.clearResolved()` | なし |
| P8 | notifier 群 dispose（**順: view → herdrDisplay → herdrPaneIndicator → latency**） | `session.disposeViewNotifiers()` → `herdr.disposeDisplayNotifiers()` → `session.disposeLatencyNotifier()` | なし（notifier は session/herdr 所有） |
| P9 | root ScrollController dispose → `super.dispose()` | root | なし |

**ui の破棄コントラクト（呼出位置）**: ui 配下の State（`InputDialogContentState` / `HerdrLabelInputDialogState` / `PaneLayoutVisualizerState` / `MultiplexerSelectorSheetState` / `ResizeWindowChooserDialogState`）は**携帯する controller を持たず（自前 dispose は unmount 時・Flutter フレームワーク駆動）**、root の P0-P9 に ui 由来の破棄物は**一切ない**。ui が扱う非同期後始末は `_showMultiplexerSheet`/`_showTerminalMenu` の `.then`（root の `_scrollToBottomKey` を `mounted` ガード付きで表示）と `closeSelectorThen` の 200ms 遅延（`mounted && !_isDisposed`）のみ。P3 以降に完了した場合はガードにより no-op（HEAD 同等）。

### 4-4. 二重所有の排除

- `_savedCommandInput`: **view-input（C8）所有**。ui は「State 保管」を撤回し、`_InputDialogContent` の `onValueChanged` を view-input coordinator へ接続するのみ。
- `_downloadSub`/`_imageTransferSub`: session-runtime（G5/G6）単一所有（P3 で close）。
- `_viewNotifier`/`_latencyNotifier`: session。`_herdrDisplayNotifier`/`_herdrPaneIndicatorNotifier`: herdr。ui は `valueListenable` 購読のみ。
- `_PaneLayoutPainter`: **ui（pane_layout_painter.dart）private 単一唯一の定義**。

---

## 5. 公開 API 維持表（v2）

| 公開シンボル | 根拠 | v2 の維持方法 |
|---|---|---|
| `TerminalScreen` コンストラクタ（12 引数） | 4 lib + scaffold | シムに本体存続・シグネチャ不変 |
| `ScrollModeSource` / `HerdrSyncTargetPolicy` enum | contract `TERM-ENUM-001` | シムから **export 1 経路**（view-input `terminal_input_mode.dart` 実体を再 export・他設計で再定義禁止） |
| `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` | download テスト 2 ファイルが `terminal_screen.dart` から import | **download_snackbar_display.dart 実体 + シム export を必ず実施** |
| `buildInputDialogContentForTesting` | input_dialog_test | 移動後も import パスをシム経由で維持（export） |
| AnsiTextView 18 props / `AnsiTextViewState` 公開メソッド | view-input 契約 | 変更禁止 |
| State テストフック 16 本 | `tester.state()` dynamic | root State で forwarding 維持 |
| GlobalKey 経由公開メソッド | build/menu | root が key 保持・`onSheetClosed` で伝達 |
| **`_PaneLayoutPainter` runtimeType（`'_PaneLayoutPainter'`）** | herdr test L45/L1712/L2149-2174 | **新ファイル内 private のまま定義・同ファイル内使用**（typedef 案取り下げ・P3 `_EagerScaleGestureRecognizer` 方式） |

---

## 6. リスクと対策（v2 更新）

| # | リスク | 対策 |
|---|---|---|
| R1 | `_PaneLayoutPainter` runtimeType | 解決済（§5）。private のまま pane_layout_painter.dart へ。`PaneIndicatorShell` と同ファイルで使用 |
| R2 | C3/C4 の移動競合（二重移動） | ui マッピングから削除済み。`mux-sel-*` Key・シート文言・`closeSelectorThen` 200ms は herdr 使用側でも不変（ui の `showMultiplexerSheet`/`closeSelectorThen` を herdr が一方向 import） |
| R3 | C5 の 2 重 public 化 | ui が唯一 public `HerdrLabelInputDialog`。herdr_crud は一方向 import。シムからは export 不要（テスト直接参照なし） |
| R4 | G5/G6 所有権空白 | session へ明渡し。ui は純関数 + コールバックのみ。`mounted`/`_isDisposed` ガードは root port（`isMounted`/`isDisposed`）経由で維持（critique H3）・listener 2 重登録なし（H6） |
| R5 | SnackBar 文言/多重 | dedup を**追加しない**（HEAD 同等・H4）。download 集約仕様（全スキップ=中立）厳守（T16） |
| R6 | キー・文言・ValueKey | `terminal-pane-layout-*` / `terminal-split-right-*` / `terminal-split-down-*` / tooltips / 'Selected: Pane 0 (80x24)' / 'Reconnecting (2)' 等を一切変更しない |
| R7 | `closeSelectorThen` 200ms・bottomsheet 300ms・`.then` の `_scrollToBottomKey.show` | 移動先でもタイマー値・`mounted && !_isDisposed` ガード不変 |
| R8 | asyncContent の状態遷移（バグ3 根因） | シート即時 open・async gap 前にテーマ/l10n 取得・`mounted` ガードを selector_sheet.dart に移植 |
| R9 | `_PaneLayoutVisualizer` アスペクト比/0 起点正規化 | `aspectRatio.clamp(0.5, 3.0)`・min 正規化（herdr x:26/y:1）・HIGH-2 全 rect0 ガードを Visualizer/Painter 双方で維持 |
| R10 | IME 挙動 | `_InputDialogContent._handleKeyEvent`（composing/KeyDown/KeyRepeat/CtrlCmd）を不変（input_dialog_test 9 本） |
| R11 | root State 500 行超過 | §2-2 の残置インベントリに限定＋フォールバックスロット（`terminal_root_bindings.dart` / `terminal_test_hooks.dart`）を事前定義。実装時に `wc -l` ゲート |
| R12 | セレクタ内 mutation ボタンの能力ガード | `_can*` でボタン非表示制御を維持。tmux は「接続中のみ」表示（H-4） |
| R13 | 逆 import / SCC | 新ファイル → `terminal_screen.dart` の import 禁止。`selector_sheet.dart`↔`selector_launch.dart` は一方向（launch → sheet）。visualizer → painter 一方向。§7 で SCC>=2 検証 |

---

## 7. 検証計画（v2）

```bash
cd /home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines
dart format lib/screens/terminal/            # format
make analyze                                  # flutter analyze
# --- 500 行ゲート（ロジック残置の有無も目視確認） ---
wc -l lib/screens/terminal/terminal_screen.dart
wc -l lib/screens/terminal/widgets/*.dart     # 全ファイル <500 行
# --- SCC>=2 検証（新設ファイル間・仲裁 §6 / critique §7 必須） ---
python3 /tmp/p3-design/scc_verify_v3.py --files lib/screens/terminal/widgets/*.dart   # 新ファイルグラフ
python3 /tmp/p3-design/scc_verify_v3.py --no-sim-import                              # シムへの逆 import 禁止
# --- 担当領域の該当テスト ---
flutter test test/screens/terminal/terminal_screen_contract_test.dart \
  test/screens/terminal/terminal_screen_remaining_contracts_test.dart \
  test/screens/terminal/terminal_screen_resize_test.dart \
  test/screens/terminal/terminal_download_snackbar_test.dart \
  test/screens/terminal/terminal_download_summary_test.dart \
  test/widgets/input_dialog_test.dart \
  test/screens/terminal/terminal_screen_herdr_test.dart \
  test/screens/terminal/terminal_screen_herdr_mutation_ui_test.dart \
  test/screens/terminal/terminal_screen_follow_scroll_test.dart
git diff HEAD -- test/                         # 差分ゼロ（厳守）
make test                                     # 全体
```

成功条件: 全テスト green・`test/` 差分ゼロ・シム ≈450（<500）・全 ui ファイル <500・SCC>=2 なし（シム逆 import なし）。

---

## 8. 未確定点（v2）

1. **C3/C4 移動後の herdr 側 import 方向の最終確認**: `herdr_selectors.dart` / `herdr_resize.dart` が ui の `selector_launch.dart` / `selector_sheet.dart` / `pane_layout_visualizer.dart` を一方向 import することは仲裁 §1/§7 で確定済みだが、`closeSelectorThen` の 200ms と `.then` の `_scrollToBottomKey.show()` が root 結線経由になるため、**コールバック束の形（`SelectorLaunchActions` 等）**は実装時に她 3 設計と突合して確定する。
2. **`_showResizePaneChooser`（L5683・tmux）の配置整合**: ui selector_launch.dart に置く案で確定したが、`PaneChooserDialog`（P2 分割済み）と Resize 詳細ダイアログ（`widgets/dialogs/resize/*`）は P4 では移動対象外の確認を再掲（本設計は対象外扱い）。
3. **root dispose の各 controller `.dispose()` 実名（例: `session.disposePollers()`）**: フェーズ呼出順は仲裁 §4 の P0-P9 に準拠するが、領域 bundle が公開するメソッド名は実装フェーズ冒頭で 4 設計のコントラクト表を合致させて確定する（本設計は「呼出位置」の指針を示す範囲）。
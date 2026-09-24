# P4 設計書: session-runtime 領域（`terminal_screen.dart` 分割）— v2

- 設計者: p4-session-designer（チームタスク #23→#28・読み取り専用）
- 対象: `lib/screens/terminal/terminal_screen.dart`（9,529 行・HEAD=P3 完了 `bff0c13`・作業ツリー＝HEAD）
- 責務: 接続〜切断〜再接続、poll ループ、TargetSource、表示データ、tmux セッション/ウィンドウ/ペイン選択・作成・kill、**autoResize/resize-window/resize-pane の実行、画像/ダウンロード転送フロー、latency notifier**、エラー・再接続状態
- 前提: **`/tmp/p4-design/arbitration.md`（リード仲裁・唯一の正）** と **`critique.md` §1/§2/§4/§10** を反映した v2。他 3 設計（`herdr.md` / `ui.md` / `view-input.md`）の v2 と契約を突き合わせる。
- 行番号の基準: 作業ツリー実ファイル（= HEAD）。

---

## v2 改訂サマリ（arbitration.md / critique.md §1・§2・§4・§10 反映）

| # | 改訂 | 反映元 | 内容 |
|---|---|---|---|
| V2-1 | G1-G4 を移動マッピングに追加 | critique §1.2 G1-G4 / arbitration §1 | `_executeAutoResize`(L5774) / `_restoreResizedWindows`(L5841) / `_scheduleInitialAutoResize`(L5854) / `_handleResizeWindow`(L6232) / `_handleResizePane`(L5869) を**本領域**へ（新規 `session_resize.dart`）。**deactivate 経路の `_restoreResizedWindows` 呼出を契約表に明記** |
| V2-2 | G5/G6 を新規 `terminal_transfer_flow.dart` に明記 | critique §1.2 G5/G6 / arbitration §1 | imageTransfer/download リスナーを**単一所有**（`_imageTransferSub`/`_downloadSub`・1 回登録ガード）。`mounted`/`_isDisposed` ガードは SessionHost 経由で維持。表示仕様は **ui の `download_snackbar_display.dart` 純関数を import**（session→ui 一方向）。**SnackBar 多重抑止は追加しない**（HEAD 同等・H4） |
| V2-3 | G7 `_latencyNotifier` を所有に明記 | critique §1.2 G7 | `_latencyNotifier`(L491) は本領域所有・**poll が唯一の書込**（L2304）。dispose は **P8**（`_viewNotifier` の直後に root が呼ぶ） |
| V2-4 | C1/C2/C7 を自領域から削除し port 経由に置換 | arbitration §1 C1/C2/C7 | `_scrollToCaret`(L4306)→**view-input**（`viewport.scrollToCaret()` 呼出）。`_flushInputQueue`(L1243)→**view-input**（`input.flushInputQueue()` 呼出）。選択バッファ 4 フィールド(L528-536)→**view-input**（`input.captureSelectUpdate(...)` / `input.takeBufferedUpdate()` の 3 段契約） |
| V2-5 | C9 `_pendingTargetIdentity`/`_pendingCaret` は root State フィールド | arbitration §1 C9 | 表現統一: 「**root State フィールド・値生成/照合は herdr API**」。本領域は `PendingViewStore` port 経由で書込/読取 |
| V2-6 | §4 dispose をフェーズ表 P0-P9 に落とす | arbitration §4 | 本領域の呼出位置: **P4**（poll/tree タイマー停止）・**P6**（autoResize/background タイマー）・**P8**（notifier dispose: view → … → latency）。subscription group（P3）にも transfer 2 本を含む |
| V2-7 | `session_runtime.dart` 450 行超で分割を**必須**化 | arbitration §5 / critique §2.2 | 450 行超えたら `session_view_pipeline.dart` へ即時分割（条件ではなく閾値で必須） |
| V2-8 | 検証計画に SCC>=2 検証を追加 | arbitration §6 / critique §9 | 新設ファイル間グラフで SCC>=2 ゼロ確認（`/tmp/p3-design/scc_verify_v3.py` 相当） |
| V2-9 | H1（mutation 中 reconnect）をリスク表に追加 | critique §8 H1 | ヘッド同一挙動の明記・ガード維持 |
| V2-10 | SnackBar 多重抑止なし・transfer listener 1 回登録を明記 | arbitration §7 / critique §8 H4/H6 | G6 を含む全 SnackBar で dedup を追加しない。リスナー登録は 1 回のみ |

**v3 追記（検証対応）**: 独立検証 `/tmp/p4-reports/verify.md` §1.2「§3 移動マッピングに未記載」9 メンバ（実測 `_getAuthOptions` L3126 / `_selectSession` L3995 / `_selectWindow` L4015 / `_splitPane` L5550 / `_showRenameWindowDialog` L6804 / `_renameWindow` L6829 / `_caretEquals` L4331 / `_shouldFollowBottom` L565 / `_showErrorSnackBar` L3150）を §3 に追記（厳密な所有権空白ゼロ化・軽微修正）。

---

## 0. 要約

- `TerminalScreenState`（合成ルート・root State）が **SessionRuntimeController を has-a** し、接続/poll/表示データ/autoResize/転送フローの state を独占所有する。
- TargetSource 抽象を shared リーフ（`target_source.dart`）に分離（tmux 実装は本領域、herdr 実装は herdr_types）。
- poll・frame スロットル・`_viewNotifier`・`_hasInitialScrolled`・`_pollingSuspended`・`_latencyNotifier`・reader/writer ポインタ・**G1-G4 の resize 実行・G5/G6 の転送リスナー**は本領域所有。herdr 固有（cache/caret/エポック/再解決/リングバッファ/indicator）は herdr controller、キー入力/スクロール/選択バッファ（C1/C2/C7）は view-input、表示ツリー/セレクタ起動は ui。
- `_pendingTargetIdentity`/`_pendingCaret`（C9）は root State フィールド（本領域は `PendingViewStore` port 経由で操作）。

---

## 1. 現状分析（事実）

### 1.1 担当領域メンバ一覧（行番号付き・実測）

`_TerminalScreenState` は L460 開始。**本領域の最終帰属**（arbitration §1 確定後）。

**A. ライフサイクル・リスナー（root 配線・subscription のみ root）**
| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 801-820 | 20 | `initState` | addObserver / scroll listener / postFrame（setupListeners→connectAndSetup→applyKeepScreenOn）※root 残置 |
| 822-872 | 51 | `didChangeAppLifecycleState` | pause/bg restore/resume 配線（本領域 `_pausePolling`/`_resumePolling` を呼ぶ） |
| 873-885 | 13 | `_scheduleBackgroundRestore` | 600ms 猶予タイマー（P6） |
| 886-902 | 17 | `didChangeMetrics` | 500ms debounce → `_executeAutoResize` |
| 903-932 | 30 | `_pausePolling`/`_resumePolling` | `_isInBackground`・Wakelock・`_pollingSuspended=false`(herdr) → startPolling/startTreeRefresh |
| 933-942 | 10 | `_applyKeepScreenOn` | settings.keepScreenOn |
| 943-1034 | 92 | `_setupListeners` | ssh/tmux/settings/network 4 subscription（**登録は root**・本領域は反応ロジックのみ） |

**B. 接続・切断・再接続（C2 の `_flushInputQueue` は view-input へ委譲）**
| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 1200-1242 | 43 | `_onReconnectSuccess` | モード reset→`_recreatePaneReader`→herdr `_reResolveHerdrTargetAfterReconnect` / tmux startPolling+startTreeRefresh→**`input.flushInputQueue()`** |
| 1254-1520 | 267 | `_connectAndSetup` | **最長メソッド**（下記 §4.6 順序図①） |
| 3107-3125 | 19 | `_attemptReconnect` | `sshNotifier.reconnect()` |
| 6867-6916 | 50 | `_showDisconnectConfirmation` | 確認→`disconnect()` |
| 7259-7275 | 17 | `_disconnect` | poll/tree cancel→`tmuxProvider.clear()`→`_restoreResizedWindows`（G2）→ssh disconnect→pop |

**C. reader/writer 生成（backend 切り替え点）**
| 行範囲 | 行数 | メンバ |
|---|---|---|
| 1521-1589 | 69 | `_recreatePaneReader`（herdr 固有生成部は herdr composer 呼出） |
| 1754-1778 | 25 | `_recreatePaneWriter` |

**D. ツリー・ポーリング制御**
| 行範囲 | 行数 | メンバ |
|---|---|---|
| 1958-2009 | 52 | `_refreshSessionTree` / `_startTreeRefresh`（10s・poll 中 skip） |
| 2010-2063 | 54 | `_startPolling` / `_scheduleNextPoll` / `_boostPolling` / `_updatePollingInterval` |

**E. ポーリング本体・表示更新パイプライン（C1/C7 は port 委譲）**
| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 2197-2412 | 216 | `_pollPaneContent` | poll ループ本体（下記 §4.6②）。copy-mode 遷移は `input.handleTmuxCopyModeDetected/Ended`、選択バッファは `input.captureSelectUpdate`、`_scrollToCaret`（初回）は `viewport.scrollToCaret()` |
| 2953-2971 | 19 | `_applyBufferedUpdate` | `input.takeBufferedUpdate()` → identity 照合（herdr API）→ `_scheduleUpdate` |
| 3043-3110 | 68 | `_scheduleUpdate` / `_applyUpdate` | 16ms スロットル・`PendingViewStore`（root）書込・照合・`followToBottom`（viewport port） |

**F. tmux 操作（select/create/kill）**
| 行範囲 | 行数 | メンバ |
|---|---|---|
| 4234-4305 | 72 | `_selectPane`（`_can(focus)`→reset→writer.selectPane→provider 同期→autoResize→updateLastPane） |
| 5440-5558 | 119 | `_showCreateWindowDialog` / `_createWindow` / `_sendNewWindowCommand` |
| 5600-5681 | 82 | `_confirmAndKillPane` |
| 6300-6375 | ~76 | `_killPane` |
| 6676-6790 | ~115 | `_confirmAndKillWindow` / `_killWindow` |

**G. resize 実行（G1-G4・新規 session_resize.dart）**
| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 5774-5840 | 67 | `_executeAutoResize` | didChangeMetrics/`_selectPane`/`_scheduleInitialAutoResize` から呼出（`resize-window` 非 `-A`・resize_test 固定） |
| 5841-5853 | 13 | `_restoreResizedWindows` | **deactivate(L3282)・disconnect(L7269)・lifecycle(L843/865/880) 経路** |
| 5854-5868 | 15 | `_scheduleInitialAutoResize` | `_connectAndSetup`(L1491) から呼出 |
| 5869-6231 | ~130 | `_handleResizePane` | tmux 絶対値 resize（T14・`_isResizing` 排他）※`_showHerdrResizePaneChooser` は herdr 領域 |
| 6232-6300 | ~69 | `_handleResizeWindow` | `resize-window mysession:0` 発行（TERM-RESIZE-005/007 固定） |

**H. 転送フロー（G5/G6・新規 terminal_transfer_flow.dart）**
| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 7579-7637 | 59 | `_ensureImageTransferListener` | `_imageTransferSub != null` で return（**1 回登録**・H6） |
| 7638-7651 | 14 | `_handleFileBrowser` | build `onFileBrowserRequested` → 画面遷移 |
| 7652-7691 | 40 | `_handleImageTransfer` | 画像ピック → 確認ダイアログ |
| 7692-7722 | 31 | `_injectImagePath` | paste（pane 送信） |
| 7558-7578 | 21 | `_ensureDownloadListener` | `downloadSnackBarDisplay`（**ui の純関数**）を import して表示。**多重抑止なし**（H4） |

**I. 表示データ・能力・latency（G7）**
| 行範囲 | メンバ | 備考 |
|---|---|---|
| 123-178 | `_TerminalViewData`（class + copyWith） | 本領域所有の表示モデル |
| 470-472 | `_sshState` / `_connectionError` / `_isConnecting` | ui に read-only |
| **491** | **`_latencyNotifier`(ValueNotifier<int>)** | **G7・本領域所有・poll(L2304) が唯一の書込・dispose は P8** |
| 707-739 | `_can` / `_canSendText` / `_canSendSpecialKey` / `_canFocusDirection` / `_canSplitPane` / `_canCopyMode` | 能力 getter |
| 752-793 | `_recordHerdrSwitchEvent` / `_captureHerdrTarget` / `_isCurrentHerdrTarget` | **窓口**（実体は herdr controller） |

**本領域フィールド（残り）**: `_viewNotifier` / `_pollTimer` / `_treeRefreshTimer` / `_isPolling` / frame スロットル 4 値 / 適応型間隔 4 値 / `_hasInitialScrolled` / `_pollingSuspended` / `_paneReader` / `_frameReader` / `_paneWriter` / `_targetSource` / `_backendKind` / `_isCreatingWindow` / `_isResizing` / `_resizedWindowTargets` / `_windowsRestoredForBackground` / `_autoResizeDebounceTimer` / `_backgroundRestoreTimer` / `_tmuxVersion` / `_isInBackground` / `_imageTransferSub` / `_downloadSub`

### 1.2 フィールドの所有権インベントリ（全フィールド・実測・arbitration 反映済み）

| フィールド | 行 | **新所有者** | 破棄責任 | 備考 |
|---|---|---|---|---|
| `_secureStorage` | 461 | session_connection | なし | 1 個共有 |
| `_scaffoldKey`/`_ansiTextViewKey`/`_scrollToBottomKey`/`_terminalScrollController` | 462-466 | **root**（SharedKey） | root（P9） | `_ansiTextViewKey` は view-input port が参照 |
| `_viewNotifier` | 478-480 | **session-runtime** | P8（先頭） | view-input は `setDisplayedContent` 経由のみ |
| `_sshState`/`_connectionError`/`_isConnecting` | 470-472 | **session-runtime** | — | ui read-only |
| `_latencyNotifier` | **491** | **session-runtime（G7）** | **P8（_viewNotifier の後）** | poll が唯一書込 |
| `_pollTimer`/`_isPolling` | 510,520 | **session-runtime** | **P4** | — |
| `_treeRefreshTimer` | 521 | **session-runtime** | **P4** | 10s 周期 |
| frame スロットル 4 値 | 512-516 | **session-runtime** | — | `_scheduleUpdate`/`_applyUpdate` |
| **`_pendingTargetIdentity` / `_pendingCaret`** | **511,516** | **root State（C9・表現統一）** | P7 null 化（root） | 書込は session_poll が `PendingViewStore` port 経由・**値の生成/照合は herdr API** |
| 適応型間隔 4 値 | 524-533 | **session-runtime** | — | TERM-LIFE-015..017 |
| `_hasInitialScrolled` | 542 | **session-runtime** | — | 唯一の書込。herdr は `onLiveReset` 経由で false 化 |
| `_pollingSuspended` | 696 | **session-runtime** | — | herdr は `suspendPolling`/`resumePolling` コールバックで間接操作 |
| `_paneReader`/`_frameReader`/`_paneWriter` | 644-655 | **session-runtime** | なし | 生成は session_readers（herdr 固有は composer 呼出） |
| `_targetSource` | 658 | **session-runtime**（フィールド） | なし | 値生成/変更は herdr controller のみ |
| `_backendKind`/`_tmuxVersion` | 698,642 | **session-runtime** | — | `_can`/capability の入力 |
| `_isCreatingWindow`/`_isResizing` | 629-631 | **session-runtime** | — | 連打防止 |
| `_resizedWindowTargets`/`_windowsRestoredForBackground`/`_autoResizeDebounceTimer`/`_backgroundRestoreTimer` | 633-641 | **session-runtime** | **P6** | G1-G4 と一体 |
| `_isInBackground`/`_directInputEnabled` | 622-628 | **session-runtime** | — | lifecycle/settings |
| `_sshSubscription`/`_tmuxSubscription`/`_settingsSubscription`/`_networkSubscription` | 785-789 | **root** | **P3** | Riverpod 破棄は root |
| **`_imageTransferSub`/`_downloadSub`** | — | **session-runtime（G5/G6・terminal_transfer_flow）** | **P3**（subscription group・transfer 2 本） | 1 回登録ガード |
| `_herdrSwitchEvents`(64) / `_herdrSnapshotCache` / `_herdrFrameAdapter` / `_herdrCaretReader` / `_herdrCaretStatus` / `_herdrResizeBridge` | 661-695,745 | **herdr_controller** | P1(先頭 bridge)/P7(cache・identity) | herdr.md §4.1 |
| 選択バッファ 4（`_bufferedContent`/`_hasBufferedUpdate`/`_bufferedCaret`/`_bufferedTargetIdentity`） | 528-536 | **view-input（C7・TerminalModeController）** | view-input | 本領域は capture/take のみ |
| `_scrollToCaret` が読む `_viewNotifier` / state 群（mode/scrollSend/zoom/follow/keyOverlay/inputQueue） | 494-620 | **view-input** | view-input | C1/C2/C8 |
| `_imageTransferSub` の値（imageTransferProvider） | — | Riverpod | — | subscription は本領域、値は provider |

> **二重所有しない規約**: ① `_targetSource` フィールド=本領域・値生成=herdr のみ。② C9 の保管欄=root State（本領域は port 経由）。③ reader/writer ポインタ=本領域（生成一元管理）。④ `_pollingSuspended`/`_pollTimer`=本領域（herdr は間接コールバック）。⑤ G5/G6 の listener=本領域 1 本（root+flow の 2 重登録禁止・H6）。⑥ `_latencyNotifier` 書込=session poll のみ。

### 1.3 呼出元 / 呼出先（領域内外・実測）

**本領域 → 他領域**:
- `_pollPaneContent` L2228/2249/2256/2391 → herdr（captureIdentity / isCurrentIdentity / refreshPaneIndicatorFromCache / handlePollError）
- `_onReconnectSuccess` L1214-1236 → herdr（reResolveAfterReconnect）・view-input（**flushInputQueue**）
- `_recreatePaneReader` → herdr（rebuildAfterClient / caret composer）
- `_connectAndSetup` → herdr（setupSession）
- `_pollPaneContent` L2327-2331 → view-input（**captureSelectUpdate**）・L2369 → view-input（handleTmuxCopyModeDetected/Ended）・L3092/L4316 相当 → view-input（**viewport.scrollToCaret**）・L3100 → view-input（viewport.followToBottom）
- `_handleImageTransfer`/`_injectImagePath` → view-input（pane 送信 port：`TerminalPaneSendPort`）
- `_ensureDownloadListener` → **ui の `download_snackbar_display` 純関数を import**（session→ui 一方向・H4 多重抑止なし）
- build 配線（`_sshState`/`_latencyNotifier` 等）→ ui（read-only）

**他領域 → 本領域**:
- ui: `_selectSession`/`_selectWindow`/`_selectPane`/`_createWindow`/`_killPane`/`_confirmAndKillWindow`/`_splitPane`(tmux)/`_handleResizePane`/`_handleResizeWindow`/`_showDisconnectConfirmation`（コールバック注入。**resize chooser 起動のみ ui・実行は本領域**）
- view-input: `TerminalPaneSendPort`/`TerminalInputCapabilities`/`TerminalScrollbackPort`/`PendingViewStore` の実装を要求
- herdr: Env（recreateReaders 相当・resetTerminalMode/boostPolling/startPolling/suspendPolling/resumePolling/onLiveReset の受領）
- root: **deactivate(L3282) が `_restoreResizedWindows`（G2）を unawaited で呼ぶ**（→ 契約表 §4.3 に明記）

### 1.4 担当領域に固定挙動を課すテスト（実測列挙）

| テストファイル | テスト名（実測） | 固定する挙動（本領域） |
|---|---|---|
| `terminal_screen_setup_test.dart` | `connects and activates first session` / `discovers tmux before it reads the session tree` | setup 順序（version→tree→focus-in→poll） |
| 〃 | `TERM-LIFE-013/015/017` | 10s tree / 50ms boost / 適応型バックオフ |
| 〃 | `TERM-LIFE-024` / `G1-6b focus-in …before polling` / `shows error when connection is missing` | auth options / focus-in+startPolling 順 / `_connectionError` |
| `terminal_screen_lifecycle_test.dart` | `TERM-LIFE-007` / `TERM-LIFE-003` / `TERM-LIFE-021` / `G1-7d TERM-LIFE-022` | keepScreenOn / metrics debounce / disconnected poll→reconnect / **dispose 順（P0-P9）** |
| `terminal_screen_crud_test.dart` | `TERM-CRUD session creation…` / `TERM-CRUD-001b` / `TERM-NAV-006` / `TERM-CRUD-004..005` / `TERM-CRUD-006..007` / `selecting another session…` / `no-op when disconnected` | セッション作成・window create+command・selectPane・killPane/killWindow 確認後実行・provider 同期・未接続 no-op |
| `terminal_screen_can_test.dart` | `herdr/tmux backend: mutation capabilities` / `T9: stale tmuxProvider 対策` / `_disconnect 時に tmuxProvider clear` | `_can`/capability・`tmuxProvider.clear()` 2 経路 |
| `terminal_screen_contract_test.dart` | `TERM-ENUM-001/002` / `TERM-SCREEN-002..003` / `TERM-FILE-001` | enum・props・**file browser 起動（G5）** |
| **`terminal_screen_resize_test.dart`** | autoResize 2 本 | **G1 `_executeAutoResize`（`resize-window` 非 `-A`）・G3 初回 autoResize・G2 復元** |
| **`terminal_screen_remaining_contracts_test.dart`** | `TERM-RESIZE-004..007` | **G4 `_handleResizeWindow`（`resize-window mysession:0` 発行）・G1-G4 の参照** |
| `terminal_screen_history_test.dart` | scrollback（I/O 部分） | `PaneHistoryPolicyResolver`（`_backendKind` 由来）＋`TerminalScrollbackPort` |
| `terminal_screen_follow_scroll_test.dart` / `scroll_send_test.dart` | follow/スクロール | poll→applyUpdate→followToBottom のフレーム追試・`_hasInitialScrolled` 初回ゲート |
| `terminal_screen_herdr_epoch_test.dart` | ①②③ | **C9/pending パイプライン契約**（`_applyUpdate`/`_applyBufferedUpdate` の照合・破棄） |
| `terminal_screen_herdr_test.dart` | backend flow / indicator | `_recreatePaneReader` 差し替え・`_viewNotifier` 更新 |
| `terminal_download_snackbar_test.dart` / `download_summary_test.dart` | download SnackBar | **G6 `_ensureDownloadListener`（`downloadSnackBarDisplay` 仕様・表色・回数・多重なし）** |
| `test/repro/repro_bug4_scrollback_test.dart` | 深読み | `_loadHistoryForScroll`（view-input 側）の 4 ガード |
| `test/repro/repro_bug2_latency_test.dart` | latency | **G7 `_latencyNotifier`（poll 書込・専用 notifier 分離）** |

**リテラル固定（実測・変更禁止）**: `termSshNotAvailable`/`termFailedToCreateWindow`/`termWindowCreatedCommandNotSent`/`termPaneNoLongerExists`/`termClosePaneTitle`/`termCloseWindowTitle`/`termClose`/`termCancel`・`'[Terminal] Pane size:'`・`'[Terminal] Killing window:'`・download SnackBar 文言/色（ui 純関数）。

### 1.5 境界の実測修正（arbitration/他設計との整合）

- **C1** `_scrollToCaret`・**C2** `_flushInputQueue` → **view-input**（本領域は port 呼出。critique §1.1 で二重 claim だったのを解消）。
- **C7** 選択バッファ 4 → **view-input**（3 段契約: capture を本領域が渡す / 値を view-input が所有 / identity 照合は herdr API / 適用適用は本領域 `takeBufferedUpdate`→scheduleUpdate）。
- **C8** `_savedCommandInput` / follow-lock 群 / scrollSend 群 → view-input（本領域は触らない）。
- **G1-G4** → 本領域（**これまで所有権空白だった**のを確定・新規 `session_resize.dart`）。
- **G5/G6** → 本領域（新規 `terminal_transfer_flow.dart`）。`_handleFileBrowser` は ui の `TERM-FILE-001` が実測で固定（L4574 配線）。
- **G7** `_latencyNotifier` → 本領域。
- `_setupHerdrSession`/`_resolveHerdr*`/`_resolveHerdrTargetFromSessions`/`_syncAfterHerdrMutation`/`_showHerdr*Selector`/`_showHerdrResizePaneChooser`/`_herdrToBreadcrumb` → **herdr 領域**（herdr.md v2）。
- `_HerdrLabelInputDialog` → **ui**（arbitration §1 C5・両方 public 化禁止）。
- `_loadHistoryForScroll` → view-input（I/O は `TerminalScrollbackPort`）。
- `_handleTwoFingerSwipe`/`_getNavigableDirections` → view-input（arbitration §1・herdr navigation API を port 経由）。

---

## 2. 目標構成（v2: G1-G4/G5/G6/G7 追加・C1/C2/C7 除去・450 分割必須規則）

**方針**: root State が **SessionRuntimeController**（has-a）を 1 個持ち、本領域 state を独占所有。依存は `ui（表示・純関数） ← session-runtime → ports ← view-input`、`herdr → ports / ui(純関数)`（arbitration §6）。**`*_env.dart` 相互 import 禁止**。

| # | ファイル | 責務（1 文） | 目安行数 | 公開シンボル | 依存先 |
|---|---|---|---|---|---|
| 1 | `lib/screens/terminal/target_source.dart`（共有リーフ） | 表示対象 pane ID 取得抽象 | 30 | `abstract interface class TargetSource` / `TmuxTargetSource` | services のみ |
| 2 | `session/session_models.dart` | 表示モデル `TerminalViewData`（copyWith・caret センチネル）と caret 値等価 | 120 | `TerminalViewData` / `caretEquals` | pane_frame_reader |
| 3 | `session/session_env.dart` | 本領域が受ける外部依存 bundle `SessionEnv` + port interface（**`PendingViewStore` 含む**） | 190 | `class SessionEnv` / `interface SessionHost` / `PendingViewStore` / `TransferHost` | herdr types / 各 port 型 |
| 4 | `session/session_runtime.dart` | **SessionRuntimeController**（合成ルート）: 表示データ・poll 状態・`_hasInitialScrolled`・`_pollingSuspended`・targetSource・reader/writer ポインタ・能力 getter・適応型間隔 | **430（450 超なら必須分割）** | `class SessionRuntimeController` | session_models / target_source / SessionEnv |
| 5 | `session/session_view_pipeline.dart` | **分割スロット（必須発動）**: frame スロットル・`_scheduleUpdate`/`_applyUpdate`/`_applyBufferedUpdate`・`PendingViewStore` 書込・`_latencyNotifier` 保持 | 230 | `class SessionViewPipeline` | SessionEnv / herdr identity API |
| 6 | `session/session_connection.dart` | 認証・接続・切断・再接続（`connectAndSetup`/`onReconnectSuccess`/`attemptReconnect`/`disconnect`/`getAuthOptions`・**C2 は input.flushInputQueue 呼出**） | 400 | `class SessionConnectionFlow` | SessionEnv / sshProvider / tmuxFacade / herdr |
| 7 | `session/session_poll.dart` | poll 本体・表示更新駆動（`pollPaneContent`・**captureSelectUpdate/takeBufferedUpdate/viewport.scrollToCaret 呼出**） | 300 | `class SessionPollEngine` | session_runtime / herdr / view-input port |
| 8 | `session/session_readers.dart` | reader/writer の backend 生成 | 200 | `class SessionReaderComposer` | 各 reader / herdr caret composer |
| 9 | `session/session_tree.dart` | セッションツリー更新（10s） | 70 | `class SessionTreeRefresher` | tmuxFacade / providers |
| 10 | `session/session_mutations.dart` | tmux の select/create/kill | 330 | `class TmuxSessionMutations` | session_readers / providers / l10n |
| 11 | `session/session_resize.dart` | **G1-G4**: autoResize・復元・初回自動 fit・resize-window/resize-pane 実行 | 320 | `class SessionResizeFlow` | PaneRecalculation（有れば）/ tmuxFacade / l10n |
| 12 | `session/terminal_transfer_flow.dart` | **G5/G6**: imageTransfer/download リスナー単一所有・表示仕様は ui 純関数 import | 200 | `class TerminalTransferFlow` | ui（`download_snackbar_display` のみ import）/ imageTransfer/download provider |
| 13 | `session/session_lifecycle.dart` | listeners・lifecycle observer・タイマー破棄順序（root から呼ばれる） | 150 | `class SessionLifecycle` | SessionEnv |

**行数根拠（数値保証）**: 合計 ≈ 2,660 行（v1 の 2,370 に G1-G4（~300）+ G5/G6（~200）を追加し C1/C2（~50）を除去）。**全ファイル 500 未満・450 超は session_runtime のみ（分割スロット session_view_pipeline を #5 として事前定義・450 超えたら必須で分割）**。herdr/ui/view-input の該当行は彼らの v2 に移動済み（進捗確認済み）。

**シム化**: `terminal_screen.dart` は thin re-export シム（`TerminalScreen`/`ScrollModeSource`/`DownloadSnackBarDisplay`/`downloadSnackBarDisplay` の export は**シムから 1 経路のみ**・arbitration §7）。

---

## 3. 移動マッピング（v2）

凡例: 【移】= 移動のみ（ロジック無変更・public 化） / 【改】= 移動 + interface 適応

| 行範囲 | メンバ | 移動先 | 区分 |
|---|---|---|---|
| 123-178 | `_TerminalViewData` → `TerminalViewData` | session_models | 移 |
| 163-192 | `_TargetSource` → `TargetSource` / `_TmuxTargetSource` → `TmuxTargetSource` | target_source | 移 |
| 461 | `_secureStorage` | session_connection | 移 |
| 470-491 | `_sshState`/`_connectionError`/`_isConnecting`/**`_latencyNotifier`（G7）** | session_runtime / session_view_pipeline | 移 |
| 478-480 | `_viewNotifier` | session_runtime（P8 破棄） | 移 |
| 507-542 | frame スロットル・適応型間隔・`_hasInitialScrolled` | session_runtime / pipeline | 移 |
| 644-658 | `_paneReader`/`_frameReader`/`_paneWriter`/`_targetSource` | session_runtime（保管） | 移 |
| 696 | `_pollingSuspended` | session_runtime | 移 |
| 707-782 | `_can` 系 getter | session_runtime | 移 |
| 752-793 | `_record/capture/isCurrentHerdrTarget` | **herdr**（本領域は port 化） | 改 |
| 801-933 | initState / lifecycle / keepScreenOn / pause / resume | session_lifecycle（root が呼ぶ） | 移 |
| 943-1034 | `_setupListeners` | session_lifecycle（登録は root・反応ロジック配線） | 改 |
| 1200-1242 | `_onReconnectSuccess` | session_connection（**flush は input.flushInputQueue**） | 改 |
| ~~1243-1253~~ | ~~`_flushInputQueue`~~ | **view-input（C2）** | **削除** |
| 1254-1520 | `_connectAndSetup` | session_connection | 改 |
| 1521-1589 | `_recreatePaneReader` | session_readers | 改 |
| 1754-1778 | `_recreatePaneWriter` | session_readers | 移 |
| 1958-2009 | `_refreshSessionTree`/`_startTreeRefresh` | session_tree | 移 |
| 2010-2063 | `_startPolling`/`_scheduleNextPoll`/`_boostPolling`/`_updatePollingInterval` | session_runtime | 移 |
| 2197-2412 | `_pollPaneContent` | session_poll（copy-mode / buffer / scrollToCaret は port 呼出） | 改 |
| 2953-2971 | `_applyBufferedUpdate` | session_poll（`input.takeBufferedUpdate()`） | 改 |
| 3043-3110 | `_scheduleUpdate`/`_applyUpdate` | session_poll（pending は `PendingViewStore`=root へ書込） | 改 |
| 3107-3125 | `_attemptReconnect` | session_connection | 移 |
| ~~4306-4329~~ | ~~`_scrollToCaret`~~ | **view-input（C1）** | **削除** |
| 4234-4305 | `_selectPane` | session_mutations | 移 |
| 5440-5558 | `_showCreateWindowDialog`/`_createWindow`/`_sendNewWindowCommand` | session_mutations | 移 |
| 5600-5681 | `_confirmAndKillPane` | session_mutations | 移 |
| 6300-6375 | `_killPane` | session_mutations | 改 |
| 6676-6790 | `_confirmAndKillWindow`/`_killWindow` | session_mutations | 移 |
| **5774-5840** | **`_executeAutoResize`（G1）** | **session_resize** | 移 |
| **5841-5853** | **`_restoreResizedWindows`（G2）** | **session_resize（deactivate 経路は §4.3 契約表へ）** | 移 |
| **5854-5868** | **`_scheduleInitialAutoResize`（G3）** | **session_resize** | 移 |
| **5869-6231** | **`_handleResizePane`（arbitration §1）** | **session_resize** | 移 |
| **6232-6300** | **`_handleResizeWindow`（G4）** | **session_resize** | 移 |
| **7558-7578** | **`_ensureDownloadListener`（G6）** | **terminal_transfer_flow（ui 純関数 import・多重抑止なし）** | 改 |
| **7579-7722** | **`_ensureImageTransferListener`/`_handleFileBrowser`/`_handleImageTransfer`/`_injectImagePath`（G5）** | **terminal_transfer_flow** | 改 |
| 6867-7275 | `_showDisconnectConfirmation`/`_disconnect` | session_connection（G2 復元呼出を含む） | 移 |
| 3126 | `_getAuthOptions` | session_connection | 移 |
| 3150 | `_showErrorSnackBar` | session_connection | 移（実測呼出は `_connectAndSetup` L1504/1512 のみ。Retry=再 setup の SnackBarAction 維持） |
| 3995 | `_selectSession` | session_mutations | 移 |
| 4015 | `_selectWindow` | session_mutations | 移 |
| 5550 | `_splitPane` | session_mutations | 改（tmux 分岐は本領域・herdr 分岐は `_syncAfterHerdrMutation`/`_handleHerdrMutationError` へ委譲） |
| 6804 | `_showRenameWindowDialog` | session_mutations | 移（tmux rename-window mutation・確認 UI は ui の `onRenameWindow` コールバック経由） |
| 6829 | `_renameWindow` | session_mutations | 移（rename-window コマンド発行） |
| 4331 | `_caretEquals` | session_models（`caretEquals` 純関数・poll の content 同一判定から使用） | 移 |
| 565 | `_shouldFollowBottom`（getter） | — | **削除（view-input 所有**：`_isPinnedToBottom`/`_isBottomLock` と同域。本領域 `_applyUpdate` の追従ジャンプ判定は **root から view-input port 経由**で参照する） |
| — | `_isResizing`/`_resizedWindowTargets`/`_autoResizeDebounceTimer`/`_backgroundRestoreTimer` | session_resize | 移 |

**残す（root シム側・arbitration §2 の狭いスコープのみ）**: `TerminalScreen` widget・コンストラクタ・createState、`build` の「合成 + 引渡し」、keys 3 本と `_terminalScrollController`、4 ProviderSubscription（P3）、**`_pendingTargetIdentity`/`_pendingCaret`（C9・PendingViewStore 実装）**、initState/didUpdateWidget/deactivate/dispose（**P0-P9 統括**）、State テストフック forwarding。**セレクタ起動・resize chooser 起動・表示ツリー本体は root に残さない**（→ ui/herdr）。

---

## 4. インターフェース契約（最重要・v2）

### 4.1 本領域が所有する state（単一所有・dispose 責任）

| state | 所有者 | 破棄責任 | 備考 |
|---|---|---|---|
| `TerminalViewData`（`_viewNotifier`） | SessionRuntimeController | **P8 先頭** | view-input は `setDisplayedContent` 経由のみ |
| `_latencyNotifier`（**G7**） | 同 | **P8（`_viewNotifier` の直後）** | poll が唯一の書込 |
| poll 状態（`_isPolling`/`_pollTimer`/`_treeRefreshTimer`/適応型間隔/unchangedPolls） | 同 | **P4**（timer cancel） | — |
| frame スロットル 4 値 | 同 | — | `_scheduleUpdate`/`_applyUpdate` |
| `_hasInitialScrolled` / `_pollingSuspended` / `_isInBackground` | 同 | — | herdr は `onLiveReset` / suspend-resume コールバックで間接操作 |
| `_paneReader`/`_frameReader`/`_paneWriter`/`_targetSource`（フィールド） | 同 | — | 生成は session_readers / herdr composer / herdr switchTarget |
| `_backendKind`/`_tmuxVersion`/`_sshState`/`_connectionError`/`_isConnecting`/`_isCreatingWindow`/`_isResizing` | 同 | — | ui に read-only |
| `_resizedWindowTargets`/`_windowsRestoredForBackground`/`_autoResizeDebounceTimer`/`_backgroundRestoreTimer` | SessionResizeFlow | **P6** | G1-G4 |
| G5/G6: `_imageTransferSub`/`_downloadSub` | TerminalTransferFlow | **P3**（subscription group） | 1 回登録ガード |
| `_secureStorage` | SessionConnectionFlow | — | 共有 1 個 |

### 4.2 他領域から受ける props / コールバック（`SessionEnv` bundle・root が生成）

| 入力 | 提供元 | 用途（本領域） |
|---|---|---|
| `WidgetRef ref` | root | ssh/tmux/settings/network/activeSessions/imageTransfer/download provider |
| props getter（sessionName/sessionId/lastWindowIndex/lastPaneId/deepLink*） | root | setup/復元 |
| `bool isMounted()/isDisposed()` | root（SessionHost） | 全 async・リスナーのガード（H3） |
| `void resetTerminalMode()/boostPolling()/startPolling()/suspendPolling()/resumePolling()` | root→herdr/view-input 呼出 | 再接続・切替末尾 |
| `void onLiveReset()`（view clear + `_hasInitialScrolled=false`） | root→herdr | `switchTarget`/`setupSession` |
| `input.flushInputQueue()` | view-input | `_onReconnectSuccess` |
| `input.captureSelectUpdate(content, caret, identity)` / `input.takeBufferedUpdate()` | view-input | select バッファ（**C7・3 段契約**） |
| `viewport.scrollToCaret()` / `viewport.followToBottom()` | view-input | `_applyUpdate` 初回/追従（**C1**） |
| `input.handleTmuxCopyModeDetected/Ended()` | view-input | poll の copy-mode 自動遷移 |
| `TerminalKeySender.flushQueuedInput()` | view-input | 切断中キュー（C2 移設後） |
| `HerdrController.handlePollError(e)` / `.captureIdentity()` / `.isCurrentIdentity(id)` / `.reResolveAfterReconnect()` / `.rebuildAfterClient(client)` / `.refreshPaneIndicatorFromCache()` / `.recordSwitchEvent(ev)` | herdr | poll・再接続・reader |
| `PendingViewStore` | **root（C9 実装）** | `_scheduleUpdate`/`_applyUpdate` が pending を書込/読取 |
| `downloadSnackBarDisplay(l10n, next, prevPhase)` | **ui 純関数（import）** | G6 の表示仕様 |

### 4.3 他領域へ提供する API

| API | 提供先 | シグネチャ（public 化後） | 備考 |
|---|---|---|---|
| `Future<void> setup({WidgetRef ref, SshClient? client})` | root | `_connectAndSetup` 置換 | herdr/tmux 分岐 |
| `Future<void> onReconnectSuccess()` | sshProvider | 再確立 + poll 再開 + `input.flushInputQueue()` | C2 委譲 |
| `Future<bool> pollPaneContent()` / `void scheduleNextPoll()/boostPolling()/suspendPolling()/resumePolling()` | root | poll 制御 | P4 |
| `void applyViewUpdate(content, caret, identity)` | 内部 | `_applyUpdate` | C9 経由 |
| `TerminalPaneSendPort`（sendText/sendKey/paneId/boost/recordSwitchEvent） | view-input | writer + target を wrap | — |
| `TerminalInputCapabilities`（canSendText 等 6） | view-input | `_can` 群 | — |
| `TerminalScrollbackPort`（reader/identity/setDisplayedContent） | view-input | 深い履歴 I/O | — |
| `bool canSend*` / `SshState sshState` / `bool isConnecting` / `String? connectionError` | ui | read-only | G7 latency notifier は build へ渡す |
| mutation コールバック: `selectPane/createWindow/killPane/killWindow/selectSession/selectWindow/splitPane(tmux)/**handleResizePane/handleResizeWindow**` | ui | メニュー/chooser から注入 | G1-G4 受領 |
| `Future<void> disconnect()` / `showDisconnectConfirmation()` | ui | メニュー | — |
| **`_restoreResizedWindows` の提供（G2）** | **root（deactivate）** | **`deactivate` が `unawaited(restoreResizedWindows().then((_){ if(checkConnection()) sshNotifier.disconnect(); }))` を呼ぶ（L3282-3289 と同型・コールバック注入）** | **critique §4.3 指摘対応・契約表に明記** |
| `void Function() onLiveReset` 実装 | herdr | view clear | 本領域所有の更新 |
| `PaneCapabilities get paneCapabilities` | herdr `_can(...)` | writer.capabilities | — |
| transfer: `Future<void> ensureListeners()`（subscription 単一登録・P3 で close） | root | G5/G6 | 多重登録なし |

### 4.4 `_TargetSource` の契約（専用節・維持）

- 抽象 `abstract interface class TargetSource { String? get currentPaneId; }`。**`currentPaneId` のみ**（`switchTarget`/`fetchTree` は含めない・HEAD L193 コメントどおり）。
- tmux（本領域 `TmuxTargetSource`）: 毎呼出し `readCurrentTarget()`（= `ref.read(tmuxProvider.notifier).currentTarget`）へ遅延委譲・null 伝播維持。
- herdr（herdr_types `HerdrTargetSource`）: 接続時解決の固定 paneId・`setPaneId` は herdr `switchTarget` のみ。
- 生成時点: tmux は `_connectAndSetup`（L1470-1475）・herdr は `_setupHerdrSession`。**フィールドは本領域・値生成は herdr**（二重所有回避）。
- エポック照合（`_HerdrTargetIdentity=(cache,epoch,paneId)`）との関係: `currentPaneId` は照合キーの 1 要素。本領域 poll は `captureIdentity()`/`isCurrentIdentity()` を herdr API で行い、結果で破棄。

### 4.5 dispose フェーズ表（arbitration §4・本領域の呼出位置を明記）

| フェーズ | 内容（HEAD L3293-3345 順序維持） | **本領域の実行者/呼出位置** |
|---|---|---|
| P0 | `_isDisposed = true` | root |
| P1 | herdr bridge.reset（先頭） | herdr |
| P2 | removeObserver / Wakelock 解除 | root（`session_lifecycle.detach()` もこの位置） |
| P3 | ProviderSubscription 群（4 本 + **transfer 2 本**） | **root が `terminalTransferFlow.disposeSubscriptions()` を呼ぶ**（G5/G6）＋ 4 本 close |
| **P4** | **poll/tree タイマー停止** | **`sessionRuntime.cancelPollTimers()`**（`_pollTimer`/`_treeRefreshTimer` cancel → null） |
| P5 | scrollSend / keyOverlay タイマー | view-input |
| **P6** | **autoResize / background タイマー** | **`sessionResize.cancelResizeTimers()`**（`_autoResizeDebounceTimer`/`_backgroundRestoreTimer`） |
| P7 | herdr cache / identity / resolved target null 化 | herdr（**C9: root が `_pendingTargetIdentity`/`_pendingCaret` を null 化**） |
| **P8** | notifier dispose（順序厳守: view → herdrDisplay → herdrPaneIndicator → latency） | **root が `sessionRuntime.disposeViewNotifier()`（P8a）→ herdr の 2 本（P8b）→ `sessionRuntime.disposeLatencyNotifier()`（P8c）** |
| P9 | root ScrollController removeListener+dispose → `super.dispose()` | root |

> 注: P1（herdr bridge.reset）と P8（herdr notifier）は別フェーズ（arbitration §4・herdr v2 も同記述）。session の deactivate（root L3273）は P 表外の「pop 時経路」で `_restoreResizedWindows`（G2）→ 接続確認 → disconnect を実行（§4.3 に記載）。

### 4.6 接続〜切断〜再接続と poll ループの順序図（HEAD 実測に基づく）

**① 初回接続（`_connectAndSetup` L1254-1520）**

```mermaid
sequenceDiagram
  participant R as root(State)
  participant C as SessionConnection
  participant S as sshProvider
  participant H as herdr(Controller)
  participant P as SessionPoll
  participant T as tmux(provider)
  R->>R: initState/postFrame → C.setup(ref, connId)
  C->>C: getById; isConnecting=true; backendKind 確定
  C->>S: connectWithoutShell(options)
  C->>C: resetTerminalMode()
  alt herdr
    C->>H: setupSession(client)（clear→readers→resolve→HerdrTargetSource→indicator→onLiveReset→startPolling）
  else tmux
    C->>C: getVersion→recreatePaneReader→refreshSessionTree
    C->>C: セッション選択/新規+historyLimit→setActiveSession→復元(deepLink/lastWindow/lastPane)
    C->>T: setActivePane→terminalDisplay.updatePane→sendFocusIn
    C->>R: targetSource=TmuxTargetSource → P.startPolling() → T.startTreeRefresh (10s)
    C->>R: isConnecting=false; if(autoResize) S3.scheduleInitialAutoResize()   [G3]
  end
```

**② poll ループ（`_scheduleNextPoll` → `_pollPaneContent` L2017-2412・v2 の port 委譲点を明示）**

```mermaid
sequenceDiagram
  loop Timer(currentPollingInterval: 50/100/500/2000ms)
    P->>P: scheduleNextPoll (suspended/disposed ガード)
    P->>P: pollPaneContent()
    alt 未接続
      P->>S: !isReconnecting → attemptReconnect(); return
    else 接続 & target/reader
      P->>H: identity=captureIdentity()
      P->>P: frameReader.read(live) [await]
      P->>R: mounted/_isDisposed ガード
      P->>H: !isCurrentIdentity ⇒ 破棄 return
      P->>H: refreshPaneIndicatorFromCache()
      P->>P: geometry→viewNotifier(paneWidth/Height)+terminalDisplay+tapPoint
      P->>P: latencyNotifier.value = elapsed(ms)   [G7: 唯一の書込]
      P->>P: 差分(content/caret)
      alt select(manual)
        P->>VI: input.captureSelectUpdate(content,caret,identity)   [C7]
      else
        P->>P: scheduleUpdate → (root PendingViewStore) → 16ms throttle → applyUpdate(identity 照合) → viewNotifier
        P->>VI: viewport.followToBottom() / 初回は viewport.scrollToCaret()   [C1]
      end
      P->>VI: input.handleTmuxCopyModeDetected/Ended（末端で takeBufferedUpdate→apply）  [C7]
      P->>P: updatePollingInterval()（copy-mode/scrollSend 中は上限 500ms）
    end
    P->>P: catch → herdr? H.handlePollError : attemptReconnect
  end
```

**③ 切断・再接続・ユーザー切断（L3107-3125 / L1200-1242 / L7259-7275・C2 委譲含む）**

```mermaid
sequenceDiagram
  participant P as SessionPoll
  participant C as SessionConnection
  participant S as sshProvider
  participant H as herdr(Controller)
  participant VI as view-input
  P->>P: poll で !client.isConnected
  P->>S: !isReconnecting → C.attemptReconnect() [reconnect()]
  S-->>C: 成功 → onReconnectSuccess()
  C->>C: resetTerminalMode() → isPolling=false → recreatePaneReader()
  alt herdr
    C->>H: reResolveAfterReconnect(); true なら pollingSuspended=false; startPolling()
  else tmux
    C->>P: startPolling(); C->>T: startTreeRefresh()
  end
  C->>VI: input.flushInputQueue()   [C2 委譲]
  C->>R: setState

  Note over C: ユーザー切断（menu→showDisconnectConfirmation→disconnect）
  C->>C: pollTimer/treeRefresh cancel → tmuxProvider.clear()
  C->>C: restoreResizedWindows()   [G2] → sshProvider.disconnect() → Navigator.pop
```

**④ dispose（P0-P9・§4.5 参照）** と **deactivate（pop 経路）**: `unawaited(restoreResizedWindows().then((_) { if (sshNotifier.checkConnection()) sshNotifier.disconnect(); }))` → `super.deactivate()`（L3282-3289 そのまま）。

---

## 5. 公開 API 維持表

| 公開シンボル | 維持方法 | 根拠（実測） |
|---|---|---|
| `TerminalScreen`（コンストラクタ 12 引数） | シムに本体存続（変更禁止） | 4 lib 呼出元 + scaffold |
| `ScrollModeSource` / `HerdrSyncTargetPolicy` enum | **シムから 1 経路のみ export**（他設計で再定義禁止・arbitration §7） | contract TERM-ENUM-001・mutation_sync L644 |
| `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` | ui の `download_snackbar_display.dart` に移設・**シム export は忘れない** → 本領域 transfer flow は同ファイルを import | download テスト 2 本 |
| State テストフック（`scrollModeSourceForTesting` 等 6 + herdr 10 種） | root State フォワード維持 | `tester.state(...)` dynamic 呼出 |
| `_TerminalViewData`（public `TerminalViewData` 化） | session_models（外部参照は port 経由） | 内部型・変更可（public 化） |
| `_PaneLayoutPainter` runtimeType | **新ファイル内 private のまま**（ui v2・typedef 禁止） | herdr テスト 7+ 箇所 |
| AnsiTextView 18 props・State 公開 5 メソッド | 変更禁止 | BRIEF |

根拠（実測）: `terminal_screen_contract_test.dart` TERM-SCREEN-002..003 / TERM-FILE-001・`terminal_download_snackbar_test` / `terminal_download_summary_test`。

---

## 6. リスクと対策（v2: H1/H4/H6・G2 deactivate を追加）

| # | リスク | 回帰シナリオ | 対策 | 検出テスト |
|---|---|---|---|---|
| 1 | setup 順序崩れ | await 位置変更で exec 順序変化 | 順序図 ① を 1:1 写経 | setup_test |
| 2 | kill-pane/window 後の provider 同期・最終 pane 時切断 | closePane→refreshTree 順・`isLastPane&&isLastWindow→disconnect` 崩れ | 1:1 写経・存在再検証（termPaneNoLongerExists）維持 | crud_test |
| 3 | エポック照合パイプライン（C9/C7） | `_applyUpdate`/`_applyBufferedUpdate` の照合・破棄順が変わる | herdr `isCurrentIdentity` 1 回・不一致 return。`PendingViewStore`（root）の書込順を維持 | herdr_epoch_test ①②③・follow |
| 4 | frame スロットル/適応型間隔 | 16ms・上限（copy-mode/scrollSend=500ms）が乱れる | ロジック不変で集約 | setup TERM-LIFE-015/017 |
| 5 | `_pollingSuspended` 二重所有 | herdr が直書き | suspend/resume コールバックのみ | herdr server-down・mutation |
| 6 | dispose 順序（P0-P9） | notifier 順・subscription 順が変わる | §4.5 のフェーズ表を root が 1 ブロック実行 | lifecycle TERM-LIFE-022 |
| 7 | 追従ジャンプ（`_hasInitialScrolled` 初回ゲート） | 初回 scrollToCaret/follow 条件が崩れる | 本領域のみ書込・herdr は onLiveReset | follow/history |
| 8 | 再接続 herdr 分岐 | resolved=false で poll 再開しない条件が崩れる | `reResolveAfterReconnect` 戻り値どおりに制御 | herdr 系・lifecycle |
| 9 | `tmuxProvider.clear()` 2 経路 | 1 経路消失で stale currentTarget 混入 | can_test T9 の 2 呼出を維持 | can_test |
| 10 | UI 文言・Key | SnackBar/ダイアログ文言・`'[Terminal] Pane size:'` 等 | l10n 参照のまま移設（文言変更禁止） | crud/setup/herdr |
| 11 | **G1-G4 の移動漏れ（所有権空白の再発）** | autoResize/resize-window/pane がどこにも無い | §3 マッピング + `session_resize.dart` に明記。**deactivate 経路の G2 呼出（§4.3）を残す** | resize_test・remaining RESIZE-004..007 |
| 12 | **G5/G6 リスナー 2 重登録 / ガード喪失（H6/H3）** | root+flow の 2 箇所から `_ensure*` 呼出で 2 重登録・disposed 後 await 完了 | `terminal_transfer_flow.dart` 内で `_imageTransferSub != null` return・`isMounted`/`isDisposed` port ガード維持 | download 2 本・herdr 画像系 |
| 13 | **G7 latency の二重書込** | poll 以外が `_latencyNotifier` を書くと専用 notifier 分離が壊れる | 書込は session poll に限定（§1.2⑥） | repro_bug2_latency |
| 14 | **H1: mutation 中の reconnect（HEAD 同一挙動）** | `_syncAfterHerdrMutation`（herdr・await 中）と `_reResolveHerdrTargetAfterReconnect`（herdr）の同時実行。mutation 側は cache 現在値参照で安全な一方、resolved 判定と `_switchHerdrTarget` が reconnect の再解決結果を上書きしうる | **HEAD と同じく cache 現在値参照・`mounted`/`_isDisposed` ガード維持で回帰しないことを明記**（順序は HEAD と同一）。本領域側は poll/apply の `isCurrentIdentity` 照合だけで対応 | herdr_mutation_sync_test（サーバ復旧での再同期） |
| 15 | **SnackBar 多重抑止を追加しない（H4）** | dedup 追加で文言/回数テストが壊れる | 多重抑止は追加しない（HEAD 同等）。§7 arbitration 準拠 | download_summary・herdr UI |
| 16 | transfer の SnackBar（download）表示仕様 | 全スキップ時に緑 'Download complete' にしない | ui の純関数 `downloadSnackBarDisplay` をそのまま import（仕様導出は ui） | download_summary LOW#3 |

---

## 7. 検証計画（v2: SCC>=2 を追加・resize/mutation_ui を範囲に）

```bash
cd /home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines
# 1. フォーマット / 静的解析
dart format --output=none --set-exit-if-changed lib/screens/terminal
flutter analyze

# 2. 本領域を固定するテスト（狭→広）
flutter test test/screens/terminal/terminal_screen_setup_test.dart
flutter test test/screens/terminal/terminal_screen_lifecycle_test.dart
flutter test test/screens/terminal/terminal_screen_crud_test.dart
flutter test test/screens/terminal/terminal_screen_can_test.dart
flutter test test/screens/terminal/terminal_screen_contract_test.dart
flutter test test/screens/terminal/terminal_screen_resize_test.dart          # G1-G4
flutter test test/screens/terminal/terminal_screen_remaining_contracts_test.dart  # TERM-RESIZE-004..007
flutter test test/screens/terminal/terminal_screen_history_test.dart
flutter test test/screens/terminal/terminal_screen_follow_scroll_test.dart
flutter test test/screens/terminal/terminal_screen_herdr_epoch_test.dart    # C9/C7 パイプライン
flutter test test/screens/terminal/terminal_screen_herdr_mutation_ui_test.dart   # resize 配線（critique §9 追加）
flutter test test/screens/terminal/terminal_download_snackbar_test.dart     # G6
flutter test test/screens/terminal/terminal_download_summary_test.dart      # G6（多重なし・LOW#3）
flutter test test/repro/repro_bug2_latency_test.dart                        # G7
flutter test test/repro/repro_bug4_scrollback_test.dart

# 3. SCC>=2 検証（新設ファイル間・arbitration §6 必須）:
#    新設ファイル（session_* / target_source / 他領域）の import/export 辺を抽出し
#    Tarjan で SCC>=2 = 0 を確認。P3 の /tmp/p3-design/scc_verify_v3.py を新設グラフへ適用。
#    ※ terminal_screen.dart（シム）から新ファイルへの逆 import（新ファイル→シム）禁止も検証。
python3 /tmp/p3-design/scc_verify_v3.py   # 適用先を新設ファイルグラフに変更（実行コマンドは統一時 lead 確定）

# 4. 他領域との統合後
flutter test test/screens/terminal/
flutter test

# 5. 既存テスト差分ゼロ（最重要）
git diff HEAD -- test/   # 空であること

# 6. 500 行未満の実測（wc -l）と session_runtime.dart 450 超なら分割必須
wc -l lib/screens/terminal/session/*.dart
```

---

## 8. 未確定点（ユーザー/lead 判断が必要なもの）

1. **root State の row 内訳確認**: arbitration §2 の「root 残置 <500 行」は ui 設計者が v2 で数値保証。本領域は「pending 2 フィールド（C9）・subscription 4 本・keys・dispose/framework 配線・hook forwarding」のみ残す想定とし、超過した場合は lead が最終分割。
2. **`download_snackbar_display.dart` の正確なパス**: ui 設計の配置に従う（本領域は module 名のみ参照。session→ui 一方向 import は仲裁 §6 どおり）。
3. **`session_runtime.dart` 450 分割のトリガ計算**: #4 の見積 430 は移動後のコメント実測。450 を超えた場合は #5（session_view_pipeline）へ `_scheduleUpdate`/`_applyUpdate`/`_applyBufferedUpdate`/frame スロットル/`_latencyNotifier` を**必ず**分離（arbitration §5・条件ではなく閾値）。
4. **C7 バッファの適用トリガ**: 適用（`takeBufferedUpdate`→`scheduleUpdate`）は copy-mode 終了時の poll（本領域）が駆動する設計。view-input の v2 と駆動元を突き合わせ、lead が一本化（呼出形状のみの差異）。
5. **`_handleResizePane` の ui 側配線**: ui `_showResizePaneChooser` は「起動のみ」、実行は本領域 `handleResizePane`（全 5 段の絶対値→相対換算ロジック含む）。PaneChooserDialog へのアダプタ経由は ui/herdr の v2 と整合確認。
6. **`_secureStorage` 共有**: 画像転送（G5）が同リソースへ触れる場合は root に昇格（現状 session_connection 所有のまま）。

---

## 付録: 事実と推測の区別

### 事実（コード・rg・テスト読了で確認済み）
- 全メンバ・行番号（§1.1）。G1-G4: `_executeAutoResize` L5774 / `_restoreResizedWindows` L5841 / `_scheduleInitialAutoResize` L5854 / `_handleResizePane` L5869 / `_handleResizeWindow` L6232。G5/G6: `_ensureImageTransferListener` L7579 / `_ensureDownloadListener` L7558 / `_handleFileBrowser` L7638 / `_handleImageTransfer` L7652 / `_injectImagePath` L7692。G7: `_latencyNotifier` L491（poll L2304 書込・dispose L3342 で view 直後）。
- `_ensureDownloadListener` は `downloadSnackBarDisplay(context.l10n, next, prev?.phase)`（ui 純関数）を import して表示・`_downloadSub != null` で return。
- `_ensureImageTransferListener` は `_imageTransferSub != null` で return（1 回登録・H6）。
- dispose L3339-3343: view → herdrDisplay → herdrPaneIndicator → latency（P8 順序厳守）。
- deactivate L3282-3289: `unawaited(_restoreResizedWindows().then((_) { if (checkConnection()) disconnect(); }))`（G2・pop 経路）。
- arbitration.md §1（C1-C9・G1-G7）・§2（root スコープ）・§4（P0-P9 フェーズ表）・§5（450 必須分割）・§6（SCC）・§7（多重抑止なし・export 1 経路）。
- test 固定点（§1.4 テスト名）は実測。

### 推測・設計判断（要 lead/critic 調整）
- 新ファイル行数（§2）は実測ベース概算。移動後の残量で ±20% 変動。
- C7 バッファ適用トリガの駆動元（§8-4）は view-input v2 との突き合わせで確定する設計判断。
- `SCC 検証スクリプトの適用先（session 新設グラフ）`は実装時のファイル名確定後に lead が final 化する（コマンドは §7 に記載）。
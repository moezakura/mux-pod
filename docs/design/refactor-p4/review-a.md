# P4 独立検証A レポート（session / input / root 領域）

- 検証者: p4-reviewer-a（teammate #41・読み取り専用）
- 対象: `lib/screens/terminal/terminal_screen.dart`（シム+root 438 行）/ `terminal_root_bindings.dart` /
  `terminal_screen_ports.dart` / `terminal_screen_access.dart` / `target_source.dart` /
  `session/**`(16 ファイル) / `input/**`(9 ファイル)
- HEAD: `bff0c13`（`terminal_screen.dart` 9,529 行）／ブランチ: `fix/refactor-many-lines`
- 参考設計: `/tmp/p4-design/arbitration.md` / `session-runtime.md` / `view-input.md` / `BRIEF.md`

## 判定: **NG**（挙動パリティ破れを 8 件検出。うち 3 件は実動作に影響する回帰）

テストは全て green・構造制約は全て満たすが、**テストで捕捉されない挙動パリティ破れ**が
複数残る（いずれも「テストは存在しないが HEAD と異なる動作」）。NG 判定の根拠は §1 の
Top5。重要指摘の修正案と再現手順は §3。

---

## 0. 検証サマリ

| 検証項目 | 結果 | 証跡 |
|---|---|---|
| 1. 挙動パリティ（await 順序・ガード・タイマー値） | **NG（8 件）** | §1・§2.1-2.2 |
| 2. 欠落・スタブ検出 | **OK（スタブなし）** | §2.3 |
| 3. 所有権と dispose（P0-P9） | **概ね OK（P3 のみ契約表とズレ）** | §2.4 |
| 4. 公開 API 不変（12 引数・テストフック） | **OK** | §2.5 |
| 5. 既存テスト不変 | **OK** | §2.6 |
| 6. 構造（500 行・part/mixin・循環 import） | **OK** | §2.7 |

---

## 1. 重要指摘 Top5

### [NG-1]（HIGH）ダウンロード進行中に空の SnackBar が頻発する回帰
- 個所: `terminal_root_bindings.dart`（adapter の `downloadSnackBarDisplay` ラッパ）と
  `session/terminal_transfer_flow.dart` L52-59。
- 内容: `downloadSnackBarDisplay` 純関数は「phase 遷移時のみ」Spec を返し、進捗 publish /
  idle 復帰では `null` を返す（HEAD は `if (display == null) return;` で非表示）。
  新実装では SessionEnv のフィールド型が**非 null** `DownloadDisplaySpec` のため、
  adapter が `null → DownloadDisplaySpec(message: '', backgroundColor: null)` の
  **空 sentinel に置換**している。transfer flow の `if (display == null) return;` は
  成立せず、**空メッセージの floating SnackBar が表示される**。
- 実証: `download_publish_handler.dart` L55-75 `onProgress` は `phase` 不変のまま
  `publishState(copyWith(items…))` を発行 → リスナー発火 → 純関数 `null` → sentinel →
  空 SnackBar 表示。
- 再現手順: ダウンロードを開始（phase=downloading）。進捗 publish 1 回ごとに
  中身の無い floating SnackBar がポップする（HEAD では非表示）。
- 修正案: adapter のラッパを nullable 戻り値でバイパスする（`SessionEnv` のフィールド型を
  `DownloadDisplaySpec? Function(...)` に変える）、または transfer flow 側で
  `display.message.isEmpty && display.backgroundColor == null` を非表示として扱う。

### [NG-2]（HIGH）deactivate で SSH 切断が失われた
- 個所: `terminal_screen.dart` `deactivate()` L194-201。
- 内容: HEAD `deactivate`（L3279-3293）は
  `unawaited(_restoreResizedWindows().then((_) { if (sshNotifier.checkConnection()) sshNotifier.disconnect(); }))`
  で「popUntil 等で `_disconnect()` を経由せず pop された場合も SSH を切断」していた。
  新実装は `restoreResizedWindows` のみ実行し **SSH disconnect が消滅**。
- 再現手順: TerminalScreen をルートへ戻す（戻るボタン / popUntil、Disconnect ダイアログ
  経由なし）。SSH 接続が切断されず残る（HEAD は切断）。
- 修正案: deactivate で `restoreResizedWindows().then((_) { if (sshNotifier.checkConnection()) sshNotifier.disconnect(); })`
  を fire-and-forget で呼ぶ。

### [NG-3]（HIGH）`_hasInitialScrolled` の二重所有により pane/セッション切替後の初回キャレットスクロールが消滅
- 個所: `session/session_runtime.dart` L73 と `session/session_view_pipeline.dart` L24。
- 内容: HEAD は単一の `_hasInitialScrolled` で「初回コンテンツ受信 → scrollToCaret(C1)」を
  制御し、`_selectPane`/`_selectWindow`/`_selectSession`/`_createWindow` の各所で
  `false` に戻していた（切替後の新 pane で再びキャレット位置へスクロール）。
  新実装では 4 箇所（`session_mutations.dart` L46/84/121/202）が
  `runtime.hasInitialScrolled` へ書くが、**pipeline は別フィールド
  `MutableViewState.hasInitialScrolled` しか読まない**（L86-89）。`view.hasInitialScrolled`
  は `true` になったきり **誰も false 化しない**（herdr の onLiveReset も未実装）。
  書込側フィールドは完全にデッドコード化。
- 結果: pane / ウィンドウ / セッション切替後の初回コンテンツで `scrollToCaret()` が
  発火しなくなり、`else if (view.hasInitialScrolled && shouldFollowBottom)` 側だけが
  動く（ピン留めでなければ何も起きない＝新 pane の先頭表示のまま）。
- 再現手順: 2 pane の tmux セッションで pane を切替 → 切替後のコンテンツがキャレット
  位置に揃わず（HEAD は中央揃えのキャレット追従スクロール）。
- 修正案: `runtime.hasInitialScrolled`（書込側）と pipeline の `view.hasInitialScrolled`
  （読取側）を 1 フィールドに統一。切替箇所で pipeline 側を false 化する。

### [NG-4]（MEDIUM）バックグラウンド復元（G2）の配線欠落：600ms 猶予タイマーと force 再 fit が常に不発
- 個所: `terminal_screen.dart` `didChangeAppLifecycleState` L172-188 と
  `session/session_resize.dart`（`scheduleBackgroundRestore` L294 / `onBackgroundNow` L319 は
  呼び出し元ゼロ＝デッドコード）。
- 内容: HEAD は
  - `inactive` → `_scheduleBackgroundRestore()`（600ms 猶予タイマー・早期復帰でキャンセル）
  - `paused/hidden/detached` → `_windowsRestoredForBackground = true`（target 非空時）→ 復元
  - `resumed` → flag なら force re-fit（`_executeAutoResize(force: true)`・TERM-RESIZE-001）
  を行っていた。新 root は `inactive` で何もせず、`paused/hidden` は直接
  `restoreResizedWindows()`（flag 未設定）、`resumed` は `resumePolling()` のみ。
  結果: 「600ms 猶予で inactive 復元」「復帰後の強制再フィット」が失われる
  （`resize.scheduleBackgroundRestore` / `onBackgroundNow` は 1 呼び出しも無い＝script 検出）。
- 再現手順: autoResize 有効で接続 → window 縮小後、通知シェード等で `inactive` に
  600ms 以上滞留（HEAD は restore、新実装は何もしない）→ `resumed`（HEAD は force 再 fit、
  新も何もしない）。
- 修正案: inactive で `_adapter.resize.scheduleBackgroundRestore()`、paused/hidden/detached で
  `_adapter.resize.onBackgroundNow()`、resumed は現状どおり（`onResumed` は env 経由で
  呼ばれているが flag が無いため発火しない）。

### [NG-5]（MEDIUM）エラー SnackBar の Retry 動作が変更（connectAndSetup → startPolling）
- 個所: `session/session_connection.dart` `_showErrorSnackBar` L423-431。
- 内容: HEAD は `SnackBarAction(onPressed: _connectAndSetup)`（接続情報取得〜SSH接続の
  フル再接続）。新実装は `runtime.startPolling()`（ポーリング再開のみ）。認証エラー
  （`SshAuthenticationError`・鍵読取失敗）からの Retry が「ポーリング→再接続試行」と
  なり、接続オプション再取得（passphrase 再読込等）の経路が変わらない。
- 修正案: `onPressed` を `connection.connectAndSetup`（PopScope で await しない形）に戻す。

---

## 2. 検証詳細

### 2.1 挙動パリティ（await 順序・ガード・タイマー）— 合致項目
コード比較（HEAD `git show HEAD:…` と新実装）で以下は HEAD と一致:
- `_connectAndSetup`（session_connection.dart）: mounted ガード→isConnecting→接続取得→
  backendKind→auth→SSH connect→mode reset→herdr 早期 return / tmux getVersion→
  recreateReader→tree→session 選択（sessionName/既存/自動生成の3分岐・各 refresh 後ガード）→
  履歴行設定→setActiveSession→deep-link/保存位置復元→updatePane+sendFocusIn→
  targetSource→startPolling→startTreeRefresh→isConnecting=false→autoResize。
  各 await 間の `mounted`/`_isDisposed` ガードも一致（`setup_test`/`crud_test` green が裏付け）。
- `_onReconnectSuccess`: resetTerminalMode→recreateReader→herdr reResolve/tmux
  startPolling+tree→flushInputQueue→setState。
- `_killPane`/`_killWindow`: poll 停止→closePane/killWindow→**reload(refreshSessionTree)**→
  session 消滅判定→lastPane/window 同期。最後の pane は `disconnect` へ。
- `_createWindow`: createWindow→**reload→snapshot（active window 検出）**→selectPane→
  command 送信→boost。
- タイマー値: 100ms（scrollToCaret・scrollSend flush 合流）/ 1500ms（key overlay）/
  50ms・2000ms（適応型 poll min/max）/ 10s（tree refresh）/ 16ms（frame throttle）/
  500ms（autoResize debounce）/ 120ms（initial autoResize retry）— 全て HEAD 一致
  （600ms background restore は実装あり・**未配線**＝NG-4）。

### 2.2 挙動パリティ（差分項目・NG-1 以外）
| # | 個所 | HEAD | 新実装 | 影響 |
|---|---|---|---|---|
| 6 | `session_poll.dart` L146 + `terminal_screen_ports.dart` L358 | `_lastPolledPaneMode = paneMode`（trim 実値） | `observePaneMode('')`（空固定） | H4② の flush 時 paneMode 空確認ガードが死コード化（`_lastPolledPaneMode.isNotEmpty` が常 false） |
| 7 | `session_poll.dart` L147-155 | copy-mode 遷移条件 `isTmuxCopyMode && _scrollModeSource == none` | `isTmuxCopyMode && !isCopyModeActive` | select(manual) 中に tmux copy-mode を検出すると source=manual→tmux へ自動遷移（HEAD は維持）。copy-mode 終了で select が自動解除される |
| 8 | `session_view_pipeline.dart` L89 | `mode==normal && !_isUserScrollDragging && _shouldFollowBottom` | `shouldFollowBottom` のみ | select/scrollSend 中・ドラッグ中の followToBottom 発火（HEAD は発火しない）。UI ドリフト |

### 2.3 欠落・スタブ検出 — OK
- 空実装 `() {}` / `=> null;` メソッド: **0 件**（script 検出）。
- `// TODO`: **1 件** `terminal_key_sender.dart:309` — HEAD（L7788）由来と同一文言で回帰なし。
- デッドコード残骸: `session_env.dart:157` `dynamic get _unused => null;` ＋
  `// ignore: unused_element`（l10n 用と書かれるが未使用。粘着）。動作には無影響。
- HEAD にあり新実装に無いメソッド（スクリプトで 280 メンバ抽出→再帰照合）は全件、
  session/input/root→herdr/ui の設計割当先へ移動済み（`_scheduleBackgroundRestore` 等の
  移動先実装が未配線なのが NG-4。`_killPane`→`killPane` 等はリネーム移設確認済み）。

### 2.4 所有権と dispose（arbitration §4 P0-P9）— 概ね OK
root `dispose()` の順序（terminal_screen.dart L203-232）:
P0 `_isDisposed=true` → P1 bridge reset → P2 removeObserver+Wakelock → P3 subscriptions
→ P4 poll/tree タイマー → P5 scrollSend/keyOverlay タイマー → P6 autoResize/background
タイマー → P7 herdr cache/identity の null 化 → P8 notifier（view→herdrDisplay→
herdrPaneIndicator→latency、`herdr.disposeNotifiers` が display→indicator の順）→
P9 listener detach → ScrollController.dispose → super.dispose。
- 各 controller の破棄は該当フェーズでのみ呼ばれ、二重 dispose 経路なし（State.dispose は
  1 回、`late final` の未初期化アクセスは initState 同期生成のため不可能）。
- **P3 のみ契約とズレ**: disposeP3Subscriptions は transfer 2 本のみ明示 close。root 4 本
  （ssh/tmux/settings/network の `listenManual`）は戻り値の ProviderSubscription を保持せず、
  Riverpod の element teardown（Consumer 自動破棄）に委ねている。機能上リークしないため
  軽微（仲裁 §4 の「4+2 本」表記との不一致）。※NG-3 の `runtime.hasInitialScrolled` は
  「書込のみ/読取なし」のデッドフィールド＝所有権分裂。

### 2.5 公開 API 不変 — OK
- `TerminalScreen` コンストラクタ: 12 引数（key + connectionId/sessionName/sessionId/
  lastWindowIndex/lastPaneId/deepLinkWindowName/deepLinkPaneIndex/paneContentReader/
  initialPaneId/herdrCacheClock/herdrCaretReader）、名称・順・型 HEAD と一致。
- `@visibleForTesting` フック: HEAD 18 本と新 root 18 本で**名称・引数・戻り型一致**
  （`loadHistoryForScrollForTesting` のみ `{bool preservePosition = false}` の互換オプション
  追加＝既存呼出テストは無引数で通過）。
- シムからの 1 経路 export（DownloadSnackBarDisplay / downloadSnackBarDisplay /
  HerdrSyncTargetPolicy / ScrollModeSource / buildInputDialogContentForTesting）維持。

### 2.6 既存テスト不変 — OK
- `git diff HEAD -- test/` = **0 行**（空。証跡あり）。
- 担当 9 ファイル: setup/can/crud/lifecycle = **32 pass**、history/follow_scroll/scroll_send
  = **30 pass**、input/paste = **9 pass**。加えて `test/screens/terminal/` 全件 =
  **325 pass**（NG-1〜8 はテスト未捕捉のため green）。
- `dart analyze lib/screens/terminal/` = **No issues found!**

### 2.7 構造 — OK
- 全対象ファイル 500 行未満（最大 = terminal_screen.dart 438 行）。
- part / part of / mixin: 対象 26 ファイル中 **0**（root の `with WidgetsBindingObserver` は
  HEAD と同一。ui 側のみ mixin 許容範囲）。
- 循環 import: 新規 66 ファイルの import グラフで **SCC>=2 = 0**（Tarjan 実測）。

---

## 3. NG の再現手順と修正案（補足）

| NG | 再現手順（簡） | 修正案 |
|---|---|---|
| NG-1 | ダウンロード開始→進捗 publish のたび空 SnackBar | SessionEnv を nullable にする、または `display.message.isEmpty` 時 return |
| NG-2 | 戻るボタンで pop → SSH が切断されない | deactivate で restore→checkConnection→disconnect を復元 |
| NG-3 | pane 切替→キャレット追従スクロールが消える | hasInitialScrolled を 1 フィールドに統一し切替で false 化 |
| NG-4 | inactive 600ms 滞留→restore されず、resumed で force 再 fit なし | inactive/paused/hidden/detached で scheduleBackgroundRestore / onBackgroundNow を配線 |
| NG-5 | 認証エラー SnackBar の Retry がポーリング再開のみ | `onPressed: () => connection.connectAndSetup()` |

---

## 4. 総括

- テスト・静的解析・構造制約・公開 API・dispose 順序は全てパス。分解の骨格は健全。
- しかし「テストが握らない挙動」に HEAD との差分が 8 件あり、うち 3 件（NG-1 空
  SnackBar 回帰 / NG-2 deactivate の SSH 切断欠落 / NG-3 hasInitialScrolled 二重所有）
  は実利用で即影響する回帰水準。**判定 NG**。
- 推奨: NG-1〜NG-4 の修正と、`didChangeAppLifecycleState`/`deactivate`/download リスナー
  経路のテスト追加（現状 325 本ではこの差分を捕捉できない）。
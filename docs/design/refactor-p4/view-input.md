# P4 設計書 v2 — view-input（AnsiTextView 配線・キー入力・モード遷移・scrollSend・follow-scroll/history・zoom・navigation dispatch）

- 対象: `lib/screens/terminal/terminal_screen.dart` のうち view-input 領域
- 前提 HEAD: `bff0c13`（P3 完了・作業ツリー clean・`git diff HEAD -- test/` 空を実測）
- 読み取り専用で調査。行番号はすべて `git show HEAD:lib/screens/terminal/terminal_screen.dart` と実ファイルが一致することを確認済み（`git status --short` 空）。
- v1 からの改訂は `arbitration.md`（唯一の正）と `critique.md` §1/§4/§10 に準拠。

---

## v2 改訂サマリ（arbitration / critique §1・§4・§10 反映）

| # | 改訂 | 根拠 |
|---|---|---|
| V1 | **C1 `_scrollToCaret`（L4306-4330, 25行）を view-input に一本化**。`TerminalScrollFollowController` が所有し、`_viewNotifier` は `TerminalScrollbackPort` 経由で読む。session poll（`_applyUpdate`）は `viewport.scrollToCaret()` を呼ぶ。**100ms `Future.delayed` + `mounted || _isDisposed` ガードを維持** | arbitration §1 C1・§7、critique §4.4/§10-view-input |
| V2 | **C2 `_flushInputQueue`（L1243-1253, 11行）を view-input に一本化**。`_inputQueue`/`_sendKeyData` と同域（`TerminalKeySender`）。session `_onReconnectSuccess` は `input.flushInputQueue()` を呼ぶ | arbitration §1 C2、critique §10-view-input |
| V3 | **C7 選択バッファ 4 フィールド（L528-536）を `TerminalModeController` に一本化**。session poll は `captureSelectUpdate(...)`、`_applyBufferedUpdate` は `input.takeBufferedUpdate()`。**破棄判定（identity 照合）は herdr API**（`TerminalTargetIdentityValidator` port）が行う 3 段契約 | arbitration §1 C7、critique §1.1/§10-view-input |
| V4 | **C8 `_savedCommandInput`（L616）を `TerminalInputCoordinator` に一本化**。ui の「State 所有」記述は撤回し、`_showInputDialog` 起動は coordinator 経由 | arbitration §1 C8、critique §1.1/§10-view-input |
| V5 | **`_handleTwoFingerSwipe`（L3771-3807） / `_getNavigableDirections`（L3845-3890）の所有を view-input に確定**（v1 の「領域外」を撤回）。herdr 固有の番号解決（`_focusHerdrPaneDirection` / `_herdrNavigableDirections` / `_herdrHasAdjacentPane` / overlap）は **herdr navigation API を port 経由**で呼ぶ | arbitration §1 末尾（— 行）・critique §10-view-input |
| V6 | **§4 dispose を arbitration §4 のフェーズ表（P0〜P9）に落とし**、view-input の呼出位置を P5（scrollSend/keyOverlay タイマー）と P8（`_viewNotifier` は session 所有・view-input は P8 より前に停止）に明記。P9 で `scrollFollow.detach()`（`removeListener`） | arbitration §4・critique §4.2 |
| V7 | **SCC>=2 検証**を §7 検証計画に追加（`/tmp/p3-design/scc_verify_v3.py` を P4 用に移植） | arbitration §6・critique §7/§10-view-input |
| V8 | **`ScrollModeSource` / `HerdrSyncTargetPolicy` の export はシムから 1 経路のみ**（#3 に一度だけ定義し shim が `export`。他設計で再定義禁止） | arbitration §7 |
| V9 | 境界の帰属確定を反映（G5 画像/ダウンロードは session-runtime、navigation は view-input）。領域合計は **43 メンバ / 約 988 行**（v1 の 41/905 から +2/83） | arbitration §1 G5・critique §1.2 |

---

## 0. 要約

view-input は「ターミナルへの**入力**（キー/特殊キー/paste/2本指スワイプのディスパッチ）と、その入力が変える**画面モード/スクロール/ズーム/表示追従**の状態遷移」を所有する。
`_TerminalScreenState` から以下を切り出す。

1. `GlobalKey<AnsiTextViewState>` の `currentState?.…` 直接呼出（**9 箇所**）を `TerminalViewportPort` に集約する。
2. 入力モード（normal/scrollSend/select）と選択モードの更新バッファ、scrollSend 自動フィットズームを `TerminalModeController` が単一所有する。
3. scrollSend の合流ティック・合流タイマー・送信方式判定を `TerminalScrollSendController` が単一所有する。
4. キー/特殊キー/paste/入力キュー/copy-mode コマンド/`_flushInputQueue` を `TerminalKeySender` が所有する（C2）。
5. follow-scroll/ロック/オーバースクロール/深い履歴ロード/`_scrollToCaret` を `TerminalScrollFollowController` が所有する（C1）。
6. 2本指スワイプのディスパッチと `navigableDirections` を `TerminalNavigationController` が所有する（V5）。
7. 上記を調停する `TerminalInputCoordinator` を root State が1個だけ持つ（`_input`）。`_savedCommandInput` はここが所有する（C8）。
8. クロスリージョン seam は**中立ファイル**の抽象 interface として定義し、view-input ↔ session-runtime ↔ herdr の循環 import を避ける。

> 最重要制約: テスト 24 本（うち view-input 固定は §1.4）が `tester.state(find.byType(TerminalScreen))` を `dynamic` で受け、`scrollModeSourceForTesting()` / `overrideScrollSendKindForTesting()` / `hasBufferedUpdateForTesting()` / `bufferedContentForTesting()` / `loadHistoryForScrollForTesting()` / `sendSpecialKeyForTesting()` を呼ぶ。**これら 6 フックは `TerminalScreen.createState()` が返す State の公開メソッドとして残す**（§5）。

---

## 1. 現状分析（事実）

### 1.1 領域メンバ（行番号付き・実測）

`_TerminalScreenState` は `class` 開始 L460。メソッド境界を機械抽出（2 スペースインデントの宣言＋次の宣言まで）して算出。行範囲は「宣言開始行-終了行（行数）」。

#### (A) モード遷移（TERM-MODE-*）

| 行範囲 | 行数 | メンバ | inventory |
|---|---|---|---|
| 1036-1062 | 27 | `_resetTerminalMode` | TERM-MODE-RESET-001 |
| 1063-1089 | 27 | `_enterScrollSendMode` | TERM-MODE-UI-001 |
| 1090-1116 | 27 | `_enterSelectMode` | TERM-MODE-UI-002 |
| 1117-1143 | 27 | `_exitToNormalMode` | TERM-MODE-UI-003 |

#### (B) zoom / scrollSend 自動フィットズーム（TERM-ZOOM-FIT-*）

| 行範囲 | 行数 | メンバ |
|---|---|---|
| 608-612 | 5 | `double get _effectiveZoom`（`settings.zoomFactor * _zoomScale`） |
| 613 | 1 | `bool get _isZoomed` |
| 1144-1192 | 49 | `_applyScrollSendFitZoom`（TERM-ZOOM-FIT-007） |
| 1193-1199 | 7 | `_restoreScrollSendZoom`（TERM-ZOOM-FIT-008） |

#### (C) scrollSend 合流送信（TERM-SCROLL-006〜011）

| 行範囲 | 行数 | メンバ |
|---|---|---|
| 2064-2075 | 12 | `_onScrollSendTicks` |
| 2076-2085 | 10 | `_ensureScrollSendTimer`（TERM-SCROLL-007） |
| 2086-2091 | 6 | `_cancelScrollSendTimer` |
| 2092-2105 | 14 | `_discardPendingScrollTicks` |
| 2106-2164 | 59 | `_flushScrollSend`（TERM-SCROLL-010） |
| 2165-2177 | 13 | `_resolveScrollSendKind`（TERM-SCROLL-011） |
| 2178-2184 | 7 | `overrideScrollSendKindForTesting` |
| 2185-2189 | 5 | `scrollModeSourceForTesting` |
| 2190-2193 | 4 | `hasBufferedUpdateForTesting` |
| 2194-2196 | 3 | `bufferedContentForTesting` |

#### (D) history / follow-scroll / scrollToCaret（TERM-SCROLL-001〜004・TERM-LIFE-020・C1）

| 行範囲 | 行数 | メンバ |
|---|---|---|
| 2972-3042 | 71 | `_loadHistoryForScroll`（TERM-LIFE-020） |
| 3167-3185 | 19 | `_onTerminalScroll` |
| 3186-3206 | 21 | `_onTerminalScrollNotification` |
| 3207-3219 | 13 | `_handleUserScrollDrag` |
| 3220-3237 | 18 | `_scrollToBottomFollowing` |
| 3238-3250 | 13 | `_onTerminalOverscroll`（TERM-SCROLL-003） |
| 3251-3272 | 22 | `_loadDeepHistoryOnScroll` |
| **4306-4330** | **25** | **`_scrollToCaret`（C1・view-input 確定）** |

#### (E) キー送信・paste・copy-mode（C2 含む）

| 行範囲 | 行数 | メンバ |
|---|---|---|
| **1243-1253** | **11** | **`_flushInputQueue`（C2・view-input 確定）** |
| 3645-3652 | 8 | `_sendSpecialKeyWithOverlay`（TERM-INPUT-004） |
| 3653-3661 | 9 | `_sendKeyWithOverlay`（TERM-INPUT-003） |
| 3662-3684 | 23 | `_showKeyOverlay`（TERM-INPUT-007） |
| 3685-3707 | 23 | `_handleKeyInput` |
| 3708-3726 | 19 | `_handleScrollSendKeyInput`（TERM-INPUT-011） |
| 3727-3748 | 22 | `_sendScrollKey` |
| 3749-3770 | 22 | `_sendScrollText` |
| 3961-3994 | 34 | `_sendKeyData` |
| 7444-7487 | 44 | `_sendKey` |
| 7488-7501 | 14 | `_enterTmuxCopyMode`（TERM-COPY-001） |
| 7502-7520 | 19 | `_cancelTmuxCopyMode`（TERM-COPY-002） |
| 7521-7557 | 37 | `_sendSpecialKey` |
| 4229-4233 | 5 | `sendSpecialKeyForTesting` |

#### (F) 入力ダイアログ起動・カスタムキー導線（C8 含む）

| 行範囲 | 行数 | メンバ |
|---|---|---|
| 7723-7752 | 30 | `_showInputDialog`（TERM-INPUT-009・C8） |
| 7753-7803 | 51 | `_sendMultilineText` |
| 3609-3626 | 18 | `_editCustomButton` |
| 3627-3644 | 18 | `_openCustomKeysScreen` |

#### (G) フィールド（所有候補）

| 行 | 宣言 | 所属 |
|---|---|---|
| 494-495 | `KeyOverlayState _keyOverlayState` / `Timer? _keyOverlayTimer` | (E) |
| **528-536** | **`String _bufferedContent` / `bool _hasBufferedUpdate` / `PaneCaret? _bufferedCaret` / `_HerdrTargetIdentity? _bufferedTargetIdentity`（C7）** | **(A)** |
| 547 | `static const double _bottomFollowEpsilon` | (D) |
| 550/554/557/562/565 | `_isPinnedToBottom` / `_isBottomLock` / `_isUserScrollDragging` / `_isProgrammaticScroll` / `_shouldFollowBottom` | (D) |
| 539 | `bool _isLoadingDeepHistory` | (D) |
| 568/571/577 | `TerminalMode _terminalMode` / `ScrollModeSource _scrollModeSource` / `bool _isCopyModeDetected` | (A) |
| 582/585/588/591 | `int _pendingScrollTicks` / `Timer? _scrollSendTimer` / `bool _scrollSendFlushInFlight` / `String _lastPolledPaneMode` | (C) |
| 596 | `ScrollSendKind? _overrideScrollSendKindForTesting` | (C) |
| 599/604 | `double _zoomScale` / `double? _zoomBeforeScrollSend` | (B) |
| **616** | **`String _savedCommandInput`（C8）** | **(F)** |
| 619 | `final InputQueue _inputQueue` | (E) |
| 464 | `GlobalKey<AnsiTextViewState> _ansiTextViewKey` | 中立 seam（§2.1） |
| 465 | `GlobalKey<ScrollToBottomButtonState> _scrollToBottomKey` | root 所有・共有 |
| 466 | `ScrollController _terminalScrollController` | root 所有・共有（§4.4） |

#### (H) navigation dispatch（V5・v2 で view-input に確定）

| 行範囲 | 行数 | メンバ | 備考 |
|---|---|---|---|
| 3771-3807 | 37 | `_handleTwoFingerSwipe`（TERM-NAV-003） | tmux → `PaneNavigator.findAdjacentPane` + `_selectPane`（session API 経由）／herdr → `focusPaneDirection`（herdr navigation API 経由） |
| 3845-3890 | 46 | `_getNavigableDirections` | tmux → `PaneNavigator.getNavigableDirections`／herdr → herdr navigation API。反転設定 `invertPaneNavigation` 適用 |

**領域合計: 43 メンバ / 約 988 行**（BRIEF の目安 41/882 + V5 の navigation 2 メンバ 83 行）。
`_focusHerdrPaneDirection`(L3808-3844)・`_herdrNavigableDirections`(L3891-3917)・`_herdrHasAdjacentPane`(L3918-3953)・`_herdrVerticalOverlap`(L3954-3956)・`_herdrHorizontalOverlap`(L3957-3960) は **herdr navigation API として herdr 領域が所有**し、view-input は port 経由で呼ぶ（V5）。
`_hasInitialScrolled`(L542) は session-runtime 所有（L1834/4009/4049/4115/4276/5496 で書換）。view-input は触らない。

### 1.2 `GlobalKey<AnsiTextViewState>` 経由の全呼出（実測・全 9 箇所）

`grep -n '_ansiTextViewKey'` の結果。

| 行 | 呼出メソッド | 文脈 | 所属 |
|---|---|---|---|
| 464 | 宣言 `final _ansiTextViewKey = GlobalKey<AnsiTextViewState>()` | — | 中立 seam |
| 1080 | `currentState?.scrollToBottom()` | `_enterScrollSendMode`（突入時に末尾へ） | (A) |
| 3020 | `currentState?.jumpToLineFromTop(prepended)` | `_loadHistoryForScroll`（preservePosition・post-frame） | (D) |
| 3029 | `currentState?.scrollToBottom()` | `_loadHistoryForScroll`（post-frame） | (D) |
| 3100 | `currentState?.followToBottom()` | `_applyUpdate`（追従ジャンプ） | **session-runtime** |
| 3224 | `currentState?.scrollToBottom().then(...)` | `_scrollToBottomFollowing` | (D) |
| 4316 | `currentState?.scrollToCaret()` | `_scrollToCaret`（herdr caret あり・C1） | (D) |
| 4318 | `currentState?.scrollToBottom()` | `_scrollToCaret`（herdr caret なし・C1） | (D) |
| 4321 | `currentState?.scrollToCaret()` | `_scrollToCaret`（tmux・C1） | (D) |
| 3417 | `key: _ansiTextViewKey`（widget 構築） | `build` の `AnsiTextView` | root build |

BRIEF の L464/L1080/3020/3029/3100/3224/4316/4321 に加え **L6605 の `resetZoom`**（`_showTerminalMenu`・ui 領域）と L3417（widget key）も実測で存在する。

`AnsiTextViewState` の P3 公開 API のうち terminal_screen が使うのは **5 つだけ**:
`jumpToLineFromTop` / `scrollToBottom` / `followToBottom` / `scrollToCaret` / `resetZoom`。

> 注意: C1 の `_scrollToCaret`（follow controller・100ms 遅延付き）と、`TerminalViewportPort.scrollToCaret()`（AnsiTextView への Raw 即時委譲）は**別物**である。session poll が呼ぶのは前者（view-input が提供する guarded API）であり、Raw port は view-input 内部でのみ使う（§4.3）。

`AnsiTextView` の props は **18 個**（`ansi_text_view.dart` L62-116 実測）:
`text`, `paneWidth`, `paneHeight`, `onKeyInput`, `backgroundColor`, `foregroundColor`, `mode`, `zoomEnabled`, `onZoomChanged`, `verticalScrollController`, `cursorX`, `cursorY`, `caret`, `onArrowSwipe`, `onTwoFingerSwipe`, `onScrollSendTicks`, `navigableDirections`, `onTap`。**変更禁止**。

`terminal_screen.dart` が `AnsiTextView` に渡す配線（`build` L3416-3467・実測）:

| prop | 実引数 | view-input 関与 |
|---|---|---|
| `onKeyInput` | `_terminalMode == scrollSend ? _handleScrollSendKeyInput : (_canSendText ? _handleKeyInput : null)` | (E) |
| `onTap` | `_scrollToBottomKey.currentState?.show()` | root 所有 |
| `onZoomChanged` | `(scale) => setState(() => _zoomScale = scale)` | (B) |
| `verticalScrollController` | `_terminalScrollController` | root 所有 |
| `caret` | `viewData.caret` | session-runtime |
| `onArrowSwipe` | `_canSendSpecialKey ? _sendSpecialKeyWithOverlay : null` | (E) |
| `onScrollSendTicks` | `_onScrollSendTicks` | (C) |
| `onTwoFingerSwipe` | `_canFocusDirection ? _handleTwoFingerSwipe : null` | **(H)（V5）** |
| `navigableDirections` | `_canFocusDirection ? _getNavigableDirections() : null` | **(H)（V5）** |
| `mode` | `_terminalMode` | (A) |
| `NotificationListener` | `onNotification: _onTerminalScrollNotification` | (D) |

### 1.3 キー送信経路の実測（要求 (2)）

```
AnsiTextView (P3 キーエンジン) ──onKeyInput(KeyInputEvent)──▶ _handleKeyInput / _handleScrollSendKeyInput
SpecialKeysBar ──onKeyPressed────────────▶ _sendKeyWithOverlay(String)  ──▶ _sendKey(key, literal:true)
               ──onSpecialKeyPressed─────▶ _sendSpecialKeyWithOverlay(String) ──▶ _sendSpecialKey(String)
               ──onInputTap──────────────▶ _showInputDialog ──▶ _sendMultilineText(text)
```

`_sendKey`（L7444-7487）:
- ゲート: `literal ? !_canSendText : !_canSendSpecialKey` で早期 return。
- 未接続: `_inputQueue.enqueue`（**literal のみ**）＋ `isOverflow` 遷移で `context.l10n.termInputQueueFull` SnackBar ＋ `setState`。非 literal はキューせず破棄。
- 送信: `_paneWriter.sendText(paneId, key)`（literal）/ `sendKey(paneId, key)`（非 literal）。`HerdrCommandException` は `isHerdrInvalidKey` のみ SnackBar、他は静黙。
- `_boostPolling()`。

`_sendKeyData`（L3961-3994）: `sendText` のみ。未接続時は `_inputQueue.enqueue`。`catch (_)` で完全静黙（`_sendKey` と違い `isHerdrInvalidKey` 通知なし）。

`_sendSpecialKey`（L7521-7557）: `_canSendSpecialKey` ゲート。**未接続はキューしない**。`_paneWriter.sendKey`。`_sendKey` と同一の例外処理。

`_handleKeyInput`（L3685-3707）: `_canSendText` ゲート → `event.isSpecialKey && tmuxKeyName != null` なら `_sendSpecialKeyWithOverlay`、それ以外 `_sendKeyData(event.data)`（**特殊キーは `_sendKey` ではなく `_sendSpecialKey` 経路**）。

`_handleScrollSendKeyInput`（L3708-3726・TERM-INPUT-011）: `_isCopyModeDetected` 早期 return → 未接続早期 return（**キューなし**）→ `PPage`/`NPage` は `_sendScrollKey(up:)`、他は `_canSendText` ゲート後 `_sendScrollText(event.data)`。`unawaited`。**オーバーレイなし**。

`_sendScrollKey`/`_sendScrollText`（L3727-3770）: `_paneWriter.sendScroll(kind: ScrollSendKind.key, ticks:1)` / `sendText`。例外は `_recordHerdrSwitchEvent`（C12）。

`_sendMultilineText`（L7753-7803・paste）: `_can(paste:true)` ゲート。`_paneWriter.pasteText(paneId, text)`。未接続時は **複数行なら `termMultilineNeedsConnection` SnackBar、単一行なら `_inputQueue.enqueue`**。`catch` で `debugPrint`。

`_flushInputQueue`（L1243-1253・TERM-INPUT-002・**C2**）: `_inputQueue.flush()` → `_sendKeyData`。呼出元は `_onReconnectSuccess`（L1249・session-runtime）。**`_inputQueue` と `_sendKeyData` の所有者（`TerminalKeySender`）と同じ域**に置くことで、キュー操作の単一所有を保つ。

**特殊キーの composition**（要求 (2)）: tmux 特殊キー名（`Escape`/`PPage`/`NPage`/`C-c` 等）→ `PaneWriter.sendKey` が backend 別に合成する（tmux: `send-keys`、herdr: `PaneKeyMap`）。view-input 側では composition しない（`_handleKeyInput` は `KeyInputEvent.tmuxKeyName` をそのまま渡すのみ）。`AnsiKeyInputEngine`（P3）が修飾キー 4 状態から `KeyInputEvent` を合成する。

### 1.4 担当領域に固定挙動を課すテスト（実測）

| ファイル | テスト/group | 何を固定しているか（実測） | 領域 |
|---|---|---|---|
| `test/screens/terminal/terminal_screen_input_test.dart`（92行） | `TerminalScreen input (G1-6b)` 5 本 | `ESC` tap → `send-keys … Escape` で `-l` を含まない／overlay が ESC を重複表示し **1500ms で消える**（`pump(1499)` で残存→`+1ms` で消滅）／`sendKeyEvent(keyA)` → `send-keys -t %0 -l -- a`／切断時は送信ゼロ | (E) |
| `terminal_screen_scroll_send_test.dart`（591行） | P0 `TERM-SCROLL-016/018/028/019/020`、P1 `021/022/023/024`、P2 `025/026/027`＋fit-zoom 2 本 | 3 ListTile 排他選択・`Switch` 不在／scrollSend 入口で `scrollModeSourceForTesting()==none` かつ buffer 空（**C7 の `hasBufferedUpdateForTesting`/`bufferedContentForTesting` を検証**）／突入で末尾へ／`SelectionArea` 不在／ドラッグ tick→flush で `\x1b[5~`／wheel 時 `\x1b[<64;1;1M`／最大8連結／文字キー sendText／方向反転／切断破棄／copy-mode 検出中 flush 破棄／モード切替 cancel／fit zoom 適用と復元 | (A)(B)(C) |
| `terminal_screen_paste_test.dart`（103行） | `TerminalScreen paste (G1-6c)` 4 本 | `Cmd` 起動→ `paste-buffer -d -p` + `send-keys…Enter` 1 回／空文字で paste なし／base64 保持／`-p` 失敗時 `-b` フォールバックし Enter 1 回 | (F)(E) |
| `terminal_screen_follow_scroll_test.dart`（394行） | `TerminalScreen follow-scroll (Issue #87 + FAB ロック)` 9 本 | 最下部で内容伸長→`offset==maxScrollExtent`／上ドラッグで追従停止／FAB tap で復帰し追従／長押しロック→上ドラッグ解除／ロック中 tap は解除のみ／select・scrollSend 遷移でロック解除／横ドラッグは axis フィルタで無効／FAB アニメ中の追従維持 | (D) |
| `terminal_screen_history_test.dart`（215行） | `TerminalScreen history (G1-7a)` 7 本 | TERM-SCROLL-001 最下部ボタン表示／**TERM-SCROLL-004 初回 caret スクロール（C1 `_scrollToCaret`）**／`scroll mode loads deep history with capture-pane -S`／`TERM-COPY-001..002` copy-mode 突入・cancel／poll による cursor+モード自動遷移／切断時 copy-mode skip | (D)(A) |
| `terminal_screen_remaining_contracts_test.dart` | TERM-INPUT-005 / **TERM-NAV-003/007（H）** | long-press swipe→`-- Right`／**2本指→`select-pane %1`（V5 で view-input の `_handleTwoFingerSwipe`）** | (E)/(H) |
| `terminal_custom_keys_test.dart`（218行） | `TerminalScreen custom key buttons` 4 本 | long-press 削除／seed token の row0 描画／送信／4 行目 | (F) |
| `terminal_custom_keys_e2e_test.dart`（277行） | `TerminalScreen custom key buttons E2E` 5 本 | add→auto-place→表示／direct input ちょうど1回送信／delete／editor 入力可視 | (F) |
| `ansi_text_view_scroll_send_test.dart`（290行） | `AnsiTextView scrollSend display branch` 8 本 | drag 上/下 tick 符号／select で SelectionArea／2本指とスワイプの排他／normal は tick 非発火 | P3（コールバック契約） |
| `ansi_text_view_key_test.dart`（347行） | Alt/Meta 合成 29 本 | `ESC+o`/制御文字/修飾キー解除/KeyRepeat | P3 |
| `terminal_screen_contract_test.dart` | `TerminalScreen public contracts` | `ScrollModeSource.values == [none, manual, tmux]`／`TerminalMode.values == [normal, select, scrollSend]`／`TerminalScreen` コンストラクタ引数 | 公開 API |
| `terminal_screen_lifecycle_test.dart` | TERM-LIFE-022 ほか | dispose で `onReconnectSuccess`/`onDisconnectDetected` を外す／再接続時の `_flushInputQueue` 相当（C2） | root/共有 |

**いずれも `terminal_screen.dart` の公開 API（`TerminalScreen` / `ScrollModeSource` / `TerminalMode` / testing フック）以外に依存しない**。

### 1.5 境界の確定（v2・arbitration 準拠）

- **view-input に確定（V5）**: `_handleTwoFingerSwipe`(3771-3807)・`_getNavigableDirections`(3845-3890)。`AnsiTextView` の `onTwoFingerSwipe`/`navigableDirections` prop 供給元であり、`terminal_screen_remaining_contracts_test` の TERM-NAV-003/007 が固定する。herdr 固有の解決（`_focusHerdrPaneDirection`/`_herdrNavigableDirections`/`_herdrHasAdjacentPane`/overlap）は **herdr navigation API** が所有し、view-input は port 経由で呼ぶ（依存方向: view-input → port ← herdr）。
- **C1 `_scrollToCaret`**: view-input（`TerminalScrollFollowController`）。根拠: (1) 直後に `_viewNotifier`（session 所有）を読むが `TerminalScrollbackPort` 経由で読める、(2) `TERM-SCROLL-004` が初回表示でこの経路を固定、(3) `_loadDeepHistoryOnScroll` と同じ follow/scroll 系。`_viewNotifier` は port 経由。
- **C2 `_flushInputQueue`**: view-input（`TerminalKeySender`）。根拠: `_inputQueue`（L619）と `_sendKeyData`（L3961）を持つ同域であり、キュー操作の単一所有を分割しない。session は `input.flushInputQueue()` を呼ぶだけ。
- **C7 選択バッファ 4 フィールド**: view-input（`TerminalModeController`）。根拠: モード遷移（select のみ抑制）が書込・破棄を司り、`scrollModeSourceForTesting` と同一のモード状態。session poll は `captureSelectUpdate`、apply は `input.takeBufferedUpdate()`。**identity 照合（破棄判定）は herdr API**。
- **C8 `_savedCommandInput`**: view-input（`TerminalInputCoordinator`）。根拠: `_showInputDialog`（起動）と `_sendMultilineText` の往復で保持される。ui は widget（`_InputDialogContent`）のみ。
- **G5（画像/ダウンロード）は session-runtime**（`_handleFileBrowser`/`_handleImageTransfer`/`_injectImagePath`/`_ensureImageTransferListener`/`_ensureDownloadListener`）。view-input は触らない（v1 の「押付」を撤回し、arbitration §1 G5 に従う）。
- `_editCustomButton`(3609-3626)・`_openCustomKeysScreen`(3627-3644) は view-input に含める（SpecialKeysBar 配線 callback）。UI 本体（`CustomKeyButtonEditorDialog`/`CustomKeysScreen`）は ui 領域。
- `_InputDialogContent`+State（L8420-8692・ui）の `_handleKeyEvent`(L8488-8516, 29行) は **ui 領域**（view-input に同名メンバは存在しない・実測）。view-input は `_showInputDialog`（起動）のみ所有。
- `_hasInitialScrolled`(L542)・`_directInputEnabled`(L625) は view-input 外（session-runtime / root）。
- `_lastPolledPaneMode`(L591) は poll（session）が書き `_flushScrollSend`（view-input）が読む → 所有を `TerminalScrollSendController` に一本化し `observePaneMode(String)` 経由。

### 1.6 リソース所有権インベントリ（HEAD）

| リソース | 生成 | 破棄 | 現所有者 | 目標所有者 |
|---|---|---|---|---|
| `GlobalKey<AnsiTextViewState> _ansiTextViewKey` | L464 field | 不要（GlobalKey） | State | root（`TerminalViewportPort` へ注入） |
| `GlobalKey<ScrollToBottomButtonState> _scrollToBottomKey` | L465 | 不要 | State | root（callback で共有） |
| `ScrollController _terminalScrollController` | L466 | `dispose` L3347-3348（`removeListener`+`dispose`） | State | root（follow controller は listener 登録/解除のみ） |
| `Listener` `_onTerminalScroll` | `initState` L809 | `dispose` L3347 | State | view-input（`scrollFollow.attach/detach`） |
| `InputQueue _inputQueue` | L619 | なし（純データ） | State | `TerminalKeySender` |
| `Timer? _scrollSendTimer` | L2079 | `dispose` L3316-3317／`_cancelScrollSendTimer` | State | `TerminalScrollSendController` |
| `Timer? _keyOverlayTimer` | L3679 | `dispose` L3325-3326 | State | `TerminalKeySender` |
| `KeyOverlayState _keyOverlayState` | L494 | `dispose` L3327 | State | `TerminalKeySender` |
| `_zoomBeforeScrollSend` | 1144 内 | モード離脱で復元 | State | `TerminalModeController` |
| `_savedCommandInput` | L616 | なし | State | `TerminalInputCoordinator`（C8） |
| `_pendingScrollTicks`/`_scrollSendFlushInFlight`/`_lastPolledPaneMode` | L582/588/591 | なし | State | `TerminalScrollSendController` |

`dispose`（L3293-3350）の実測順序: `_isDisposed=true` → bridge reset → observer remove → Wakelock → subscriptions → `_pollTimer`/`_treeRefreshTimer` → **`_scrollSendTimer` cancel（L3316）** → **`_keyOverlayTimer` cancel + `_keyOverlayState.dispose`（L3325-3327）** → autoResize/backgroundRestore timers → notifiers dispose → **`_terminalScrollController.removeListener` + dispose（L3347-3348）** → `super.dispose()`。§4.4 のフェーズ表と一致。

---

## 2. 目標構成

### 2.1 依存の方向（循環 import 禁止・arbitration §6）

```
                 ┌──────────────────────────────────────────────┐
                 │ 中立ファイル（abstract interface / value type） │
                 │  terminal_input_ports.dart (send/caps/scrollback/nav/host/validator)
                 │  terminal_viewport_port.dart (raw AnsiTextView seam)
                 │  terminal_input_mode.dart (ScrollModeSource/TerminalBufferedUpdate)
                 └───▲───────────────▲───────────────▲──────────┘
                     │               │               │
   view-input ───────┘               │               └─────── session-runtime
   (input/*.dart)                    │                        (root State が port を実装)
                     │               │
                     └── herdr navigation API（port 実装）/ ui（resetZoom のみ）
```

- 依存の向き（arbitration §6）: `ui（表示・純関数） ← session-runtime → ports ← view-input`、`herdr → ports / ui(純関数) / herdr 内部`。
- view-input は session-runtime / herdr の**具象型を import しない**（port 経由）。session-runtime / herdr / ui は view-input の具象（`TerminalInputCoordinator`）を参照しない（port と callback 経由）。
- `*_env.dart` は相互 import 禁止。`terminal_screen.dart`（シム）への**逆 import（新ファイル → シム）を禁止**（arbitration §6）。
- **`terminal_screen.dart` はシム**（`TerminalScreen` 本体・enum export・`DownloadSnackBarDisplay` のみ。ロジックなし）。State は root ファイルに移し、`TerminalScreen.createState()` がそれを返す。**State は public 化**（P3 `AnsiTextViewState` と同方式）。

### 2.2 新規/変更ファイル一覧（view-input 提案分）

| # | パス | 責務（1文） | 推定行数 | 公開シンボル | 依存先 |
|---|---|---|---|---|---|
| 1 | `lib/screens/terminal/input/terminal_viewport_port.dart` | `GlobalKey<AnsiTextViewState>` を唯一の窓口として viewport 操作を公開する中立 seam | ~80 | `TerminalViewportPort` | P3 `ansi_text_view.dart` |
| 2 | `lib/screens/terminal/input/terminal_input_ports.dart` | view-input が外領域から受ける入力を抽象化する中立 interface 群 | ~190 | `TerminalPaneSendPort` / `TerminalInputCapabilities` / `TerminalScrollbackPort` / `TerminalNavigationPort` / `TerminalTargetIdentityValidator` / `TerminalInputHost` | backend domain, `pane_frame_reader.dart`, `pane_navigator.dart` |
| 3 | `lib/screens/terminal/input/terminal_input_mode.dart` | 入力モード enum と選択モード更新バッファの値型（`ScrollModeSource` の唯一の定義） | ~60 | `ScrollModeSource`（移設）/ `TerminalBufferedUpdate` | P3 `TerminalMode` |
| 4 | `lib/screens/terminal/input/terminal_mode_controller.dart` | モード・scrollModeSource・copy-mode 検出・選択更新バッファ・fit zoom の単一所有者 | ~250 | `TerminalModeController` | #3, #2 |
| 5 | `lib/screens/terminal/input/terminal_scroll_send_controller.dart` | scrollSend の累積ティック・合流タイマー・送信方式判定の単一所有者 | ~180 | `TerminalScrollSendController` | #2 |
| 6 | `lib/screens/terminal/input/terminal_key_sender.dart` | キー/特殊キー/paste/copy-mode コマンド・入力キュー・`_flushInputQueue`・キーオーバーレイの単一所有者 | ~340 | `TerminalKeySender` | #1, #2 |
| 7 | `lib/screens/terminal/input/terminal_scroll_follow_controller.dart` | follow-scroll/ロック/オーバースクロール/深い履歴ロード/`scrollToCaret`(C1) の単一所有者 | ~250 | `TerminalScrollFollowController` | #1, #2 |
| 8 | `lib/screens/terminal/input/terminal_navigation_controller.dart` | 2本指スワイプのディスパッチと `navigableDirections` の計算（V5） | ~150 | `TerminalNavigationController` | #2 |
| 9 | `lib/screens/terminal/input/terminal_input_coordinator.dart` | AnsiTextView/SpecialKeysBar の callback とモード遷移を調停し外領域へ mode/API を提供する facade（C8） | ~270 | `TerminalInputCoordinator` | #1〜#8 |

すべて **500 行未満**（推定最大 #6 の 340 行）。合計 ≈ 1,770 行。
`#3` は `ScrollModeSource` の**唯一の定義**であり、シムが `export` する（V8）。`HerdrSyncTargetPolicy` は shim に存続し、他設計で再定義しない（V8）。

### 2.3 各ファイルの内部設計

#### #1 `TerminalViewportPort`
```dart
class TerminalViewportPort {
  TerminalViewportPort(this._key);
  final GlobalKey<AnsiTextViewState> _key;
  AnsiTextViewState? get _s => _key.currentState;
  Future<void> scrollToBottom() => _s?.scrollToBottom() ?? Future.value();
  void jumpToLineFromTop(int line) => _s?.jumpToLineFromTop(line);
  void followToBottom() => _s?.followToBottom();
  void scrollToCaret() => _s?.scrollToCaret();   // Raw（即時）。内部専用
  void resetZoom() => _s?.resetZoom();
  GlobalKey<AnsiTextViewState> get widgetKey => _key; // AnsiTextView(key:) 用
}
```
- HEAD の `?.` null 許容を完全維持。ui の `resetZoom`(L6605) と session-runtime の `followToBottom`(L3100) も port を受け取る。
- **C1 との区別**: ここの `scrollToCaret()` は即時委譲（100ms/guard なし）。C1 の guarded 版は #7 が提供する（§4.3）。

#### #2 `terminal_input_ports.dart`（中立 interface）
```dart
/// ペイン送信の窓口（session-runtime が実装）。
abstract interface class TerminalPaneSendPort {
  PaneWriter? get paneWriter;
  String? get currentPaneId;
  bool get isConnected;
  void boostPolling();
  void recordHerdrSwitchEvent(String event);
}

/// `_can(...)` 能力判定（root/session-runtime が実装）。
abstract interface class TerminalInputCapabilities {
  bool get canSendText;
  bool get canSendSpecialKey;
  bool get canFocusDirection;
  bool get canCopyMode;
  bool get canPaste;
  bool get canWheelSend;
}

/// 深い履歴読み取り（session-runtime が実装。`_viewNotifier`/reader/identity を所有）。
abstract interface class TerminalScrollbackPort {
  bool get canRead;
  Object? captureTargetIdentity();
  int get scrollbackLimit;
  Future<String?> readScrollbackContent();
  String get displayedContent;              // _viewNotifier.value.content
  void setDisplayedContent(String content); // _viewNotifier.value = copyWith(content:)
}

/// herdr API による表示対象同一性の照合（C7 破棄判定・C1 herdr caret 判定）。
abstract interface class TerminalTargetIdentityValidator {
  bool isCurrent(Object? identity);
}

/// tmux/herdr の pane ナビゲーション（session-runtime / herdr が実装・V5）。
abstract interface class TerminalNavigationPort {
  /// tmux: PaneNavigator で隣接 pane を解決し select する。
  Future<void> selectAdjacentPane(SwipeDirection direction, {required bool invert});
  /// tmux: 隣接方向マップ。herdr: herdr navigation API の結果。
  Map<SwipeDirection, bool>? navigableDirections({required bool invert});
  /// herdr: 方向フォーカス（`pane focus --direction`）。tmux は no-op。
  Future<void> focusPaneDirection(SwipeDirection direction);
  bool get isHerdr;
}

/// root への副作用通知（context を協調オブジェクトが保持しないため callback 化）。
abstract interface class TerminalInputHost {
  bool get isMounted;
  bool get isDisposed;
  void markNeedsBuild();                     // setState(() {}) 相当
  void showScrollToBottomButton();           // _scrollToBottomKey.currentState?.show()
  void notifyInputQueueFull();               // termInputQueueFull SnackBar
  void notifyMultilineNeedsConnection();     // termMultilineNeedsConnection SnackBar
}
```
- `_HerdrTargetIdentity` は view-input に公開しない（`Object?` の不透明トークン）。
- `SwipeDirection` は P3 `pane_navigator.dart` の公開型。

#### #4 `TerminalModeController`（C7）
- 所有: `_terminalMode` / `_scrollModeSource` / `_isCopyModeDetected` / `_bufferedContent` / `_hasBufferedUpdate` / `_bufferedCaret` / `_bufferedTargetIdentity` / `_zoomScale` / `_zoomBeforeScrollSend`。
- 公開: `mode`, `source`, `isCopyModeDetected`, `hasBufferedUpdate`, `bufferedContent`, `zoomScale`, `effectiveZoom`, `isZoomed`。
- 変換（state のみ・副作用なし）: `applyNormal()`, `applyScrollSend()`, `applySelectManual()`, `applySelectTmux({required bool fromScrollSend})`, `applyTmuxEnded()`。各々 HEAD の `setState` 内代入集合と厳密一致。`applySelectTmux` は HEAD 同様 buffer を触らない。
- **buffer（C7 3 段契約）**:
  1. `captureSelectUpdate({required String content, PaneCaret? caret, Object? targetIdentity})`（session poll が呼ぶ）。
  2. `TerminalBufferedUpdate? takeBufferedUpdate()` が **`validator.isCurrent(token)` を呼び、不一致なら破棄して null を返す**（破棄判定は herdr API = `TerminalTargetIdentityValidator`）。
  3. `clearBuffer()`（モード遷移）。
- zoom: `onZoomChanged(scale)`, `applyScrollSendFitZoom()`, `restoreScrollSendZoom()`, `resetZoomScale()`。
- `dispose`: なし（Timer/Listener なし）。

#### #5 `TerminalScrollSendController`
- 所有: `_pendingScrollTicks` / `_scrollSendTimer` / `_scrollSendFlushInFlight` / `_lastPolledPaneMode` / `_overrideScrollSendKindForTesting`。
- 公開: `onTicks(int)`, `flush()`（`Future<void>`）, `discard()`, `observePaneMode(String)`, `setKindOverride(ScrollSendKind?)`, `resolveKind()`。
- `flush()` のガード・クランプ（`abs().clamp(1,8)`）・超過保持・`_boostPolling` は HEAD 同一。I/O は `TerminalPaneSendPort`。
- `dispose`: `cancel()`。周期 `Duration(milliseconds:100)` 固定。

#### #6 `TerminalKeySender`（C2）
- 所有: `_inputQueue` / `_keyOverlayState` / `_keyOverlayTimer`。
- 公開: `sendKey`, `sendKeyData`, `sendSpecialKey`, `sendKeyWithOverlay`, `sendSpecialKeyWithOverlay`, `handleKeyInput`, `handleScrollSendKeyInput`, `sendScrollKey`, `sendScrollText`, `sendMultilineText`, **`flushInputQueue()`（C2）**, `enterTmuxCopyMode`, `cancelTmuxCopyMode`, `showKeyOverlay`, `dispose()`。
- `flushInputQueue()` は `_inputQueue.flush()` → `sendKeyData`（HEAD L1243-1253 と同一）。session `_onReconnectSuccess` から呼ばれる公開 API。
- **例外処理の HEAD 相違を厳守**: `sendKeyData` は完全静黙、`sendKey`/`sendSpecialKey` は `isHerdrInvalidKey` のみ通知。
- `enterTmuxCopyMode`/`cancelTmuxCopyMode` は `tmuxFacade` 直叩き（`ref.read(tmuxProvider.notifier).currentTarget`）を維持。

#### #7 `TerminalScrollFollowController`（C1）
- 所有: `_isPinnedToBottom` / `_isBottomLock` / `_isUserScrollDragging` / `_isProgrammaticScroll` / `_isLoadingDeepHistory` / `_bottomFollowEpsilon`。
- 公開: `isPinnedToBottom`, `isBottomLock`, `isUserScrollDragging`, `shouldFollowBottom`, `toggleBottomLock(bool)`, `resetFollowFlags()`, `onScroll()`, `onScrollNotification(ScrollNotification)`, `scrollToBottomFollowing()`, `loadDeepHistoryOnScroll()`, `loadHistoryForScroll({preservePosition})`, **`scrollToCaret()`（C1）**。
- **`scrollToCaret()`（C1）** は HEAD L4306-4330 をそのまま移設:
  ```dart
  void scrollToCaret() {
    Future.delayed(const Duration(milliseconds: 100), () {   // ← 100ms 固定（不変）
      if (!host.isMounted || host.isDisposed) return;         // ← mounted || _isDisposed ガード維持
      if (nav.isHerdr) {
        final caret = scrollback.displayedCaret;              // _viewNotifier.value.caret（port 経由）
        if (caret != null && caret.visible && caret.hasPosition) {
          viewport.scrollToCaret();                           // Raw AnsiTextView
        } else {
          viewport.scrollToBottom();
        }
      } else {
        viewport.scrollToCaret();
      }
    });
  }
  ```
  `_viewNotifier`（session 所有）は `TerminalScrollbackPort` 経由で読む。session poll は `input.scrollToCaret()`（guarded 版）を呼ぶ。
- `loadHistoryForScroll` は `TerminalScrollbackPort` から内容を取得し、HEAD の行数プリペンド計算 + `postFrameCallback` + `jumpToLineFromTop`/`scrollToBottom` を `TerminalViewportPort` 経由で行う（§1.2 L3020/3029）。mode ガード（`mode != select` で破棄）は controller が参照。
- 登録/解除: root が `attach(scrollController)`（`addListener(onScroll)`）、P9 で `detach()`（`removeListener`）。

#### #8 `TerminalNavigationController`（V5）
- `handleTwoFingerSwipe(SwipeDirection direction)`: `caps.canFocusDirection` 偽なら return。`nav.isHerdr` なら `nav.focusPaneDirection(direction)`（herdr API）、そうでなければ `nav.selectAdjacentPane(direction, invert: settings.invertPaneNavigation)`（session API）。HEAD L3771-3807 の分岐を port 越しに維持。
- `navigableDirections()`: `caps.canFocusDirection` 偽なら null。`nav.navigableDirections(invert: settings.invertPaneNavigation)` を返す。HEAD L3845-3890 の反転マップ生成を port 側（tmux: PaneNavigator / herdr: herdr API）へ委譲。
- 所有 state なし（純ディスパッチャ）。`dispose` なし。

#### #9 `TerminalInputCoordinator`（C8）
- root が保持する唯一の view-input オブジェクト。#4〜#8 を内包（`late final`）し、widget callback と session/ui 向け API を公開する。`_savedCommandInput` を所有（C8）。
- モード遷移（HEAD L1036-1143 の副作用順を厳守）:
  - `enterScrollSendMode()`: `scrollSend.discard()` → `mode.applyScrollSendFitZoom()` → `mode.applyScrollSend()` → `scrollFollow.resetFollowFlags()` → `host.markNeedsBuild()` → `viewport.scrollToBottom()`。
  - `enterSelectMode()`: `scrollSend.discard()` → `mode.restoreScrollSendZoom()` → `mode.applySelectManual()` → `scrollFollow.resetFollowFlags()` → `host.markNeedsBuild()` → `keySender.enterTmuxCopyMode()`（`getCanCopyMode()` 真時）→ `scrollFollow.loadHistoryForScroll()`。
  - `exitToNormalMode()`: `scrollSend.discard()` → `mode.restoreScrollSendZoom()` → select 由来なら `keySender.cancelTmuxCopyMode()` + `onApplyBuffered()` → `mode.applyNormal()` → `host.markNeedsBuild()`。
  - `resetTerminalMode()`: 同型（TERM-MODE-RESET-001）。
- copy-mode 自動検出（session poll から呼ばれる・HEAD L2345-2390）:
  - `handleTmuxCopyModeDetected({required bool fromScrollSend})`: `mode.applySelectTmux(fromScrollSend:)` → `scrollFollow.resetFollowFlags()` → `fromScrollSend` なら `scrollSend.discard()` + `mode.restoreScrollSendZoom()` + `recordHerdrSwitchEvent('copy-mode auto transition from scrollSend')` → `markNeedsBuild()`。
  - `handleTmuxCopyModeEnded()`: `mode.applyTmuxEnded()` → `markNeedsBuild()` → `onApplyBuffered()`。
  - `observePaneMode(String)` を `scrollSend` へ転送。
- **C1/C2 の session 向け API**: `scrollToCaret()`（#7 へ転送・guarded）、`flushInputQueue()`（#6 へ転送）。`captureSelectUpdate(...)` / `takeBufferedUpdate()`（#4 へ転送・C7）。
- 入力ダイアログ: `showInputDialog(BuildContext context)`（`_savedCommandInput` 所有、`showModalBottomSheet` は引数 context を使用。協調オブジェクトは context を保持しない）。ui の `buildInputDialogContentForTesting` ファクトリを再利用。
- テストフック転送元: `scrollModeSourceForTesting`, `hasBufferedUpdateForTesting`, `bufferedContentForTesting`, `overrideScrollSendKindForTesting`, `loadHistoryForScrollForTesting`, `sendSpecialKeyForTesting`（root State が同名で転送）。

---

## 3. 移動マッピング

### 3.1 モード遷移（A）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_resetTerminalMode` (1036-1062) | `TerminalInputCoordinator.resetTerminalMode`（副作用順維持） | 改造（協調） |
| `_enterScrollSendMode` (1063-1089) | 同 `enterScrollSendMode` | 改造 |
| `_enterSelectMode` (1090-1116) | 同 `enterSelectMode` | 改造 |
| `_exitToNormalMode` (1117-1143) | 同 `exitToNormalMode` | 改造 |
| **buffer 4 フィールド (528-536)** | **`TerminalModeController`（C7）** | 移動 |
| `_terminalMode`/`_scrollModeSource`/`_isCopyModeDetected` (568/571/577) | `TerminalModeController` | 移動 |
| `_applyBufferedUpdate` (2953-2971) | **session-runtime**（`input.takeBufferedUpdate()` を呼び、非 null なら `_scheduleUpdate`）。破棄判定は herdr API（C7） | 残置＋改造 |

### 3.2 zoom（B）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_zoomScale`(599)/`_zoomBeforeScrollSend`(604) | `TerminalModeController` | 移動 |
| `_effectiveZoom`(608-612)/`_isZoomed`(613) | 同 | 移動 |
| `_applyScrollSendFitZoom`(1144-1192) | 同 `applyScrollSendFitZoom` | 移動 |
| `_restoreScrollSendZoom`(1193-1199) | 同 `restoreScrollSendZoom` | 移動 |

ui の読取（breadcrumb L4547/L4556・menu L6585-6607）は `input` の getter へ置換。

### 3.3 scrollSend（C）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_onScrollSendTicks`(2064) / `_ensureScrollSendTimer`(2076) / `_cancelScrollSendTimer`(2086) / `_discardPendingScrollTicks`(2092) / `_flushScrollSend`(2106) / `_resolveScrollSendKind`(2165) | `TerminalScrollSendController` | 移動（I/O は port 化） |
| `overrideScrollSendKindForTesting`(2178) | 同 controller + root 転送 | 移設 |
| `_pendingScrollTicks`/`_scrollSendTimer`/`_scrollSendFlushInFlight`/`_lastPolledPaneMode`/`_overrideScrollSendKindForTesting` | 同 controller | 移動 |

### 3.4 history/follow/scrollToCaret（D・C1）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_loadHistoryForScroll`(2972-3042) | `TerminalScrollFollowController`（read/表示は `TerminalScrollbackPort`） | 改造 |
| `_onTerminalScroll`(3167) / `_onTerminalScrollNotification`(3186) / `_handleUserScrollDrag`(3207) / `_scrollToBottomFollowing`(3220) / `_onTerminalOverscroll`(3238) / `_loadDeepHistoryOnScroll`(3251) | 同 controller | 移動 |
| **`_scrollToCaret`(4306-4330)** | **同 controller（C1・100ms+guard 維持）** | 移動 |
| `_isPinnedToBottom` ほか 4 フラグ + `_bottomFollowEpsilon` + `_isLoadingDeepHistory` | 同 controller | 移動 |
| `_hasInitialScrolled`(542) | **session-runtime** | 残置 |
| `_applyUpdate`(3074-3106) の follow 分岐 | session-runtime（`input.scrollToCaret()`・`viewport.followToBottom()` を参照） | 残置 |

### 3.5 キー/paste（E・C2）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_sendKeyData`(3961) / `_sendKey`(7444) / `_sendSpecialKey`(7521) / `_sendSpecialKeyWithOverlay`(3645) / `_sendKeyWithOverlay`(3653) / `_showKeyOverlay`(3662) / `_handleKeyInput`(3685) / `_handleScrollSendKeyInput`(3708) / `_sendScrollKey`(3727) / `_sendScrollText`(3749) / `_enterTmuxCopyMode`(7488) / `_cancelTmuxCopyMode`(7502) | `TerminalKeySender` | 移動（ゲート/送信を port 化） |
| **`_flushInputQueue`(1243-1253)** | **`TerminalKeySender`（C2）** | 移動 |
| `_inputQueue`(619) / `_keyOverlayState`(494) / `_keyOverlayTimer`(495) | 同 sender | 移動 |
| `sendSpecialKeyForTesting`(4229) | 同 sender + root 転送 | 移設 |

### 3.6 入力ダイアログ・カスタムキー（F・C8）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_showInputDialog`(7723-7752) | `TerminalInputCoordinator`（context 引数化） | 改造 |
| `_sendMultilineText`(7753-7803) | `TerminalKeySender` | 移動 |
| **`_savedCommandInput`(616)** | **`TerminalInputCoordinator`（C8）** | 移動 |
| `_editCustomButton`(3609) / `_openCustomKeysScreen`(3627) | `TerminalInputCoordinator`（UI 本体は ui） | 移動 |
| `_InputDialogContent`(8420-8692) | ui（変更なし） | 残置 |

### 3.7 navigation dispatch（H・V5）
| 既存（行） | 移動先 | 種別 |
|---|---|---|
| `_handleTwoFingerSwipe`(3771-3807) | `TerminalNavigationController` | 改造（port 分岐） |
| `_getNavigableDirections`(3845-3890) | 同 controller | 改造（port 分岐） |
| `_focusHerdrPaneDirection`(3808-3844) / `_herdrNavigableDirections`(3891-3917) / `_herdrHasAdjacentPane`(3918-3953) / `_herdrVerticalOverlap`(3954-3956) / `_herdrHorizontalOverlap`(3957-3960) | **herdr navigation API**（herdr 領域）。view-input は port 経由で呼ぶ | 移設（他領域） |

### 3.8 領域外（明示的に触らない・arbitration 準拠）
- G5: `_handleFileBrowser`(7638-7651), `_handleImageTransfer`(7652-7691), `_injectImagePath`(7692-7722), `_ensureImageTransferListener`(7579-7637), `_ensureDownloadListener`(7558-7578) → **session-runtime**。
- `_handleKeyEvent`(8488-8516) / `_InputDialogContent` 全体 → **ui**。
- `_hasInitialScrolled`(542) / `_directInputEnabled`(625) → session-runtime / root。

---

## 4. インターフェース契約（最重要）

### 4.1 view-input が所有する state（単一所有者）

| state | 所有者 | 初期値 | 書込者 | 読取者（自領域外） | 破棄 |
|---|---|---|---|---|---|
| `mode` (TerminalMode) | `TerminalModeController` | `normal` | coordinator 経由のみ | session-runtime(poll/`_applyUpdate`)・ui(build/breadcrumb/menu) | 不要 |
| `source` (ScrollModeSource) | 同 | `none` | 同 | session-runtime(poll) | 不要 |
| `isCopyModeDetected` | 同 | `false` | 同 | session-runtime(poll)・scrollSend/keySender | 不要 |
| **select 更新バッファ 4（C7）** | 同 | 空/false | session poll が `captureSelectUpdate` | — | 不要 |
| `zoomScale` | 同 | `1.0` | AnsiTextView `onZoomChanged` | ui(breadcrumb) | 不要 |
| `zoomBeforeScrollSend` | 同 | `null` | mode transitions | — | 不要 |
| `pendingScrollTicks`/`scrollSendTimer`/`flushInFlight`/`observedPaneMode`/`kindOverride` | `TerminalScrollSendController` | `0`/null/false/`''`/null | coordinator・session(`observePaneMode`) | — | P5: timer cancel |
| `inputQueue`/`keyOverlayState`/`keyOverlayTimer` | `TerminalKeySender` | 空/新規/null | sender 内・`flushInputQueue` | — | P5: timer cancel + notifier dispose |
| follow/lock 4 フラグ + `isLoadingDeepHistory` | `TerminalScrollFollowController` | true/false/…/false | coordinator・root build(FAB) | session(`_applyUpdate`)・ui(FAB/breadcrumb) | P9: listener 解除 |
| `savedCommandInput`（C8） | `TerminalInputCoordinator` | `''` | coordinator | — | 不要 |
| navigation（state なし） | `TerminalNavigationController` | — | — | — | 不要 |

**二重所有は提案しない**:
- `_lastPolledPaneMode`: poll が値生成、所有は scrollSend controller（`observePaneMode`）。
- **選択バッファ（C7）**: session poll は `captureSelectUpdate(content, caret, targetIdentity)` で**値を渡すが所有は mode controller**。apply は session の `_applyBufferedUpdate` が `input.takeBufferedUpdate()` を呼び、**identity 照合（破棄判定）は herdr API（`TerminalTargetIdentityValidator`）** が行う。stale なら `null`（session は `_scheduleUpdate` を呼ばない）。
- `_hasInitialScrolled`: session-runtime 所有。view-input は触らない。
- C9 `_pendingTargetIdentity`/`_pendingCaret`: **root State フィールド**（値生成は herdr API）。view-input は触らない。

### 4.2 他領域から受ける props / callback（view-input の入力）

| 受け手 | 名前 | 型 | 提供元（領域） | 用途 |
|---|---|---|---|---|
| #2 port | `TerminalPaneSendPort` | interface | session-runtime（root が実装） | `_paneWriter`/`paneId`/接続/`_boostPolling`/`_recordHerdrSwitchEvent` |
| #2 port | `TerminalInputCapabilities` | interface | session-runtime | `_canSendText` 等 6 getter |
| #2 port | `TerminalScrollbackPort` | interface | session-runtime | `_loadHistoryForScroll`/`_scrollToCaret` の reader/`_viewNotifier`（C1） |
| #2 port | `TerminalTargetIdentityValidator` | interface | herdr API | 選択バッファ破棄判定（C7）・caret 判定（C1） |
| #2 port | `TerminalNavigationPort` | interface | session-runtime（tmux）/ herdr（herdr） | 2本指スワイプ・navigableDirections（V5） |
| #2 port | `TerminalInputHost` | interface | root | `markNeedsBuild`/FAB 表示/2 種 SnackBar/`mounted`/`_isDisposed` |
| #9 | `onApplyBuffered` | `void Function()` | session-runtime | `_applyBufferedUpdate` 起動 |
| #9 | `getCanCopyMode` | `bool Function()` | session-runtime（`_canCopyMode`） | select 突入時の copy-mode |
| #9 | `ref` | `WidgetRef` | root | settings/ssh/tmux 読取 |
| #9 | `BuildContext` | 引数 | root | `showModalBottomSheet`（保持しない） |
| #7 | `ScrollController` | root 所有 | root | `addListener`/`removeListener` |
| #4 | `settingsProvider` | — | P1 | `zoomFactor`/`isAutoFit`/`scrollSendInput`/`autoFitZoomOnScrollSend`/`invertPaneNavigation` |

### 4.3 他領域へ提供する API（view-input の出力）

| 提供先 | API | 用途 |
|---|---|---|
| root `build` | `input.mode`, `input.zoomScale`/`isZoomed`, `input.keyInputCallbackFor(caps)`, `input.onScrollSendTicks`, `input.scrollFollow.onScrollNotification`, `input.scrollFollow.isBottomLock`, `input.scrollFollow.toggleBottomLock`, `input.handleTwoFingerSwipe`, `input.navigableDirections()` | `AnsiTextView`/`FAB` 配線（V5） |
| root `build` | `input.sendKeyWithOverlay`, `input.sendSpecialKeyWithOverlay`, `input.showInputDialog(context)`, `input.editCustomButton`, `input.openCustomKeysScreen` | `SpecialKeysBar` 配線 |
| ui（menu/indicator/breadcrumb） | `input.enterScrollSendMode()`, `input.enterSelectMode()`, `input.exitToNormalMode()`, `input.mode`, `input.isZoomed`, `input.effectiveZoom`, `viewport.resetZoom()` | メニュー 3 択・zoom リセット・インジケータ close |
| **session-runtime（C1）** | **`input.scrollToCaret()`（guarded・100ms+`mounted‖_isDisposed`）** | `_applyUpdate` の初回表示・caret 追従（`viewport.scrollToCaret()` は Raw 即時で内部専用） |
| **session-runtime（C2）** | **`input.flushInputQueue()`** | `_onReconnectSuccess`（HEAD L1249） |
| session-runtime（C7） | `input.captureSelectUpdate(content:, caret:, targetIdentity:)`, `input.takeBufferedUpdate()` | poll のバッファリング / apply 時の破棄判定（herdr API） |
| session-runtime | `input.resetTerminalMode()`, `input.mode`, `input.source`, `input.isCopyModeDetected`, `input.observePaneMode()`, `input.handleTmuxCopyModeDetected()`, `input.handleTmuxCopyModeEnded()` | 再接続/接続/pane 切替/poll 自動遷移 |
| session-runtime / ui | `TerminalViewportPort`（Raw: `followToBottom`/`resetZoom`/`jumpToLineFromTop`/`scrollToBottom`/`scrollToCaret`） | `GlobalKey` 直接呼出の置換先 |
| 全領域 | `input.scrollFollow.loadHistoryForScrollForTesting()` 等 6 testing フック（root 転送） | テスト契約維持 |

> 命名の注意: `viewport.scrollToCaret()`（Raw・即時）と `input.scrollToCaret()`（C1・guarded）は別物。**session poll が使うのは `input.scrollToCaret()`**。ui の `resetZoom` は `viewport.resetZoom()`。

### 4.4 `dispose` フェーズ表（arbitration §4 準拠・root State が統括）

| フェーズ | 内容（HEAD L3293-3345 の順序を維持） | view-input の関与 |
|---|---|---|
| P0 | `_isDisposed = true` | — （以降 view-input の遅延コールバックは `host.isDisposed` で no-op。C1 の 100ms 遅延も含む） |
| P1 | herdr: `bridge.reset()`（先頭） | — |
| P2 | `WidgetsBinding.removeObserver` / Wakelock 解除 | — |
| P3 | ProviderSubscription 群（4 本 + transfer 2 本） | — |
| P4 | poll/tree タイマー停止（session） | — |
| **P5** | **scrollSend / keyOverlay タイマー（view-input）** | **`input.disposeTimers()` → `scrollSend.dispose()`（`_scrollSendTimer` cancel）+ `keySender.dispose()`（`_keyOverlayTimer` cancel + `_keyOverlayState.dispose`）** |
| P6 | autoResize / background タイマー（session） | — |
| P7 | herdr cache / identity / resolved target の null 化 | — |
| **P8** | notifier 群の dispose（**順序厳守**: `_viewNotifier` → `_herdrDisplayNotifier` → `_herdrPaneIndicatorNotifier` → `_latencyNotifier`） | **view-input は P8 より前に停止済み。`_viewNotifier`（session 所有）を P8 以降に読まない**（`TerminalScrollbackPort`/`TerminalTargetIdentityValidator` は P5 以降解体） |
| **P9** | root の `ScrollController` dispose → `super.dispose()` | **`scrollFollow.detach()`（`removeListener(_onTerminalScroll)`）→ root が `_terminalScrollController.dispose()`**（HEAD L3347-3348 と同位置） |

- `_viewNotifier` は **session-runtime 所有**であり view-input は所有も破棄もしない（P8 の先頭で session が dispose）。view-input の controller は P5 で timer を止め、P9 で listener を外すのみ。
- C1 の `_scrollToCaret` は `Future.delayed(100ms)` 後に必ず `host.isMounted || host.isDisposed` を再検査する（P0 以降は no-op）。**100ms リテラルは不変**（arbitration §7）。
- `KeyOverlayState.dispose()` は P5（HEAD L3325-3327 と同位置）。

---

## 5. 公開 API 維持表

| シンボル | 維持方法 | 根拠（実測依存） |
|---|---|---|
| `enum ScrollModeSource { none, manual, tmux }` | **#3 に一度だけ定義**し、シムから `export`（V8）。他設計で再定義禁止 | `terminal_screen_contract_test.dart` の値順序テスト |
| `enum HerdrSyncTargetPolicy` | シムに存続し、シムから 1 経路のみ `export`（V8）。他設計で再定義禁止 | BRIEF 維持必須 |
| `enum TerminalMode { normal, select, scrollSend }` | P3 `ansi_terminal_model.dart`（変更禁止） | 同テスト・`ansi_text_view.dart` が export |
| `class TerminalScreen`（コンストラクタ 12 引数） | シムに本体存続 | `terminal_screen_contract_test.dart`・`main.dart` L130・3 lib 呼出元 |
| `createState()` が返す State の testing フック 6 | root State の公開メソッドとして転送 | `dynamic state = tester.state<…>` で呼ぶ（§1.4） |
| `_TerminalScreenState`（private） | `TerminalScreenState`（public）へ改名（P3 `AnsiTextViewState` と同方式） | `@visibleForTesting` は P3 で不採用・素の public 化 |
| `DownloadSnackBarDisplay` | シムに存続 | BRIEF 明記 |
| `_TerminalViewData` 等 private 内部型 | 変更しない | 外部参照なし |
| `AnsiTextView` 18 props | **絶対変更禁止** | P3 完了・BRIEF 明記 |
| `AnsiTextViewState` 公開 5 メソッド | **絶対変更禁止** | `TerminalViewportPort` の委譲先 |
| import パス `.../terminal_screen.dart` | 変更しない（シム存続） | 24 test + 4 lib が import |
| **export の単一路化（V8）** | `ScrollModeSource`/`HerdrSyncTargetPolicy`/`DownloadSnackBarDisplay`/`downloadSnackBarDisplay` はシムから 1 経路のみ。新ファイルで同名を再定義しない | arbitration §7 |

---

## 6. リスクと対策

| # | リスク | 根拠（実測） | 対策 |
|---|---|---|---|
| R1 | **モード遷移の原子性が壊れる**（TERM-SCROLL-018） | `_enterScrollSendMode` は `mode=scrollSend` と `source=none` を同一 `setState` | `applyScrollSend()` が 2 フィールドを1メソッド設定、coordinator が `markNeedsBuild()` を遷移後1回。`scrollModeSourceForTesting()==none` かつ buffer 空を検証 |
| R2 | **`setState` 回数・タイミング差** | root `build` は `_terminalMode` を border(L3380)/`onKeyInput`(L3432)/`mode`(L3447) で読む | HEAD と同じ「全代入後に notify」1回。`ValueNotifier` 化は採用しない |
| R3 | `_lastPolledPaneMode` の二重所有 | poll(L2343) が書き flush(L2122) が読む | 所有を scrollSend controller に一本化し `observePaneMode` |
| **R4** | **選択バッファの二重所有（C7）** | poll(L2327-2331) が書きモード遷移(L1048 等)が消す | **所有を mode controller に一本化**。session は `captureSelectUpdate`、apply は `takeBufferedUpdate`。**破棄判定は herdr API**（`TerminalTargetIdentityValidator`）が行う |
| R5 | `GlobalKey` の null タイミング | 9 呼出は全て `currentState?.` | `TerminalViewportPort` も `_key.currentState?` を維持。widget key は root が渡す |
| R6 | タイマー所有移動で残骸送信 | `_scrollSendTimer` は `dispose` L3316 と `discard()` で cancel | `dispose()` に集約、遷移からは `discard()`。**P5** で必ず cancel |
| R7 | キーオーバーレイ 1500ms の境界 | input test が `pump(1499)` 残存→`+1ms` 消滅 | `Timer(1500ms)` を `TerminalKeySender.showKeyOverlay` にそのまま移設。**P5** で cancel |
| R8 | 非同期ギャップの `mounted`/`_isDisposed` | `_loadHistoryForScroll`/`_scrollToCaret` は await/delay 後にガード | `TerminalInputHost.isMounted/isDisposed` を同順で検査 |
| **R9** | **C1 `_scrollToCaret` の 100ms 遅延 + guard 消失** | `Future.delayed(100ms)` 後に `mounted || _isDisposed`（L4308） | `TerminalScrollFollowController.scrollToCaret` に 100ms と guard をそのまま維持。`host.isMounted/isDisposed` 経由。pump 回数固定テストを保護 |
| R10 | `_sendKeyData` と `_sendKey` の例外差 | `_sendKeyData` 完全静黙・`_sendKey` は `isHerdrInvalidKey` 通知 | 移植時に分岐をそのまま保持 |
| R11 | herdr epoch/mutation との交差 | `_switchHerdrTarget`(L4080) が `_resetTerminalMode()` と `_hasInitialScrolled=false` を呼ぶ | coordinator の `resetTerminalMode` を session が呼ぶ契約。`_hasInitialScrolled` は session 維持 |
| R12 | `_viewNotifier` 所有衝突 | `_loadHistoryForScroll` が直接 `copyWith(content:)` | `TerminalScrollbackPort.setDisplayedContent` 経由（C1/C7 も port 経由） |
| R13 | context 保持によるリーク | P3 `FileBrowserDownloadFlow` は context 非保持 | coordinator は `BuildContext` を保持せず `showInputDialog(BuildContext)` の引数で受ける |
| R14 | test 差分ゼロ違反 | `git diff HEAD -- test/` が空 | 実装後必須検証（§7）。新規テスト追加のみ可 |
| **R15** | **循環 import / SCC>=2（V7）** | view-input は herdr navigation / session の具象を import しない（port 経由） | §7 の SCC スクリプトで新設ファイルグラフを検証。`terminal_screen.dart`（シム）への逆 import を禁止 |
| **R16** | **C5/C3/C4 との export 衝突（V8）** | `HerdrLabelInputDialog` 等の public 化と `ScrollModeSource` export が同シムで衝突しうる | 本領域は `ScrollModeSource` のみ定義・export。他は他設計に委ね、シムで二重定義しない |

---

## 7. 検証計画

```bash
cd /home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines

# 1. フォーマット / 静的解析
dart format --output=none --set-exit-if-changed lib/screens/terminal lib/widgets
make analyze

# 2. view-input を固定するテスト（狭→広）
flutter test test/screens/terminal/terminal_screen_input_test.dart
flutter test test/screens/terminal/terminal_screen_scroll_send_test.dart
flutter test test/screens/terminal/terminal_screen_paste_test.dart
flutter test test/screens/terminal/terminal_screen_follow_scroll_test.dart
flutter test test/screens/terminal/terminal_screen_history_test.dart
flutter test test/screens/terminal/terminal_screen_contract_test.dart
flutter test test/screens/terminal/terminal_screen_remaining_contracts_test.dart
flutter test test/screens/terminal/terminal_custom_keys_test.dart
flutter test test/screens/terminal/terminal_custom_keys_e2e_test.dart
flutter test test/screens/terminal/ansi_text_view_key_test.dart
flutter test test/screens/terminal/ansi_text_view_scroll_send_test.dart

# 3. test 差分ゼロ（最重要）
git diff HEAD -- test/   # 空であること

# 4. 循環 import（SCC>=2）検証（V7・arbitration §6）
#    /tmp/p3-design/scc_verify_v3.py を P4 用に移植（view-input の新設 9 ファイルを
#    仮想ノードとして追加し、Tarjan SCC で size>=2 を列挙）。
#    view-input の新設ファイルが SCC>=2 に含まれないこと、terminal_screen.dart シムへの
#    逆 import 辺が無いことを確認する。
python3 /tmp/p4-design/scc_verify.py

# 5. 最終的に全体
flutter test
```

- 新規 9 ファイルの推定合計 ≈ 1,770 行（#1 80 + #2 190 + #3 60 + #4 250 + #5 180 + #6 340 + #7 250 + #8 150 + #9 270）。**すべて 500 行未満**（最大 #6 340 行）。450 行超は #6(340) のみで上限内。`TerminalInputCoordinator`(270) も上限内。
- SCC 検証は view-input の port が「view-input → ports ← session/herdr」の一方向であり、`input/*.dart` と `terminal_screen.dart` の間に逆辺が無いことを機械確認する。

---

## 8. 未確定点（lead 判断）

1. **C1/C2 の session 側呼出名の最終表記**: 本書は session 向けに `input.scrollToCaret()`（C1 guarded）と `input.flushInputQueue()`（C2）を提示した。arbitration の `viewport.scrollToCaret()` 表記は「Raw 即時」と衝突するため、session 統合時に `input`（coordinator）経由へ統一するか、view-input が提供する `viewport` facade に guarded 版を載せるかを確定する必要がある（本書は前者を推奨）。
2. **`_editCustomButton` / `_openCustomKeysScreen` の帰属**。本書は view-input（キーバー配線）だが、ui のダイアログ群と同居案もある。
3. **`TerminalTargetIdentityValidator` port の提供元**: herdr API（`HerdrTargetIdentity` を返す）の 1 メソッドを誰が実装するか（root State か herdr controller）。herdr 設計との突合が必要。
4. **State public 化名**（`TerminalScreenState`）と root ファイルパスは lead の統合方針に委ねる。
5. `_loadHistoryForScroll` の port 境界の重さ（読取＋表示反映を session へ完全移管するか、本書の「トリガ/位置計算は view-input、I/O は port」折衷か）。

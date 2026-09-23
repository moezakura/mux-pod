# P3-2 設計: `lib/screens/terminal/widgets/ansi_text_view.dart`（1670 行）責務ベース再設計

- 設計者: p3-ansi-designer（タスク#2・読み取り専用）
- 対象: `lib/screens/terminal/widgets/ansi_text_view.dart`（**HEAD と作業ツリー同一**・`git diff HEAD -- lib/screens/` 空を確認済み）
- 行番号基準: 作業ツリー実ファイル（HEAD f474d23 と同一）
- 前提資料: `docs/design/refactor-p2/critique.md`（特に §1.1 keepKeyboardOnEnter の実行時 prop 伝播穴・§4.2 public フィールド委譲問題・§0 export 方針）/ `docs/design/refactor-p2/skeys.md`（合成ルート State＋エンジン群の前例）を反映済み

---

## v2 改訂サマリ（p3-critic レビュー /tmp/p3-design/critique.md §2・§6 反映）

- 必須修正（ブロッキング）は**なし**。以下 4 点の推奨修正を反映（番号は critique §2.1〜2.5 対応）。
  1. **§2（2.1＝過剰分割の解消要件）**: 「全コラボレータは現行実コード 100 行超の塊（値型・View プレゼンテーションを除く）を移す」という明示的な「これは過剰分割ではない」要件を追記。`ansi_terminal_model`（値型 2 種）と `ansi_display_model`（表示モデル＋静的 geometry）は当該要件の除外範疇として位置づける。
  2. **§3（2.2＝updatePalette 等価性 / 2.3 補足＝直接 new 対応規約）**: `AnsiDisplayModel.updatePalette` が**新規メソッド**（内部で `AnsiParser` を defaultForeground/defaultBackground から再生成しキャッシュを無効化）であることを明記し、現行 didUpdateWidget L264-276 との等価性を追記。協調オブジェクトの生成は**initState / `late final`（フィールド初期化子にしない）**規約を §3 冒頭に追記（modifier_test の `AnsiTextViewState()` 直接 new で `LateInitializationError` を起こさないため）。
  3. **§1.1/§1.4/§3/§4（2.5＝実測ズレ）**: 「プロパティ 21」→ **実測 18**（text/paneWidth/paneHeight/onKeyInput/backgroundColor/foregroundColor/mode/zoomEnabled/onZoomChanged/verticalScrollController/cursorX/cursorY/caret/onArrowSwipe/onTwoFingerSwipe/onScrollSendTicks/navigableDirections/onTap・L60-125）に修正。`toggleCtrl` 等「呼出元ゼロ」の根拠を `AnsiTextViewState.` 接頭辞で絞った実測である旨に修正（素の `toggleCtrl` は P2 済み special_keys_bar 側の別オブジェクトに存在）。
  4. **§2/§8/§6（2.4＝`_EagerScaleGestureRecognizer` の可視性）**: private のままでも**定義と使用が同一ファイル内なら可**（別ファイルへ移す場合のみ public 化が必要）を §8-1・§6 リスク 11 に明記。

---

## 1. 現状分析（事実）

### 1.1 ファイル構造（実ファイル grep/awk 実測）

| 行範囲 | 構成要素 |
|---|---|
| L1-16 | import 9 系統（dart:async / flutter:gestures, material, services / flutter_riverpod / settings_provider / terminal_display_provider / pane_frame_reader / ansi_parser / font_calculator / terminal_font_styles / pane_navigator / design_colors / terminal_zoom） |
| L18-34 | `class KeyInputEvent`（public・data/isSpecialKey/tmuxKeyName） |
| L40-52 | `enum TerminalMode { normal, select, scrollSend }`（public・3 値） |
| L58-152 | `class AnsiTextView extends ConsumerStatefulWidget`（public・プロパティ 18（L60-125）/ コンストラクタ L127-151 / createState L152） |
| L153-1621 | `class AnsiTextViewState extends ConsumerState<AnsiTextView>`（**約 1469 行**） |
| L1623-1670 | `class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer`（private・2 本指検出で arena 強制勝利） |

### 1.2 AnsiTextViewState 内の混在責務（実測行範囲）

| # | 責務 | 行範囲 | 概算行数 |
|---|---|---|---|
| A | 状態所有フィールド（FocusNode / ScrollController×2 / caret Timer+ValueNotifier / vertical getter / _resolvedCaret / _parser / 修飾子 4bool / ジェスチャ状態群 / キャッシュ / _lineHeight / tick 端数 / ポインタ数） | L154-241 | ~88 |
| B | ライフサイクル（initState / didUpdateWidget / _invalidateCache / _getParsedLines / dispose） | L244-322 | ~79 |
| C | ズーム+2 本指ジェスチャ（_onScaleStart/_onScaleUpdate/_applyZoom/_onScaleEnd/_commitZoom/_showEdgeFlash / resetZoom / currentScale） | L324-450, L720-721 | ~129 |
| D | ホールド+スワイプ（_onLongPressStart/_onLongPressMoveUpdate/_onLongPressEnd） | L452-510 | ~59 |
| E | 視覚フィードバック・オーバーレイ（_buildSwipeOverlay/_buildTwoFingerSwipeOverlay/_buildEdgeFlash/_buildPanGlow） | L512-718 | ~207 |
| F | build（LayoutBuilder〜ツリー合成・ListView・水平・scrollSend・zoom・SelectionArea・Focus・normal） | L723-1064 | ~342 |
| G | キャレット span（_buildCaretSpan） | L1066-1085 | ~20 |
| H | キー入力（_handleKeyEvent 本体 L1087-1304・isAsciiPrintable L1308-1313・deriveBaseChar L1328-1339） | ~225 |
| I | エスケープシーケンス/ tmux キー名合成（_getArrowSequence/_getArrowTmuxKey/_getModifiedTmuxKey/_getFinalCharSequence/_getParamSequence/_getFKeySequence） | L1342-1423 | ~82 |
| J | 修飾キートグルの公開 API（toggleCtrl/toggleAlt/toggleShift/ctrlPressed/altPressed/shiftPressed/resetModifiers） | L1426-1459 | ~34 |
| K | scrollSend ドラッグ+ティック変換（_onScrollSendDragStart/_onScrollSendDragUpdate/_onScrollSendDragEnd/_emitScrollTicks） | L1461-1505 | ~45 |
| L | スクロール制御公開 API（jumpToLineFromTop/scrollToBottom/followToBottom/scrollToTop/scrollToCaret） | L1508-1619 | ~112 |

### 1.3 状態・リソース所有権インベントリ（実測）

| 資源 | 生成 | 破棄 | 備考 |
|---|---|---|---|
| `_focusNode`（FocusNode） | L154（フィールド初期化） | L383 | 後述 H/F の Focus と onTap requestFocus |
| `_horizontalScrollController` | L155（フィールド初期化） | L384 | 水平 ScrollView 用 |
| `_internalVerticalScrollController` | L247-248（**外部 controller 未指定時のみ** initState） | L385-386（内部作成時のみ） | **外部 `widget.verticalScrollController` は親（terminal_screen）所有・破棄しない** |
| `_verticalScrollController` getter | - | - | `widget.verticalScrollController ?? _internal!`（L164-165） |
| `_caretBlinkTimer`（Timer.periodic 500ms） | L258（initState） | L379 | キャレット離散点滅 |
| `_caretVisible`（ValueNotifier<bool>） | L161 | L380 | キャレット行のみ再構築（リビルド最適化） |
| `_parser`（AnsiParser） | L250（initState）/ L266-270（色変更で再生成） | なし | パースキャッシュ L228-231 とセット |
| 修飾子 4bool | L200-203 | - | キーイベント内で遷移 |
| ジェスチャ状態群（scale/2本指/長押し/tick/ポインタ数） | L206-241 | - | setState 通知式 |

**事実**: 本ファイルに `TextInputConnection` / `TextEditingController` / `StreamSubscription` / `GlobalKey` / `TextInput` は**存在しない**（grep 実測: TextInput 系 0 件）。タスク概要の「IME/DirectInput 合成」は本ファイルでは **Focus の `onKeyEvent`（ハードウェアキーボード）経路のみ**を指す。IME/TextInput 実体は P2 済み `special_keys_bar.dart` 側。

### 1.4 呼出元（rg 実測）

- **lib**: `lib/screens/terminal/terminal_screen.dart`（9529 行・P4 対象・**触れない**）のみ。import パス `import 'widgets/ansi_text_view.dart';`（terminal_screen L79）。
  - `AnsiTextView(`: L3416-3468（props 18 全て）
  - `_ansiTextViewKey = GlobalKey<AnsiTextViewState>()`: L464 / `key: _ansiTextViewKey`: L3417
  - State 公開メソッド呼出: `scrollToBottom()` L1080/3029/3224/4318 / `jumpToLineFromTop()` L3020 / `followToBottom()` L3100 / `scrollToCaret()` L4316/4321 / `resetZoom()` L6605 — すべて `_ansiTextViewKey.currentState?.xxx`（**これらは State の public メソッドであることが契約**）
  - `TerminalMode`: L568/1041/1068/1095/1121/1128/2050/3020/3256/3432/4534/4571 …
  - `KeyInputEvent`: L3685/3708（`_handleKeyInput` / `_handleScrollSendKeyInput` の引数型）
- **test**: 12 本が `package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart` を import（rg 実測・全リストは §1.5）。

### 1.5 既存テストが固定している挙動（実測・差分ゼロ契約）

テストファイルごとに「何を固定するか」を実測した。**ウィジェットツリー型・Key・スクロール命令の動作・公開メソッドの存在**が主契約。

| テストファイル | テスト数 | 固定している挙動（実測箇所） |
|---|---|---|
| `ansi_text_view_test.dart` | 19（testWidgets） | **`ListView` の存在と `itemExtent == fontSize×1.2`（L123-124）・`padding == EdgeInsets.only(top: viewport−contentH)`（L163-165）/ 0.0（L199-201）**・タップで onTap（L88-89）・キャレットは **RichText 内にインライン（`Positioned` 0 件）**（L250-264）・キャレット位置/幅 2px/高さ fontSize・**500ms で ON/OFF 点滅**（L302-314）・herdr caret の visible ゲート/位置不明/範囲外で非描画（L374-493） |
| `ansi_text_view_key_test.dart` | 19 | `Focus` 経由で `sendKeyDownEvent` → `onKeyInput` 発火（全 19 本）。Alt/Meta 合成（Issue #116 の `deriveBaseChar` 使用径路）、Esc/Enter/Tab/矢印/F1-F12 のシーケンス・`isSpecialKey`/`tmuxKeyName` |
| `ansi_text_view_modifier_test.dart` | 19（`test()` 純単体） | **`AnsiTextViewState.isAsciiPrintable` 静的メソッド**・**`AnsiTextViewState().deriveBaseChar(...)`（State を**直接 `new`**し、インスタンスメソッドとして呼ぶ、L50/55/91/100/104/113/115/138/143/149/153/157/161/162/166）** |
| `ansi_text_view_bg_test.dart` | 10 | `ColoredBox`（背景レイヤー）の色と枚数（L76-86）・**`IgnorePointer` に包まれタップを奪わない**（L115-160）・`RichText` 内 `TextSpan.backgroundColor`（opaque 化）（L181-215） |
| `ansi_text_view_scroll_send_test.dart` | 8 | `SelectionArea` が scrollSend で **0 個**・select で **1 個**（L164/L195）・`NeverScrollableScrollPhysics` で offset 不動（position.jumpTo(1000) 後も変化なし）（L155-186）・ドラッグ 1 tick = `_lineHeight×1.5`=18px（fontSize10）で正負ティック（L79-117）・±25% ヒステリシス/方向反転デッドゾーン（L120-154）・2 本指パンでスワイプ不発火・ピンチ不発火（L198-262）・normal モードはティック出さずリストスクロール（L272-290） |
| `terminal_screen_contract_test.dart` | 4 | **`TerminalMode.values == [normal, select, scrollSend]`**（L23-26）・`tester.widget<AnsiTextView>` のプロパティ読取（L67） |
| `terminal_screen_scroll_send_test.dart` | 14 | `tester.widget<AnsiTextView>(...).mode`（L45-46）によるモード遷移検証（モードは 3 値で排他）・`SelectionArea findsNothing`（L223） |
| `terminal_screen_follow_scroll_test.dart` | 9 | **AnsiTextView 配下の縦 Scrollable の `position.pixels/maxScrollExtent`**（`_verticalTerminalScrollable` L71-79）・`followToBottom()` のフレーム追試（max が伸びる間追従）（L140-193）・FAB→`scrollToBottom()` 300ms animateTo 消化（L197-246）・アニメ中伸長にも `followToBottom` が追従（L357-389） |
| `terminal_screen_history_test.dart` | 7 | 同 `_verticalTerminalScrollable` で忠実: `paneWidth/paneHeight` 由来の maxScrollExtent・`jumpToLineFromTop` 相当の先頭復帰（L72-93） |
| `terminal_screen_herdr_test.dart` | 57 | `tester.widget<AnsiTextView>(...)` の **`paneWidth`/`paneHeight` 実値**（L1898-1954）・scrollToBottom 相当の末尾アライン（L2073/2628-2728） |
| `terminal_screen_input_test.dart` | 5 | タップ→sendKeyEvent(`keyA`)→`onKeyInput` 経由で send-keys（G1-6b）（L64-69） |
| `terminal_screen_lifecycle_test.dart` | 8 | タップ→onTap 系（L177） |
| `terminal_screen_remaining_contracts_test.dart` | 9（うち関連 2） | **`ValueKey('terminal-input-gesture')`**（L43・長押しスワイプ位置取得）・**`ValueKey('terminal-two-finger-gesture')`**（L61・2 本指ジェスチャ座標・`select-pane` 発火） |

**テストが固定するツリー要件（設計が破壊してはならない実測まとめ）**:
1. 縦 `ListView`（`find.byType(ListView)` / axisDirection.down の `Scrollable`）が常に存在し、`controller`・`itemExtent`・`padding`・`physics` が現行どおり。
2. select モードのみ `SelectionArea` 1 個。scrollSend / normal には無い。
3. `ValueKey` 3 種: `terminal-input-gesture`（normal の GestureDetector）/ `terminal-two-finger-gesture`（zoom の RawGestureDetector）/ `terminal-scroll-send-gesture`（scrollSend の GestureDetector）。
4. キャレットは `RichText` 内 `WidgetSpan`（`Positioned` を使わない）・`ValueListenableBuilder` で 500ms 点滅。
5. 公開 State API（`AnsiTextViewState.isAsciiPrintable` 静的・`AnsiTextViewState().deriveBaseChar`・GlobalKey 経由の scroll/reset 5+1 メソッド・`currentScale`・修飾子トグル群）。
6. `TerminalMode.values` の順序。
7. AnsiTextView の公開プロパティ全て（`tester.widget<AnsiTextView>` で直接読まれる）。

---

## 2. 目標構成（10 ファイル・全ファイル 500 行未満）

**方針**: P2 skeys で承認された「**合成ルート State（facade）＋状態所有者エンジン群（has-a）**」を採用。`ansi_text_view.dart` は Widget クラス + facade State + thin re-export（公開パス不変）に留める。機械的分割ではなく、各協調オブジェクトが**真の状態所有者**（P2 critique §1.8「真の state owner」基準）になるよう、所有フィールドを丸ごと移動する（1 行委譲 wrapper は State の公開 API 面のみ）。

| # | ファイル | 1 文責務 | 公開シンボル | 依存先 | 推定行数 |
|---|---|---|---|---|---|
| 1 | `ansi_text_view.dart`（**既存・改修**） | AnsiTextView の公開 Widget と facade State（協調オブジェクトの合成ルート・公開 API 全維持・build は計算＋`AnsiTerminalView` 呼出のみ）+ `KeyInputEvent`/`TerminalMode` の **thin re-export** | `AnsiTextView`（現行と完全同シグネチャ）/ `AnsiTextViewState`（公開 API 維持・内部は委譲） | 2-10 全て（葉ではない） | ~350 |
| 2 | `ansi_terminal_model.dart`（新） | 入力プロトコルと操作モードの値型定義 | `KeyInputEvent` / `TerminalMode` | - | ~55 |
| 3 | `ansi_display_model.dart`（新） | ANSI 表示モデル: パースキャッシュ・行高・カーソル解決・キャレット span（**リビルド最適化の中核**） | `AnsiDisplayModel`（parser getter / parsedLines() / lineHeight / updatePalette()）+ 静的 `resolveCaret(caret,cursorX,cursorY)` / `caretSpan(fontSize)` | ansi_parser / pane_frame_reader（葉） | ~180 |
| 4 | `ansi_key_composer.dart`（新） | `KeyEvent` → エスケープシーケンス/tmux キー名の**純粋合成**（Issue #116 の ascii 導出含む・単体テスト可能） | `AnsiKeyComposer`（静的: `arrowSequence`/`paramSequence`/`finalCharSequence`/`fKeySequence`/`arrowTmuxKey`/`modifiedTmuxKey`/`isAsciiPrintable`/`deriveBaseChar`） | ansi_terminal_model | ~235 |
| 5 | `ansi_key_input_engine.dart`（新） | キーイベント処理の状態機械。**修飾子 4bool の唯一の所有者**・KeyDown/Up 遷移・特殊キー分岐・Consume 順・`toggleCtrl/Alt/Shift`・`resetModifiers`。callbacks は**毎呼び出し引数**（ライブ参照） | `AnsiKeyInputEngine`（`handleKeyEvent(FocusNode, KeyEvent, {required onKeyInput}) → KeyEventResult`・`toggleCtrl/Alt/Shift`・`resetModifiers`・`ctrlPressed/altPressed/shiftPressed`） | ansi_key_composer / ansi_terminal_model / flutter:services | ~265 |
| 6 | `ansi_scroll_driver.dart`（新） | 垂直 ScrollController の所有（外部経由判定）と 5 つのスクロール命令（jumpToLineFromTop/scrollToBottom/followToBottom/scrollToTop/scrollToCaret） | `AnsiScrollDriver`（`attach({external, content, host})`（`host` は isActive/paneHeight 供給）/ `controller` getter / 5 命令 / `dispose()`） | ansi_display_model / ansi_terminal_model | ~175 |
| 7 | `ansi_gesture_engine.dart`（新） | タッチ操作状態機械: ピンチズーム・2 本指パン/スワイプ・ホールド+スワイプ・scrollSend ドラッグティック変換の**唯一の状態所有者**。widget prop は全て **host getter でライブ読取** | `AnsiGestureEngine` + host インターフェース `AnsiGestureHost` | ansi_terminal_model / terminal_zoom（純関数）/ pane_navigator（SwipeDirection・detectSwipeDirection）/ flutter:services | ~335 |
| 8 | `ansi_terminal_overlays.dart`（新） | 視覚フィードバック 3 種の**プレゼンテーション Widget**（状態を持たない） | `AnsiSwipeOverlay` / `AnsiEdgeFlashOverlay` / `AnsiPanGlowOverlay`（+ ディスパッチャ `AnsiTwoFingerOverlay`） | theme/design_colors（葉） | ~190 |
| 9 | `ansi_line_row.dart`（新） | 1 行のレンダリング（キャレット inline 挿入・背景レイヤー敷き込み・固定幅・`ValueListenableBuilder` でキャレット行のみ再構築） | `AnsiLineRow` | ansi_display_model / ansi_terminal_model / font_calculator | ~145 |
| 10 | `ansi_terminal_view.dart`（新） | ビューツリー合成（ListView・水平 ScrollView・scrollSend/zoom/select/normal 分岐）と private `_EagerScaleGestureRecognizer` | `AnsiTerminalView`（Stateless） | overlays / line_row / display_model / 協調オブジェクト受け取り | ~395 |

**行数保証の根拠（概算・各節現行実測からの移設量）**:
- 1: AnsiTextView widget 95（不変）+ State（フィールド ~25・init/didUpdate/dispose ~45・公開 API 委譲 ~45・build 計算部 ~80（LayoutBuilder+フォント計算+表示サイズ通知+AnsiTerminalView 生成））≈ **350**
- 2: L18-34 + L40-52 + doc ≈ 55
- 3: L178-195(_resolvedCaret 50) + L197-198/L228-234(キャッシュ+_lineHeight) + L229-312(parser/_getParsedLines/_invalidateCache 系 60) + L1066-1085(_buildCaretSpan 20) + クラス境界/doc ≈ **180**
- 4: L1308-1313(ascii 6) + L1328-1339(derive 12) + L1342-1423(sequence 82) + doc ≈ **235**
- 5: L200-203(4bool) + L1087-1304(_handleKeyEvent 218) + L1426-1459(公開トグル 34) + クラス境界 ≈ **265**
- 6: L164-166(getter 3) + L1508-1619(スクロール命令 112) + 内部 controller 生成/破棄 12 + host/doc ≈ **175**
- 7: L206-241(ジェスチャ状態 36) + L324-450(ズーム/2本指 127) + L452-510(長押し 59) + L1461-1505(ドラッグ/tick 45) + L720-721(currentScale) + host/doc ≈ **335**
- 8: L512-718(オーバーレイ 207) + クラス化/doc 追加 ≈ **190**
- 9: L723-1064 の行レンダリング部（itemBuilder 内 Slice ~105） + クラス/doc ≈ **145**
- 10: build のツリー合成部（L723-1064 のうち ~175）+ L1623-1670(recognizer 48) + 配線/doc ≈ **395**

合計 ≈ 2,180 行（現行 1,670 に対し +31%・P2 の +17-20% より大きい）。増分の内訳は「クラス境界・doc・host インターフェース・再 export」。**過剰分割批判（P2 critique §2.3 rdialog）への反論**: rdialog 批判は「単一用途の小部品を目的化分割」だった。本設計の協調オブジェクトは、P2 skeys の 8 ファイル（composer/modifier_state/engine/rows/buttons…）と同型の「真の所有者」である。`_buildSwipeOverlay` 等の単一用途見た目クラスは #8 に集約し、細切れ分割はしない。

**v2 追加（critique §2.1 反映・過剰分割でないための明示要件）**: 各協調オブジェクト（#2-10）は**現行実コード 100 行超の塊を移動**する（値型 `ansi_terminal_model`・View プレゼンテーション `ansi_terminal_overlays`/`ansi_line_row`/`ansi_terminal_view` の描画部は除く）。実測の移動量: キー系（L1087-1304 + L1308-1339 + L1342-1459 ≈ 300）/ ジェスチャ系（L206-510 相当 + L1461-1505 ≈ 300）/ スクロール命令（L1508-1619 ≈ 112）/ 表示モデル（L178-312 + L1066-1085 ≈ 130）。`ansi_display_model` の境界は「状態移動は parser＋キャッシュ部のみ」と見られ得るため、キャレット解決・span を静的 geometry として同一ファイルに同居させ**一括の "表示モデル" 責務**（100 行超）で正当化する。

### 依存グラフ（非循環・一方向）

```
ansi_text_view.dart（AnsiTextView + State = 合成ルート）
 ├─ re-export: ansi_terminal_model.dart
 ├─ ansi_display_model.dart（表示モデル）
 ├─ ansi_scroll_driver.dart ─→ ansi_display_model
 ├─ ansi_key_input_engine.dart ─→ ansi_key_composer.dart ─→ ansi_terminal_model
 ├─ ansi_gesture_engine.dart ─→ terminal_zoom / pane_navigator / ansi_terminal_model
 ├─ ansi_terminal_view.dart ─→ overlays・line_row・display_model・type
 │    └─（_EagerScaleGestureRecognizer を内包・private）
 └─ ansi_line_row.dart ─→ ansi_display_model・font_calculator
```

- `part` / `mixin` / private 基底クラスは**不使用**。継承なし。State は has-a で協調オブジェクトを所有。
- `AnsiTextViewState`（Widget と同ライブラリでなくてはならない・`ConsumerState<AnsiTextView>` の generic 依存があるため**循環 import 不可**）は `ansi_text_view.dart` 内に留め、内部ロジックの大部分を has-a 委譲する＝P2 skeys の State 旧 `special_keys_bar.dart` と同型。

---

## 3. 移動マッピング

**v2 追加（critique §2.3 補足反映・協調オブジェクト生成の規約）**: 協調オブジェクト（display_model / key_input_engine / gesture_engine / scroll_driver）はすべて **initState で生成し `late final` フィールドに保持**する。**フィールド初期化子で生成しない**こと（`AnsiTextViewState()` を直接 new する modifier_test 19 本で `LateInitializationError` になるのを防ぐ。直接 new された State は initState が走らず、委譲先がインスタンス状態に触れない静的委譲（deriveBaseChar / isAsciiPrintable）のみ実行可能）。§5 の「生成」列 は「attach 時 / late final」と読む。

| 既存行範囲 | 内容 | 移動先 | 種別 |
|---|---|---|---|
| L18-34 | `KeyInputEvent` | ansi_terminal_model.dart | 移動（ansi_text_view.dart から re-export） |
| L40-52 | `TerminalMode` | ansi_terminal_model.dart | 移動（re-export） |
| L58-152 | `AnsiTextView`（プロパティ 18・コンストラクタ・createState） | ansi_text_view.dart 残存 | そのまま残す |
| L154-155 | `_focusNode` / `_horizontalScrollController` | ansi_text_view.dart（State フィールド）残存 | そのまま残す |
| L156, L164-166, L247-248, L385-386 | `_internalVerticalScrollController`・`_verticalScrollController` getter・生成/破棄 | ansi_scroll_driver.dart（`attach`/`controller`/`dispose` へ） | 移動（controller 生成条件・破棄条件・`?? _internal!` を保つ） |
| L160-161, L258-262, L379-380 | `_caretBlinkTimer` / `_caretVisible` / initState 中の生成・dispose 中の破棄 | ansi_text_view.dart（State）残存 | そのまま残す |
| L178-195 | `_resolvedCaret` getter | ansi_display_model.dart `resolveCaret(caret, cursorX, cursorY)` | 移動（純関数化） |
| L197-198, L228-234, L229-312 | `_parser`・キャッシュ 4 値・`_lineHeight`・`_getParsedLines`・`_invalidateCache` | ansi_display_model.dart | 移動＋**新規 API 追加（v2・critique §2.2）**: 既存メソッドの移動（キャッシュキー text/fontSize/fontFamily は不変）に加え、`updatePalette(foreground, background)` を**新設**する。内部実装は「`AnsiParser(defaultForeground:…, defaultBackground:…)` 再生成＋キャッシュ無効化」（現行 didUpdateWidget L264-276 の parser 再生成→`_invalidateCache()` と等価）。AnsiParser に同メンバは存在しない（rg `updatePalette` 0 件・ansi_parser.dart L18）ため、**新規 API** として扱う |
| L244-322 | initState（外部 controller 判定/parser/timer）/ didUpdateWidget（色→recreate parser）/ dispose 順序 | ansi_text_view.dart（State・再構成） | そのまま残す（**生成/破棄順は現行どおり**） |
| L324-332 | `resetZoom` | ansi_gesture_engine.dart（State は 1 行委譲） | 移動（セマンティクス: setState→onZoomChanged(1.0)） |
| L334-450 | `_onScaleStart/_onScaleUpdate/_applyZoom/_onScaleEnd/_commitZoom/_showEdgeFlash` | ansi_gesture_engine.dart | 移動（widget prop は host getter でライブ読取・ref 書込は `host.commitZoomFactor` へ） |
| L452-510 | ホールド+スワイプ 3 ハンドラ | ansi_gesture_engine.dart | 移動（閾値 30.0・150ms リセット・原点再設定） |
| L512-718 | オーバーレイ 3 種 + ディスパッチャ | ansi_terminal_overlays.dart | 移動（props 化・色/形状・`IgnorePointer` は不変） |
| L720-721 | `currentScale` getter | ansi_gesture_engine.dart（State は 1 行委譲） | 移動 |
| L723-1064 | build | **分割**: 計算部（LayoutBuilder・ref.watch settings・FontCalculator・表示サイズ通知）→ ansi_text_view.dart State / ツリー合成（ListView 等）→ ansi_terminal_view.dart / 行レンダリング → ansi_line_row.dart | 分割移動（ツリー形状・Key・SelectionArea 分岐は不変） |
| L1066-1085 | `_buildCaretSpan` | ansi_display_model.dart `caretSpan(fontSize)` | 移動 |
| L1087-1304 | `_handleKeyEvent` 本体 | ansi_key_input_engine.dart | 移動（`onKeyInput` は**毎呼び出し引数**＝ライブ参照維持） |
| L1308-1313 / L1328-1339 | `isAsciiPrintable` / `deriveBaseChar` | ansi_key_composer.dart 静的 + **State に同名 public 継続**（静的委譲なので `AnsiTextViewState()` 直接構築でも動作） | 移動（公開維持） |
| L1342-1423 | sequence 合成 6 メソッド | ansi_key_composer.dart 静的 | 移動（修飾子は引数渡し・Consume 順はエンジンから渡す値で再現） |
| L1426-1459 | 修飾子 public API（toggle 3/ getter 3 / reset） | ansi_key_input_engine.dart（実体）+ State 委譲（setState + HapticFeedback は State 側で維持） | 移動（公開維持） |
| L1461-1505 | scrollSend ドラッグ 3 + `_emitScrollTicks` | ansi_gesture_engine.dart | 移動（±25% ヒステリシス・端数保持は不変） |
| L1508-1619 | スクロール命令 5 | ansi_scroll_driver.dart（State は 1 行委譲） | 移動（フレーム再試上限 60/8・postFrame guard `isActive` は維持） |
| L1623-1670 | `_EagerScaleGestureRecognizer` | ansi_terminal_view.dart 内 private | 移動 |

---

## 4. 公開 API 維持表

| 維持するシンボル | 現行定義 | 実装先 | 呼出元（rg 実測） |
|---|---|---|---|
| `AnsiTextView` + コンストラクタ（super.key + 18 named props） | L58-152 | ansi_text_view.dart（不変） | terminal_screen L3416-3468 / テスト 12 本 |
| `AnsiTextViewState`（クラス名・暗黙デフォルトコンストラクタ） | L153 | ansi_text_view.dart（facade 化・クラス名/型不変） | terminal_screen `GlobalKey<AnsiTextViewState>` L464 / modifier_test の**直接 `new`** |
| `AnsiTextViewState.jumpToLineFromTop` / `.scrollToBottom` / `.followToBottom` / `.scrollToTop` / `.scrollToCaret` | L1508-1619 | State public 委譲 → AnsiScrollDriver | terminal_screen L1080/3020/3029/3100/3224/4316/4318/4321 |
| `AnsiTextViewState.resetZoom` / `.currentScale` | L324-332 / L720-721 | State public 委譲 → AnsiGestureEngine | terminal_screen L6605 / （テスト未使用・公開維持） |
| `AnsiTextViewState.toggleCtrl/toggleAlt/toggleShift` / `.ctrlPressed/.altPressed/.shiftPressed` / `.resetModifiers` | L1426-1459 | State public 委譲 → AnsiKeyInputEngine（setState+haptic は State 側） | 呼出元ゼロだが公開面のため維持（rg 実測: 素の `toggleCtrl` は P2 済み special_keys_bar 側の別オブジェクトに存在（special_keys_bar_rows L100 等）。**`AnsiTextViewState.toggleCtrl` に限定**すれば lib/test 0 件・v2 critique §2.5） |
| `AnsiTextViewState.isAsciiPrintable`（static） | L1308-1313 | State public 静的委譲 → `AnsiKeyComposer.isAsciiPrintable` | modifier_test 19 件 |
| `AnsiTextViewState.deriveBaseChar`（instance） | L1328-1339 | State public 委譲 → `AnsiKeyComposer.deriveBaseChar`（静的呼出） | modifier_test 19 件（**直接 `new` した State 上で呼ぶため、委譲先はインスタンス状態不使用の静的であること**） |
| `KeyInputEvent` | L18-34 | ansi_terminal_model.dart → ansi_text_view.dart から `export` | terminal_screen L3685/3708 / ansi_text_view_key_test 16+ |
| `TerminalMode`（enum 3 値・順序） | L40-52 | ansi_terminal_model.dart → export | terminal_screen / contract_test L23-26 / scroll_send 系テスト |

**import パスが変わらない根拠**: lib 側は terminal_screen L79 `import 'widgets/ansi_text_view.dart';` のみ、テスト側は 12 本すべて同パス（§1.5）。再構成後も `ansi_text_view.dart` が `export 'ansi_terminal_model.dart' show KeyInputEvent, TerminalMode;` を張り、`AnsiTextView`/`AnsiTextViewState` を同ファイルに保持するため **import 変更は 0 ファイル**（P2 の `connection_provider.dart` / `resize_dialog.dart` 前例に同じ）。シム化の対象は入力値型のみで、`ansi_text_view.dart` 本体はロジック（State facade）を持つため P2 の「thin re-export シム」規定（骨格が空ならシム）とは異なり、**「公開面固定の合成ルート」**として位置づける。

---

## 5. 状態所有権表

| 資源 | 現行: 生成/破棄 | 新所有者 | 更新通知経路 |
|---|---|---|---|
| `_focusNode` | L154 / dispose L383 | **AnsiTextViewState（root）** | Focus（scrollSend/normal の `Focus` widget・view に prop 渡し）+ onTap `requestFocus` |
| `_horizontalScrollController` | L155 / dispose L384 | **AnsiTextViewState（root）** | 水平 SingleChildScrollView（view に prop 渡し） |
| `_internalVerticalScrollController` | initState L247（外部未指定時のみ）/ dispose L385（内部時のみ） | **AnsiScrollDriver**（`attach` で生成判定・`dispose` で内部のみ破棄） | ListView.controller とスクロール命令は `driver.controller` 経由 |
| 外部 `verticalScrollController`（widget prop） | 親（terminal_screen L3431 `_terminalScrollController`）が生成・破棄 | **親所有のまま（driver は参照のみ・絶対に dispose しない）** | 親 → prop → driver.controller → ListView |
| `_caretBlinkTimer`（Timer.periodic 500ms） | initState L258 / dispose L379 | **AnsiTextViewState（root）** | ValueNotifier トグル → AnsiLineRow の ValueListenableBuilder（キャレット行のみ再構築） |
| `_caretVisible`（ValueNotifier<bool>） | L161 / dispose L380 | **AnsiTextViewState（root）** | 同上 |
| `AnsiParser` + キャッシュ 4 値 + `_lineHeight` | initState L250 / 色変更 L266-270 再生成 / 破棄なし | **AnsiDisplayModel** | setState ではなく build 内の cache-key 検証で再パース（現行どおり） |
| 修飾子 4bool | L200-203 | **AnsiKeyInputEngine** | `toggleX`/`resetModifiers` は State が engine を呼びその後に setState+haptic（現行の public 動作）・キーイベント内遷移はエンジン内 |
| ズーム/2 本指/長押し/tick/ポインタ状態（14 フィールド） | L206-241 | **AnsiGestureEngine** | host `notifyChanged()` → State `setState`（現行の setState 位置と同一） |
| `_EagerScaleGestureRecognizer` インスタンス | build 内 GestureRecognizerFactory（L1027-1040） | AnsiTerminalView 内（build 毎生成・現行と同一） | - |

**dispose 順序（現行 L379-387 と一致させる）**: `_caretBlinkTimer.cancel()` → `_caretVisible.dispose()` → `_focusNode.dispose()` → `_horizontalScrollController.dispose()` → `driver.dispose()`（内部 vertical のみ）→ `super.dispose()`。

**didUpdateWidget 呼出順序（現行 L264-276）**: 色（foreground/background）不一致のときのみ `content.updatePalette(foreground, background)` → キャッシュ無効化。`updatePalette` は新規 API（内部で AnsiParser を再生成しキャッシュを無効化・現行の parser 再生成→`_invalidateCache()` と等価・v2 critique §2.2）。フォント変更は cache-key 検証で自動再パース（現行どおり）。**実行時 prop（onKeyInput/mode/navigableDirections/onTwoFingerSwipe/onArrowSwipe/onScrollSendTicks/onZoomChanged）はエンジンにキャッシュさせず、全部イベント時に host getter / 毎呼び出し引数で読む**（P2 critique §1.1 のステルス回帰を再発させない）。

---

## 6. リスクと対策

| # | リスク | 対策・検出 | 検出手段（既存/新規テスト） |
|---|---|---|---|
| 1 | **実行時 prop のライブ参照が固定化**（onKeyInput/mode 系。terminal_screen が `_terminalMode`/`_canSendText` により onKeyInput を毎ビルド差し替えている実経路あり L3431-3441） | `handleKeyEvent` の `onKeyInput` は毎呼び出し引数・gesture engine は host getter で widget を読む（キャッシュ禁止）。didUpdateWidget に setter 伝播を要しない設計にする | terminal_screen_input_test（モード切替後のキー入力）/ scroll_send系（mode 差し替え） |
| 2 | `AnsiTextViewState()` 直接構築テスト（modifier_test）が、initState 未実行の State で `deriveBaseChar` を呼ぶ → `late`/initState 依存の委譲先参照で LateInitializationError | `deriveBaseChar` は **静的委譲**（`AnsiKeyComposer.deriveBaseChar` へ → インスタンス状態不使用で `new` 直後でも動作）。`isAsciiPrintable` 同様 | ansi_text_view_modifier_test（19 本・既存で検出） |
| 3 | **ビルド再構築範囲の変更**（キャレット点滅が行全体へ波及・ListView 再生成） | AnsiLineRow 内の `ValueListenableBuilder(_caretVisible)` をキャレット行テキストのみに被せる、ListView は `itemExtent`/`addRepaintBoundaries`/`padding` を不変で再現。display-model の cache-key（text/fontSize/fontFamily）を維持 | ansi_text_view_test L92-201（itemExtent/padding）/ L302-314（点滅） |
| 4 | **ツリー形状・Key 破壊**（SelectionArea 有無・ValueKey 3 種・`find.byType(ListView)`・`Scrollable` axisDirection） | AnsiTerminalView が現行 build の分岐（select→Container+SelectionArea / scrollSend→Container+Focus+Listener+GestureDetector / normal→Focus+GestureDetector+Stack+overlay / zoom→RawGestureDetector+Transform.scale）を一字不変で再現し、Key 文字列も不変 | ansi_text_view_scroll_send_test L155-186/L190-195・terminal_screen_remaining_contracts_test L43/L61・follow/history の `_verticalTerminalScrollable` |
| 5 | **`jumpToLineFromTop`/`followToBottom` のフレーム追試と mounted ガード**（上限 60/8・postFrame） | AnsiScrollDriver に移設し `isActive`（=`mounted`）でガード。maxScrollExtent 伸長時の再試行で追従を取りこぼさない | terminal_screen_follow_scroll_test 9 本（ポーリング伸長→追従・オフセット検証） |
| 6 | scrollSend の**ジェスチャ競合特例**（ズーム認識子無効化・`_activePointers` 監視・ドラッグを内側に） | zoom 分岐条件 `widget.zoomEnabled && mode != scrollSend` と Listener の onPointerDown/Up/Cancel → engine のポインタカウントを不変保持 | ansi_text_view_scroll_send_test TERM-SCROLL-014/015（2 本指でスワイプ/ズーム/ティック不発火） |
| 7 | **dispose 順序 / 内部 controller の二重破棄** | 内部 vertical は `attach` 時のみ生成・外部は参照のみ。dispose 内の `cancel→dispose→driver.dispose` の順を現行と一致 | 終了系テスト（lifecycle）、`flutter analyze` |
| 8 | scrollSend ティック換算（1 tick=`_lineHeight×1.5`・±25% ヒステリシス・端数保持）の数値ズレ | `_emitScrollTicks` を gesture engine へ**ロジック不変**で移動（符号反転デッドゾーン 0.25・端数減算順序） | ansi_text_view_scroll_send_test TERM-SCROLL-010/011/012（ドラッグ距離 18px 単位の厳密検証） |
| 9 | `terminalDisplayProvider` の画面サイズ通知（build 内 postFrame・無限ループ防止の差値ガード） | State.build に残し、`currentDisplay.screenWidth/Height != constraints` のときだけ postFrame → `updateScreenSize` | ansi 系テスト（リサイズ/display 通知）・既存回帰 |
| 10 | `isAsciiPrintable`/`deriveBaseChar` の挙動（keyLabel 大文字→Shift 有無で小文字化 R1・複数文字/非 ASCII/制御文字 null R3） | ansi_key_composer 静的へ一字不変移動・State から静的委譲 | ansi_text_view_modifier_test 19 本（既存で完全カバー） |
| 11 | 単純な数の見積超過による 500 行破り | 超過スロットを定義: (a) key_input_engine が 500 超 → `AnsiKeyEventDecoder`（特殊キー switch のみ）を別ファイルへ / (b) gesture_engine が 500 超 → scrollSend ティック部を `ansi_scroll_tick_accumulator.dart` へ / (c) terminal_view が 500 超 → `_EagerScaleGestureRecognizer` のみ別ファイルへ分離（**v2・critique §2.4**: 下線 private は同一ファイル内でしか参照できないため、この場合のみ public 化が必要。現行設計は「view 内 private＋同ファイル内使用」で可視性が成立しており、別ファイル分離は最終手段） | `flutter analyze` + 行数チェック |

---

## 7. 検証計画（実装フェーズで実行）

```bash
dart format --output=none --set-exit-if-changed .          # 書式不変
flutter analyze                                            # 型・import 破綻検出
flutter test --exclude-tags=repro                           # 全体回帰
git diff HEAD -- test/                                      # 差分ゼロ（テスト変更禁止の証明）
dart tool/generate_herdr_protocols.dart --check             # 生成物（Herdr Protocol）不変
# 重点（関連 12 本 + 依存）:
flutter test test/screens/terminal/ansi_text_view_test.dart \
  test/screens/terminal/ansi_text_view_bg_test.dart \
  test/screens/terminal/ansi_text_view_key_test.dart \
  test/screens/terminal/ansi_text_view_modifier_test.dart \
  test/screens/terminal/ansi_text_view_scroll_send_test.dart \
  test/screens/terminal/terminal_screen_contract_test.dart \
  test/screens/terminal/terminal_screen_follow_scroll_test.dart \
  test/screens/terminal/terminal_screen_history_test.dart \
  test/screens/terminal/terminal_screen_input_test.dart \
  test/screens/terminal/terminal_screen_lifecycle_test.dart \
  test/screens/terminal/terminal_screen_scroll_send_test.dart \
  test/screens/terminal/terminal_screen_herdr_test.dart \
  test/screens/terminal/terminal_screen_remaining_contracts_test.dart
```

推奨新規テスト（任意・拘束なし）: リビルド範囲（キャレット行のみ再構築）の回帰 / `AnsiGestureEngine` のティック累積単体 / `AnsiKeyComposer` の純粋合成単体。

---

## 8. 未確定点

- **なし**。ただし以下は設計判断として記録:
  1. `_EagerScaleGestureRecognizer`（private）は現行同様 view 層の private に置く。Dart の下線プレフィックスは同一ライブラリ（同一ファイル）内のみ参照可能だが、**定義と使用が同一ファイル内（ansi_terminal_view.dart）なら private のまま可**（v2・critique §2.4 反映）。別ファイルへ移す場合のみ public 化が必要だが、本設計では不要。
  2. `toggleCtrl/toggleAlt/toggleShift/ctrlPressed/altPressed/shiftPressed/resetModifiers` は `AnsiTextViewState.` 接頭辞に限定した rg で呼出元ゼロ（lib/test 0 件・素の `toggleCtrl` は P2 済み special_keys_bar 側の別オブジェクトに存在）だが、State の公開面として維持（P2 conn §4.3「デッドだが公開 API は維持」に同じ）。
  3. `isAsciiPrintable`/`deriveBaseChar` の State 側残置は「静的委譲」に限定（テストの直接 new 互換）。
# P2-6: `lib/widgets/special_keys_bar.dart` 責務ベース再設計（設計書 v2）

- 対象: `lib/widgets/special_keys_bar.dart`（HEAD 1577 行）
- 種別: 設計のみ（コード変更なし）
- 方針: 責務境界を最優先。機械的分割（1行委譲wrapper・util grab-bag・private共有mixin/part）を排除。

## v2 改訂履歴（design-critic レビュー /tmp/p2-design/critique.md §1 反映）

| # | 変更 |
|---|---|
| v2-1 | 【重大】実行時 prop 伝播の配線を設計に追加。エンジンに `setCallbacks` / `setCjkMode` / `setKeepKeyboardOnEnter` を設け、State の **didUpdateWidget で毎回（無条件）最新値を伝播**。初期値固定はステルス回帰と明記（§2・§6-3-g・§7）。 |
| v2-2 | `SpecialKeysBarCallbacks` から状態（cjkMode / keepKeyboardOnEnter）を分離。コールバック値オブジェクトは onKeyPressed / onSpecialKeyPressed / hapticFeedback のみ。状態はエンジンの唯一所有（§2・§4）。 |
| v2-3 | composer の「純粋」記述を修正。`applyHardwareModifiers` は `HardwareKeyboard.instance` 依存のため単体テスト不能 → テスト方針を「純粋部（composeSpecial/composeLiteral/hwSpecialKeyMap）は単体、HW修飾子は Widget テストでシミュレートキー駆動」に修正（§2・§5）。 |
| v2-4 | 依存グラフに `special_keys_bar_rows.dart`（DirectInputRow）→ `special_keys_direct_input_engine.dart` の辺を追加（controller/focusNode/handleSubmitted/handleHardwareKeyEvent 配線）（§3）。 |
| v2-5 | State ~340 行見積の根拠（内訳）を提示し、超過時の追加分離スロット（送信オーケストの `SpecialKeysSender` 化）を明記（§2-付記・§7）。 |
| v2-6 | ValueKey 記述のスコープを「**SpecialKeysBar 関連はゼロ**」に修正（リポジトリ全体では `ValueKey('mux-sel-*')` が herdr セレクタ UI に存在、本バーとは無関係）（§4・§8）。併せて責務Aの行範囲表記に `_rowScrollControllers`（L91）混在の注記を追加（§1）。 |

---

## 1. 現状責務分析（HEAD 1577行・検証済み行番号）

`_SpecialKeysBarState` 1クラスが **6つの異なる責務** を兼務している。State は Flutter の仕様上分割不可のため、各責務を「状態の所有者を明確にした協調クラス＋子Widget」へ抽出する。

| # | 責務 | 該当箇所（検証済み） | 行数 |
|---|---|---|---|
| A | **IME/DirectInput 状態機械**（sentinel・delta送信・CJK全文送信・composing追跡・iOS重複除去・二重入力抑制・外付けキーボード処理） | fields 88-112 のうち `_directInputController` `_directInputFocusNode` `_sentText` `_isComposing` `_lastComposingText` `_isResettingController` `_lastKeyEventHandledAt` `_sentinel`(const)、メソッド 204-595 の大部分（※88-112 には責務Cの `_rowScrollControllers` L91 が混在） | ~390 |
| B | **ソフトウェア修飾子状態**（CTRL/ALT/SHIFTトグルと消費・リセット） | fields 79-81、`_resetSoftwareModifiers` 513-523、各所の setState 消費 | ~60 |
| C | **行スクロール制御**（行数追従・新規ボタン位置への自動スクロール） | fields 107-110、158-201、didUpdateWidget のdiff部分 | ~55 |
| D | **tmuxキー名合成**（S/C/M順・BTab特別扱い・ハードウェア修飾子適用・キー→tmuxマップ） | `_applyHardwareModifiers` 456-474、`_hwSpecialKeyMap` 475-501、`_sendSpecialKey`/`_sendLiteralKey` 内の合成部 | ~80 |
| E | **バー/行レイアウト**（レガシー判定・pencilホスト判定・可視トークンフィルタ・行Widget） | build 600-637、_buildRow 638-654、_buildPencilOnlyRow 655-662、_buildLegacyModifierKeysRow 663-696、_buildLegacyArrowKeysRow 697-733、_buildGenericTokenRow 734-772、_visibleTokens 773-777、_shouldRenderToken 846-855 | ~230 |
| F | **トークン→Widget解決**（18種スイッチ・「ck:」カスタム解決・ラベル幅計算） | _buildToken 778-845、_buttonForToken 856-865、_labelWidth 866-869、_buildCustomKeyButton 870-887 | ~110 |
| G | **ボタンWidget群**（12種） | _buildDirectInputField 1084-1180、_buildSpecialKeyButton 1181-1230、_buildLiteralKeyButton 1231-1279、_buildModifierButton 1280-1337、_buildArrowButton 1338-1362、_buildNavigationKeyButton 1363-1397、_buildImageTransferButton 1398-1427、_buildNumberKeyButton 1428-1461、_buildInputButton 1462-1503、_buildManageButton 994-1016、_buildDirectInputToggle 1049-1083、_buildEnterKeyButton 934-993、_buildShiftEnterKeyButton 888-933、_buildNavigationControls 1017-1040、_buildDirectInputRow 1041-1048 | ~620 |
| H | 送信オーケストレーション（`_sendSpecialKey` 1504-1546・`_sendLiteralKey` 1547-1577、haptic＋修飾子消費＋コールバック発火） | 1504-1577 | ~75 |

**状態の所有者の現状**（全て State に混在）: 修飾子3bool / TextEditingController / FocusNode / delta状態 `_sentText` / IME状態 `_isComposing` `_lastComposingText` / 再入防止 `_isResettingController` / 二重入力抑制時刻 / 行ScrollControllerリスト。

**パススルー経路の重要仕様（抽出時に厳守）**:
- **sentinel方式**: 常に `'\u200B'` を保持し空状態のBackspaceを検出（iOS/iPadOS）。`_resetToSentinel` は **PostFrameCallback で再リセット＋`_isResettingController` 解除を次フレーム遅延**（iOSの遅延確定吸収）。composing進行中は再リセットしない。
- **delta送信**: `_sentText` との共通接頭辞差分のみ送信・削除分はBSpace。
- **二重入力抑制**: `_handleKeyEvent` 処理時刻を記録し、直近 **100ms以内** のテキスト更新をスキップ。
- **Samsung workaround**: CTRL/ALT押下中は composing 開始1文字目（ASCIIのみ）を即時 `C-x`/`M-x` 送信して sentinel へリセット。
- **keepKeyboardOnEnter**: `onSubmitted` 内の **同期 requestFocus()** でフレームワーク既定の unfocus を実質キャンセル（editable_text の明示サポート経路）。※送信時に `widget.keepKeyboardOnEnter` を**ライブ参照**（L402）。
- **Focus(onKeyEvent)** が TextField を包み、`_handleKeyEvent` が Ctrl/Meta+AZ、Enter、特殊キーマップを処理。IME composing中は無視。
- 無効化パス: `_isResettingController=true` → `clear()`（リスナーは同期発火するためガード必須）→ false、`_sentText=''`。

**実行時 prop のライブ参照（v2 で最重要の事実）**:
- `widget.keepKeyboardOnEnter` は `_onDirectInputSubmitted` 内で**送信時にライブ参照**（L402）。didUpdateWidget に当該分岐は無いが、ライブ参照ゆえ実行中トグルが即反映される。
- `widget.cjkMode` は `_onDirectInputChanged` 内でライブ参照（L246 付近、CJK分岐）。
- `widget.hapticFeedback` は約20箇所（L228/291/352/390/409/504/542/557/592 ほか）でライブ参照。
- 実経路: `terminal_screen.dart` は `settingsProvider.select((s) => s.keepKeyboardOnEnter)` を watch して prop を毎構築時に渡すため（Consumer 内）、**動作中に keepKeyboardOnEnter が false→true へ変更され得る**。

---

## 2. 提案構成（8ファイル・全ファイル500行未満）

既存フラット命名（`custom_key_button_widget.dart` 等）に合わせ、`special_keys_` 接頭辞のフラット配置。**`special_keys_bar.dart` のパス・公開APIは不変**（呼出元0変更）。

| ファイル | 1文責務 | 公開面 | 推定行数 |
|---|---|---|---|
| **`lib/widgets/special_keys_bar.dart`（既存・改修）** | SpecialKeysBar の公開Widgetと、協調クラス群・子Widget群を配線するだけの合成ルート（State）。**didUpdateWidget で実行時 prop を毎回エンジンへ伝播**する。 | `SpecialKeysBar`（**現行と完全同シグネチャ**） | ~340（内訳は付記） |
| **`lib/widgets/special_keys_direct_input_engine.dart`** | DirectInput/IME の状態機械。TextEditingController・FocusNode・sentinel・delta・composing・二重入力抑制・外付けキーボードイベント処理の**唯一の所有者**。**状態フラグ（cjkMode / keepKeyboardOnEnter）も唯一所有**し、実行時伝播用 setter を持つ。 | `SpecialKeysDirectInputEngine`（controller/focusNode getter、`attach`/`dispose`、`handleTextChanged`/`handleSubmitted`/`handleHardwareKeyEvent`、`resetToSentinel`/`clearForDeactivation`、**`setCallbacks(SpecialKeysBarCallbacks)` / `setCjkMode(bool)` / `setKeepKeyboardOnEnter(bool)`**）＋値オブジェクト `SpecialKeysBarCallbacks` | ~400 |
| **`lib/widgets/special_keys_modifier_state.dart`** | ソフトウェア修飾子（S/C/M）押下状態の唯一の所有者。消費（1個ずつ通知）と一括リセット（1回通知）の意味論を持つ ChangeNotifier。 | `SpecialKeysModifierState`（`shift/ctrl/alt` getter、`any`、`consumeAll()`（消費順S→C→M情報を返す）、`clearAll()`、`toggle*(...)`） | ~90 |
| **`lib/widgets/special_keys_tmux_composer.dart`** | tmuxキー名の合成。ソフトウェア修飾子接頭辞（S,C,M順・BTab特別扱い）、ハードウェア修飾子検出（`HardwareKeyboard.instance` 読み取り）、LogicalKeyboardKey→tmuxキー静的表。**純粋なのは composeSpecial/composeLiteral/hwSpecialKeyMap のみ**（applyHardwareModifiers は flutter/services 依存）。 | `SpecialKeysTmuxComposer`（`composeSpecial(baseKey, shift, ctrl, alt)` / `composeLiteral(...)` / `applyHardwareModifiers(baseKey)` / `hwSpecialKeyMap`） | ~120 |
| **`lib/widgets/special_keys_row_scrollers.dart`** | 行水平ScrollController群の所有・行数追従sync・新規トークン位置への自動スクロール手配（postFrame＋isActiveガード）。 | `SpecialKeysRowScrollers`（`sync(rowCount)` / `scheduleScrollToNewToken(row, {atStart})` / `controllerAt(row)` / `dispose`） | ~80 |
| **`lib/widgets/special_keys_token_view.dart`** | トークン→ボタンWidget解決（18種スイッチ・`ck:`カスタム解決・幅計算）とモード依存可視性ルールの所有者。 | `SpecialKeysTokenView`（`visibleOf(tokens, directInputEnabled, hasImage)` 静的、`build(context, token, {height})`、`shouldRender(token)`） | ~170 |
| **`lib/widgets/special_keys_bar_rows.dart`** | 行レイアウトの決定（レガシー行判定 `listEquals`・pencilホスト行・鉛筆のみ行・可視行計算）と行Widget 4種（レガシー修飾子行/レガシーナビ行/汎用トークン行/DirectInput行）。**DirectInputRow はエンジンから controller/focusNode/handleSubmitted/handleHardwareKeyEvent を配線**する。 | `SpecialKeysBarLayout`（`RowLayout.compute(rows, directInputEnabled, hasImage)` 純粋）＋ `LegacyModifierRow` / `LegacyNavigationRow` / `GenericTokenRow` / `DirectInputRow` | ~360 |
| **`lib/widgets/special_keys_bar_buttons.dart`** | バーのプッシュボタン群（キー風32px・36pxアイコン風・アクセント RET/S-RET/Cmd・鉛筆・トグル・LIVE）の静的な見た目Widget。状態を持たない。 | `SpecialKeyButton` / `LiteralKeyButton` / `ModifierButton` / `EnterKeyButton` / `ShiftEnterKeyButton` / `ArrowKeyButton` / `NavigationKeyButton` / `NumberKeyButton` / `SpecialKeysImageButton`（※既存 `ImageTransferButton` と別物のため別名）/ `CmdInputButton` / `ManageButton` / `DirectInputToggleButton` | ~330 |

### 実行時 prop 伝播の必須配線（v2-1 の詳細）

現行は送信時刻に `widget.keepKeyboardOnEnter` / `widget.cjkMode` / `widget.hapticFeedback` をライブ参照する。エンジン化後も**毎回の最新値が送信時刻に読めること**を保証するため:

- `SpecialKeysBarCallbacks` は **onKeyPressed / onSpecialKeyPressed / hapticFeedback の3要素のみ**。`hapticFeedback` もライブ参照（約20箇所）なので、**コンストラクタ注入固定は禁止**。
- cjkMode / keepKeyboardOnEnter は状態フラグであり、**エンジンの setter（`setCjkMode` / `setKeepKeyboardOnEnter`）経由でのみ保持**される。callbacks 値オブジェクトに複製しない（二重管理禁止・v2-2）。
- State の `didUpdateWidget` は**無条件で毎回** `engine.setCallbacks(...)`・`setCjkMode(...)`・`setKeepKeyboardOnEnter(...)` を呼び、最新 widget 値を伝播する（分岐を増やさない方針としないこと。既存テストは初期値のみ検証するため、伝播漏れは**テストでは検出不能**）。
- これとは別に、従来どおりの**分岐駆動の副作用**（directInputEnabled 有効化→reset / 無効化→clearForDeactivation / cjkMode 切替→resetToSentinel、行数 sync・行diffスクロール）は State が実行する（v2-1 の伝播と分岐副作用は役割が異なる）。

### 付記: 合成ルート State ~340 行の根拠と超過時スロット（v2-5）

見積内訳（v2、概算）: SpecialKeysBar widget クラス ~65 / State 残置 fields ~10・initState ~12・didUpdateWidget ~45（伝播3行＋分岐副作用・行diffスクロール判定含む）/ dispose ~8 / `_sendSpecialKey`+`_sendLiteralKey` ~75（合成と消費は composer/modifier_state へ委譲し順序のみ保持）/ build 骨格 ~55（`SpecialKeysBarLayout.compute` 呼出＋行Widget 4種の配置）/ isActive 供給・notifier 経由 setState 等の小配線 ~30 / import・doc ~50。**合計 ~350**（上限近くで500行未満は満たす見込み）。

**超過時の追加分離スロット**（`flutter analyze` 後の実測で countLines が 500 を超えた場合のみ適用・段階2）:
- 先ず **送信オーケストの分離**: `_sendSpecialKey`/`_sendLiteralKey` を `SpecialKeysSender`（新ファイル `special_keys_sender.dart`）へ。composer/modifier_state/callbacks を受け取り「haptic → 合成 → 修飾子消費 → コールバック発火」の順序を保持する実ロジックを持つ独立クラス（単発2メソッドでも BTab 特別扱い・S/C/M消費順・リテラル単文字条件という実ロジックがあるため1行委譲wrapper には該当しない）。State は1行の委譲呼出のみになる。
- 更に必要な場合: build 骨格の `SpecialKeysBarView`（StatelessWidget）化により行配置を子へ移動。

---

## 3. 依存グラフ（非循環・明示的）

```
special_keys_bar.dart（SpecialKeysBar + State = 合成ルート）
 ├─ special_keys_modifier_state.dart
 ├─ special_keys_direct_input_engine.dart
 │   ├─ special_keys_modifier_state.dart        （Samsung workaround の修飾子消費）
 │   └─ special_keys_tmux_composer.dart         （HWキーイベントのマップ/合成）
 ├─ special_keys_row_scrollers.dart
 ├─ special_keys_bar_rows.dart
 │   ├─ special_keys_direct_input_engine.dart   ★v2-4: DirectInputRow が controller/
 │   │                                            focusNode getter・handleSubmitted・
 │   │                                            handleHardwareKeyEvent を配線
 │   ├─ special_keys_bar_buttons.dart
 │   ├─ special_keys_token_view.dart
 │   │   ├─ special_keys_bar_buttons.dart
 │   │   ├─ special_keys_modifier_state.dart    （ctrl/alt/shift トークン行）
 │   │   └─ custom_key_button_widget.dart（既存）
 │   └─ services/custom_keys（CustomKeyRows・CustomKeyButton）（既存）
 └─ special_keys_tmux_composer.dart              （_sendSpecialKey/_sendLiteralKey 用）

special_keys_bar_buttons.dart → theme/design_colors・google_fonts・l10n（既存・葉）
special_keys_direct_input_engine.dart → flutter/services（LogicalKeyboardKey 等）
special_keys_tmux_composer.dart → flutter/services（HardwareKeyboard / LogicalKeyboardKey）
```

- 循環なし。エンジン→State、State→エンジンの相互参照は発生しない（エンジンは `bool Function() isActive`（= `() => mounted`）と `SpecialKeysBarCallbacks` を受け取るのみ。**注: callbacks はコンストラクタ注入に加えて didUpdateWidget 経由で毎回 `setCallbacks` により更新される**）。
- 継承は一切使わない（mixin/base/part 禁止）。協調は「State が has-a で所有し、通知（ChangeNotifier）と値オブジェクトで接続」。
- 既存の `CustomKeyButtonWidget`（103行・別責務）は**移動しない**。

---

## 4. API変更 before → after

| 対象 | Before | After | 備考 |
|---|---|---|---|
| `SpecialKeysBar`（パス・クラス・コンストラクタ） | 不変 | **不変** | 公開パラメータは実測 **14**（`super.key` 含む / 名前付き13）。※タスク説明の「19」は誤差のため修正 |
| `_SpecialKeysBarState`（private） | 全責務を兼務 | 合成ルートのみ（実行時 prop 伝播を含む） | private なので API 非該当 |
| 新規公開クラス | — | 上記7ファイルの7クラス | 全て本バー内部でのみ使用。public にするのはテスト可能性のため（エンジン・合成・レイアウトはテスト可能）。**エンジンの `setCallbacks`/`setCjkMode`/`setKeepKeyboardOnEnter` は実行時伝播の正式経路** |
| 削除 | — | なし（public API の削除なし） | |

**テストが参照する公開APIの実測**（test/widgets/special_keys_bar_test.dart 40テスト）:
- `find.byType(SpecialKeysBar)` / `find.byType(TextField)` / `find.byType(SingleChildScrollView)`（水平）/ `find.byType(GestureDetector)`（ancestor）
- `find.byWidgetPredicate((w) => w is CustomKeyButtonWidget && w.button.id == ...)`
- `find.text('CTRL'|'ESC'|...)` / `find.byIcon(Icons.edit_outlined)` 等の**表示内容**
- `TextField.controller` / `TextField.focusNode` への直接アクセス（direct input系）
- ScrollController.offset の直接検証（行 auto-scroll 系 L906-944）

→ **SpecialKeysBar 関連の ValueKey 参照はゼロ**（v2-6: リポジトリ全体には `ValueKey('mux-sel-*')` が herdr セレクタ UI 用に存在するが本バーとは無関係）。表示されるテキスト・アイコン・Widget型（`TextField`/`SingleChildScrollView`/`CustomKeyButtonWidget`/`GestureDetector`）・幾何（32x32鉛筆・行位置・スクロールオフセット）を維持する限り、**テスト更新ゼロ**で成立。

---

## 5. 呼出元・テスト更新リスト（実測）

| ファイル | 種別 | 更新要否 | 内容 |
|---|---|---|---|
| `lib/screens/terminal/terminal_screen.dart`（import L71・呼出 L3570-3595） | 呼出元 | **不要** | シグネチャ不変のため0編集。Consumer内の `ref.watch` 構成にも影響なし（keepKeyboardOnEnter の select-watch もそのまま） |
| `test/widgets/special_keys_bar_test.dart`（1072行・40テスト） | テスト | **不要** | 上記参照面が不変のため。※移行途中の各ステップで実行し回帰ゲートとする |
| `test/screens/terminal/terminal_custom_keys_test.dart` / `terminal_custom_keys_e2e_test.dart` / `terminal_screen_herdr_test.dart` / `terminal_screen_can_test.dart` / `connections_screen_herdr_test.dart` | テスト | **不要** | `find.byType(SpecialKeysBar)` + text/icon のみ |
| 新規テスト（任意・推奨） | 追加 | — | 下記「新規テスト方針」 |

**新規テスト方針（v2-3 修正）**:
- `SpecialKeysTmuxComposer` の**純粋部のみ単体テスト可能**: `composeSpecial` / `composeLiteral`（S/C/M順・BTab・リテラル単文字条件）と `hwSpecialKeyMap`（静的定数）。
- `applyHardwareModifiers` は `HardwareKeyboard.instance` を読むため**単体テスト不能**。Widget テストで `tester.sendKeyDownEvent(...)` により HardwareKeyboard 状態を駆動し、エンジン経由（`handleHardwareKeyEvent`）で検証する。
- 推奨追加: 実行時 prop 伝播の回帰テスト（既存40本は初期値のみで**実行中トグルを検証しない**ため）— 例: `keepKeyboardOnEnter:false` で pump → `customHarness(... keepKeyboardOnEnter: true ...)` で再 pump → submit 後に focus 維持、を検証。

---

## 6. 移行手順（各ステップで `flutter analyze` + `flutter test test/widgets/special_keys_bar_test.dart` をパス）

依存の葉から順に、**動かす前に作る・1ステップ=1責務** で進める。UIツリー不変のため 4〜8 は各ステップ終了時点で全テスト green を維持できる。

1. **`special_keys_tmux_composer.dart` 新設**（依存なし）
   `_applyHardwareModifiers`・`_hwSpecialKeyMap` をコピー移動し、`_sendSpecialKey`/`_sendLiteralKey` の合成部を `composeSpecial`/`composeLiteral` へ抽出。State は composer を呼ぶだけにする。合成順・BTab分岐・`key.length==1` 条件は現行から一字も変えない。※`applyHardwareModifiers` は HardwareKeyboard 読み取りのまま移動（純粋化しない）。
2. **`special_keys_modifier_state.dart` 新設**（foundationのみ）
   3bool を `SpecialKeysModifierState` へ移動。State は `initState` で listener を張り `setState`、dispose で解除。全 setState 消費点（`_sendSpecialKey`/`_sendLiteralKey`/`_resetSoftwareModifiers`/Samsung系）を `consumeAll()`/`clearAll()` に置換。**消費順 S→C→M と条件付き setState は維持**。通知はメソッド呼び出し内で同期＝現行の setState 位置と同一。
3. **`special_keys_direct_input_engine.dart` 新設**（最大ステップ・IME挙動は手順に沿って機械的に移動）
   - コンストラクタ: `{required SpecialKeysModifierState modifiers, required SpecialKeysBarCallbacks callbacks, required bool Function() isActive}`。
   - `initState` 相当 `attach()`: **sentinel 値を設定してから listener を張る**（現行 115-127 の順序を維持）。
   - 204-505（`_onDirectInputChanged`〜`_resetToSentinel`）と 444-454（時刻抑制）・524-595（`_handleKeyEvent`/`_sendDirectEnterAndClear`）を**ロジック変更なしで移動**。haptic・コールバックは `callbacks` 経由。`setState(() => _ctrlPressed = false)` は `modifiers.consumeCtrl()` へ。`widget.cjkMode` / `widget.keepKeyboardOnEnter` / `widget.hapticFeedback` のライブ参照は**エンジンが保持する最新値**（下記 g で毎回更新）への参照に置換。
   - **フォーカス・IMEタイミング保全の具体手順**:
     a. `_resetToSentinel` の PostFrameCallback はエンジン内にそのまま保持。ガードは `mounted` → `isActive()`（Stateが `() => mounted` を渡す）へ置換。dispose 後は `_disposed` フラグでも遮断（二重ガード）。
     b. `_onDirectInputSubmitted` 内の同期 `focusNode.requestFocus()`（keepKeyboardOnEnter）の**呼び出し位置・順序**（`onSpecialKeyPressed('Enter')`→`resetToSentinel()`→`requestFocus()`）を維持。`keepKeyboardOnEnter` は**その時点の setter 反映値**を参照。TextField 側は `onSubmitted: engine.handleSubmitted` の同期デリゲートのみ。
     c. `Focus(onKeyEvent: engine.handleHardwareKeyEvent)` の **Focus 配置・戻り値 `KeyEventResult`** を不変に。composing 中 `ignored` → 特殊キー `handled` の分岐順も不変。
     d. 無効化パスは `clearForDeactivation()`（`_isResettingController=true` → clear → false → `_sentText=''`）専用メソッドとして **同期発火ガードの順序**を保持。
     e. `didUpdateWidget` の分岐副作用（有効化→reset / 無効化→clearForDeactivation / cjk切替→reset、その後 scrollers sync → 行diffスクロール）を State 側で現行どおり維持。
     f. **（v2-1 追加）** 分岐副作用とは別に、`didUpdateWidget` 冒頭で**無条件に毎回** `engine.setCallbacks(callbacks)`・`engine.setCjkMode(widget.cjkMode)`・`engine.setKeepKeyboardOnEnter(widget.keepKeyboardOnEnter)` を呼ぶ。**初期値固定・初回のみ注入は禁止**（keepKeyboardOnEnter/hapticFeedback/cjkMode のライブ参照を再現するための必須配線。terminal_screen の select-watch による実行中トグルが既存実経路）。
4. **`special_keys_row_scrollers.dart` 新設**
   `_rowScrollControllers`/`_syncRowControllers`/`_scheduleScrollToNewToken`/`_grewAtStart` を移動。postFrame ガードは `isActive` + `hasClients`（現行同等）。`dispose` 順（エンジン→scrollers）を維持。
5. **`special_keys_bar_buttons.dart` 新設**
   12種のボタンWidgetを「props（label/icon/isPressed/onTap）+ haptic」の StatelessWidget として抽出。スタイル値（keyBackground 等）・`GoogleFonts.jetBrainsMono`・テキスト/アイコンは現行から不変。`ModifierButton` は `SpecialKeysModifierState` を受け取り押下状態を描画。
6. **`special_keys_token_view.dart` 新設**
   `_buildToken` スイッチ・`_buttonForToken`・`_labelWidth`・`_visibleTokens`/`_shouldRenderToken` を移動。`ck:` 解決ロジック（`'ck_${token.substring(3)}'`）とカスタム幅計算は不変。
7. **`special_keys_bar_rows.dart` 新設**
   `build` の判定部を `SpecialKeysBarLayout.compute(...)` へ抽出（`listEquals` レガシー判定・`!hostsPencil` 条件・pencilホスト/鉛筆のみ行・可視行の空判定は一字不変）。行Widget 4種へ置換。**DirectInputRow はコンストラクタでエンジンを受け取り**、`controller`/`focusNode` getter・`handleSubmitted`・`handleHardwareKeyEvent` を配線する（★v2-4）。`TextField` は `DirectInputRow` に内包し、**`directInputField()` 等のテストFinder（byType(TextField)）がそのまま当たる構成**を維持。
8. **`special_keys_bar.dart` 整理**
   State を合成ルートに縮小（~340行・内訳は§2付記）。不要となった private メソッドを削除。import を更新し、`flutter analyze`（警告ゼロ）＋全テスト（`make test`）で締める。**実際の行数が 500 を超えた場合は §2 付記の分離スロット（`SpecialKeysSender` 化）を適用**。

各ステップの境界で `git commit` し、ステップ3は直入力/CJK系テスト（`direct input field` 6本 + `CJK mode` 4本）と `keepKeyboardOnEnter` 系2本（L678/L832）を重点実行。ステップ3完了時点で新規の実行時トグル回帰テスト（§5）を追加する。

---

## 7. リスクと対策

| # | リスク | 影響 | 対策 |
|---|---|---|---|
| 1 | **IMEタイミング回帰**（最大リスク）: sentinel再リセットのpostFrame遅延・composing尊重・`_isResettingController` ガード・同期requestFocus・100ms抑制を失うと iOS/Android IME で多重送信/欠落 | 実機挙動劣化（テストは薄い） | 6-3 の手順a-eを厳守。エンジン移動は**ロジック変更禁止**（移動のみ・差分は commit レビューで確認）。既存40テスト＋step3 の重点実行 |
| 2 | **実行時 prop 伝播の漏れ（v2-1・ステルス回帰）**: エンジンが初回の keepKeyboardOnEnter=false で固定されると「有効化しても submit 後に unfocus」になる。既存テストは初期値のみで検出不能 | 設定変更が反映されない（実経路あり: terminal_screen の select-watch） | didUpdateWidget での**無条件 setCallbacks/setCjkMode/setKeepKeyboardOnEnter** を設計に固定。新規回帰テスト（実行中トグル）を step3 後に追加 |
| 3 | `mounted` → `isActive()` への置換の等価性 | 微小 | postFrame 実行時に State が unmounted で dispose 済みなら `_disposed` ガードが同等遮断。unmounted 未dispose の窓は同一フレーム内で実質存在しない（推測として明記・回帰テストで担保） |
| 4 | ChangeNotifier 化による通知回数の差異（setState 複数回→1回等） | なし | setState の実行回数・フレーム数は**どのテストも観測していない**（実測）。最終描画状態が同一であることのみ担保 |
| 5 | ボタン/行の新Widget型導入で `find.byType` 系が壊れる | 低 | テストが参照するのは TextField / SingleChildScrollView / CustomKeyButtonWidget / GestureDetector / text / icon のみ。これらは**別名・別型にしない** |
| 6 | 分割過剰（8ファイル）と見なされる | 中 | 各ファイルは「状態所有者」または「見た目」の単一責務で、1行委譲wrapperは含まない（超過時スロットも実ロジックを持つ `SpecialKeysSender` のみ）。批判レビューで歯止め |
| 7 | `ImageTransferButton`（既存 ConsumerWidget）との混同・統合誘惑 | — | バーの実装はコールバック駆動で別責務。統合は挙動変更（provider購読化）を招くため**対象外**と明示 |
| 8 | 合成ルート State が500行超過（見積 ~350は楽観的との批判あり） | 中 | §2 付記の内訳で ~350 と試算。超過検出時は `SpecialKeysSender` 化（→~280行）を**第1候補**として適用 |

---

## 8. 事実と推測の区別

### 事実（コード・テスト・呼出元からの直接観測）
- HEAD 1577行。`_SpecialKeysBarState` のメソッド配置は1節の行番号どおり（grepで検証）。責務Aの fields 範囲 88-112 には責務Cの `_rowScrollControllers`（L91）が混在（表記上の重複のみ）。
- `SpecialKeysBar` の公開パラメータは名前付き13＋`super.key`=**14**（タスク説明の19は誤り）。
- 呼出元は `lib/screens/terminal/terminal_screen.dart` L3570-3595 の1箇所のみ（名前付き12を明示、hapticFeedback は既定 true）。他はテスト5ファイル（`find.byType(SpecialKeysBar)` 使用）。
- **ライブ参照の事実**: `widget.keepKeyboardOnEnter` L402・`widget.cjkMode` L246付近・`widget.hapticFeedback` 約20箇所（L228/291/352/390/409/504/542/557/592 ほか）。terminal_screen は `settingsProvider.select((s) => s.keepKeyboardOnEnter)` を watch して毎構築時に prop を渡す（実行中トグルの実経路）。
- テストが参照するのは byType/byText/byIcon/byWidgetPredicate/ancestor(GestureDetector)/TextField の controller・focusNode・ScrollController.offset のみ。**SpecialKeysBar 関連の ValueKey 参照はゼロ**（v2-6: リポジトリ全体の `ValueKey('mux-sel-*')` は herdr セレクタ UI 用で無関係）。
- DirectInput 系テストは `TextField` の controller.text（sentinel除去）と focusNode.hasFocus を直接検証。CJK4本は全文送信・composing重複除去・モード切替リセット・Enter 1回を検証。既存テストは**実行中 prop トグルを検証しない**（keepKeyboardOnEnter 系 L678/L832 とも初期値のみ）。
- `CustomKeyRows`（standardRow1/2・directInputExtras・`isCustomToken`）は `lib/services/custom_keys/custom_key_button.dart` に既存。`CustomKeyButtonWidget` は既に別ファイル（103行）。`ImageTransferButton`（ConsumerWidget・L12）が `lib/widgets/image_transfer_button.dart` に既存で別実装。
- P1 precedent: `lib/theme/` の `app_theme_palette.dart`（データ所有者）+ `app_theme_builder.dart`（ビルダー）+ `app_theme.dart`（facade 25行）の「所有者分離」パターン。

### 推測（検証が必要 or 設計判断）
- 「setState 実行回数・フレーム数はテスト未観測」→ コード grep では確認したが、回帰を絶対視しない（step2 で 40 テスト green を確認）。
- 「unmounted かつ未dispose の窓は postFrame 時点で実質存在しない」→ Flutter の解除タイミングに基づく推測。`isActive()`＋`_disposed` 二重ガードで実害を封じる。
- 「8ファイル分割が責務ベースの適正粒度」→ 設計判断。批判レビュー（Devil's Advocate / Gap Hunter）で検証する。
- 「エンジンと新規7クラスを public にするのがテスト可能性に有利」→ 判断。private 化し見た目テストのみに絞る選択肢もあるが、責務クラスの単体テスト余地を残す。
- 「State ~350行（500未満）収まる」→ 内訳による見積。超過時は §2 付記の `SpecialKeysSender` 化で対応（v2-5）。
- 「hapticFeedback の実行中トグルは現状 terminal_screen が既定 true のため実害なし」→ 現状は実害薄いが、**未来の呼出元変更で壊れ得る経路**として伝播対象に含める（v2-1）。

---

## 付録: タスク説明の「既知の構造」との差分（検証結果）

- 「公開パラメータ19」→ 実測 **14**（誤差を修正）。
- 「DirectInput/IME 204-505」→ `_onDirectInputChanged` 204 〜 `_resetToSentinel` 420 で、444-454 に時刻抑制、456-501 にHWマップ、502-523 にHW送信/修飾子リセット、524-595 にキーイベント/Enterクリア。責務Aの範囲は 88-112(fields・L91に責務C混在)+204-595 が実体。
- 「送信 1504-1577」→ 正しい（`_sendSpecialKey` 1504 / `_sendLiteralKey` 1547）。
- 行番号はすべて grep 済みの実測値。
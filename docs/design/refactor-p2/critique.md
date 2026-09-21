# P2 責務ベース再設計（4設計書）に対する批判的レビュー

- レビュアー: p2-design-critic（タスク#27）
- 対象: /tmp/p2-design/skeys.md / rdialog.md / providers-core.md / providers-conn.md
- 検証方法: 実ファイルの grep / read による事実確認（HEAD f474d23）
- 凡例: 【重大】挙動不変を損ない得る設計穴 【中】設計不備・事実の歪曲 【軽微】事実誤認・表記 【良い点】正確だった点

---

## 0. 全体サマリ（4設計書横断）

1. **export 戦略が設計書間で3分裂**（後述 §各書）。同じ P2 内で「compat re-export 禁止／re-export 推奨／barrel 許容+代替」と基準が揺れており、呼出元 churn の前提が矛盾。チーム方針の統一が先決。
2. **行数見積の総計は現行を上回る**: 現行 6,247 行（7ファイル）→ 提案合計 ≈7,310 行（+17%）。「各ファイル500行未満」は全設計書で満たす見込みだが、分割による増加（クラス境界・import・doc）の正当化が各書とも薄い。
3. テスト fake/overrideWith/extends 依存の洗い出しは3設計書とも**概ね正確**（実測で確認: FakeSshNotifier 7、_FakeConnectionsNotifier 3、_FakeActiveSessionsNotifier 2、FakeSettingsNotifier 7、DownloadNotifier 直接構築）。
4. 「機械的分割を解消できていない箇所」は各書の節で明記（skeys の callbacks 伝播穴・rdialog の骨格コピペ残存・core の shell 330行・conn の orchestrator state 経路）。

---

## 1. skeys.md（special_keys_bar.dart）

### 1.1 【重大】keepKeyboardOnEnter の実行時変更がエンジンに伝播する経路が設計に無い

- **事実**:
  - 現行 `_onDirectInputSubmitted` は送信時に `widget.keepKeyboardOnEnter` を**ライブ参照**（special_keys_bar.dart L402）。
  - 現行 didUpdateWidget の分岐は directInputEnabled と cjkMode のみ（L130-152）— keepKeyboardOnEnter の分岐は**存在しない**が、ライブ参照なので実行中トグルが即反映される。
  - terminal_screen は `settingsProvider.select((s) => s.keepKeyboardOnEnter)` を watch して prop で毎回渡す（terminal_screen.dart L3588-3591 付近の Consumer 内）。つまり動作中に false→true へ変更される実経路が存在する。
  - 設計書のエンジン公開面は「attach/dispose/handleTextChanged/handleSubmitted/handleHardwareKeyEvent/resetToSentinel/clearForDeactivation/setCjkMode/setEnabled」のみ。**setKeepKeyboardOnEnter / setCallbacks がない**。callbacks はコンストラクタで注入固定。
- **評価**: エンジンが initState 相当時点の callbacks（keepKeyboardOnEnter 含む）を保持し続けると、設定変更が反映されず「keepKeyboardOnEnter を有効にしても submit 後に unfocus される」ようになる。既存テスト（L678 / L832）は初期値のみ設定し実行中トグルを検証していないため、**回帰しても検出不能**。さらに移行手順 6-3-e「didUpdateWidget の分岐順（…cjk切替→reset…）を State 側で現行どおり維持」という指示が「分岐を増やさない」方向に実装者を誘導する。→ 対策: didUpdateWidget で `engine.setCallbacks(…)`（または `setKeepKeyboardOnEnter`）を必ず追加すること、を設計書に明記すべき。
- （同種のリスク）`hapticFeedback` も現行は全箇所ライブ参照（L228/291/352/390/409/504/542/557/592 ほか約20箇所）だが、terminal_screen は未指定（既定 true）のため実害なし=**推測**。

### 1.2 【中】`SpecialKeysBarCallbacks` に「コールバックでない状態」が混入

- 事実: 設計書の callbacks 定義は `(onKeyPressed / onSpecialKeyPressed / hapticFeedback / cjkMode / keepKeyboardOnEnter)`。cjkMode・keepKeyboardOnEnter は状態フラグであり、エンジン側に `setCjkMode` が別途存在する（二重管理）。エンジンの「唯一の所有者」主張（責務A）と、状態を callbacks 値オブジェクトに複製する設計が矛盾。
- 推測: 実装時に setCjkMode 更新を忘れると、トグル時のリセット（didUpdateWidget L139）とエンジン内部の cjkMode がずれる。

### 1.3 【中】tmux_composer を「純粋」と称するのは不正確（テスト容易性の主張も過大）

- 事実: `applyHardwareModifiers` は `HardwareKeyboard.instance.isShiftPressed/…` を直接読む（L457-462）。`hwSpecialKeyMap` は static 定数で純粋。`composeSpecial`/`composeLiteral`（新設）は純粋になり得る。
- 評価: 「SpecialKeysTmuxComposer の純粋単体テスト」推奨（§5）は、applyHardwareModifiers については単体テスト不能（HardwareKeyboard はテスト環境で instance が存在するが状態を注入できない）。「Flutter依存は services のみ」の記述も誤り（flutter/services の HardwareKeyboard に依存）。

### 1.4 【中】依存グラフの欠落: DirectInputRow → エンジン

- 事実: `_buildDirectInputField`（L1084-1180）は `_directInputController` / `_directInputFocusNode` / `_handleKeyEvent` / `_onDirectInputSubmitted` を State から直接参照。設計上これらはエンジン所有 → `special_keys_bar_rows.dart`（DirectInputRow）は **engine を import し、controller/focusNode getter と handleSubmitted/handleHardwareKeyEvent を配線する必要がある**。
- 評価: 設計書の依存グラフ §3 に bar_rows → engine の辺が**記載されていない**。記載どおり実装するとコンパイル不能（または泣き別れの依存追加）。グラフの完成度は「循環なし」の検証根拠でもあるため、書面上の重大な抜け。

### 1.5 【中】合成ルート State ~340行の見積根拠が弱い

- 推測: State は initState/didUpdateWidget（rows 差分スクロール判定 L144-152 含む）/dispose/build（~110行の行判定部を Layout へ委譲後も骨格が残る）/送信2本（L1504-1577）+ 配線で 340行は楽観的。実装後に 400〜450行になる可能性があり、「全ファイル500行未満」を満たすかは不確実。

### 1.6 【軽微】表記・事実

- 責務Aの範囲: 設計書1節と付録で「fields 88-112 / 204-595」と書くが、88-112 には責務Cの `_rowScrollControllers`（L91）が混在する（スコープ表記の不整合のみ）。
- 「ValueKey 参照はゼロ（リポジトリ全体で確認済み）」（§4）: スコープが不正確。リポジトリ全体では `ValueKey('mux-sel-*')` が terminal_screen_herdr_test に9件存在（L1517/1554/1569/1608/1626/1646/2194/2195/2461）。ただしすべて herdr セレクタ UI のキーで SpecialKeysBar とは無関係 → **結論（特殊キーバー関連はゼロ）は正しい**。
- 「公開パラメータ19→14 修正」: 実測一致。名前付き13 + super.key ✓。
- 行数見積: 8ファイル合計 ≈1,890 vs 現行 1,577（+20%）。
- テスト本数: 40 ✓（group 別: direct input 6本 L610群 / CJK 4本 L749群 / row auto-scroll 3本 / dynamic rows 4本 — 移行手順 6-3 の重点実行指定は実測と一致）。

### 1.7 【良い点】

- 呼出元1箇所（terminal_screen L3570-3595）・テスト参照面（byType(TextField)/SingleChildScrollView/CustomKeyButtonWidget/GestureDetector/text/icon/controller/focusNode/scroll offset）の洗い出しは実測と**完全一致**。ScrollController.offset を直接検証するテスト（L906-944）への言及も的確。
- `_sendSpecialKey`/`_sendLiteralKey` を State に残す判断（1行委譲wrapper批判への自衛）は妥当。BTab 特別扱いと S/C/M 消費順の維持明記 ✓。
- `ImageTransferButton`（ConsumerWidget・L12 実測）との統合拒否と名前衝突回避（SpecialKeysImageButton）は正しい判断。
- エンジンの sentinel/delta/composing/100ms抑制（L204-455 実測）・Samsung workaround（L227-242 実測）の仕様転記は正確。

### 1.8 元の批判（機械的分割）は解消されたか → **概ね解消・ただし1穴**

- 各ファイルが真の「状態所有者」（engine=IME、modifier_state=3bool、row_scrollers=ScrollController群、composer=合成、token_view=解決、button群=見た目）であり、1行委譲 wrapper や util grab-bag はない。機械的分割ではない。
- 未解消: §1.1 の「didUpdateWidget ベースの動的 prop をエンジンへ伝播する配線」が設計に存在しない。このまま実装すると「形を変えた分割」による**挙動乖離**（ステルス回帰）を招く唯一の箇所。

---

## 2. rdialog.md（resize_dialog.dart）

### 2.1 【軽微・事実誤認】テスト件数「9件」→ 実測 10件

- 事実: `test/widgets/dialogs/resize_dialog_test.dart` 261行（一致）だが `testWidgets(` は **10** 件（L98/104/110/131/154/175/192/207/241/251）。「9件」は誤り。import 5行（設計書 §1.3 と一致）・`HerdrResizePaneDialog` のみ参照も一致。

### 2.2 【軽微・事実誤認】`_SizePreset` の行数「1」→ 実測 5行（L183-187）

- クラス定義 `class _SizePreset { final String label; … }` は183-187 の5行。§1.1 の表（183 | 1行）は誤り。本質的な影響なし。

### 2.3 【中】「14ファイル」は過剰分割の疑い（目的化した1ファイル=1責務）

- 事実: `SizeInputRow` / `PresetChips` / `WarningBox` / `SizePreset` は resize ダイアログ以外での利用予定が**現状ない**（import 元は terminal_screen と resize_dialog_test の2ファイルのみ=設計書自身の実測）。プレビュー3種・シミュレータ・ResizeResult は価値ある分離だが、単一用途の小部品（30-130行）×複数は、可読性向上よりファイル数増加の方が支配的。
- さらに**4ダイアログの共通骨格（`_cols/_rows` initState・`_presets` getter L89/232/374 の3重複・AlertDialog 骨格）はコピペとして残る**（設計書 §7 リスク表も自認）。「エンジン/合成で重複を吸収」という責務ベース再設計の主目的が、このファイルでは**部品化でしか達成されない**。
- 対案（代替案）: `resize_dialog.dart` を「4ダイアログ + barrel」に保ちつつ、純ロジック（simulator）+ プレビュー部品を切り出す 3-4ファイル構成でも、最大 ~500行前後に収まる可能性がある（シミュレータ151+プレビュー134/52+ダイアログ146/137/140/294=1,054行のうち446行が他へ出るため）。これなら import 変更も barrel 不要で最小。※行数は概算（推測）。

### 2.4 【中】`HerdrLayoutPreview` プロパティ化時のガード漏れリスク

- 事実: `_buildLayoutPreview` は `_cols < 1 ? 1 : _cols` / `_rows < 1 ? 1 : _rows` の clamp（L584-585）と `context.l10n.resizeHerdrPtyHeader(_cols, _rows)`（L584 付近）を参照する。設計書は「cols/rows/l10n をプロパティ化」と述べるが、**min 1 clamp の維持**を明記していない（「1:1移設」の一般論のみ）。実装者が「プロパティ化」を機に整理すると表示が変わるリスク。
- 対策: 設計書に「cols<1 の clamp は HerdrLayoutPreview 内で維持」と明記。

### 2.5 【軽微】PaneGridPreview の公開 API が内部仕様をリーク

- 事実: `_buildPaneGridPreview` は引数7個（allPanes/highlightPaneId/previewPaneId/previewCols/previewRows/showEstimatedLabel/l10n）— 設計書 §1.1 の「引数7個」は一致。これを public StatelessWidget 化すると、`previewCols`/`previewRows`/`showEstimatedLabel` という**プレビュー専用の内部仕様が公開面**になる。public 化（=テスト容易性）のコスト評価が欠ける。internal 化＋テストは同ライブラリ内テストでも可能な点を検討余地として提示。

### 2.6 【軽微】barrel と「1ファイル=1責務」の衝突は設計書自身が認める

- 代替案（個別 import）も提示されており誠実。ただし §8「barrel の是非 — チーム方針依存」とある通り、**どの設計書が採用するかで export 戦略が分裂**（本レビュー§0）。

### 2.7 【良い点】

- `simulatePaneResizeAbsolute` の 1:1 公開化は本設計の最良判断。identity 3条件（panes 空 L779 / 対象ID不在 L784 / winW or winH==0 L792）は実コードと**完全一致**。Step1-4 のアルゴリズム記述も実コード（L773-923）と整合。
- 公開ダイアログ4種+ResizeResult のコンストラクタ不変・呼出元 showDialog 4箇所（L5888/5967/6190/6252）・l10n キー18種・import 元2ファイル — すべて実測一致。
- `_buildNumberInput`（min=10/max=500・clamp・chevron）の記述も実コード（L1167-1221）と一致。

### 2.8 元の批判は解消されたか → **部分的**

- 「4責務が1ファイルに混在」という診断は正確。ただし本ファイルの「混在」は本来の機械的分割批判（意味なく切り刻む）とは性質が違い、ダイアログ4種は独立機能として明確。**重複の実体は `_presets` getter 3重複と骨格であり、それは設計後もコピペとして残る**（=解消していない）。逆に単一用途の部品9点を別ファイル化する部分は「新たな機械的分割」に近い。

---

## 3. providers-core.md（download / settings）

### 3.1 【中】DownloadNotifier shell 330行への「責務再集中」

- 事実: 現行 DownloadNotifier は 691行。設計の shell は「公開 API + フロー編成 + 通知・l10n + `_items` 所有 + state 反映」で **~330行**（現行の約半分）。
- 評価: P1 の元批判は「Facade/Notifier に責務再集中」だった点に照らすと、本設計は「機械的・状態的ロジック」を5コラボレータへ出しただけで、**通知・l10n・items という第2の塊が shell に残る**。`DownloadNotificationSink` 等の予備スロット（§7-5）が設計内に用意されているのは良いが、「残り物の寄せ集め」にならないための境界（通知組み立てを state から導出する旨 §3.3）は合理的。
- 推測: 実装で 330行を超過する可能性が高く、その際の sink 分離は**第2フェーズの再設計**になるため、最初から通知関連を分離しておく方が P1 批判の再発防止に確実。

### 3.2 【中】`DownloadCollisionResolver` の reserved 状態の所有者が不明

- 事実: 現行の名前解決は「バッチを跨いだ reserved 管理」「起動時自動リネーム（LOW#3）」「事前スキャン」を含む（download_provider.dart L333/350/496-543 ほか）。設計書は resolver を「純関数化」（§8: 「事前スキャン・採番・決定適用の純関数化」）と記すが、**reserved は誰が保持するのか**（shell の `_items` と同義か、session か）が明記されていない。resolver がステートレスなら、スキャン結果 ↔ 決定適用の間で reserved 集合を往復させる API になる。
- 対策: 設計書に「reserved 集合の所有者（shell recommends 保持＋resolver へ引数渡し）」を 1 行明記する。

### 3.3 【軽微】実測との微妙なズレ

- 「設定画面系 15 ファイル」→ `settingsProvider.notifier` を参照する lib ファイルは**14**（実測）。terminal_screen 等も含めた総数は別だが、内訳表記は要修正。
- 「33 種の setter」→ lib 内で `notifier).setXxx` として実呼出されるのは 30 + toggleDirectInput（実測、grep の正規表現差で ±3 はあり得る）。テスト側は settings_search_provider_test 等で追加があるため断定はしない（**推測**）。
- FakeSettingsNotifier の override: **build + 6 setter の 7 件、実測一致** ✓。
- DownloadNotifier コンストラクタ（clock/progressThrottle/notificationService/exporter）実測一致 ✓。`file_browser_download_flow_test` が `DownloadNotifier(exporter: …)` で直接構築する点も一致 ✓。
- 40キー・SharedPreferences のみ（SecureStorage 不使用）・未使用 setter 4種（lib/test で呼出ゼロ）— すべて実測一致 ✓。

### 3.4 【良い点】

- **re-export 戦略**（`export 'download_state.dart'`）による呼出元 churn ゼロは、import 変更 ≈25 ファイルのリスクを消す確実な判断（§5.2 の非採用時コスト提示も正直）。※ conn 設計書と方針が逆（§0）な点のみ残念。
- 世代/トークン/保存先の所有を `DownloadBatchSession` に集約する判断は M1/M2/M3/HIGH#1 の再発防止に的を射る（実測: `_generation` L269 / `_token` L250 / `_destination` L257 / `_disposedBatches` L264 が現行で散在）。
- fire-and-forget `_loadSettings` の制御フロー保持（migration → state → setCachedLanguage → platform apply → `ref.mounted` L320 付近）と、TEST-SETTINGS-PROVIDER-001 の注記認識は正確。
- 行数見積: download ≈1,040（+14%）/ settings ≈840（+12%）— 他設計書より控えめで妥当。

### 3.5 元の批判は解消されたか → **概ね解消・shell 境界のみ要監視**

- 5コラボレータはすべて真の状態所有者であり、機械的分割ではない。ただし **Notifier shell（330行）への「通知+l10n+items」残留**が、P1 批判の繰り返しになり得る唯一の点。§3.1 の sink 分離を初期設計に含めることを推奨。

---

## 4. providers-conn.md（connection / active_session / ssh）

### 4.1 【重大】orchestrator の state 書き込み経路が未定義

- 事実: 現行の切断検知（connectionStateStream 購読 L270）は購読内で `state = state.copyWith(connectionState: …, error: …)` を行い、その後 `onDisconnectDetected?.call()` → `reconnect()`（L330-345）。`_onNetworkStatusChanged` も `state = state.copyWith(isNetworkAvailable …)`（L140-148）。
- 設計書 §2.3: orchestrator に「接続状態ストリーム購読と切断検知（状態遷移 + onDisconnectDetected 発火）」を持たせる一方、**注入クロージャ一覧は `onLastConnected / startForeground / stopForeground / requestReconnect / onDisconnectDetected` のみ**で、state 更新手段がない。policy には `updateState` 注入がある（§2.3）のに orchestrator にはない**非対称**。
- 評価: このまま実装すると orchestrator が state を書けない（または notifier への直接依存=循環が発生する）。設計書に「orchestrator → `void Function(SshState Function(SshState)) updateState` 注入（notifier が渡す）」を明記すべき。

### 4.2 【重大】`onDisconnectDetected` / `onReconnectSuccess` の配線が未定義（フィールドは「委譲」できない）

- 事実: terminal_screen は `sshNotifier.onReconnectSuccess = _onReconnectSuccess`（L1019）と `sshNotifier.onDisconnectDetected = null; sshNotifier.onReconnectSuccess = null`（L3276-3277）を**public フィールドに直接代入**。テスト2件は `notifier.onDisconnectDetected == null` を検証（terminal_screen_lifecycle_test L209、terminal_screen_herdr_test L1482）。FakeSshNotifier は build() を @override して購読を張らない（fake_ssh_notifier.dart L20-25）。
- 設計書 §2.3 は notifier を「onDisconnectDetected / onReconnectSuccess を委譲」と書くが、**フィールドは委譲できない**（代入時点で orchestrator へ伝える仕組みが必要）。発火は orchestrator 内の stream 購読、設定は notifier のフィールド — 両者の同期方法（setter 転送 or 両者が同一オブジェクト参照 or build 時に初期値同期）が未定義。
- 対策: 「notifier のフィールドは getter/setter にし、setter が orchestrator の対応フィールドへ代入する」方式を明記。L3276-3277 のクリアが購読停止と同時でない点も現行仕様として維持要。

### 4.3 【中・事実誤認】`lastConnection` / `lastOptions` を「デッド公開 API」と分類したのは誤り

- 事実: フィールド `_lastConnection` / `_lastOptions`（L85-86）は、公開 getter（L184/187）こそ外部未使用だが、**再接続実行の必須内部状態**。`_doReconnect` のガード（L354: `if (_lastConnection == null || _lastOptions == null)`、L416 同様）と、再接続時の接続情報再使用（L443-446: `host/port/username` + `options: _lastOptions!`）に直接使われる。
- 評価: 「デッド公開 API、維持対象」の表記は削除対象と誤読されるリスクが高い。**getter はデッドだが実体は再接続の心臓部**であり、orchestrator へ明示的に移設することを設計書に明記する必要がある（§2.3 の orchestrator 表にも「_lastConnection/_lastOptions の保有」の記載がない）。

### 4.4 【中・事実の誇張】`onDisconnectDetected` は terminal_screen が「利用」していない

- 事実: terminal_screen の onDisconnectDetected への言及は null 代入のみ（L3277）。ハンドラ設定は onReconnectSuccess のみ（L1019 で `_onReconnectSuccess` を設定、L1200 が実体）。§1.3 の利用実測表「onDisconnectDetected / onReconnectSuccess → terminal_screen が利用」は overstatement（onDisconnectDetected は常時 null で発火は無効）。※設計の分割には影響しないが、実態認識を正すべき。

### 4.5 【中】クロージャ注入結合の複雑化リスクの評価不足

- 事実: 現行は単一 SshNotifier が全てを所有し、fake は build() だけ override して購読をスキップする戦略（fake_ssh_notifier.dart L20-25 で検証可能）。
- 推測: policy（注入5種）・orchestrator（注入5種）・notifier の3者に state 書き込み・購読・timer が分散すると、`_onNetworkStatusChanged` → 即時 `_doReconnect()` 直呼び（L151-153、policy から orchestrator への**同期**呼び出し）のような制御フローが追跡困難になる。P1 の「クロージャ結合」流儀は P1 では成功したが、SSH 状態機械は相互依存が深く、**コールバック地獄のリスクが P1 より大きい**。設計書はこのトレードオフを評価していない。

### 4.6 【軽微】実測とのズレ

- ActiveSessionsNotifier の公開メソッドは実測 **12**（addOrUpdateSession / updateLastPane / updateWindowCount / touchSession / updateSessionsForConnection / updateSessionsFromDomain / setCurrentSession / clearCurrentSession / closeSession / removeSession / removeSessionsForConnection / clear — L284-552）。設計書の「11 メソッド」は誤差。
- 設計書の「FakeSshNotifier（6 @override）」→ 実測は @override **7**（client フィールド L10-11 + build L20 + connect L27 + connectWithoutShell L44 + disconnect L78 + reconnect L85 + reconnectNow L92）。フィールドを数えていないだけなので本質影響なし。
- `_FakeConnectionsNotifier`（build/getById/updateLastConnected の3 override）と `_FakeActiveSessionsNotifier`（build/updateWindowCount の2 override）は**実測一致** ✓（terminal_test_scaffold.dart L28-67）。
- `selectedConnectionIdProvider`/`selectedConnectionProvider` の「lib の画面から未使用（テストのみ）」— 実測一致 ✓（lib 内で参照するのは connection_provider.dart 自身のみ L622-629）。

### 4.7 【良い点】

- 「build() 起点の副作用維持」— FakeSshNotifier の build() @override による購読スキップ戦略を壊さない明記（§2 冒頭・§7-2）は、テスト二重の継承前提を正しく理解している。`client` フィールド override（getter のフィールド override は Dart で合法）の維持方針も正しい。
- import 更新一覧（§5）の網羅性は実測と整合（12 lib + 17 test + 2 helper、ssh_provider.dart 存続により file_browser/file_transfer/image_transfer/download/markdown_preview 各 provider を「変更なし」とできる点も実測一致）。
- inventory コメント（PROV-ACTIVE / LEGACY-xxxx）の移設方針（§7-5）は、同リポジトリの inventory 追跡ツールの存在を踏まえた誠実な配慮。
- `ConnectionStorage` への l10n 引数渡し（現行 `lookupL10n()` をロード時解決 L216 付近）は解決タイミングを維持する正しい設計。
- クラス境界・行数の実測値（§1）はすべて正確。

### 4.8 元の批判は解消されたか → **構造は本質的だが、配線の穴が2つ**

- orchestrator / policy / merger / storage への分離は真の責務ベース（policy=いつ・どれだけ待つか / orchestrator=どう繋ぐか・切るか の境界は明確で良い）。
- 未解消: §4.1（state 書き込み経路）と §4.2（callback フィールド配線）は「形を変えた分割」に堕ちるリスクを内包する設計穴。§4.3 の誤分類も含め、**写経前に設計書の修正が必要**。

---

## 5. 重要指摘トップ5（リーダー向け要約）

1. **【skeys・重大】keepKeyboardOnEnter 等の実行時 prop 変更がエンジンに伝播しない設計**。
   現行は `widget.keepKeyboardOnEnter` を送信時にライブ参照（L402）＝設定の実行中トグルが即反映されるが、エンジンはコンストラクタで callbacks を固定保持するため反映されなくなる。didUpdateWidget は現行 cjk しか分岐しない（L130-152）上、既存テストは初期値のみで検証 → ステルス回帰。`setCallbacks`/`setKeepKeyboardOnEnter` を設計に明記せよ。

2. **【conn・重大】orchestrator の state 書き込み経路と callback フィールド配線が未定義**。
   orchestrator は「状態遷移+onDisconnectDetected 発火」を担うとされながら注入クロージャに state 更新手段がない（§2.3 非対称）。また terminal_screen は notifier の **public フィールド**へ直接代入する（L1019/3276-3277、テスト2件は isNull 検証）が、フィールドは「委譲」できない。両方とも実装開始前に設計書へ配線方式（updateState 注入・setter 転送）を追記すること。

3. **【conn・事実誤認】`lastConnection`/`lastOptions` は「デッド公開 API」ではない**。
   getter は外部未使用だが、実体は再接続の必須内部状態（L354/416 のガード、L443-446 の再使用）。削除対象と誤読されると再接続が壊れる。orchestrator への保有移設を明記せよ。

4. **【core・中】DownloadNotifier shell 330行への責務残留が P1 批判の再発リスク**。
   通知・l10n・`_items` が shell に残り、現行 691行の約半分が残存。`DownloadNotificationSink` 予備スロットを初期設計に組み込むこと。また `DownloadCollisionResolver` の reserved 状態の所有者（バッチ間で保持・LOW#3）が未明記。

5. **【チーム・方針分裂】export 戦略が3設計書で矛盾**。
   conn=compat re-export 禁止 / core=re-export 推奨（churn ゼロ）/ rdialog=barrel 許容+代替提示。同じ P2 で「1ファイル=1責務」の解釈が異なり、呼出元 churn の前提が食い違う。リーダーが基準を一本化してから各設計書を確定させること。

（番外・事実誤認のまとめ: rdialog のテスト9件→実測10、_SizePreset 1行→実測5行 / conn の ActiveSessionsNotifier 11メソッド→実測12、FakeSshNotifier 6→実測7 / core の設定画面15→実測14ファイル。いずれも軽微で設計の骨子には影響しない。）

---

## 6. 事実と推測の区別（レビュー側の注記）

- **事実**: 本レビューの【事実】欄はすべて HEAD f474d23 の実ファイル・テストに対する grep / read の直接観測（行番号付き）。
- **推測**: §1.1 の hapticFeedback 実害なし / §1.5 の State 340行超過 / §2.3 の代替構成行数 / §3.3 の setter 数 ±3 / §4.5 のコールバック地獄リスク — はコードから直接観測不能な見積・判断であり、設計書側の「推測」ラベルと同格。
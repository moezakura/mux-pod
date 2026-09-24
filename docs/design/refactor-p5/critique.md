# P5 批判レポート（critique.md）

- 批判者: p5-critic（読み取り専用・リポジトリ編集なし）
- 対象: 4 設計書（terminal-screens.md / providers.md / services.md / widgets-screens.md）
- 実測方法: 設計書の主張（行番号・fixture 値・使用箇所・件数・メタデータ）を現 checkout に対して grep / 行抽出 / JSON 文字列正規化比較で裏取り。テストの再実行は設計書の実測（全 pass）を前提に、宣言件数（`test(`/`testWidgets(`）を全 18 ファイルで実測し完全一致を確認。

## 0. 実測で確認できた事実（全設計の前提が正しい箇所）

| 事項 | 実測結果 |
|---|---|
| 18 ファイル行数 | BRIEF 記載と完全一致（2785/1703/1516/1188/1101/1032/1027/908/899/849/828/673/630/591/587/569/562/525） |
| テスト件数 | terminal 57/28/21/14=120、providers 35/33/37/33=138、services 30/94/45/48/54=271、widgets 41/17/30/21/7=116（宣言数 grep 実測・各設計の実行実測と一致） |
| メタデータ | 18 ファイル全てに `@Tags/@Skip/@Timeout/@TestOn/@OnPlatform` なし（grep exit=1 で確認）。repro タグ非存在 → CI `--exclude-tags=repro` 影響なし |
| fixture 同一性 | `kHerdrSnapshotFixture`(file1 L102=file3 L26)・`kHerdrSnapshotPane2Fixture`・`kHerdrEmptySnapshotFixture` は JSON 正規化比較で同一。`kHerdrSnapshotNewTabFixture`(file3)=`kHerdrNewTabActiveSnapshotFixture`(file2) も同一 |
| fixture 同名別値 | `kHerdrSnapshotWithLayoutFixture`: file1 L121=**120x24**、file2 L31=**80x24**（同一名・別値）。repo 全体の参照は file1(file2 のみ) → rename 判断は実測と整合 |
| テストファイル間 import | file1 L29・parity L17 が `mutation_ui_test.dart` を import（設計の §4-4 記述どおり） |
| ssh setUp のスコープ | SecureStorageService 使用は L395-396 とホスト鍵 3 件（L806/835/868/879/912）のみ。`SshConnector._onVerifyHostKey`(L176-177) は dartssh2 の `onVerifyHostKey` コールバック経由で発火するが、fake raw client は実 handshake をしないため非ホスト鍵テストでは発火しない |
| Widgets 重複 helper | `directInputField`/`visibleText` は group4(L640-644) と group5(L779-783) で**完全同一**。dialog の MediaQuery pump 4 ブロックは textScaler 2.0/1.3・size 308/411 で**パラメータと構造が異なる**（L379 は `MediaQuery(`、L465/510/589 は `MediaQuery(data: ...)`） |
| `_RecordingSftpClient` | 既存で 4 テストファイルに重複（image_transfer / markdown_flow / markdown_preview / sftp_browser）。P5 以前の既存事実 |

## 1. 【重大】指摘（修正必須）

### 1-1. [terminal-screens] `_pumpHerdrTerminal`（file3 L170）の移動先が未定義
- 設計書箇所: §2.1 H1/H2/H3 の収容リスト・§3 移動マッピング（file3 行）に登場しない。
- 実測: `.dart` L170-198 に `Future<FakeSshClient> _pumpHerdrTerminal(...)` が定義され、**21 件中 20 件のテスト**（L206・255・286・335・390・422・456・515・569・628・663・696・803・920・972・1017・1060・1099・1146 ほか）が使用。新ファイル構成では T18-1..6（sync_mechanism）・T18-7..13（sync_tab_crud）・T19（sync_error）の **3 ファイル全て**で必要。
- 影響: どこにも配置されないためコンパイル不能、または各新ファイルへ 30 行をコピーし BRIEF 3「重複定義を増やさない」に違反。
- **必須修正**: H2 `herdr_test_helpers.dart` に `pumpHerdrTerminal(...)`（公開名化・本体 verbatim）として収容し、§2.1 と §3 の file3 移動マッピングに明記。あわせて「file3 由来 3 本の main() 冒頭の `setUp(SharedPreferences.setMockInitialValues)` 再現＋`_pumpHerdrTerminal` の参照更新」を 1 項目として列挙すること。

### 1-2. [terminal-screens] `paneIndicatorPainter`（file1 L45）の移動先が未定義
- 設計書箇所: §2.1 H1/H2/H3・§3 移動マッピング・§4 リスク 6（G6/G7 ローカル helpers のみ言及）のいずれにも無い。
- 実測: file1 L45-47 にトップレベル定義。使用箇所は **G1-29「M2 regression: tmux では pane indicator が表示される」（L1712 → selector_flow へ移動）** と **G6 pane indicator 11 件（L2149・2168・2187・2212・2222・2381・2403・2418・2457・2503・2532 → pane_indicator へ移動）** の 2 新ファイル。
- 影響: どちらか一方に置くと他方が未定義（コンパイル不能）、両方にコピーすると BRIEF 3 違反。§2.2 の pane_indicator 見積り 458 行にも「paneIndicatorPainter を足す」ことが含まれていない。
- **必須修正**: H2 に `paneIndicatorPainter()`（~3 行、Finder predicate）を収容。§2.1 H2 リストへ追記。

## 2. 【中】指摘

### 2-1. [terminal-screens] H1 `herdr_fixtures.dart` の行数見積り（約 300 行）が実測と乖離
- 設計書箇所: §2.1 H1「約 23 constant・約 300 行見積り」。
- 実測: 27 fixture 定義のブロック行（`const X =`〜`';` まで）を全計測 → **合計 489 行**。重複解消（SnapshotFixture･Pane2･Empty の 3 ペアと NewTab ペア）で実効 **約 432 行**＋先頭 doc コメント（file1/file2 に 8 個以上）を移すと **~470 行**に達し、500 行制限のマージンがほぼ消える。300 行の根拠（「約 23 constant」だけ）が数値根拠になっていない。
- **必須修正**: 見積りを見直し（実測ベース 430-470 行）、500 行以内を担保する具体策（fixture を内容別に H1a/H1b 分割する、または不要 doc コメントを残さない等）を §2.2 に明記。「全ファイル 500 行未満」は helper ファイルにも適用される旨を再確認すること。

### 2-2. [providers] download 分割後ファイルの `TestWidgetsFlutterBinding.ensureInitialized()` 保持が未明記
- 設計書箇所: §2-2/§2-3（helper と新ファイルの構成・import 先に記載なし。現行 L185 に存在）。
- 実測: L184-185 `void main() { TestWidgetsFlutterBinding.ensureInitialized();`。L198 で `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(...)` を使用。全テストが `test()`（testWidgets でない）のため Binding は自動初期化されず、新 7 ファイル全てで必須。
- 影響: 脱落すると MethodChannel モック登録時に例外（件数は不変でも fail に転じる）。
- **必須修正**: §2-3 の各新ファイルの「ヘッダ」中身として `ensureInitialized()`＋`final scope = DownloadProviderTmpScope(); setUp(scope.setUp); tearDown(scope.tearDown);` を明記。

### 2-3. [providers] `tmp`/`appTmp` へのテスト本文直接参照（多数）の書き換えが未記載
- 設計書箇所: §3-1「`_pathProviderChannel`＋`tmp/appTmp`＋setUp/tearDown → `DownloadProviderTmpScope`」のみで、参照書き換えの要否を明記していない。
- 実測: `tmp` は 76 件（うちテスト本文の `FakeDownloadDestination(tmp.path)`・`File('${tmp.path}/...')`・`existsSync()` 検証が ~45 箇所）、`appTmp` は 10 件（うちアサーション内の `'$appTmp/...'` が 8 箇所: L1500・1502・1522・1523・1545・1547・1574）。スコープ型へ移すと全参照を `scope.tmp`/`scope.appTmp` に書き換える必要がある。
- 影響: 漏れるとコンパイルエラー。書き換え幅が「行コピー」前提の検証計画で見えない。
- **必須修正**: §3-1 に「テスト本文の `tmp`/`appTmp` 参照（~45+8 箇所、期待値は不変）をスコープフィールドへ機械置換する」旨を明記し、件数検証とは別に「置換後も assert 行の期待値文字列が不変であること」の diff 確認を検証計画へ追加。

### 2-4. [providers × widgets] `FakeSaveAsExporter` が 2 設計で同名・別実装の helper として二重新設
- 設計書箇所: providers §2-2（`download_provider_test_utils.dart`）と widgets-screens §2-E（`download_flow_harness.dart`）。
- 実測: providers 版 L134-152（`{result, error}` 付き・error throw 可能）と widgets 版 L83-101（`{result}` のみ）は構造類似・別実装。
- 影響: `test/` ツリー内に同名の別クラスが 2 本（コンパイルは衝突しないが、BRIEF 3「重複定義を増やさない」の趣旨違反。将来の仕様ズレ源）。
- **必須修正（設計者間調整）**: 誤差対応版（`error` 付き）に統一して `test/helpers/` へ 1 本化し両設計が import する。または widgets 側を責務別名（例 `DownloadFlowSaveAsExporter`）へ変更。どちらかを §6 未確定点へ追加。

### 2-5. [widgets] custom_key_button_editor_dialog の「MediaQuery pump 1 本化」は §4「行コピーのみ」方針と矛盾
- 設計書箇所: §2-B（`pumpDialogMediaQuery` テンプレート化・4 重複 1 本化）と §4「行コピーのみで移動し、テスト本文の編集はしない」。
- 実測: 4 ブロックは textScaler 2.0/1.3/1.3・view size 308/411 に加え、`MediaQuery(data: ...)` 直置き（L465/510/589）と外側 `MediaQuery(`（L379）で**構造が異なる**。さらに t12-t17 は全て同一ファイル（`custom_key_button_editor_dialog_test.dart` 維持）に留まるため、1 本化は BRIEF が求める「共有化」対象ではなく任意最適化。
- 影響: テンプレート化はテスト本文の書き換えを伴い「アサーション不変」の検証境界が曖昧になる。
- **修正（推奨・再検討）**: 1 本化を撤回し verbatim 移動を推奨。1 本化を維持する場合は、textScaler・size・`MediaQuery` 配置のパラメータ契約を明記し、既存 4 ブロックとの行 diff が空であることを検証計画へ追加。

### 2-6. [services] 検証計画 #4 の「helper ディレクトリへ flutter test」は誤検知の恐れ
- 設計書箇所: §5 検証計画 4（`flutter test test/services/ssh/helpers/ ...`）。
- 実測: 対象ディレクトリに `*_test.dart` が無い場合、flutter test は「No tests ran / No tests were found」で **非 0 終了**になる。exit=0 前提の検証にならない。
- **修正（推奨）**: `flutter test test/services/ssh/` 等ディレクトリ全体の件数が（既存分＋分割分）に一致し、helper 分がカウントされないことを件数で確認する方式へ変更。

### 2-7. [services] ssh `setUp/tearDown` 移動（ホスト鍵ファイルのみ）は実測上安全だが、分割後 9 件の pass 確認を明記
- 設計書箇所: §4 リスク表・§3 移動マッピング。実測（前掲 0-表）で SecureStorageService はホスト鍵 3 件のみ依存、非ホスト鍵テストは実 handshake をしないため発火しない。
- 評価: 移動方針は妥当。ただし「setUp が外れた残り 9 件」が将来の実装変更で secure storage に触れた際の挙動変化を防ぐため、検証計画に「分割後 connection / execute / managed_pty の 9 件が独立に pass」を明記されたし。

## 3. 【軽微】指摘

1. [terminal-screens] §2.3 の内訳「9+4+8+4+5（G1 分割）」は G4 統合分の扱いが混線（実体は G1 4+4+8+4+9 の 29 と G4 の 1）。数字は合計 57 で正しいが、記述を「9+4+8+4+4(G1)+1(G4)」に直し、5 の内訳（G1-26..29=4＋G4-1=1）を明記。
2. [terminal-screens] file2 由来ヘルパー 11 種の private→public 化（H2）に伴う呼び出し書き換え範囲（file2 由来 5 ファイル）の一覧が無い。H2 公開名と新ファイル内ローカル名（G6 の `pumpHerdrForIndicator` 等）の衝突チェックを実装時に行う旨を明記。
3. [terminal-screens] `kHerdrSnapshotWithLayoutFixture` rename（120x24→`kHerdrLargeLayoutSnapshotFixture`）の波及は実測で file1 の 3 テストのみ（L1887 G3-1 / L2210 G6#10 / L2668 G7-3）。G3-1 は `paneWidth==120` を assert、G6#10 は findsNothing のみで width 非依存、G7-3 は内容未詳。**値 1 バイト不変を fixture ダンプ diff（新/旧）で機械検証**する旨を検証計画へ追加。
4. [widgets] `_invokeLinkTap`（L781-800・リンクガード専用・実測 L743/769/770 のみ）を helper へ移す一方、同 group 専用の `mockUrlLauncher` はローカル維持とする判断の非対称。両者とも link_guard ファイル内ローカル維持を推奨（helper 肥大化回避）。どちらかに決めた根拠を §3-C に追記。
5. [providers] custom_keys の「group 非新設」方針は fullName 完全一致の観点で妥当（実測: group 0・main() 直下 33 件）。§6 未確定点の「可読性 group 導入」は fullName を変えるため、採用時は fullName 集合 diff 検証が必須である旨は既に注記済みだが、5 設計に共通する「group 追加は不可」として未確定点を閉じることを推奨。
6. [services] `_FakePersistentShell(super.client)`（L127）は `PersistentShell(this._sshClient, ...)`（L78）への位置型 super 引数。公開名 `FakePersistentShell` への rename は既存 `test/helpers/fake_ssh_client.dart` と衝突なし（grep 実測）→ 設計の主張どおり。

## 4. 審査観点別サマリ（a〜g）

- **(a) テスト名/件数/メタデータの変質**: 全 18 ファイルにメタデータ無し（実測）でリスク小。group 名不変方針（terminal の G1/T18 同名 5/2 分割、providers の group 維持、services/widgets のラッパー維持）は JSON fullName 集合の一致で保証可能。⚠ 唯一の変質リスクは fixture rename（`kHerdrSnapshotWithLayoutFixture`→`kHerdrLargeLayoutSnapshotFixture`、`kHerdrSnapshotNewTabFixture` 廃止）と private→public rename によるソース変更で、**これらは「メタデータ不変」ではなく「ソース編集」**。rename 対象と値不変の機械検証を計画に明記すること（軽微 3・重大 1-1/1-2 参照）。
- **(b) 共有コードの二重定義・抽出漏れ**: **重大 2 件（1-1/1-2）** と設計間重複 1 件（2-4）。他は既存 helper 再利用を実測確認（`FakeSshClient`/`FakeSftpClient`/`terminal_test_scaffold`）。`FakeImageTransferNotifier` の既存二重定義（scaffold vs parity_pump L204）は P5 対象外の扱いに同意。
- **(c) 500 行超過見積り甘さ**: 最大実質リスクは terminal H1（2-1: 実測 ~432-470 行 vs 見積り 300）。テストファイル側は pane_indicator 458／sync_error 426 が上限だが余裕 42/74 行あり、paneIndicatorPainter を H2 に移せば pane_indicator は減る。他 3 設計は最大 365（providers）・330（services）・310（widgets）で余裕十分。機械的分割（`*_part1`）は 4 設計とも不使用 ✓。
- **(d) setUp/tearDown スコープ**: terminal file3（SharedPreferences を 3 ファイル再現・isolate 分離で無害）、widgets E（helper 化・channel null 化維持）、services ssh（ホスト鍵のみへ移動・実測安全）、providers connection（`resetConnectionStorage` 1 行化）は妥当。⚠ download のスコープ型化は参照書き換え（2-3）と ensureInitialized（2-2）が未明記。
- **(e) 実行順序依存・fixture 共有汚染**: 全テストが各テスト毎に container/fake を new する既存パターン（実測）で、ファイル間は isolate 分離（flutter_test の suite 単位）。クロスファイル static（SecureStorageService 等）は setUp でリセットされ、tearDown で null 復元。低リスク。
- **(f) helper の main() 誤検出**: 全 helper は非 `_test.dart` 命名・main() なし。providers は既存 `fake_sftp_file_test.dart`（main あり）を helper 扱いしない旨を明記 ✓。⚠ 検証コマンド自体の問題は 2-6。
- **(g) 検証計画の妥当性**: 件数（testDone/testStart − loading）＋ fullName 集合 diff の計画は良い。**共通限界は「件数・名前はアサーション/期待値の改変・削除・タイマー値変更を検出しない」点**。BRIEF 厳守事項 1 の機械保証には「旧ファイルのテスト本体ブロックと新ファイル対応ブロックの行 diff が空」または「抽出行の一括 diff」が必須で、4 設計すべてに欠落（widgets は方針のみ）。→ 各設計の検証計画に 1 項目追加を必須とする。また全設計が「全テスト pass」を件数検証に含めるか曖昧（件数は fail でも同数になる）→「EXIT=0・fail 0」を明記（providers §5-4 のみ明記あり）。

## 5. 設計者別 必須/推奨修正一覧

### p5-terminal-tests（terminal-screens.md）
- **必須**: 1-1 `_pumpHerdrTerminal` を H2（または sync 専用 helper）へ収容・マッピング明記。1-2 `paneIndicatorPainter` を H2 へ収容。2-1 H1 見積り実測更新と 500 行担保方策。
- **推奨**: 軽微 1（§2.3 内訳記述）、軽微 2（公開名化の書き換え一覧）、軽微 3（rename fixture 値の機械 diff 検証）、§5 検証計画に「テスト本体行 diff」追加。旧 4 ファイル削除前に parity import 差し替え（§4-4 記載済み）の順序遵守。

### p5-provider-tests（providers.md）
- **必須**: 2-2 ensureInitialized 明記、2-3 tmp/appTmp 参照書き換え明記、2-4 FakeSaveAsExporter の設計間整合。
- **推奨**: §5-2 の新文件数確認コマンド glob（`download_provider_*_test.dart` が旧 `download_provider_test.dart` にもマッチすること）を削除前提と明記。§5 に全テスト pass（fail 0）の明記。

### p5-service-tests（services.md）
- **必須**: なし（ssh setUp 移動は実測的に安全と確認）。2-6 検証コマンド修正。
- **推奨**: 2-7 分割後 9 件の pass 明記、§5 にテスト本体行 diff 追加、未確定点 1（connect/exec ヘルパー集約）は「差分ゼロ検証後に採用」の現方針を維持。

### p5-widgets/screens（widgets-screens.md）
- **必須**: 2-5 MediaQuery 1 本化の撤回 or 契約明記＋diff 検証。
- **推奨**: 軽微 4（`_invokeLinkTap` のローカル維持）、§5 にテスト本体行 diff 追加、§4「行コピーのみ」を全体方針として検証項目化。

## 6. 総評

- **terminal-screens**: 構造把握・重複解消は丁寧だが、**共有ヘルパーの抽出漏れ 2 件（重大）と H1 行数見積りの実測乖離（中）** があり、修正後の再審査が必要。特に fixture 27 本統合は細心の「値不変」管理（rename 誤爆防止）が実装のキモ。
- **providers**: 分割粒度・ヘルパー設計は良好。**ensureInitialized と tmp/appTmp 参照書き換えの明記漏れ（中 2 件）** を修正すれば着実に実装可能。FakeSaveAsExporter は widgets 設計と要調整。
- **services**: 最も盤石。**必須修正なし**（検証コマンドと参考記述の改善のみ）。ssh setUp 移動の安全性は実測で裏付け。
- **widgets-screens**: 構成は妥当だが、**MediaQuery pump の 1 本化（自己矛盾）だけがアサーション不変のリスク源**。verbatim 移動に寄せればほぼ無風。
- 横断最大のリスクは「**件数・fullName 一致チェックがアサーションの改変/削除を検出しない**」ことで、4 設計すべてにテスト本体の行 diff 検証を追加することが必須。

以上。
# P5 設計書: test/providers の 500 行超 4 ファイル分割（download / active_session / connection / custom_keys）

- 作成者: p5-provider-tests
- 対象: test/providers/ の 500 行超 4 ファイル（合計 4,311 行）
- 方針: BRIEF の厳守事項 1〜8 に従う。テスト名・件数・アサーション・メタデータ不変。
- 実測は「実行」で裏取り済み（後述セクション 5 参照）。

---

## v2 改訂サマリ（critique.md §2・§4-g・§5 へ対応）

| # | critique | 対応 | 反映箇所 |
|---|---|---|---|
| 1 | §2-2【必須】download 分割後ファイルの `TestWidgetsFlutterBinding.ensureInitialized()` 保持が未明記 | 各新ファイル共通ヘッダとして `ensureInitialized()` を明記（§2-3） | §2-3「7 ファイル共通ヘッダ」 |
| 2 | §2-3【必須】`tmp`/`appTmp` のテスト本文直接参照（~45+8 箇所）の書き換えが未記載 | 実測（67 変数参照行）を一覧化。**「変数参照方式」を採用**（各 main の `late Directory tmp; late String appTmp;` へ setUp で scope 値を再代入）→ テスト本文の書き換え **0 件**・期待値文字列はバイト不変 | §2-3 補・§3-1・§4 |
| 3 | §2-4【必須】`FakeSaveAsExporter` が providers/widgets 両設計で同名・別実装 helper として二重新設 | `test/helpers/fake_save_as_exporter.dart` に**一本化**（誤差対応版 `{result, error, calls}` をスーパーセットとして採用）し両設計が import。widgets 設計者への調整通知を §7 に記載 | §2-2 ・§3-1・§7 |
| 4 | §5-2【推奨】glob（`download_provider_*_test.dart`）が旧 `download_provider_test.dart` にマッチ | 「旧ファイル削除後」を前提として明記。glob 実行前に旧 8 ファイル削除済みである旨を §5-2 に追記 | §5 |
| 5 | §4-g【推奨】全テスト pass（fail 0）を件数検証に含めず曖昧 | §5 に「EXIT=0 かつ fail 0」を明記 | §5 |
| 6 | §4-g【必須】「件数・名前はアサーションの改変/削除を検出しない」→ テスト本体の行 diff 検証が全 4 設計に欠落 | §5 に「旧ファイルのテスト本体ブロックと新ファイル対応ブロックの行 diff が空」の検証項目を追加 | §5 |
| 7 | 軽微 5【推奨】custom_keys の group 導入は fullName を変えるため「group 追加は不可」として未確定点を閉じる | §6-1 を「確定: group 非新設」で閉鎖（fullName 集合 diff を §5 に追加） | §6 |
| 8 | §2-3 指摘の行番号（appTmp 8 箇所） | 実測は **7 行**（L1500/1502/1522/1523/1545/1547/1574）。誤差を実測値に修正 | §2-3 補 |

---


## 1. 現状分析（事実）

### 1-1. ファイル別サマリ（行数・件数・メタデータ）

| ファイル | 行数 | テスト件数（実測） | group 数 | @Tags/@Skip/@Timeout/@OnPlatform |
|---|---|---|---|---|
| download_provider_test.dart | 1703 | **35** | 2 | なし |
| active_session_provider_test.dart | 1027 | **33** | 1 | なし |
| connection_provider_test.dart | 908 | **37** | 4（内1は外側） | なし |
| custom_keys_provider_test.dart | 673 | **33** | 0（group なし、全テスト main() 直下） | なし |

- 件数は `flutter test <file> --reporter=json` 実行で確認。各ファイル JSON に `"type":"testDone"` が
  「件数+1」現れるが、+1 はスイート読み込みの擬似イベント `loading <path>` であり、実テストは下表の通り。
- 4 ファイルとも `@Tags`（repro 等）・`@Skip`・`@Timeout` は**存在しない**（grep で確認）。
  分割に伴う CI `--exclude-tags=repro` への影響なし。
- `testWidgets` は 0 件（すべて `test()`。widget ツリーを使わない provider 単体テスト）。
  `pumpWidget` ヘルパーは本 4 ファイルに不使用。

### 1-2. test/helpers/ の既存リソース（再利用可否）

| helper | 行数 | main() | 本設計での再利用 |
|---|---|---|---|
| fake_sftp_client.dart | 281 | なし | ◯ download（`FakeSftpClient` / `FakeSftpFile` を継承・再利用。後述 `TestSftpClient` の親） |
| fake_ssh_client.dart | 253 | なし | ◯ download（`FakeSshClient` を継承） |
| fake_ssh_notifier.dart | 94 | なし | ◯ download（`makeDownloadProviderContainer` で使用） |
| fake_settings_notifier.dart | 45 | なし | ◯ download（`makeDownloadProviderContainer` で使用） |
| fake_ssh_foreground_task_service.dart | 38 | なし | ◯ download（`FakeSshForegroundTaskService` を通知 7 テストで既に使用） |
| fake_sftp_file_test.dart | 108 | **あり** | △ **テストファイル**（`FakeSftpFile` の検証用・総件数 2,009 に含まれる）。helper 扱いしないこと |
| fake_file_browser_notifier.dart / fake_settings_notifier / fake_tmux_notifier / terminal_* | - | - | ✗ 対象外 |

- **重要**: `test/helpers/fake_sftp_file_test.dart` は `void main()` を持つ**既存テストファイル**。
  新規 helper には `main()` を絶対に置かない（BRIEF 3 項）とともに、本ファイルは分割対象外。
- 新規追加する helper は全ファイル非 `_test.dart` 命名とし `flutter test` の対象外にする。

### 1-3. download_provider_test.dart（1703 行 / 35 件）

#### トップレベル構造（行番号）

| 行範囲 | 内容 |
|---|---|
| 1-23 | imports（dart:async / dart:io / dartssh2 / flutter services・riverpod・test / lib 8 imports / helpers 5 imports） |
| 26-37 | `_OpenSftpFailingSshClient extends FakeSshClient`（openSftp が throw。MEDIUM#2 回帰用）→ **使用 1 テストのみ（972 行目近辺）** |
| 39-91 | `_TestSftpClient extends FakeSftpClient`（stat/open の fail 指定・emitChunkSize/beforeEmit）。doc コメントあり → **ほぼ全テストで使用** |
| 93-132 | `FakeDownloadDestination implements DownloadDestination`（実 IO 委譲・existsCalls/openCalls 記録・openError/disposeCalled） → **全 35 テストで使用** |
| 134-152 | `FakeSaveAsExporter implements SaveAsExporter`（result/error/calls 記録） → **7 箇所で使用** |
| 153-172 | `_GatedSaveAsExporter implements SaveAsExporter`（export を保留できる Completer 式 fake） → **使用 1 テストのみ（1633 M3）** |
| 174-180 | トップレベル関数 `FileEntry _entry(...)` → **全テストで使用（46 箇所）** |
| 182 | `const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider')` |
| 184 | `main()` 開始。`TestWidgetsFlutterBinding.ensureInitialized()` あり |
| 186-233 | `late Directory tmp;` / `late String appTmp;`＋ `setUp`（tmp 作成・path_provider channel モック 190-204）・`tearDown`（channel 解除・tmp 削除 206-213）・ローカル関数 `makeContainer(...)`（215-233） |

#### group 構成とテスト一覧（開始行-終了行 / 件数）

**group('downloadProvider')** …235 行〜約 1476 行、**29 件**（1241 行）

| # | 開始-終了 | テスト名（先頭） | テーマ |
|---|---|---|---|
| 1 | 236-252 | 初期状態: idle・items 空・派生値は 0/null | 基本 |
| 2 | 253-296 | 衝突なし: downloading → completed | 基本 |
| 3 | 297-325 | 衝突検出: awaitingOverwrite + collidingItems | 基本 |
| 4 | 326-359 | overwrite 決定: 既存ファイルを明示上書き | 基本 |
| 5 | 360-398 | rename 決定: _1 接尾辞で空き名を採番 | 基本 |
| 6 | 399-433 | skip 決定: isSkipped・skippedCount==1 | 基本 |
| 7 | 434-490 | cancel: 冪等・後続キュー未実行・部分削除 | キャンセル |
| 8 | 491-546 | キャンセル後の再開始: 新トークンで正常完了 | キャンセル |
| 9 | 547-600 | SSH 切断: error + 部分削除 | 切断/エラー |
| 10 | 601-637 | 順次一括・部分失敗続行 + 集計 | 切断/エラー |
| 11 | 638-683 | 切断×キャンセル競合(a): cancel 先行 | 切断/エラー |
| 12 | 684-730 | 切断×キャンセル競合(b): 切断先行 | 切断/エラー |
| 13 | 731-790 | fraction: 既知サイズ部分進捗・未知は null | 進捗/速度 |
| 14 | 791-839 | speedLabel: 100ms 間引き + TransferSpeedEma | 進捗/速度 |
| 15 | 840-873 | reset: completed → idle・items クリア | キャンセル/リセット |
| 16 | 874-920 | reset: cancel 直後も idle へ復帰 | キャンセル/リセット |
| 17 | 921-971 | 転送中の reset: キュー安全 abort（HIGH#1） | キャンセル/リセット |
| 18 | 972-994 | openSftp 失敗: phase=error（MEDIUM#2） | 切断/エラー |
| 19 | 995-1068 | M1: 旧バッチ finally が新バッチ保存先を dispose しない | バッチ境界 |
| 20 | 1069-1146 | M4: 旧バッチ切断リスナーが新バッチを error にしない | バッチ境界 |
| 21 | 1147-1163 | M2: SSH 非接続 error return でも保存先 dispose | バッチ境界 |
| 22 | 1164-1196 | M2: awaitingOverwrite 中 SSH 切断 → error+dispose | バッチ境界 |
| 23 | 1197-1230 | M2: awaitingOverwrite 中新バッチ開始で旧保存先 dispose | バッチ境界 |
| 24 | 1231-1261 | 同一バッチ内の重複宛先: 自動リネーム（LOW#3） | 基本(命名) |
| 25 | 1262-1317 | 通知: 進捗（100ms 間引き同期）と完了サマリ | 通知 |
| 26 | 1318-1368 | 通知: キャンセル文言 | 通知 |
| 27 | 1369-1417 | 通知: SSH 切断の失敗文言 | 通知 |
| 28 | 1418-1447 | 通知: サービス未起動は no-op | 通知 |
| 29 | 1448-1477 | 通知: 更新 throw でも正常完走 | 通知 |

**group('downloadProvider.single（startSingleTmpDownload・tmp→Save-As）')** …1477 行〜約 1702 行、**6 件**（226 行）

| # | 開始-終了 | テスト名（先頭） | 備考 |
|---|---|---|---|
| 30 | 1478-1505 | tmpDL 成功 → export 成功: completed + localPath 更新 + tmp 削除 | FakeSaveAsExporter |
| 31 | 1506-1526 | export キャンセル（null）: cancelled + tmp 削除 | FakeSaveAsExporter |
| 32 | 1527-1550 | export throw: error + tmp 削除 | FakeSaveAsExporter(error) |
| 33 | 1551-1577 | ダウンロード失敗: export されず tmp 削除 | failOpenFor |
| 34 | 1578-1632 | 単一: 進捗（100ms 間引き）と完了通知 | 注入クロック |
| 35 | 1633-1703 | M3: 中間 completed を publish せず downloading→exporting→completed | **_GatedSaveAsExporter 唯一の使用** |

#### 共有要素（ファイル内定義）と使用実測

| 要素 | 定義行 | 使用回数（grep） | 抽出先 |
|---|---|---|---|
| `makeContainer(...)` | 215-233 | 35 テスト全使用 | helper へ（公開名化） |
| `_TestSftpClient` | 39-91 | 36 | helper へ（`TestSftpClient` 公開名化） |
| `FakeDownloadDestination` | 93-132 | 36 | helper へ（既に公開名） |
| `FakeSaveAsExporter` | 134-152 | 7 | helper へ（既に公開名） |
| `_GatedSaveAsExporter` | 153-172 | 3（定義+1633+コメント） | helper へ（`GatedSaveAsExporter` 公開名化） |
| `_OpenSftpFailingSshClient` | 26-37 | 2（定義+テスト18） | helper へ（公開名化） |
| `_entry()` | 174-180 | 46 | helper へ（`entry()` 公開名化） |
| `_pathProviderChannel`＋`tmp/appTmp`＋setUp/tearDown | 182, 186-213 | 全テスト | helper のスコープ型へ（`DownloadProviderTmpScope`） |
| `FakeSshForegroundTaskService` | - | 7 | **既存 helper 再利用（変更不要）** |

- 鍵となる見立て（依頼書の指摘どおり）: **fake notifier（fake_ssh_notifier / fake_settings_notifier、
  既存 helper 再利用）＋注入クロック（`DateTime Function()`）＋exporter（FakeSaveAsExporter /
  GatedSaveAsExporter）の抽出**が download 分割の要。`makeContainer` はこれらを包む 1 関数 5 ファイル共有。

### 1-4. active_session_provider_test.dart（1027 行 / 33 件）

- 構造: `main()`(11) → 単一 `group('ActiveSessionProvider')`(12〜1026 付近)。**group は 1 つだけ**。
- `setUp`(13-15): `SharedPreferences.setMockInitialValues({})` のみ（1 行）。
- fake / fixture / 定数 / トップレベル関数は**一切なし**。各テストが `ProviderContainer`＋`addTearDown(dispose)`
  を自前で生成（パターンは 3 行）。
- 依存: flutter_test / flutter_riverpod / active_session_provider / multiplexer_backend /
  multiplexer_session / tmux_models / shared_preferences / dart:convert。
- テスト 33 件の内訳（実測・実行確認）：

| # | 開始-終了 | テーマ |
|---|---|---|
| 1-11 | 17-265 | initial / addOrUpdateSession（新規・sessionId キー・同名分離・更新・updateWindowCount・updateLastPane・setCurrentSession×2・clearCurrentSession・closeSession） |
| 12-14 | 266-430 | PROV-ACTIVE-028（updateWindowCount 永続化）/ 029（touchSession 永続化）/ 034（removeSession 永続化・currentSession 維持） |
| 15-16 | 431-467 | clear resets / getSessionsForConnection |
| 17-21 | 468-556 | ActiveSession JSON round trip / sessionId 保存 / fromJson null フォールバック / copyWith(clearLastPane) / ActiveSessionsState copyWith(clearCurrentSession) |
| 22-23 | 557-624 | loads persisted sessions / persists updates and removeSessionsForConnection |
| 24-27 | 625-706 | updateSessionsForConnection 履歴保持 / backend tmux デフォルト / herdr round trip / fromJson 欠落時 tmux |
| 28-33 | 707-1027 | updateSessionsFromDomain（登録・他接続保持・同名 ID 分離・legacy sessionId-null 移行・曖昧時非移行・ラベル不一致破棄） |

### 1-5. connection_provider_test.dart（908 行 / 37 件）

- 構造: 外側 `group('ConnectionProvider')`(13〜878) の中に**内側 group 3 つ**＋直下テスト群。
- `setUp`(14-16): `SharedPreferences.setMockInitialValues({})` ＋ `SecureStorageService.setTestValues({})`。
- 依存: dart:convert / flutter_test / riverpod / connection_provider / backend_type /
  multiplexer_config / connection_migration / secure_storage / shared_preferences。
- トップレベル・末尾: `_CorruptOnSecondReadStorage extends SecureStorageService`(884-908、
  1 回目読み込みを壊す fake) → **テスト 761（rolls back）でのみ使用**。

| 範囲 | 内容 | 件数 |
|---|---|---|
| 13-176 | 外側 group 直下: setUp＋7 テスト（initial / add / remove / update / findByDeepLinkIdOrName / filteredConnections / selectedConnection）+ 468-496 の `sort by lastConnected then created` | **8** |
| 177-466 | 内側 `group('Connection')`: JSON round trip / fromJson デフォルト・tmuxPath→multiplexer 移行・empty→null・multiplexer 優先・unknown backend エラー・copyWith・storageSchemaVersion 系（計 17 件） | **17** |
| 496-809 | 内側 `group('ConnectionMigration')`: migrate（旧 tmuxPath / 混在 / 既移行スキップ / v2 スキップ / 混在 v2+legacy / re-migrate 抑止 / null ソース / backup-rollback / read-back 失敗 rollback / stale backup 復帰） | **10** |
| 811-877 | 内側 `group('corrupted record isolation')`: 健全+破損分離 / 旧 tmuxPath 移行ロード | **2** |

### 1-6. custom_keys_provider_test.dart（673 行 / 33 件）

- 構造: `main()`(9) 直下に **group なしで 33 テストがフラット**。`TestWidgetsFlutterBinding.ensureInitialized()`(10) あり。
- テスト毎の共通ボイラープレート（全 33 テストほぼ同一）:
  `SharedPreferences.setMockInitialValues({...})` → `ProviderContainer` → `addTearDown(dispose)` →
  `container.read(customKeysProvider)` → `await Future<void>.delayed(Duration.zero)`（flush）。
- 依存: dart:convert / flutter_test / riverpod / shared_preferences / custom_keys_provider /
  custom_key_button。fake・fixture・定数はなし。`CustomKeysRows` / `CustomKeysNotifier` 定数キーを参照。
- テスト 33 件の内訳（実測・実行確認）：

| # | 開始-終了 | テーマ |
|---|---|---|
| 1-6 | 12-124 | defaults / add-update-delete persist / deleteButton row トークン / setRowTokens 検証 / corrupt JSON フォールバック / 不正 button エントリスキップ |
| 7-13 | 125-272 | row0 デフォルト / legacy レイアウト移行 / 既存 custom row 維持 / setRowTokens row0 永続化 / row0 unplaced / row0 deleteButton / row0 未知トークン破棄 |
| 14-22 | 273-460 | unusedTokens×2 / placeToken（標準・backspace 自動挿入・dash なし無変更・同列移動・shelf・未知 no-op・recreation 生存） |
| 23-25 | 461-520 | row2 num 補完（customized row2 / default row2 / persisted default row2） |
| 26-31 | 521-636 | addRow（追加 / maxRows no-op）・removeRow（トークン shelf 化 / 全削除）・placeToken 新行・maxRows 超 truncation |
| 32-33 | 637-673 | legacy row keys → rows 統合・corrupt rows フォールバック |

## 2. 目標構成

### 2-1. 共通方針

- 新規 helper の配置は原則 `test/providers/helpers/`（既存 `test/helpers/` は汎用 fake 置き場。provider
  固有の共有コードは `test/providers/helpers/` が責務に沿う）。BRIEF 3 項の
  `test/<dir>/helpers/<name>.dart` に適合。ただし `FakeSaveAsExporter` のみ providers/widgets 両設計の
  共通要素のため `test/helpers/` に一本化（critique §2-4 対応・§7 参照）。
- helper は `main()` を持たない（`flutter test` のテスト対象にならない）。クラス/関数は**公開名**で定義
  （BRIEF 5 項の private 共有禁止を遵守。既存 private 名 `_TestSftpClient` 等は公開名へ rename する。
  これはテスト名・アサーションの変更ではない）。
- **download 分割のテスト本文は「変数参照方式」で無変更**（critique §2-3 対応）: 各新ファイルの `main()`
  に `late Directory tmp; late String appTmp;` を宣言し、`setUp` で `DownloadProviderTmpScope` の値を
  再代入する。テスト本文の `tmp`/`appTmp` 参照（実測 67 行）は**一切書き換えない**（期待値文字列の
  バイト不変が構造的に保証される）。詳細は §2-3 補・`§3-1`。
- 各新テストファイルは 500 行未満。数値根拠は「移動するテスト本体の行和＋ヘッダ約 40-63 行」。
  全ファイルの最大見積りは **365 行**（active_session domain_migration、ヘッダ変更影響なし）。

### 2-2. 新規 helper（4 本: `test/providers/helpers/` 3 本 ＋ `test/helpers/` 共通 1 本）

| helper ファイル | 内容（責務） | 行数見積り |
|---|---|---|
| `test/providers/helpers/download_provider_test_utils.dart` | download 系 fake 一式を集約: `TestSftpClient`（旧 `_TestSftpClient`）/ `FakeDownloadDestination` / `GatedSaveAsExporter`（旧 `_GatedSaveAsExporter`）/ `OpenSftpFailingSshClient`（旧 `_OpenSftpFailingSshClient`）/ `entry()`（旧 `_entry`）/ `makeDownloadProviderContainer(...)`（旧 `makeContainer`。clock・notificationService・exporter の注入対応）/ `DownloadProviderTmpScope`（tmp/appTmp・path_provider channel モックの setUp/tearDown を内包。既存 helpers の FakeSshClient/FakeSftpClient/FakeSshNotifier/FakeSettingsNotifier/FakeSshForegroundTaskService を import 再利用）。**`FakeSaveAsExporter` はここに置かず test/helpers/ の共通版を import する**（critique §2-4 対応） | 約 200 |
| `test/providers/helpers/custom_keys_test_harness.dart` | `Future<ProviderContainer> createCustomKeysContainer({Map<String, Object> initialValues = const {}})`。`setMockInitialValues`→container 生成→`addTearDown`→`read`（load トリガ）→`await Duration.zero`（flush）の 33 テスト共通手順を 1 関数化 | 約 40 |
| `test/providers/helpers/connection_test_storage.dart` | `void resetConnectionStorage()`（`SharedPreferences.setMockInitialValues({})` と `SecureStorageService.setTestValues({})`）。各ファイルの `setUp` 内で呼ぶ | 約 15 |
| `test/helpers/fake_save_as_exporter.dart`（新規・**共通**） | **`FakeSaveAsExporter` の一本化版**（providers 現行 L134-152 `{result, error, calls}` と widgets 現行 L83-101 `{result}` を統合し、誤差対応の**スーパーセット `{result, error, calls}`** を採用）。providers は download_provider_test_utils.dart 経由、widgets は download_flow_harness.dart 経由で import。両設計の既存利用（result のみ / error throw）はサブセット互換で無変更 | 約 25 |

- 注: `FakeSaveAsExporter` は providers/widgets 両設計で同名・別実装の二重新設を避けるため
  `test/helpers/fake_save_as_exporter.dart` へ**一本化**（critique §2-4 対応・§7 に widgets 側の調整通知）。
  一本化により「BRIEF 3『重複定義を増やさない』」を遵守。
- 注: active_session は**共有 fake/fixture が元々無く** helper 不要（setUp は 1 行、
  各ファイルにそのまま置く）。
- 注: connection の `_CorruptOnSecondReadStorage` は使用 1 箇所（テスト 761）のため
  migration ファイル内に残す（helper 化しない）。

### 2-3. download_provider_test.dart → 7 ファイル

| 新ファイル | 責務（1 文） | 含める group | 行数見積り（根拠） | import 先（主要） |
|---|---|---|---|---|
| `download_provider_basic_flow_test.dart` | ダウンロード基本フロー: 初期状態・衝突検出・overwrite/rename/skip・同一バッチ重複宛先の自動リネーム | `downloadProvider` | 198+31=229 本体＋ヘッダ約48＝**約280** | flutter_test / riverpod / download_provider（DownloadPhase 等）/ helpers(utils)+既存 helpers ×2（ssh/sftp） |
| `download_provider_cancel_reset_test.dart` | キャンセル・リセット・転送再開始の 冪等性と abort 安全性 | `downloadProvider` | 56+56+34+47+51=244 本体＋約48＝**約295** | 同左 |
| `download_provider_disconnect_error_test.dart` | SSH 切断・部分失敗続行・切断×キャンセル競合・openSftp 失敗のエラー経路 | `downloadProvider` | 54+37+46+47+23=207 本体＋約53＝**約265** | 同左 |
| `download_provider_progress_speed_test.dart` | fraction（既知/未知サイズ進捗）と speedLabel（注入クロック・間引き）の派生表示 | `downloadProvider` | 60+49=109 本体＋約48＝**約160** | 同左 |
| `download_provider_batch_lifecycle_test.dart` | 新旧バッチ並走時の保存先 dispose・切断リスナーの境界管理（M1/M2/M4 回帰） | `downloadProvider` | 74+78+17+33+34=236 本体＋約53＝**約295** | 同左 |
| `download_provider_notification_test.dart` | TransferNotificationService 連携（進捗/完了/キャンセル/失敗/未起動/throw 握りつぶし） | `downloadProvider` | 215 本体＋約53＝**約275** | 同左 |
| `download_provider_single_download_test.dart` | startSingleTmpDownload の tmp→Save-As 単一フロー（成功/キャンセル/throw/失敗/進捗/M3 phase 遷移） | `downloadProvider.single（startSingleTmpDownload・tmp→Save-As）`（**元の group 名をそのまま保持**） | 226 本体＋約63＝**約295** | 同左 |

- 全 7 ファイルで group 名は元の `downloadProvider` / `downloadProvider.single（…）` を**変更せず**そのまま使う
  （BRIEF 1 項遵守。大きすぎる group は「同一 group 名のまま複数ファイルへテストを分散」で分割する）。
- テスト件数: 7+5+5+2+5+5+6 = **35**（不変）。

#### 7 ファイル共通ヘッダ（critique §2-2【必須】対応）

各新ファイルの `main()` 冒頭は以下を定型とする（全 7 ファイルで必須）:

```dart
void main() {
  // 必須: 全テストが test() のため Binding は自動初期化されない。
  // MethodChannel モック登録（DownloadProviderTmpScope.setUp 内）に先立って必要（現行 L185 と同一）。
  TestWidgetsFlutterBinding.ensureInitialized();

  final scope = DownloadProviderTmpScope();
  // テスト本文は tmp/appTmp を直接参照する（critique §2-3・変数参照方式）。
  // 書き換えを避けるため main 直下の late 変数へ setUp で scope の値を再代入する。
  late Directory tmp;
  late String appTmp;
  setUp(() {
    scope.setUp();
    tmp = scope.tmp;
    appTmp = scope.appTmp;
  });
  tearDown(scope.tearDown);

  group('downloadProvider', () { /* 各ファイルのテスト（本文は現行と verbatim 同一） */ });
}
```

- 上記ヘッダは 1 ファイルあたり約 8 行増（§2-3 表の行数見積りに反映済み。最大でも約 295 行で 500 未満）。
- `DownloadProviderTmpScope` の実装（helper 内）: `setUp()` は現行 setUp 本文（tmp 作成・
  `appTmp = '${tmp.path}/app_tmp'`・path_provider channel モック登録）を、`tearDown()` は現行 tearDown
  本文（channel null 化・tmp 削除 try-catch）をそのまま移す。`tmp` は `Directory`、`appTmp` は `String` を公開。

#### 2-3-補: テスト本文の `tmp`/`appTmp` 参照と書き換え方針（critique §2-3【必須】対応）

現行 L185 以降（テスト本文）の参照を全行抽出した実測:

| 参照パターン | 実測行数 | 代表行 | 書き換え方針（**変数参照方式**） |
|---|---|---|---|
| `FakeDownloadDestination(tmp.path)` | 30 行 | 全 35 テストの転送宛先 | `tmp` は各 main の `late Directory tmp`（setUp で scope.tmp 再代入）→ **本文無変更** |
| `File('${tmp.path}/…').readAsBytesSync()/writeAsBytesSync()/existsSync()` | 26 行 | 実 IO 検証（L285/308/322/335 等） | 同上 → **本文無変更** |
| 追加宛先ディレクトリ `'${tmp.path}/b'` / `'${tmp.path}/again'` / `'${tmp.path}/new'` | 4 行 | L864/1036/1112/1217 | 同上 → **本文無変更** |
| `appTmp` の期待値文字列 `'$appTmp/sftp_download/data_1.bin'` | 7 行 | L1500/1502/1522/1523/1545/1547/1574 | `late String appTmp`（setUp で scope.appTmp 再代入）→ **期待値文字列がソース上バイト不変** |
| テスト名・コメント中の「tmp」 | 9 行 | L1477/1478/1498/1501/1506/1521/1527/1546/1551 | **対象外**（テスト名不変のため・変数参照ではない） |

計: 変数参照は **60 行（tmp）＋ 7 行（appTmp）＝ 67 行**。変数参照方式の採用により**テスト本文の書き換えは 0 件**。

- 「helper 経由（`scope.tmpPath` 等を本文で直接参照）」方式は**不採用**: 60+7 行の機械置換と期待値文字列の
  ソース変更を伴い、critique §2-3 が求める「置換後も assert 行の期待値文字列が不変」の検証負荷が増えるため。
  変数参照方式なら assert 行は現行と **1 文字も変わらず**、行 diff 検証（§5）が自明に空になる。
- 参考: `setUp`/`tearDown` 側の tmp/appTmp（L186-213: 生成・代入・channel モック・削除）は
  `DownloadProviderTmpScope` 内へ移設（テスト本文外の構築コード）。

### 2-4. active_session_provider_test.dart → 5 ファイル

| 新ファイル | 責務（1 文） | 含める group | 行数見積り（根拠） | import 先 |
|---|---|---|---|---|
| `active_session_provider_crud_test.dart` | session の CRUD（追加/更新/touch/close/remove/current 選択/clear/接続別取得） | `ActiveSessionProvider` | 286 本体＋約40＝**約330** | flutter_test / riverpod / active_session_provider / shared_preferences |
| `active_session_provider_persistence_test.dart` | PROV-ACTIVE 永続化（028/029/034）とロード・removeSessionsForConnection の保持 | `ActiveSessionProvider` | 165+32+36=233 本体＋約40＝**約275** | 同左＋dart:convert |
| `active_session_model_json_test.dart` | ActiveSession/ActiveSessionsState の JSON round trip・fromJson フォールバック・copyWith | `ActiveSessionProvider` | 89 本体＋約35＝**約125** | 同左＋multiplexer_backend |
| `active_session_domain_sync_test.dart` | updateSessionsForConnection の履歴保持・backend デフォルト/herdr 保存 | `ActiveSessionProvider` | 35+12+18+17=82 本体＋約40＝**約125** | 同左＋multiplexer_session / tmux_models |
| `active_session_domain_migration_test.dart` | updateSessionsFromDomain の同名 ID 分離・legacy sessionId-null 移行・曖昧非移行・不一致破棄 | `ActiveSessionProvider` | 52+25+67+84+57+36=321 本体＋約40＝**約365**（全 21 ファイル中最大） | 同左＋multiplexer_session / dart:convert |

- 各ファイルは `setUp(() { SharedPreferences.setMockInitialValues({}); })` を 1 行ずつ持つ（他に共有なし）。
- テスト件数: 13+5+5+4+6 = **33**（不変）。

### 2-5. connection_provider_test.dart → 4 ファイル

| 新ファイル | 責務（1 文） | 含める group | 行数見積り（根拠） | import 先 |
|---|---|---|---|---|
| `connection_provider_test.dart`（既存ファイルを縮小） | connectionsProvider の初期化・加除更新・検索・選択・ソートの動作 | `ConnectionProvider`（外側グループ。直下テスト 7＋sort 1 を残す） | 159+29=188 本体＋約35＝**約225** | 既存 import 維持 |
| `connection_model_test.dart` | Connection モデルの JSON round trip・fromJson デフォルト/tmuxPath 相互運用・copyWith・storageSchemaVersion | `Connection` | 291 本体＋約40＝**約335** | dart:convert / backend_type / multiplexer_config / connection_provider |
| `connection_migration_test.dart` | ConnectionMigration の legacy→multiplexer 移行・v2 スキップ・backup/rollback・stale backup 復帰（`_CorruptOnSecondReadStorage` は本ファイル末尾に残す） | `ConnectionMigration` | 316 本体＋約45＋fake クラス約25＝**約390** | dart:convert / connection_migration / secure_storage / shared_preferences |
| `connection_corrupted_record_test.dart` | 破損レコード隔離・旧 tmuxPath レコードの移行ロード | `corrupted record isolation` | 72 本体＋約40＝**約115** | dart:convert / connection_provider / secure_storage |

- 各ファイルの `setUp` は `resetConnectionStorage()`（helper）を呼ぶ（BRIEF 3 項の共有化）。
  ※ 注: `connection_migration_test.dart` の 390 行見積りは 500 未満で余裕あり（実測換算でも本体 316 行）。
- テスト件数: 8+17+10+2 = **37**（不変）。

### 2-6. custom_keys_provider_test.dart → 5 ファイル

- 元ファイルに group が無いため、**新ファイルに group を新設せず元と同じ「main() 直下の test()」構成を維持する**
  （テスト full name を完全不変にする最小リスク策。詳細は未確定点）。
- 各ファイルは `TestWidgetsFlutterBinding.ensureInitialized();` と `createCustomKeysContainer()`（helper）を使う。

| 新ファイル | 責務（1 文） | 行数見積り（根拠） | import 先 |
|---|---|---|---|
| `custom_keys_buttons_test.dart` | ボタンの CRUD・永続化・ロード時検証（corrupt JSON・不正エントリスキップ） | 113 本体＋約40＝**約155** | flutter_test / riverpod / custom_keys_provider / custom_key_button / shared_preferences / helpers(harness) |
| `custom_keys_row0_test.dart` | row0（カスタム行）の配置・persist・未知トークン破棄・unplaced/deleteButton | 148 本体＋約40＝**約190** | 同左 |
| `custom_keys_placement_test.dart` | placeToken/unusedTokens/shelf 移動・backspace 自動挿入・recreation 生存 | 188 本体＋約40＝**約230** | 同左 |
| `custom_keys_rows_test.dart` | addRow/removeRow/maxRows 制限・truncation・新行への placeToken | 116 本体＋約40＝**約160** | 同左 |
| `custom_keys_migration_test.dart` | row2 num 補完・legacy row keys→rows 統合・corrupt rows フォールバック | 60+37=97 本体＋約40＝**約140** | 同左 |

- テスト件数: 6+7+9+6+5 = **33**（不変）。

## 3. 移動マッピング

### 3-1. download_provider_test.dart（35 件 → 7 ファイル）

| 移動元（行範囲） | テスト数 | 移動先 |
|---|---|---|
| 236-433（#1-6） | 6 | basic_flow |
| 1231-1261（#24 同一バッチ重複宛先） | 1 | basic_flow |
| 434-546（#7-8）＋ 840-971（#15-17） | 5 | cancel_reset |
| 547-637（#9-10）＋ 638-730（#11-12）＋ 972-994（#18） | 5 | disconnect_error |
| 731-839（#13-14） | 2 | progress_speed |
| 995-1230（#19-23） | 5 | batch_lifecycle |
| 1262-1477（#25-29） | 5 | notification |
| 1478-1703（#30-35） | 6 | single_download |

**共有コードの移設先（すべて download_provider_test_utils.dart へ）**:
- `makeContainer`(215-233) → `makeDownloadProviderContainer`（公開関数）
- `_TestSftpClient`(39-91) → `TestSftpClient`
- `FakeDownloadDestination`(93-132) → 同名のまま移動
- `FakeSaveAsExporter`(134-152) → **共通helper `test/helpers/fake_save_as_exporter.dart` へ一本化**
  （providers/widgets 両設計で import。誤差対応版 `{result, error, calls}` スーパーセット・§7 参照）
- `_GatedSaveAsExporter`(153-172) → `GatedSaveAsExporter`（download 専用のため download_provider_test_utils.dart）
- `_OpenSftpFailingSshClient`(26-37) → `OpenSftpFailingSshClient`
- `_entry`(174-180) → `entry`
- `_pathProviderChannel`(182)＋`tmp/appTmp`＋setUp/tearDown(186-213) → `DownloadProviderTmpScope`
  （各テストファイルの `main()` 冒頭で `final scope = DownloadProviderTmpScope();` の後、
  `setUp(() { scope.setUp(); tmp = scope.tmp; appTmp = scope.appTmp; }); tearDown(scope.tearDown);` と登録。
  `late Directory tmp; late String appTmp;` は各 main に宣言しテスト本文を無変更で参照させる＝**変数参照方式**）
- **テスト本文の `tmp`/`appTmp` 参照（実測 67 行）は書き換え不要**（上記の再代入により本文へ一切触れない。
  期待値文字列 `'$appTmp/sftp_download/data_1.bin'` は 7 行すべてバイト不変）。
  分類一覧と行番号は §2-3 補を参照。

### 3-2. active_session_provider_test.dart（33 件 → 5 ファイル）

| 移動元（行範囲） | テスト数 | 移動先 |
|---|---|---|
| 17-265（#1-11）＋ 431-467（#15-16） | 13 | crud |
| 266-430（#12-14）＋ 557-624（#22-23） | 5 | persistence |
| 468-556（#17-21） | 5 | model_json |
| 625-706（#24-27） | 4 | domain_sync |
| 707-1027（#28-33） | 6 | domain_migration |

共有コード: setUp の `SharedPreferences.setMockInitialValues({})` を各ファイルへ 1 行コピー（他に共有なし）。

### 3-3. connection_provider_test.dart（37 件 → 4 ファイル）

| 移動元（行範囲） | テスト数 | 移動先 |
|---|---|---|
| 19-176（7 直下）＋ 468-496（sort） | 8 | connection_provider_test.dart（縮小） |
| 177-466（内側 Connection） | 17 | connection_model_test.dart |
| 496-809（内側 ConnectionMigration）＋`_CorruptOnSecondReadStorage`(884-908) | 10 | connection_migration_test.dart |
| 811-877（corrupted record isolation） | 2 | connection_corrupted_record_test.dart |

共有コード: setUp のリセット 2 行 → `resetConnectionStorage()`（helper）を各 setUp から呼ぶ。
`_CorruptOnSecondReadStorage` は使用が migration 内 1 箇所のため同ファイルへ残す（helper にしない）。

### 3-4. custom_keys_provider_test.dart（33 件 → 5 ファイル）

| 移動元（行範囲） | テスト数 | 移動先 |
|---|---|---|
| 12-124（#1-6） | 6 | buttons |
| 125-272（#7-13） | 7 | row0 |
| 273-460（#14-22） | 9 | placement |
| 521-636（#26-31） | 6 | rows |
| 461-520（#23-25）＋ 637-673（#32-33） | 5 | migration |

共有コード: テスト毎の 5 行ボイラープレート → `createCustomKeysContainer({initialValues})`（helper）へ。
`CustomKeysRows` / `CustomKeysNotifier.rowsKey` 等定数は lib 側参照のため import だけで済む（重複定義しない）。

## 4. リスクと対策

| リスク | 対策 |
|---|---|
| **setUp の共有範囲**（download の tmp/appTmp/channel モック） | スコープ型 `DownloadProviderTmpScope` にカプセル化し、各ファイルの `main()` で setUp/tearDown を登録。テストごとに fresh tmp を作る現行セマンティクスを維持。各ファイル先頭の `TestWidgetsFlutterBinding.ensureInitialized()` は**必須**（`test()` のみのため Binding が自動初期化されず、channel モック登録時に例外になる。critique §2-2）。複数ファイルは別 isolate で実行されるため tmp パス競合・channel モックの相互干渉なし |
| **テスト本文の `tmp`/`appTmp` 参照（critique §2-3）** | **変数参照方式**により書き換え 0 件。各 main の `late Directory tmp; late String appTmp;` に setUp で scope 値を再代入し、テスト本文・期待値文字列（`'$appTmp/sftp_download/data_1.bin'` 7 行）は**バイト不変**。helper 経由（scope フィールド直接参照）は期待値文字列のソース変更を伴うため不採用。参照 67 行の分類は §2-3 補 |
| **fixture のスコープと private 名** | BRIEF 5 項により private 基底共有は禁止 → 公開クラス/関数へ rename（`TestSftpClient` 等）。テストコード中の参照名が変わるがテスト名・アサーション・期待値は不変。`FakeSftpFile` 等は既存 helper を import 再利用し**重複定義しない** |
| **グローバル状態（SecureStorageService の static test map / SharedPreferences mock）** | `setTestValues({})`＋`setMockInitialValues({})` は各テストファイルの setUp で必ずリセット。ただし flutter test はファイル毎に独立 isolate で実行されるため、**ファイル間の実行順序依存は存在しない**（同一ファイル内のテスト間依存もなし・各テストが container を自前生成し addTearDown で dispose） |
| **ドメイン層の static キャッシュ / タイマー** | download は `DownloadNotifier` を makeContainer で毎回新規生成（clock / progressThrottle 100ms / notificationService / exporter を注入）するため、インスタンス間の状態共有なし。`Future.delayed` / `pumpEventQueue` は各テスト内で完結。タイマー値（100ms 間引き）は変更しない |
| **ボイラープレート抽出による「実行順序の見かけ上の変化」**（custom_keys の `read`→`flush`） | `createCustomKeysContainer()` は `read`（load トリガ）→ `Future.delayed(Duration.zero)`（flush）の順を固定。実測の全 33 テストは flush 後にしか state を検証しておらず、中間状態アサーションが無いため意味不変。分割実装時に git diff で各テストの検証行が無変更であることを確認する |
| **FakeSaveAsExporter の設計間二重定義（critique §2-4）** | providers/widgets の同名・別実装を解消するため `test/helpers/fake_save_as_exporter.dart` に**一本化**（誤差対応スーパーセット）。両設計が import し、既存利用はサブセット互換。実装時にどちらか一方へ自分の fake を残さない（§7 調整通知） |
| **pumpWidget ヘルパーの重複回避** | 本 4 ファイルに widget テスト・pumpWidget は存在しない（全 `test()`）。既存 `terminal_*_scaffold` などの重複導入はしない |
| **group 名の不変性** | download/active/connection は元 group 名をそのまま保持。custom_keys は元が group 無しのため、新規 group を**設けない**（テスト full name 完全一致）。`*_part1` 等の機械的命名はしない |
| **分割数の増加によるヘルパー import の重複** | helper は 3 本のみ新設し、既存 5 helper（ssh/sftp/notifier×2/foreground）を再利用。新 helper に同じ fake を再定義しない |

## 5. 検証計画

1. **分割前の件数確定（完了済み・実行で確認）**:
   ```
   flutter test test/providers/download_provider_test.dart --reporter=json       # testDone 35
   flutter test test/providers/active_session_provider_test.dart --reporter=json # testDone 33
   flutter test test/providers/connection_provider_test.dart --reporter=json     # testDone 37
   flutter test test/providers/custom_keys_provider_test.dart --reporter=json    # testDone 33
   ```
   （JSON の `"type":"testDone"` 件数は +1 大きく出るが、これは `loading <path>` の擬似イベント。実テスト数は上記。）
2. **分割後の件数一致**（分割後ファイル群の合計 = 35/33/37/33）:
   ```
   flutter test test/providers/download_provider_{basic_flow,cancel_reset,disconnect_error,progress_speed,batch_lifecycle,notification,single_download}_test.dart --reporter=json  # 35
   flutter test test/providers/active_session_provider_{crud,persistence,model_json,domain_sync,domain_migration}_test.dart  # 33
   flutter test test/providers/connection_provider_test.dart test/providers/connection_{model,migration,corrupted_record}_test.dart  # 37
   flutter test test/providers/custom_keys_{buttons,row0,placement,rows,migration}_test.dart  # 33
   ```
   **※ glob（`download_provider_*_test.dart` / `connection_*_test.dart`）は旧 `download_provider_test.dart` /
   `connection_provider_test.dart` にもマッチするため使用しない**（critique §5 推奨）。旧ファイル削除後に
   glob を使う場合は、左記の明示列挙（or 旧ファイル削除後の glob）で件数を確認すること。
3. **テスト名一覧の同一性（fullName 集合一致）**: 分割前後で `testStart` イベントの `name` 一覧が完全一致すること。
   全 4 ファイル/全新ファイルを対象に `sort` 後 `diff` で確認。custom_keys は group 非新設（§6-1 で確定）に
   より fullName が無条件一致する。`@Tags/@Skip/@Timeout` は 4 ファイルとも無いためメタデータ保持確認は不要。
4. **テスト本体行 diff が空（critique §4-g【必須】対応）**: 旧ファイルの各テスト本体ブロックの行と、
   新ファイルの対応ブロックの行が**一字違わず一致**すること（`diff` で空を確認）。
   - download: 変数参照方式により assert 期待値文字列・タイマー値（100ms）が現行とバイト同一であることを
     この diff で機械確認（`FakeDownloadDestination(tmp.path)` 等 67 参照行の無変更を含む）。
   - active/connection/custom_keys: テスト本体は verbatim コピー（行コピーのみ）のため同様に空 diff。
5. **全新ファイルの実行（全テスト pass）**: 対象は 21 テストファイル＋helper 4 本（providers/helpers 3 ＋ test/helpers 1）。
   `make analyze`（flutter analyze）で helper 含む新ファイルの warning/error ゼロ。
   `flutter test test/providers/` で **EXIT=0 かつ fail 0**（件数一致だけでは fail を検出できないため、
   `--reporter=json` の `testDone.result == 'success'` を全て確認する・critique §4-g 推奨）。
6. **全体件数 2,009 不変の確認**（リード実施）: `flutter test --exclude-tags=repro --reporter=json`
   の testDone 合計が 2,009 のままであること（`loading` 擬似イベントを除外して数える）。

## 6. 未確定点

v2 で以下の判断を**確定**（critique の指摘により未確定点から閉鎖）:

1. **custom_keys の group 導入 →「しない」で確定**（critique ・軽微 5 推奨）。元ファイルは group 無し
   （main() 直下 33 テスト）のため、group を新設すると fullName が変わる。全設計共通の「group 追加は不可」
   方針に揃え、新ファイルも group なしでテストする。fullName 集合一致は §5-3 で検証。
2. **download の分割粒度 → 7 ファイル構成で確定**（progress_speed を独立維持。critique は粒度に異論なし）。
   通知ファイルへの統合（6 ファイル化）は実装時要求があれば再検討可能。
3. **helper の配置 → 原則 `test/providers/helpers/`、共通 fake のみ `test/helpers/`** で確定。
   `FakeSaveAsExporter` は providers/widgets 共通のため `test/helpers/fake_save_as_exporter.dart`
   （§2-2・§7）。provider 固有の download/custom_keys/connection helper は `test/providers/helpers/`。

残る未確定点は「なし」。

## 7. widgets-screens 設計者への調整通知（critique §2-4【必須】対応・転送用）

※ 読み取り専用のため直接メッセージの代わりに本節を転送用メモとして用意。リード経由で
p5-widgets/screens 担当へ伝達することを推奨。

**依頼内容**: providers 設計書 v2（本稿）と widgets-screens 設計書 §2-E の間で、
`FakeSaveAsExporter` の定義を一本化してください。

- **現状**: providers 側は現行 download_provider_test.dart L134-152（`{result, error, calls}`・error throw 可）を、
  widgets 側は現行 file_browser_download_flow_test.dart L83-101（`{result}` のみ）を、それぞれ独立した
  helper として新設する提案でした（同名・別実装）。critique §2-4 の指摘どおり BRIEF 3「重複定義を増やさない」
  の趣旨に反します。
- **確定案**: `test/helpers/fake_save_as_exporter.dart` に**一本化**します。
  実装は誤差対応の**スーパーセット `{result, error, calls}`**（providers 版の全機能・L134-152 と同一仕様）。
  - providers 側: `download_provider_test_utils.dart` へは定義を置かず、本 helper を import。
  - widgets 側（要調整）: `screens/file_browser/helpers/download_flow_harness.dart` の `FakeSaveAsExporter`
    定義（現行 L83-101）を廃止し、`test/helpers/fake_save_as_exporter.dart` を import してください。
    既存利用は `result:` のみのサブセット互換のため、テスト本文・期待値は無変更で動作します。
- **制約**: テスト名・アサーション・期待値・タイマー値は両設計とも不変。
  1 本化により将来の仕様ズレを防ぎます。
- **確認事項**: widgets 側で `error:` 付き利用が無いこと（現行 L83-101 は `{result}` のみ・実測済み）。
  もし widgets 側テストで error throw を検証する将来要件が有れば、本 helper の `error` フィールドを利用可能。

以上。
# P2 設計: `lib/providers/download_provider.dart` + `lib/providers/settings_provider.dart` 責務ベース再設計（v2）

- 担当: providers-core-designer（タスク#25）
- 改訂 v2（design-critic レビュー §3 + リーダー方針反映）: ①`DownloadNotificationSink` を**初期構成**へ追加（shell は「フロー編成 + state 反映」に限定・行数再計算）②reserved 集合の所有者を `DownloadBatchSession` に明記 ③数値修正（notifier 参照 14 ファイル実測・setter 数は実測値表記）
- 対象:
  - `lib/providers/download_provider.dart`（HEAD 910 行）
  - `lib/providers/settings_provider.dart`（HEAD 750 行）
- 制約: **設計のみ・コード変更禁止**。本ファイルは `/tmp/p2-design/providers-core.md`（リポジトリ外）
- 原則: ①1ファイル=1責務 ②合成優先（private共有のmixin/基底/part禁止）③公開API変更は許容（呼出元・テスト更新含む）④依存非循環 ⑤各ファイル500行未満 ⑥挙動不変（テスト期待値不変）

---

## 1. 現状責務分析（事実・HEAD 検証済み）

### 1.1 download_provider.dart（910 行）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 24-49 | `DownloadPhase`（公開 enum・8値） | 転送フェーズの型 | 26 |
| 51-127 | `DownloadItemState`（公開） | 1アイテムの不変状態（copyWith） | 77 |
| 129-214 | `DownloadState`（公開） | バッチ全体の不変状態 + 派生集計 getter（receivedBytes/totalBytes/completedCount/failedCount/skippedCount/fraction） | 86 |
| 216-906 | `DownloadNotifier`（公開・Notifier） | **多責務が混在**（下記 1.3） | 691 |
| 908-910 | `downloadProvider` | NotifierProvider 定義 | 3 |

### 1.2 settings_provider.dart（750 行）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 13-26 | `TransferConflictPolicy`（公開 enum） | 衝突ポリシー + 永続化値変換 | 14 |
| 30-275 | `AppSettings`（公開） | **41 フィールドの不変状態モデル** + copyWith（+ isAutoFit/isAutoResize getter） | 246 |
| 277-731 | `SettingsNotifier`（公開・Notifier） | **多責務が混在**（下記 1.4） | 455 |
| 733-736 | `settingsProvider` | NotifierProvider 定義 | 4 |
| 738-741 | `darkModeProvider` | 便利 Provider（watch 委譲） | 4 |
| 743-750 | `wheelSendVerifiedProvider` | 定数 Provider（コメント+実装） | 8 |

### 1.3 DownloadNotifier 内の混在責務（事実・行数は近似）

| 責務 | 主要メンバー | 特徴 |
|---|---|---|
| a. バッチ/世代ライフサイクルと保存先リソース所有 | `_generation` / `_disposedBatches` / `_token` / `_destination` / `_disposeDestination` / `_disposeOrphan` / `reset()` の解放部 | M1（クロスバッチ誤破棄）・M2（リーク）・HIGH#1（転送中 reset）の不変条件が集中 |
| b. 順次キュー実行 | `_runQueue`（openSftp・SSH切断購読・世代ガード・アイテム単位 try/catch・publishCompletion 方針） | 転送タスク層基盤契約（throw しない・100ms 間引きはタスク層責務） |
| c. 進捗集計・間引き | `_onProgress` / `_ema` / `_lastProgressAt` / `progressThrottle` / `speedLabel` 導出 | EMA（α=0.3）+ 100ms throttle・アイテム境界リセット |
| d. 名前衝突の解決 | `applyOverwriteDecisions` / `_firstAvailableName` / `_firstAvailablePath` / `_existsInDestination` / sanitize・起動時自動リネーム | 事前スキャン・`_1` 採番・reserved 管理（LOW#3） |
| e. Save-As 単一フロー | `startSingleTmpDownload` / `_deleteTmpBestEffort` / tmp 採番 | tmp 領域 → エクスポート → tmp 削除・M3（中間 completed 抑止） |
| f. 通知・l10n | `_notify` / `_l10n` / `_bytesLabel` / `_notification` | fire-and-forget・ベストエフォート |
| g. 公開フロー編成 | `startDownloads` / `cancel` / `reset` / `build` | 上記 a〜f を束ねて state へ反映 |

### 1.4 SettingsNotifier 内の混在責務（事実）

| 責務 | 主要メンバー | 行数 |
|---|---|---|
| a. 永続化キー定義 | `_*Key` **40 個**の private const | 40 |
| b. 非同期ロード | `_loadSettings`（`SharedPreferences.getInstance` → `SettingsMigrationRunner.run` → `ref.mounted` ガード → state 構築 → `setCachedLanguage` → 向き/リフレッシュレート適用） | ~70 |
| c. 保存 | `_saveSetting`（型 dispatch: bool/double/int/String） | 13 |
| d. setter 公開 API | **40 個**の `setXxx` 定義（実測・うち 4 個は lib/test 全域で未使用）+ `toggleDirectInput` + `reload`（`state=copyWith` + `_saveSetting` の反復） | ~300 |
| e. プラットフォーム適用 | `_applyScreenOrientation`（SystemChrome）+ `_applyRefreshRate`（FlutterDisplayMode・Android のみ） | ~100 |
| f. Provider 配線 | `settingsProvider` / `darkModeProvider` / `wheelSendVerifiedProvider` | 20 |

### 1.5 依存サービス（既存の再利用可能アセット・事実）

- download 側: `SftpDownloadService`（`download` / `sanitizeLocalName`）、`TransferSpeedEma`（α=0.3・clock 注入可）、`formatTransferSpeed`、`TransferCancelToken` / `TransferCancelledException`、`DownloadDestination` / `DownloadSink` / `FileDestination`、`SaveAsExporter` / `FfdSaveAsExporter`、`TransferNotificationService` / `SshForegroundTaskService`、`SshClient`（`connectionStateStream` / `openSftp`）
- settings 側: `SettingsMigrationRunner`（v1 は adjustMode 統合）、`l10n_lookup.dart`（`l10nForLanguage` / `setCachedLanguage` / `lookupL10n`）

---

## 2. 調査結果（利用元・テスト・永続化・非同期ライフタイム）

### 2.1 downloadProvider の利用元（事実・rg 検証済み）

| ファイル | 参照内容 |
|---|---|
| `lib/screens/file_browser/file_browser_screen.dart` | `ref.listenManual<DownloadState>(downloadProvider, ...)`（phase 遷移駆動・L40-90）・`notifier.startDownloads` / `startSingleTmpDownload` / `applyOverwriteDecisions` / `reset`（L289/305/698/740/749/754）・`DownloadState.collidingItems`（L776） |
| `lib/screens/file_browser/widgets/transfer_progress_sheet.dart` | `ref.watch(downloadProvider)`・`state.phase/items/fraction/speedLabel`・`notifier.cancel()`（L38-141）・`DownloadItemState` 参照（L153） |
| `lib/screens/terminal/terminal_screen.dart` | `ref.listenManual<DownloadState>(downloadProvider, ...)`（L7560）・純関数 `downloadSnackBarDisplay(AppLocalizations, DownloadState, DownloadPhase?)`（L9479-9530・enum の網羅 switch） |
| `lib/services/background/foreground_task_service.dart` | コメントのみ（DownloadNotifier から利用される旨） |

- lib/widgets/ 配下からの download 参照は**なし**（事実）。
- 公開 API 面: `DownloadNotifier` のコンストラクタ（`clock` / `progressThrottle` / `notificationService` / `exporter` の named 任意引数）、`startDownloads(List<FileEntry>, DownloadDestination)` / `startSingleTmpDownload(FileEntry)` / `applyOverwriteDecisions(Map<String, OverwriteChoice>)` / `cancel()` / `reset()`。

### 2.2 settingsProvider の利用元（事実・rg 検証済み）

| ファイル | 参照内容 |
|---|---|
| 設定画面系 12 ファイル（sections 3 + pickers 10。search 2 は watch のみで notifier 未参照） | `ref.watch(settingsProvider)` でフィールド読み・`ref.read(settingsProvider.notifier).setXxx(...)` |
| `lib/screens/terminal/terminal_screen.dart`（~30 箇所） | `settingsProvider` のフィールド読み + `toggleDirectInput` / `setZoomFactor` |
| `lib/screens/terminal/widgets/ansi_text_view.dart` | `setZoomFactor` + `ref.watch(settingsProvider)` |

- **`settingsProvider.notifier` 参照は実測 14 ファイル**（settings 系 12 + terminal_screen + ansi_text_view・rg 検証済み）。lib から参照される setter は実測 **33 種 + `toggleDirectInput`**（定義は 40 個・§1.4 d。差の 7 種は未使用）。
| `lib/providers/file_transfer_provider.dart` / `image_transfer_provider.dart` / `terminal_display_provider.dart` | `ref.read(settingsProvider)` で upload 設定・表示設定を消費 |
| `lib/services/background/foreground_task_service.dart` / `lib/main.dart` | `settingsProvider` 読み |
| `lib/l10n/l10n_lookup.dart` | `settingsProvider.language` と連携（コメント契約） |

- **未使用の公開 setter（事実・lib/test 全域で呼出なし）**: `setScrollbackLines` / `setEnableNotifications` / `setRequireBiometricAuth` / `setDirectInputEnabled`（`toggleDirectInput` からのみ間接参照）。削除しても挙動は変わらないが、互換コスト最小のため**維持を推奨**（原則③は変更許容であって削除義務ではない）。

### 2.3 テストが参照する公開面（事実）

- `test/providers/download_provider_test.dart`（1703 行）:
  - `DownloadNotifier(clock:, notificationService:, exporter:)` を**直接構築**して `downloadProvider.overrideWith`（L223-228）→ コンストラクタ互換が必須
  - `container.read(downloadProvider)` で `phase/items/collidingItems/receivedBytes/totalBytes/completedCount/failedCount/skippedCount/fraction/speedLabel` を検証
  - `notifier.startDownloads` / `applyOverwriteDecisions` / `cancel` / `reset` / `startSingleTmpDownload`
  - `DownloadPhase` / `DownloadState` / `DownloadItemState` を import（`providers/download_provider.dart` 経由）
- `test/screens/file_browser/file_browser_download_flow_test.dart`: `DownloadNotifier(exporter: exporter)` 直接構築 + phase 待機 + collidingItems
- `test/providers/settings_provider_test.dart`（435 行）: `notifier.reload()`（20 回）/ `setLanguage`（4 回）/ `setCjkMode`（2 回）/ `setScrollSendInput`（1 回）+ SharedPreferences キー（`settings_*` 文字列直書きで検証・L24 他）→ **キー文字列の互換がテストで直接保証されている**
- `test/helpers/fake_settings_notifier.dart`: `FakeSettingsNotifier extends SettingsNotifier` が **`build()` と 7 つの setter**（`setKeepScreenOn` / `setScrollSendInput` / `setInvertScrollSendDirection` / `setAutoFitZoomOnScrollSend` / `setExperimentalHerdrCaretPositionEnabled` / `setZoomFactor`）を override → SettingsNotifier の公開メソッド名・シグネチャ互換が必須
- `test/helpers/terminal_test_scaffold.dart` / `test/screens/connections/*` / `test/screens/settings/*`: `FakeSettingsNotifier(settings: const AppSettings(...))` → **`AppSettings` の const コンストラクタとフィールド名互換が必須**

### 2.4 永続化の形式（事実）

- settings は **SharedPreferences のみ**（`flutter_secure_storage` 不使用・rg で確認）。キーは `settings_*` の **40 個**（`static const String _*Key`・grep でカウント済み）。値は bool/double/int/String のスカラー型のみ・**JSON 直列化なし**。マイグレーションは `SettingsMigrationRunner`（v1: autoFit/autoResize → adjustMode）。
- `TransferConflictPolicy` は `persistedValue`（'autoRename'/'prompt'）で String 保存・不正値は prompt へフォールバック。
- download は**永続化なし**（画面状態のみ）。
- SecureStorage は `lib/providers/key_provider.dart` の SSH 鍵のみで使用（本タスク対象外・対比として記録）。

### 2.5 過去に問題になった非同期ライフタイム（事実）

- **SettingsNotifier.build() は fire-and-forget で `_loadSettings()` を開始**する（`unawaited` 相当・await しない）。テスト側も `TEST-SETTINGS-PROVIDER-001` コメントで「素の ProviderContainer では dispose 前に非同期完了が保証されない → testWidgets + pumpAndSettle が必要」と明記済み。`ref.mounted` ガードでコンテナ破棄後の state 更新を防止している。
- DownloadNotifier はバッチ世代（`_generation`）とトークンスナップショットで在途コールバックを abort（HIGH#1）・`ref.onDispose` で切断購読を解除。

---

## 3. 提案構成（合成・責務境界・各ファイル 1 文責務）

設計方針: P1 の SshClient リファクタ（状態/イベント/資源を所有者へ分離し、構成ルートがクロージャで配線）と同じ「**構成ルート + コラボレータ**」パターンを採る。Notifier は公開 API とフロー編成（状態遷移調整）だけを受け持ち、機械的・状態的ロジックは各コラボレータへ分離する。private 共有のための mixin/基底/part は**一切使わない**。

### 3.1 download 側（7 ファイル）

| 新ファイル | 1 文責務 | 公開面 | 推定行数 |
|---|---|---|---|
| `lib/providers/download_state.dart` | ダウンロード転送の不変状態モデル（enum + 2 値オブジェクト + 派生集計）を定義する。 | `DownloadPhase` / `DownloadItemState` / `DownloadState`（現行と同一・移動のみ） | ~190 |
| `lib/providers/download_batch_session.dart` | バッチ世代・キャンセルトークン・**アイテムリスト（items）**・**予約名集合（reservedNames）**・保存先リソースの所有と解放を 1 箇所に管理する。 | `DownloadBatchSession`（`begin` / `invalidate` / `updateItem`（世代ガード付き）/ `disposeDestination` / `disposeOrphan` / `isCurrent` / `isDisposed(batch)`・`items` / `reservedNames` を所有） | ~170 |
| `lib/providers/download_run_queue.dart` | 1 バッチの順次 SFTP ダウンロードキュー（openSftp・SSH 切断監視・アイテム単位 try/catch・publishCompletion 方針）を実行する。 | `DownloadQueueRunner.run(SshClient, session, callbacks)`。進捗・アイテム更新・完了は**コールバックで報告**し、state/l10n/通知には触れない | ~180 |
| `lib/providers/download_progress_tracker.dart` | 進捗の内部累積・100ms 間引き判定・EMA 速度・速度ラベルを計算する。 | `DownloadProgressTracker`（`update(done, total, now) → ProgressSample(shouldPublish, cumulative, speedLabel)`）（clock 注入可） | ~90 |
| `lib/providers/download_collision_resolver.dart` | 同名衝突の事前スキャン・`_1` 採番・上書き/リネーム/スキップ決定の名前解決を行う。 | `DownloadCollisionResolver`（`preScan` / `firstAvailableName` / `firstAvailablePath` / `resolveDecisions`）。**reserved 集合は状態として保持せず、呼び出し側から引数で受ける**（所有者は `DownloadBatchSession`） | ~120 |
| `lib/providers/download_notification_sink.dart` | 転送通知テキスト（l10n 解決・バイト表示含む）の組み立てと fire-and-forget 発行を行う。 | `DownloadNotificationSink`（`TransferNotificationService` 注入可・`progress` / `complete` / `cancelled` / `failed` / `error` のセマンティックメソッド・throw 握りつぶし） | ~90 |
| `lib/providers/download_provider.dart` | ダウンロード公開 API（Notifier シェル・構成ルート）としてフローを編成し Riverpod state へ反映する（**通知・l10n・items は保持しない**・すべて session / sink 等へ委譲）。 | **現行の公開面を全て維持**: `DownloadNotifier`（コンストラクタ注入 4 引数・`startDownloads` / `startSingleTmpDownload` / `applyOverwriteDecisions` / `cancel` / `reset` / `build`）+ `downloadProvider` + `export 'download_state.dart';`（再エクスポート） | ~260 |

### 3.2 settings 側（4 ファイル）

| 新ファイル | 1 文責務 | 公開面 | 推定行数 |
|---|---|---|---|
| `lib/providers/settings_state.dart` | アプリ設定の不変状態モデル（enum + 41 フィールド値オブジェクト + copyWith）を定義する。 | `TransferConflictPolicy` / `AppSettings`（現行と同一・移動のみ） | ~260 |
| `lib/providers/settings_persistence.dart` | SharedPreferences とのキー・型マッピング（読込・保存）とマイグレーション起動を担当する。 | `SettingsPersistence`（`load() → AppSettings` / `save(key, value)`）。**キー文字列は現行の 40 個を完全互換で保持** | ~160 |
| `lib/providers/settings_platform_applier.dart` | 設定値（向き・リフレッシュレート）を OS/デバイスへ適用する。 | `SettingsPlatformApplier`（`applyOrientation` / `applyRefreshRate`・binding 未初期化時は no-op 維持） | ~110 |
| `lib/providers/settings_provider.dart` | 設定公開 API（Notifier シェル・構成ルート）として setter 群・ロードフローを編成し Riverpod state へ反映する。 | **現行の公開面を全て維持**: `SettingsNotifier`（40 setter 定義（実測） + `toggleDirectInput` + `reload` + `build` の fire-and-forget 維持）+ `settingsProvider` / `darkModeProvider` / `wheelSendVerifiedProvider` + `export 'settings_state.dart';` | ~310 |

### 3.3 配置の判断根拠

- 状態モデルを `providers/` 直下に置く理由: ①SshState が `ssh_provider.dart` 内（=provider 層の慣習）②DownloadState/AppSettings は UI 向け公開状態であり services 層（転送・保存実装）から参照されない ③re-export で呼出元 import 無変更。
- コラボレータに Riverpod 非依存のプレーンクラスを使う理由: 単体テスト容易性（clock/引数注入）・「状態遷移の publish」と「状態遷移の決定」の分離。
- runner / Notifier シェルを l10n/通知から切り離し `DownloadNotificationSink` に集約する理由: 通知テキスト（notifDownloadProgress / Complete / Cancelled / Failed 等）とバイト表示は state（items/counts）から導出可能であり、shell はセマンティックなイベント（進捗・完了・キャンセル・エラー）を sink へ渡すだけで済む。副作用の発火点を「sink」に一元化し、shell を「フロー編成 + state 反映」に限定する（P1 批判「facade への責務再集中」の再発防止）。

### 3.4 依存グラフ（全て一方向・非循環）

```
download_state.dart          （依存なし・純値オブジェクト）
  ▲
download_provider.dart ──► download_batch_session.dart
  │  └─► download_run_queue.dart ──► download_batch_session.dart
  │         └─► services/sftp/sftp_download_service.dart / services/ssh/ssh_client.dart
  │                （service/sshClient は shell が生成・注入）
  │  └─► download_progress_tracker.dart ──► services/sftp/transfer_progress.dart
  │         └─► services/sftp/transfer_format.dart（formatTransferSpeed）
  │  └─► download_collision_resolver.dart ──► services/download/download_destination.dart
  │  └─► download_notification_sink.dart ──► services/background/foreground_task_service.dart
  │         └─► l10n/l10n_lookup.dart（l10n 解決）
  └────► services/download/save_as_exporter.dart

settings_state.dart          （依存なし・純値オブジェクト）
  ▲
settings_provider.dart ──► settings_persistence.dart ──► services/settings_migration.dart
  │  └─► settings_platform_applier.dart ──► flutter_displaymode / services
  └────► l10n/l10n_lookup.dart
```

- コラボレータは provider を import しない（shell がコールバックで配線・P1 と同じ「クロージャ結合・相互参照なし」）。
- `download_provider.dart` → `download_state.dart`、`settings_provider.dart` → `settings_state.dart` の一方向のみ。循環なし。

---

## 4. API 変更（原則③・互換方針）

### 4.1 変更しないもの（テスト・呼出元互換）

- `downloadProvider` / `settingsProvider` / `darkModeProvider` / `wheelSendVerifiedProvider` の型・名前
- `DownloadNotifier` のコンストラクタ（`clock` / `progressThrottle` / `notificationService` / `exporter`）と全公開メソッド（テストが直接構築・検証）
- `SettingsNotifier` の全公開 setter・`reload`・`toggleDirectInput`（FakeSettingsNotifier の override 互換）
- `DownloadState` / `DownloadItemState` / `DownloadPhase` / `AppSettings` / `TransferConflictPolicy` の全公開面（フィールド・getter・copyWith・const コンストラクタ）
- SharedPreferences の 40 キー文字列と値型（テストがキー直書きで検証）
- **再エクスポート**（`export 'download_state.dart';` / `export 'settings_state.dart';`）を provider ファイルに置くことで、**呼出元・テストの import は原則無変更**（約 25 ファイルの churn ゼロ）

### 4.2 追加されるもの

- 新規コラボレータ 7 クラス（`DownloadBatchSession` / `DownloadQueueRunner` / `DownloadProgressTracker` / `DownloadCollisionResolver` / `DownloadNotificationSink` / `SettingsPersistence` / `SettingsPlatformApplier`）— 新規公開 API であり、既存コードは変更不要

### 4.3 内部実装の変更点（挙動不変の範囲内）

- `SettingsNotifier._loadSettings()` は shell 内に残し、中身を `persistence.load()` + `setCachedLanguage` + `applier.applyOrientation/applyRefreshRate` への委譲に置換（**await 順序と `ref.mounted` ガードを現行どおり維持**）
- `DownloadNotifier` の各フローはコラボレータへの委譲に置換。通知テキスト組み立て・l10n・バイト表示は `DownloadNotificationSink` へ移設し、shell はセマンティックイベントを渡すだけにする（**発火箇所・文言・`unawaited` タイミングは現行と同じ状態遷移で発生**させ、二重通知なし・M3 を回帰テストで検証）
- 未使用 setter（`setScrollbackLines` 等 4 種）は削除せず維持（互換コスト最小）

---

## 5. 呼出元・テスト更新リスト

### 5.1 変更不要になるもの（re-export 戦略により）

- lib 側: `file_browser_screen.dart` / `transfer_progress_sheet.dart` / `terminal_screen.dart`（2 箇所）+ 設定画面 12 ファイル / `main.dart` / `ansi_text_view.dart` / `file_transfer_provider.dart` / `image_transfer_provider.dart` / `terminal_display_provider.dart` / `l10n_lookup.dart`（コメントのみ）
- test 側: `download_provider_test.dart` / `settings_provider_test.dart` / `file_browser_download_flow_test.dart` / `fake_settings_notifier.dart` / `terminal_test_scaffold.dart` / `settings_search_provider_test.dart` / `connections_*` / `settings/*` テスト（import 面のみで見る限り無変更）

### 5.2 必須の手直し

1. **インポート追加**: 新規コラボレータを import するのは `download_provider.dart` / `settings_provider.dart` のみ（他ファイルは変更なし）
2. **呼出元・テストの変更は原則ゼロ**が目標。もしチーム判断で re-export を採用しない場合のみ、`DownloadPhase` / `DownloadState` / `DownloadItemState`（file_browser / terminal / progress_sheet / download テスト）と `AppSettings` / `TransferConflictPolicy`（設定画面・FakeSettingsNotifier・多数テスト）に import 追加が発生（≈25 ファイル）→ **re-export 採用を推奨**
3. **任意・推奨の新規テスト**（挙動検証の強化であり必須ではない）:
   - `test/providers/download_collision_resolver_test.dart`（採番・reserved・決定適用の純ロジック）
   - `test/providers/download_progress_tracker_test.dart`（間引き・EMA・速度ラベル）
   - `test/providers/download_notification_sink_test.dart`（テキスト組み立て・発火タイミング・throw 握りつぶし）
   - `test/providers/settings_persistence_test.dart`（キー互換・型 dispatch・マイグレーション起動）

### 5.3 実装時の検証ゲート（挙動不変の証明）

- 各分割ステップ後に `make analyze` + `make test` を実行し、**既存テストが 1 件も変更なしで green** であることを確認（=挙動不変の定義）
- 特に注意する回帰テスト群:
  - download: 衝突なし/衝突スキャン/overwrite/rename/skip/cancel 決定・キャンセル冪等・転送中 reset（HIGH#1）・切断→error・openSftp 失敗（MEDIUM#2）・単一 tmp の全経路（M3・二重通知なし）・クロスバッチ誤破棄なし（M1）
  - settings: 永続化キー互換（L24 他）・reload 後の再読込・fire-and-forget の pumpAndSettle 手法（TEST-SETTINGS-PROVIDER-001 維持）

---

## 6. 移行手順（各ステップ green 維持）

**Phase A — 状態モデルの抽出（機械的移動・リスク最小）**
1. `download_state.dart` / `settings_state.dart` を作成し、enum・値オブジェクトを移動
2. 元ファイルに `export 'download_state.dart';` / `export 'settings_state.dart';` を追加し元定義を削除
3. analyze + test（import 無変更で green を確認）

**Phase B — settings のコラボレータ抽出**
4. `settings_persistence.dart`（40 キー定数 + load/save を移動。キー文字列・型・`SettingsMigrationRunner.run` 呼び出し順はそのまま）
5. `settings_platform_applier.dart`（向き・リフレッシュレート適用のみ移動。try/catch と Android ガード維持）
6. `SettingsNotifier` は委譲に書き換え（setter は `state=copyWith` + `persistence.save` の 2 行構成に）
7. analyze + test

**Phase C — download のコラボレータ抽出（依存の少ない順）**
8. `download_batch_session.dart`（世代・token・**items**・**reservedNames**・destination・disposedBatches の所有を集約。現行の「1 回だけ dispose・世代一致時のみフィールドクリア」と `_updateItem` の世代ガードを維持）
9. `download_collision_resolver.dart`（事前スキャン・採番・決定適用の純関数化。reserved は状態を持たず引数で受ける）
10. `download_progress_tracker.dart`（EMA + 間引き + 速度ラベル）
11. `download_notification_sink.dart`（通知テキスト組み立て・l10n・バイト表示・fire-and-forget 発行の移設）
12. `download_run_queue.dart`（キュー実行。state/l10n/通知を shell のコールバックへ）
13. `DownloadNotifier` は構成ルート化（**フロー編成 + state 反映のみ**・items/通知は session/sink へ移設済み）
14. analyze + test（**既存テスト変更ゼロで green**）

**Phase D — 最終確認**
15. 全ファイル 500 行未満の確認（wc -l）
16. `make analyze` + `make test` フル実行 + 依存グラフの非循環確認（import の向きを目視）

---

## 7. リスク

| # | リスク | 影響 | 対策 |
|---|---|---|---|
| 1 | **世代/バッチ不変条件（M1/M2/M3/M4/HIGH#1）の分割時再発** | クロスバッチ誤破棄・転送中 reset の RangeError 再発（過去のバグ群） | 不変条件（世代ガード付き items 更新・reservedNames 予約）を `DownloadBatchSession` に物理的に集約し、既存回帰テスト（1703 行の網羅）がゲート。コールバック境界を最小に（進捗/アイテム更新/完了の 3 種のみ） |
| 2 | **fire-and-forget load の順序変更**（settings） | setCachedLanguage / 向き適用のタイミングずれ・`ref.mounted` ガード喪失 | `_loadSettings` の制御フロー（migration → state → cache → apply）を shell に残し委譲のみ・await 順序・ガードを現行と厳密一致させる |
| 3 | **通知のタイミング/テキストずれ**（download） | notifDownloadComplete の二重通知（M3 再発）や文言差 | 発火位置を現行コードと同じ文脈に限定（キュー完了/エラー/キャンセル/進捗 publish 時）し、**テキスト組み立ては `DownloadNotificationSink` に一元化**（文言差の混入防止）。単一バッチは `publishCompletion:false` 経路で最終確定を shell に集約（現行と同じ） |
| 4 | **re-export による循環 import** | コンパイルエラー | 状態ファイルは provider を import しない一方向を明文化（状態ファイルには `ref` を渡さない設計）。analyze で検出 |
| 5 | **行数見積のズレ**（shell が 500 行を超える可能性） | 設計原則⑤違反 | sink 分離を**初期構成**に含めたため shell 見積は ~260 行。実装で超過する場合のみ、state 反映部のヘルパー（publish 処理）を追加分離する（実装時に判断・初期構成は変更しない） |
| 6 | **テストの import 変更**（re-export を外した場合） | ≈25 ファイルの churn | re-export を標準採用し import 無変更を保証。テスト期待値は一切変えない（挙動不変の定義） |
| 7 | 分割によるファイル数増加（download 910→7 ファイル・settings 750→4 ファイル） | diff 増・レビュー負荷 | 機械的移動 Phase A と責務分離 Phase B/C を分けた段階的コミットでレビュー容易化。各ファイル冒頭に 1 文責務 doc comment |

---

## 8. 事実と推測の区別

### 事実（コード・rg・テストで検証済み）
- 行数: download 910 / settings 750。シンボル位置: `DownloadPhase`@24 / `DownloadItemState`@51 / `DownloadState`@129 / `DownloadNotifier`@216 / `downloadProvider`@908、`TransferConflictPolicy`@13 / `AppSettings`@30 / `SettingsNotifier`@277 / `settingsProvider`@733 / `darkModeProvider`@738 / `wheelSendVerifiedProvider`@750
- settings の永続化キーは `static const String _*Key` 40 個・SharedPreferences のみ（SecureStorage 不使用）。値はスカラー型のみで JSON なし
- `settingsProvider.notifier` 参照は lib 内実測 **14 ファイル**（settings 系 12 + terminal_screen + ansi_text_view）。`Future<void> setXxx` 定義は **40 個**（実測・うち 4 個は lib/test 全域で未使用）で、lib から参照されるのは実測 **33 種 + `toggleDirectInput`**
- `SettingsNotifier.build()` は fire-and-forget の `_loadSettings()`（テストに TEST-SETTINGS-PROVIDER-001 の注記あり・`ref.mounted` ガードあり）
- `setScrollbackLines` / `setEnableNotifications` / `setRequireBiometricAuth` / `setDirectInputEnabled` は lib/test 全域で未使用
- `FakeSettingsNotifier` が override するのは `build` + 6 setter（setKeepScreenOn / setScrollSendInput / setInvertScrollSendDirection / setAutoFitZoomOnScrollSend / setExperimentalHerdrCaretPositionEnabled / setZoomFactor）
- テストの直接構築: `DownloadNotifier(clock:/notificationService:/exporter:)`（download_provider_test / file_browser_download_flow_test）
- download の利用元は screens 3 ファイル + コメント 1 ファイルのみ・lib/widgets に download 参照なし
- 再利用可能なサービス層アセットの存在（§1.5 一覧）

### 推測・判断（設計上の選択）
- 各ファイルの推定行数（§3）は現行実装の責務配分からの見積もりであり、実装後に変動しうる
- 「re-export による呼出元 import 無変更」が最も低リスクという判断（原則③で API 変更は許容されるが、挙動不変・churn 最小の両立を優先）
- `DownloadBatchSession` への不変条件集約が、過去バグ（M1/M2/M3/M4/HIGH#1）の再発防止に有効という判断
- 未使用 setter の維持が「削除より互換コストが低い」という判断（削除は今後の別タスクで可）
- 状態モデルを `providers/` 直下に置く配置は SshState の慣習に倣った判断（`lib/services/download/` への移動も選択肢だが、services から参照されないため provider 層が自然）
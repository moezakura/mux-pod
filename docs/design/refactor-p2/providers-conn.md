# 責務ベース再設計 — providers 3 ファイル（connection / active_session / ssh）v2

- 対象: `lib/providers/connection_provider.dart`（HEAD 638行）, `lib/providers/active_session_provider.dart`（HEAD 563行）, `lib/providers/ssh_provider.dart`（HEAD 555行）
- 出発点: HEAD（f474d23）の元ファイル。working tree の既存構造は参考であり拘束されない。
- 方針: 設計のみ。コード変更なし。公開 API は変更可（呼出元・テストの参照更新を含める）だが、本設計では **型名・メソッド名・provider 名・挙動・呼出元 import をすべて不変** とする（挙動不変・テスト期待値不変）。
- 本改訂（v2）: design-critic の critique.md §4（4.1〜4.6）とリーダー方針（P2 共通: compat re-export 採用・呼出元 import 変更ゼロ）に対応。

---

## 1. 現状責務分析（実測・HEAD）

### 1.1 connection_provider.dart（638行）— 少なくとも3責務＋UI状態3種＋派生2種の混在

| クラス | 行範囲 | 実測行数 | 現状の責務 | 外部依存（実測 import） |
|---|---|---|---|---|
| `Connection` | 15-156 | 142 | 接続設定モデル（copyWith / toJson / fromJson / schema エイリアス） | `MultiplexerConfig`, `BackendType`, `ConnectionStorageSchema` |
| `CorruptedConnection` | 157-174 | 18 | 破損レコード情報モデル | なし |
| `ConnectionsState` | 175-213 | 39 | 接続一覧状態（connections / isLoading / error / corruptedRecords / warning） | なし |
| `ConnectionsNotifier` | 214-521 | 308 | **①ロード（SecureStorage + SharedPreferences 移行 + ConnectionMigration + 破損判定 + 警告組み立て）②保存 ③CRUD（add/remove/update/updateLastConnected）④クエリ（getById / findByDeepLinkIdOrName）⑤reload** | `SecureStorageService`, `SharedPreferences`, `ConnectionMigration`, `lookupL10n` |
| `SelectedConnectionIdNotifier` | 522-531 | 10 | 選択中接続ID（UI状態） | なし |
| `ConnectionSearchNotifier` | 532-551 | 20 | 検索クエリ（UI状態） | なし |
| `ConnectionSortOption` / `ConnectionSortNotifier` | 552-561 | 10 | ソート種別 enum + UI状態 | なし |
| 残り（provider 定義 + 派生） | 562-638 | 77 | 6 provider 定義 + `filteredConnectionsProvider`（検索・ソート合成）+ `selectedConnectionProvider` | riverpod |

- **責務境界**: モデル（142+18）・状態（39）・ストレージ/CRUD オーケストレーション（308）・UI状態（40）・派生セレクタ（77）が1ファイルに同居。
- Notifier が SecureStorage / SharedPreferences / Migration という3種の永続化経路を直接知っている（= 永続化責務の肥大）。

### 1.2 active_session_provider.dart（563行）— モデル ＋ 状態 ＋ 巨大 notifier

| クラス | 行範囲 | 実測行数 | 現状の責務 | 外部依存（実測 import） |
|---|---|---|---|---|
| `ActiveSession` | 14-168 | 155 | セッションモデル（copyWith / toJson / fromJson / `key` getter） | `MultiplexerBackendKind`, `MultiplexerSession`（domain） |
| `ActiveSessionsState` | 169-214 | 46 | 一覧状態（sessions / currentSessionKey / currentSession / getSessionsForConnection） | なし |
| `ActiveSessionsNotifier` | 215-563 | 349 | ロード/保存（_saveFuture 直列キュー）＋**12 メソッド**（addOrUpdateSession / updateLastPane / updateWindowCount / touchSession / updateSessionsForConnection / updateSessionsFromDomain / setCurrentSession / clearCurrentSession / closeSession / removeSession / removeSessionsForConnection / clear） | `SharedPreferences`, `TmuxSession`（`updateSessionsForConnection` のみ） |

- notifier 内で特に大きいのは `updateSessionsFromDomain`（~90行）: 既存保持マップ構築・sessionId 優先キー化・legacy エントリ（sessionId null）の adopting 判定（同名ラベル唯一のみ）・重複継承防止。**「差分マージ＋履歴引継ぎ」という独立した1責務**が notifier に埋まっている。
- 保存直列キュー（_saveFuture チェーン）も独立責務（永続化）。

### 1.3 ssh_provider.dart（555行）— SshState ＋ 単一 notifier に4〜5責務

| クラス | 行範囲 | 実測行数 | 現状の責務 | 外部依存（実測 import） |
|---|---|---|---|---|
| `SshState` | 13-75 | 63 | 接続状態モデル（connectionState / error / sessionTitle / 再接続系 / ネットワーク系 / isWaitingForNetwork 等の導出getter） | `SshConnectionState`（services/ssh/ssh_connection_state.dart） |
| `SshNotifier` | 76-555 | 480 | **①接続オーケストレーション**（connect / connectWithoutShell / disconnect / client 保有 / checkConnection / write / resize / updateSessionTitle）**②再接続ポリシー**（reconnect / _doReconnect / reconnectNow / resetReconnect / 指数バックオフ / Timer / single-flight）**③ネットワーク監視**（statusStream 購読 / isPaused / 復帰時即時再接続）**④切断検知**（connectionStateStream 購読 / onDisconnectDetected / onReconnectSuccess）**⑤Foreground サービス・最終接続日時更新** | `networkMonitorProvider`, `SshClient`, `SshForegroundTaskService`, `connectionsProvider`（updateLastConnected）, `lookupL10n` |

**公開 API の利用実測（grep 結果・v2 で修正）**:
- `client` / `connectWithoutShell` / `reconnect` / `reconnectNow` / `checkConnection` / `disconnect` → terminal_screen が利用（`client` getter は file_browser / file_transfer / image_transfer / download / markdown_preview 各 provider と sftp_markdown_image widget も利用）
- `onReconnectSuccess`: terminal_screen **L1019 でハンドラ代入**（`_onReconnectSuccess`、実体 L1200）、**L3276 で null クリア**。テストは代入確認（isNotNull: lifecycle_test L203 / herdr_test L1475）、クリア確認（isNull: L208 / L1481）、**直接実行 `notifier.onReconnectSuccess?.call()`**（herdr_test L1302 / L1361 / L2374）
- `onDisconnectDetected`: terminal_screen は **L3277 で null 代入のみ（ハンドラ設定は存在しない = 発火は常に無効）**。テスト2件は isNull 検証（lifecycle_test L209 / herdr_test L1482）
- `_lastConnection` / `_lastOptions`: 公開 getter `lastConnection` / `lastOptions`（L184/L187）は外部未使用だが、**実体は再接続の必須内部状態** — `_doReconnect` のガード（L354: `if (_lastConnection == null || _lastOptions == null) return false;`、L416 同様）と再接続時の接続情報再使用（L443-446: `host/port/username` + `options: _lastOptions!`）に直接使用。**デッドではない**（v1 の「デッド公開 API」分類は誤り・削除対象と誤読されるため修正）
- `updateSessionTitle` / `write` / `resize` / `resetReconnect`: lib・test とも呼出元ゼロ（維持対象）

**テスト二重の実測（v2 で修正済み）**:
- `FakeSshNotifier extends SshNotifier`: **@override 7 件**（client フィールド L10-11 / build L20 / connect L27 / connectWithoutShell L44 / disconnect L78 / reconnect L85 / reconnectNow L92）。**build() を @override して購読を一切張らない**（fake_ssh_notifier.dart L20-25）
- `_FakeConnectionsNotifier extends ConnectionsNotifier`: **3 件**（build / getById / updateLastConnected）
- `_FakeActiveSessionsNotifier extends ActiveSessionsNotifier`: **2 件**（build / updateWindowCount）

---

## 2. 提案構成

**全体方針**:
- モデル / 状態 / ストレージ / notifier / UI状態 / 派生セレクタをファイル分離。notifier は「合成 + 公開面」に絞る（P1 の facade 思想と同型）。
- **compat layer（リーダー方針・P2 共通）**: 既存の公開エントリポイント `connection_provider.dart` / `active_session_provider.dart` は**削除しない**。ロジックを持たない thin re-export として残し、doc comment に実装先を明記。→ **呼出元・テストの import 変更ゼロ**（§5 の import 更新リストは不要となるため、§5 は互換維持の検証要件に置き換え）。`ssh_provider.dart` は facade として存続。※「1ファイル=1責務」の例外として「既存公開面の安定供給」という責務を compat layer が担う（チーム合意事項）。
- provider 名・型名・メソッド名はすべて維持。mixin / 基底 / part は使わない。新規内部クラスは「合成された協調オブジェクト」として notifier が生成・保有（テスト fake は notifier の public メソッドを @override するため、内部クラスは internal でよい）。
- 接続状態購読・ネットワーク購読などの**ライフサイクル副作用は必ず notifier.build() 起点**に残す（fake が build() を @override して副作用をスキップする現行テスト戦略を維持するため。事実: FakeSshNotifier の build() は購読なし）。

### 2.1 connection_provider.dart → 実装6ファイル + compat 1ファイル（合計 ~780行）

| ファイル | 責務（1文） | 公開面（名前不変） | 推定行数 |
|---|---|---|---|
| `lib/providers/connection.dart` | **接続設定モデル**: Connection / CorruptedConnection の構造・コピー・JSON 双方向変換、schema バージョンエイリアス。 | `Connection`, `CorruptedConnection`（既存 public、移動） | ~175 |
| `lib/providers/connections_state.dart` | **接続一覧の状態**: connections / isLoading / error / corruptedRecords / warning と copyWith。 | `ConnectionsState`（既存 public、移動） | ~45 |
| `lib/providers/connection_storage.dart` | **接続レコードの永続化**: SecureStorage 読み書き、SharedPreferences からの引継ぎコピー、ConnectionMigration 実行、破損レコード収集・警告文言の組み立て。JSON 変換・永続化の詳細だけを知る。 | `ConnectionStorage`（新規 internal。`load()` / `save(List<Connection>)`。SecureStorageService は従来どおり直接生成、テストの setTestValues 互換） | ~160 |
| `lib/providers/connections_notifier.dart` | **接続一覧の管理（CRUD + ロード + クエリ）**: ConnectionStorage を合成し、add / remove / update / updateLastConnected / reload / getById / findByDeepLinkIdOrName を提供。永続化の詳細・migration を知らない。 | `ConnectionsNotifier`（既存 public、**final 化禁止** — _FakeConnectionsNotifier が build/getById/updateLastConnected を @override）+ `connectionsProvider` | ~200 |
| `lib/providers/connection_ui_state.dart` | **接続一覧 UI 状態**: 選択中 ID・検索クエリ・ソート種別の3 notifier。 | `SelectedConnectionIdNotifier` / `ConnectionSearchNotifier` / `ConnectionSortOption` / `ConnectionSortNotifier` + `selectedConnectionIdProvider` / `connectionSearchProvider` / `connectionSortProvider`（既存 public、移動） | ~105 |
| `lib/providers/connection_selectors.dart` | **接続一覧の派生ビュー**: 検索・ソート適用済みリストと選択中接続の導出。 | `filteredConnectionsProvider` / `selectedConnectionProvider`（既存 public、移動） | ~75 |
| `lib/providers/connection_provider.dart`（存続） | **既存公開面の安定供給（compat layer）**: 上記6ファイルの公開シンボルを re-export するだけ。**ロジック禁止・doc comment に実装先を明記**。 | 既存と同一の公開面（呼出元・テストの import 変更ゼロ） | ~10 |

- l10n は `ConnectionStorage.load()` の引数（`lookupL10n()` の結果）で受け渡し（現行の「ロード時点での解決」L216 付近を維持）。

### 2.2 active_session_provider.dart → 実装5ファイル + compat 1ファイル（合計 ~600行）

| ファイル | 責務（1文） | 公開面（名前不変） | 推定行数 |
|---|---|---|---|
| `lib/providers/active_session.dart` | **アクティブセッションのモデル**: 構造・copyWith・JSON 双方向変換・一意キー導出。 | `ActiveSession`（既存 public、移動） | ~165 |
| `lib/providers/active_sessions_state.dart` | **アクティブセッション一覧の状態**: sessions / currentSessionKey と導出ヘルパー（currentSession / getSessionsForConnection）。 | `ActiveSessionsState`（既存 public、移動） | ~50 |
| `lib/providers/active_sessions_storage.dart` | **セッションリストの永続化**: SharedPreferences への load/save。**保存直列キュー（_saveFuture チェーン）の所有者。** | `ActiveSessionsStorage`（新規 internal。`load()` / `save(List<ActiveSession>)`） | ~55 |
| `lib/providers/active_sessions_merger.dart` | **接続単位のセッション差分マージと履歴引継ぎ**: 既存保持マップ構築、sessionId 優先キー化、legacy（sessionId null）エントリの adopting 判定（同名ラベル唯一のみ）・重複継承防止。**純関数的**（引数に既存一覧・新一覧・接続情報・`now` を受け取り新一覧を返す）。 | `ActiveSessionsMerger`（新規 internal。`merge(...)` 1メソッド） | ~110 |
| `lib/providers/active_sessions_notifier.dart` | **アクティブセッション一覧の管理**: storage / merger を合成し、既存 **12 メソッド** の公開面を維持。`updateSessionsForConnection`（TmuxSession → domain 変換）はこのファイルに残す。 | `ActiveSessionsNotifier`（既存 public、**final 化禁止** — _FakeActiveSessionsNotifier が build/updateWindowCount を @override）+ `activeSessionsProvider` | ~210 |
| `lib/providers/active_session_provider.dart`（存続） | **既存公開面の安定供給（compat layer）**: 上記5ファイルの公開シンボルを re-export するだけ。**ロジック禁止・doc comment に実装先を明記**。 | 既存と同一の公開面（import 変更ゼロ） | ~10 |

- `updateSessionsFromDomain` のマージ本体（~90行）を merger へ写経移行。**挙動不変は active_session_provider_test の legacy/ID キー系 10 テスト群がカバー**（事実: 同名ラベル分離・移行・重複継承防止のテストが既存）。

### 2.3 ssh_provider.dart → 実装4ファイル（facade 存続・合計 ~625行）

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `lib/providers/ssh_state.dart` | **SSH 接続状態のモデル**: 全フィールド + 導出 getter。 | `SshState`（既存 public、移動） | ~70 |
| `lib/providers/ssh_connection_orchestrator.dart` | **SSH 接続のオーケストレーション**: SshClient の生成・破棄・保有、connect / connectWithoutShell / disconnect、接続状態ストリーム購読と切断検知、write / resize / checkConnection。**`_lastConnection` / `_lastOptions`（再接続の必須内部状態）の保有者。** | `SshConnectionOrchestrator`（新規 internal。**公開フィールド: `onDisconnectDetected` / `onReconnectSuccess`（ハンドラの単一所有者）**。公開メソッド: `connect` / `connectWithoutShell` / `disconnect` / `reconnectConnection` / `client` getter / `checkConnection` / `write` / `resize` / 購読 start/stop。**注入クロージャ: `getState` / `updateState` / `requestReconnect` / `onLastConnected` / `startForeground` / `stopForeground`**（下記配線表）） | ~215 |
| `lib/providers/ssh_reconnect_policy.dart` | **再接続ポリシー**: 指数バックオフ（1s/1.5x/最大60s・無制限リトライ）、Timer スケジュール、single-flight（Codex B3）、ネットワーク pause/resume（オフラインで一時停止・復帰で即時再開）、reconnectNow / resetReconnect。**実際の再接続実行は注入クロージャ（orchestrator.reconnectConnection）に依頼。** | `SshReconnectPolicy`（新規 internal。**注入: `reconnectAction` / `getState` / `updateState`**。公開: `startNetworkMonitoring(Stream<NetworkStatus>)` / `stop` / `reconnect` / `reconnectNow` / `reset`） | ~190 |
| `lib/providers/ssh_provider.dart`（存続・再構成） | **SSH セッションの公開面（facade 合成）**: SshState を公開し、orchestrator / policy を合成。build() で network stream 購読の開始と onDispose クリーンアップを統括。SSH の全公開 API を orchestrator / policy へ委譲。 | `SshNotifier`（既存 public、**final 化禁止** — FakeSshNotifier が @override 7 件）+ `sshProvider` | ~150 |

**配線（v2 確定・critique 4.1 / 4.2 対応）**:

| 注入先 | 注入されるクロージャ / フィールド | 実体（notifier が配線） | 責務上の意味 |
|---|---|---|---|
| `SshConnectionOrchestrator` | `updateState: void Function(SshState Function(SshState))` | `(transform) { state = transform(state); }` | **state 書き込み経路（critique 4.1）**。切断検知 L270 付近・再接続成功時の state 更新はこれ経由 |
| `SshConnectionOrchestrator` | `getState: SshState Function()` | `() => state` | state 読み取り経路（切断検知後の `state.isReconnecting` 判定 L337 等） |
| `SshConnectionOrchestrator` | `requestReconnect: Future<bool> Function()` | `() => policy.reconnect()` | 切断検知 → 再接続依頼（現行 L340 `reconnect()` 呼びの unawaited を維持） |
| `SshConnectionOrchestrator` | `onLastConnected: void Function(String connectionId)` | `(id) { ref.read(connectionsProvider.notifier).updateLastConnected(id); }` | 最終接続日時更新（現行 L291 の **unawaited** 呼び出しを維持） |
| `SshConnectionOrchestrator` | `startForeground` / `stopForeground` | `_foregroundService.startService(...)` / `.stopService()` | Foreground サービス（現行 connect 成功時・disconnect 時） |
| `SshConnectionOrchestrator` | **公開フィールド** `onDisconnectDetected` / `onReconnectSuccess` | — | ハンドラの単一所有者（**発火は orchestrator 内**: 切断検知時・再接続成功時） |
| `SshReconnectPolicy` | `reconnectAction: Future<bool> Function()` | `() => orchestrator.reconnectConnection()` | 実際の再接続実行（現行 `_doReconnect` 相当） |
| `SshReconnectPolicy` | `getState` / `updateState` | 同上 | policy 側の state 読み書き（pause 判定・attempt 管理） |
| `SshReconnectPolicy` | `startNetworkMonitoring(stream)` | notifier.build() が `ref.read(networkMonitorProvider).statusStream` を渡す | ネットワーク監視（現行 `_startNetworkMonitoring` L111-116 と同位置・fake は build() @override でスキップ） |
| `SshNotifier`（getter/setter） | `onDisconnectDetected` / `onReconnectSuccess` | `→ _orchestrator.xxx` へ転送 | **critique 4.2 対応**（下記） |

**callback 配線の具体形（critique 4.2 対応・v2 確定）**:
- orchestrator が `onDisconnectDetected` / `onReconnectSuccess` を**公開フィールドとして保有**（発火箇所 = 切断検知ハンドラ / 再接続成功時は orchestrator 内のため）。
- notifier は**public フィールドを getter/setter に変更**し、setter が orchestrator の対応フィールドへ代入、getter は orchestrator の現在値を返す（読み透過）:
  ```dart
  void Function()? get onReconnectSuccess => _orchestrator.onReconnectSuccess;
  set onReconnectSuccess(void Function()? v) => _orchestrator.onReconnectSuccess = v;
  ```
- これにより以下が**すべて現行どおり動作**（実測）:
  - terminal_screen L1019 `sshNotifier.onReconnectSuccess = _onReconnectSuccess;`（setter 経由で orchestrator へ転送）
  - L3276-3277 の null クリア（setter 経由。**購読停止と同時でない**点も現行仕様として維持）
  - テストの `expect(notifier.onReconnectSuccess, isNotNull/isNull)`（getter 読み透過）
  - テストの `notifier.onReconnectSuccess?.call()`（herdr_test L1302 / L1361 / L2374 — getter が orchestrator の現在値を返すため直接実行可能）
- onDisconnectDetected は現行「常時 null（ハンドラ設定なし）」のため発火は無効だが、**発火経路は現行どおり写経する**（挙動不変。将来のハンドラ設定に備えた配線）。

**保有物の明記（critique 4.3 対応）**:
- `_lastConnection` / `_lastOptions` は **orchestrator が保有**（connectWithoutShell L222-223 で設定・reconnectConnection L354/L416 のガード・L443-446 の再使用はすべて orchestrator 内）。
- `lastConnection` / `lastOptions` getter は**notifier に残して orchestrator へ委譲**（外部互換のため維持。v1 の「デッド公開 API」分類は削除）。

**責務境界**: **policy = 「いつ・どれだけ待って試すか」、orchestrator = 「どう繋ぐか・切るか・何を覚えておくか」、notifier = 「状態公開と配線」**。coordinator 同士はクロージャ注入のみで結合（orchestrator → requestReconnect → policy → reconnectAction → orchestrator の一方向ループは**クロージャ経由のみ**でクラス参照なし → 非循環）。

---

## 3. 依存グラフ（提案後・非循環）

```
lib/providers/（プロバイダ層）
┌────────────────────────────────────────────────────────────────┐
│ connection.dart ◀── connections_state.dart ◀── connections_notifier.dart
│        ▲                ▲                        │
│        │                │                        ▼
│        └── connection_storage.dart ◀── connections_notifier.dart ──▶ connection_selectors.dart
│                                           ▲              ▲
│              connection_ui_state.dart ────┘              │
│                                                          │
│  [compat] connection_provider.dart ──re-export──▶ 上記6ファイル（公開面の安定供給・ロジックなし）
│   ▲ 呼出元は従来パスを import（変更ゼロ）
│   │   main.dart / connections_screen / connection_form_screen / notification_panes_provider /
│   │   ssh_provider(→ connections_notifier を直接 import しても可) / テスト群
│
│ active_session.dart ◀── active_sessions_state.dart ◀── active_sessions_notifier.dart
│        ▲                    ▲                     ▲
│        └─ active_sessions_storage.dart ───────────┘
│        └─ active_sessions_merger.dart ────────────┘
│  [compat] active_session_provider.dart ──re-export──▶ 上記5ファイル（ロジックなし）
│   ▲ 呼出元は従来パスを import（変更ゼロ）
│   │   session_history_provider / home_screen / dashboard_screen / terminal_screen /
│   │   connections_screen / notification_panes_screen / テスト群
│
│ ssh_state.dart ◀── ssh_provider.dart（facade・存続）
│ ssh_connection_orchestrator.dart ◀── ssh_provider.dart
│ ssh_reconnect_policy.dart ◀── ssh_provider.dart
│  ssh_provider.dart ◀── terminal_screen / file_browser / file_transfer / image_transfer /
│                         download / markdown_preview 各 provider / sftp_markdown_image
│                         （ssh_provider.dart 存続のため import 変更ゼロ）
└────────────────────────────────────────────────────────────────┘

協調オブジェクト間のクロージャ配線（クラス参照なし・非循環）:
  notifier ──getState/updateState/requestReconnect/onLastConnected/startForeground/stopForeground──▶ orchestrator
  notifier ──reconnectAction/getState/updateState/networkStream──▶ policy
  orchestrator ──requestReconnect（クロージャ）──▶ policy.reconnect
  policy ──reconnectAction（クロージャ）──▶ orchestrator.reconnectConnection
  notifier.onDisconnectDetected/onReconnectSuccess ──getter/setter──▶ orchestrator のフィールド

外部（サービス層・不変）:
  connection_storage.dart ──▶ SecureStorageService / SharedPreferences / ConnectionMigration / l10n_lookup
  ssh_provider.dart ──▶ networkMonitorProvider / SshForegroundTaskService / lookupL10n
  ssh_connection_orchestrator.dart ──▶ SshClient（services/ssh）
  active_sessions_storage.dart ──▶ SharedPreferences
  active_sessions_notifier.dart ──▶ TmuxSession.toDomain（services/tmux）
```

- 循環なし。既存の循環回避コメント（Connection の schema エイリアス）はモデルが services/connection/connection_storage_schema.dart を import するだけで解決（services 側は providers を import しない構造を維持）。

---

## 4. API 変更

**呼出元・テストの import は一切変更しない（compat layer 採用・リーダー方針）**。public API（型・メソッド・provider 名・シグネチャ）もすべて不変。

| 種別 | 変更内容 |
|---|---|
| `connection_provider.dart` | ロジックを実装6ファイルへ移動し、**thin re-export（compat layer）化**。doc comment に実装先を明記。公開面は現行と同一 |
| `active_session_provider.dart` | 同様に実装5ファイル + **thin re-export（compat layer）化** |
| `ssh_provider.dart` | **facade として存続**（再構成）。`ssh_state.dart` / `ssh_connection_orchestrator.dart` / `ssh_reconnect_policy.dart` は ssh_provider.dart からのみ import（internal） |
| `SshNotifier.onDisconnectDetected` / `onReconnectSuccess` | **public フィールド → getter/setter 化**（setter が orchestrator へ転送・getter は読み透過）。代入・読取・直接 `call()` の全互換を維持 |
| `SshNotifier.lastConnection` / `lastOptions` | getter は維持（orchestrator へ委譲）。実体 `_lastConnection` / `_lastOptions` は orchestrator へ移設 |
| 新規 public | `ConnectionStorage` / `ActiveSessionsStorage` / `ActiveSessionsMerger` / `SshConnectionOrchestrator` / `SshReconnectPolicy`（**internal 推奨**。テストが直接触らない方針。connection_provider_test の `_CorruptOnSecondReadStorage extends SecureStorageService` は SecureStorageService 継承のままなので無影響） |
| 不要になる公開 API | なし（`updateSessionTitle` / `write` / `resize` / `resetReconnect` は呼出元ゼロだが維持） |

**維持必須の継承前提（テスト fake・実測）**:
- `SshNotifier`: **@override 7 件の互換** — `client`（getter をフィールド override する形は Dart で合法・critique 4.7 確認）、`build`, `connect`, `connectWithoutShell`, `disconnect`, `reconnect`, `reconnectNow` が public で override 可能であること
- `ConnectionsNotifier`: `build`, `getById`, `updateLastConnected` が public で override 可能
- `ActiveSessionsNotifier`: `build`, `updateWindowCount` が public で override 可能
- → **3 notifier とも final 化しない・private メソッド化しない**。また FakeSshNotifier は build() @override で購読をスキップするため、購読開始・Timer 生成は notifier.build() 起点に残す（§2.3 配線表のとおり）

---

## 5. 呼出元・テストの互換維持要件（import 変更ゼロの検証リスト）

リーダー方針により **import 更新は発生しない**。代わりに、分割後も同一パスで成立し続けることを実装時に機械検証すべき要件を列挙する（v1 の import 更新リストは不要となったため削除）。

| # | 要件 | 実測箇所 | 維持方法 |
|---|---|---|---|
| 1 | 呼出元 import パス不変 | lib 12 ファイル（main / 7 画面 / 4 provider / 1 widget）+ test 17 ファイル + helper 2 | compat re-export（§2.1 / §2.2）で同一シンボルを同一パスから供給 |
| 2 | `onReconnectSuccess` のフィールド代入互換 | terminal_screen L1019（設定）/ L3276（クリア） | notifier getter/setter → orchestrator 転送（§2.3） |
| 3 | `onReconnectSuccess` / `onDisconnectDetected` の isNull/isNotNull 検証 | lifecycle_test L203/L208/L209 / herdr_test L1475/L1481/L1482 | getter 読み透過（orchestrator の現在値を返す） |
| 4 | `notifier.onReconnectSuccess?.call()` 直接実行 | herdr_test L1302/L1361/L2374 | 同上（orchestrator に転送済みハンドラが実行される） |
| 5 | FakeSshNotifier @override 7 件 | fake_ssh_notifier.dart | notifier の公開面・シグネチャ不変（§4） |
| 6 | _FakeConnectionsNotifier 3 件 / _FakeActiveSessionsNotifier 2 件 | terminal_test_scaffold.dart | 同上 |
| 7 | provider 名・状態参照（filtered / selected / search / sort / activeSessions / ssh） | connections_screen / home_screen / terminal_screen 等 | 全 provider 名不変（§2） |
| 8 | `_FakeConnectionsNotifier.build()` がストレージ非依存（const ConnectionsState 返却） | terminal_test_scaffold.dart L30-32 | build() 内で storage を触らない構造を維持（ロードは build() から明示呼び出しのまま） |

---

## 6. 移行手順

各ステップで `flutter analyze` / 対象テストをパスさせる（コンパイル単位が小さい順＝依存が少ない順に実行）。**compat layer は各対象の実装ファイル移動と同一ステップで置換**する（旧ファイルの中身を re-export に書き換えるだけなので、呼出元・テストの変更はゼロのまま常にコンパイル可能）。

1. **active_session 群**（依存が最少・他 provider を import しない）: `active_session.dart` → `active_sessions_state.dart` → `active_sessions_storage.dart` → `active_sessions_merger.dart`（`updateSessionsFromDomain` 本体を写経、引数で既存一覧・新一覧を受け取る純関数化）→ `active_sessions_notifier.dart`（storage/merger 合成 + `activeSessionsProvider`）→ **`active_session_provider.dart` を re-export 化**（doc comment で実装先明記）→ `flutter test test/providers/active_session_provider_test.dart` で挙動確認。
2. **connection 群**: `connection.dart` → `connections_state.dart` → `connection_storage.dart`（_loadConnections の SecureStorage/SharedPreferences/migration/破損判定/警告を移す）→ `connections_notifier.dart` → `connection_ui_state.dart` → `connection_selectors.dart` → **`connection_provider.dart` を re-export 化** → `flutter test test/providers/connection_provider_test.dart` + `notification_panes_provider_test.dart`。
3. **ssh 群**（依存先が整ってから最後・**制御フロー写経表に従う**）: `ssh_state.dart` → `ssh_connection_orchestrator.dart`（`_lastConnection`/`_lastOptions`・ハンドラ2フィールド・注入6種の生成）→ `ssh_reconnect_policy.dart` → `ssh_provider.dart` 再構成（facade・getter/setter 化）→ `flutter test test/screens/terminal/` + ファイル系 provider テスト + `flutter test test/helpers/` 関連。
4. 全体: `make analyze` → `make test`（テスト期待値は不変であることを確認。差分が出た場合は写経ミスとして即時修正）。

### 6.1 制御フロー写経表（ssh・critique 4.5 対応）

クロージャ結合3者（notifier / orchestrator / policy）への分散で制御フローが追跡困難になるリスクに対し、**HEAD の各フローを「誰が・何順で・同期的か非同期的か」まで1:1で写経する**ことを実装時の拘束とする:

| ID | フロー（HEAD 実測位置） | 写経要件（順序・同期性・await 有無） |
|---|---|---|
| F1 | connect 成功（L193-220） | connecting state → client 生成 → connect → **startShell** → connected state → **updateLastConnected は unawaited（L212）** → `await startForeground` |
| F2 | connect / connectWithoutShell 失敗（L216-251 / L296-331） | **3 catch 分岐（SshConnectionError / SshAuthenticationError / catch-all）それぞれ error state + `_client?.dispose()` + client = null**（await なし）。orchestrator 内の client フィールドに対して行う |
| F3 | 切断検知（L268-346） | **state 更新 → `onDisconnectDetected?.call()` → `state.isReconnecting` 判定 → `requestReconnect()`（unawaited）** の順を厳守 |
| F4 | ネットワーク変化（L140-164） | 復帰時: **isPaused && isReconnecting → isPaused=false / attempt=0 / timer cancel → reconnectConnection() を同期・unawaited で直呼び（現行 L151-153 `_doReconnect()`）**。オフライン時: isReconnecting → isPaused=true + timer cancel。**非同期化・await 追加禁止**（single-flight が重複実行を防ぐ前提） |
| F5 | reconnect()（L348-389） | ガード（_lastConnection/_lastOptions null → false）→ オフライン pause → max attempts（0=無制限）→ delay = clamp(1000 × 1.5^attempt, 1000, 60000) → state 更新（attempt+1 / nextRetryAt）→ Timer 発火 → **completer の future を返す（呼出元が await）** |
| F6 | reconnectConnection（_doReconnect 相当 L398-466） | **single-flight（_reconnectInFlight / Completer 共有）→ オフライン中断 → subscription cancel → `await` 旧 client dispose（Codex B3 コメント維持）→ 新 client + subscription → connect → 成功 state + `onReconnectSuccess?.call()` → true / 失敗: error state + `Future.microtask(() => reconnect())` 再スケジュール → false** |
| F7 | disconnect（L493-530） | timer cancel → subscription cancel → `await stopForeground` → `await client.disconnect()` → client = null → state リセット（sessionTitle / isReconnecting / isPaused / attempt / nextRetryAt） |

- F4 の「policy → orchestrator への**同期**呼び出し」だけはクロージャ結合で唯一の同期経路であり、§2.3 配線表の `reconnectAction` がこれに該当する。**戻り値の Future を await しない**（現行どおり）。

---

## 7. リスク

| # | リスク | 対策（設計で担保） |
|---|---|---|
| 1 | **fake の extends 前提を壊す変更**（final 化・メソッドの private 化・シグネチャ変更） | §4 の「維持必須の継承前提」（FakeSshNotifier 7 / _FakeConnectionsNotifier 3 / _FakeActiveSessionsNotifier 2）を実装時のチェックリスト化。@override 一覧を機械的に照合 |
| 2 | **build() 起点の副作用を移動してしまう**（ネットワーク購読・onDispose） | policy/orchestrator への購読開始・停止は notifier.build() と ref.onDispose に残す（FakeSshNotifier は build() @override で購読を張らない現行戦略の維持） |
| 3 | **updateSessionsFromDomain の写経ミス**（legacy adopting・重複継承防止の条件分岐） | 既存テスト群（ID マッチ・同名分離・legacy 移行・複数 legacy 非移行）が網羅。テスト期待値を変えないことをゲートに |
| 4 | **storage 分離で l10n の解決タイミングが変わる** | load() に l10n を引数で渡し、現行の「ロード時点の lookupL10n()」を維持 |
| 5 | **inventory コメント（// inventory: PROV-ACTIVE-xxx / LEGACY-xxxx）の所在移動** | tool/herdr-inventory/*.json が 37 件の PROV-ACTIVE id を参照（事実）。コメントは新ファイルへそのまま移設し、id も文言も変えない。compat layer には inventory マーカーを置かない（移動元から必ず引き剥がす） |
| 6 | **Socket/Stream 購読の二重開始**（connectWithoutShell 内購読と build 監視の分離） | orchestrator への購読開始位置を現行コードと同一（connectWithoutShell / disconnect / 再接続時のみ）にする写経ルール（§6.1 F1/F6/F7） |
| 7 | **接続状態の single-flight 変更**（Codex B3） | policy に移す際、_reconnectInFlight / _reconnectInFlightResult のロジックを §6.1 F6 どおりそのまま移設 |
| 8 | **クロージャ結合の複雑化**（critique 4.5: 3者に state 書き込み・購読・timer が分散し、コールバック地獄化） | ①結合数を固定（orchestrator 注入6 + ハンドラ2フィールド / policy 注入3 / notifier 配線）。②「**発火は所有者（orchestrator）内・設定は notifier 経由**」の一方向ルール。③§6.1 写経表を実装時のチェックリスト化。④F4 の同期直呼びは唯一の同期経路と明記。⑤P1 と異なり相互依存の深い状態機械であるため、**写経表レビューを実装レビューの必須項目**とする |
| 9 | **compat layer の stale 化**（再export が実装先と乖離） | doc comment に実装先を明記。実装ファイルの公開シンボル変更時は compat layer も同時更新（analyze では未使用 export は検出されないため、レビューで確認） |
| 10 | **callback クリアと購読停止のタイミング差**（L3276-3277 は deactivate 時・購読停止と非同期） | 現行仕様として維持（クリアは setter 経由で orchestrator のハンドラのみ null 化。購読は onDispose で停止） |

---

## 8. 事実と推測の区別

### 事実（コード・grep で確認済み・v2 で追加/修正）
- 3 ファイルの行数とクラス内訳（§1 の表）。全クラス・メソッド名・provider 名の実測。
- import 一覧と外部依存（services/ssh, services/connection, services/keychain, services/backend, services/network, services/background, l10n）。
- 呼出元一覧（§5）: main.dart / 7 画面 / 9 provider / 1 widget / テスト 20 ファイル以上。
- fake 注入: FakeSshNotifier **7 @override**（client フィールド / build / connect / connectWithoutShell / disconnect / reconnect / reconnectNow）、_FakeConnectionsNotifier **3**、_FakeActiveSessionsNotifier **2**。すべて build() を @override（副作用スキップ）。
- `SecureStorageService.setTestValues` / `SharedPreferences.setMockInitialValues` がテストで使用され、notifier が直接 SecureStorageService() を生成する構造。
- **onReconnectSuccess**: terminal_screen L1019 代入・L1200 がハンドラ実体・L3276 クリア。テスト: isNotNull（lifecycle L203 / herdr L1475）、isNull（L208 / L1481）、直接 call()（herdr L1302 / L1361 / L2374）。
- **onDisconnectDetected**: terminal_screen は L3277 の null 代入のみ（ハンドラ設定なし・発火は常に無効）。テスト isNull 2 件（lifecycle L209 / herdr L1482）。
- **_lastConnection / _lastOptions**: 再接続の必須内部状態。ガード L354 / L416、再利用 L443-446。公開 getter（L184/L187）は外部未使用。
- **ネットワーク復帰 → 即時再接続**: L145-158。`isPaused && isReconnecting` 時に timer cancel 後、**`_doReconnect()` を同期・unawaited で直呼び**（L151-153）。
- ActiveSessionsNotifier の公開メソッドは **12**（addOrUpdateSession / updateLastPane / updateWindowCount / touchSession / updateSessionsForConnection / updateSessionsFromDomain / setCurrentSession / clearCurrentSession / closeSession / removeSession / removeSessionsForConnection / clear — L284-552）。
- `updateSessionTitle` / `write` / `resize` / `resetReconnect` に lib・test とも呼出元なし。
- selectedConnectionIdProvider / selectedConnectionProvider は lib の画面から未使用（テストのみ参照）。
- tool/herdr-inventory が PROV-ACTIVE id を 37 件参照。
- ConnectionStorageSchema へのエイリアスと「provider 層から import すると循環依存になる」コメントが Connection 内に存在。

### 推測・設計判断（要確認事項）
- 推定行数（§2）は現状行数からの概算。実装時に上下する。
- notifier の orchestrator / policy 生成タイミング（`late final` フィールドとし、初回アクセス時に生成。build() は購読開始のみ行う設計）は Riverpod のライフサイクルに依存する設計判断。fake は build() @override で購読を張らないため、**ハンドラ getter/setter の転送先（orchestrator）は fake でも生成される**想定（生成時に `ref` を触らないよう、クロージャは ref 参照を遅延評価にする）— これは設計提案であり、テストで確認する（推測）。
- `updateState` クロージャの実体（`state = transform(state)`）が notifier の state setter 経由で riverpod に通知されることは自明だが、orchestrator 内で**連続して複数回 state を書く**現行箇所（例: 切断検知後の write → read の順序依存）は、写経表の順序どおり1回の updateState に1遷移を対応させる（推測・要実装確認）。
- inventory ツールが「ファイル移動」をどう追跡するかは未調査（tool/herdr-inventory の実装確認が必要）。コメント移設方針はリスクとして §7-5 に記載。

---

## 9. まとめ（1ファイル=1責務 対応表）

| 現ファイル | 責務数 | 提案ファイル数（実装+compat） | 各ファイル最大行数 |
|---|---|---|---|
| connection_provider.dart（638行・6責務） | モデル / 状態 / 永続化 / CRUD / UI状態 / 派生ビュー | 6 + compat（~780行） | ~200（notifier） |
| active_session_provider.dart（563行・3責務） | モデル / 状態 / 管理（マージ+永続化内包） | 5 + compat（~600行） | ~210（notifier） |
| ssh_provider.dart（555行・5責務） | 状態 / オーケストレーション / 再接続 / 公開面 | 4（facade 存続・~625行） | ~215（orchestrator） |

全 15 ファイルが 500 行未満（compat layer は ~10 行）。公開 API 不変・呼出元 import 変更ゼロ・依存非循環・テスト期待値不変を満たす。
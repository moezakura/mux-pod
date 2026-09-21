# 責務ベース再設計 — SSH 層（ssh_client / persistent_shell / herdr_caret_helper_manager）v2

- 対象: lib/services/ssh/ssh_client.dart (1298行), lib/services/ssh/persistent_shell.dart (500行), lib/services/herdr/caret/herdr_caret_helper_manager.dart (634行)
- 出発点: `git show HEAD:<path>` の元ファイル（HEAD = 9f30573）。working tree の既存分割（part + mixin チェーン）は参考であり拘束されない。
- 方針: 設計のみ。コード変更なし。公開 API は変更可（呼出元・テストの参照更新を含める）。挙動不変（テスト期待値は変えない）。
- 本改訂（v2）: design-critic の critique.md 指摘6項目（l10n 伝達・execute 再起動経路・facade 責務1文体・keepalive/execLock 所有者・protocol 分離・数値実測）に対応。

---

## 1. 現状責務分析

### 1.1 ssh_client.dart（HEAD 1298行）— 8〜10責務の混在

```bash
# working tree の part 構造（参考）
lib/services/ssh/ssh_client.dart:  class SshClient extends _SshClientCore with _SshShellMixin, _SshExecMixin, _SshKeepAliveMixin, _SshConnectMixin implements BackendAdapter
```

以下、HEAD 元ファイルから抽出したフィールドと、それを参照するメソッドの対応（状態の所有者を決める根拠）。

| フィールド | 所有する状態 | 参照メソッド |
|---|---|---|
| `_connectionFactory` | 接続確立の注入（テスト用） | `connect` |
| `_persistentShellFactory` | 持続シェル生成の注入（テスト用） | `_tryStartShell` |
| `_timerFactory` | Timer 生成の注入（テスト用） | `_scheduleNextKeepAlive` |
| `_client` (SSHClient?) | SSH トランスポート本体 | `openSftp`/`connect`/`startShell`/`startManagedPty`/`execute`/`_executeEphemeral`/`_startPersistentShell`/`_tryStartShell`/`restartPersistentShell`/`restartInputShell`/`_sendKeepAlive`/`_cleanup` |
| `_session` (SSHSession?) | インタラクティブシェル | `startShell`/`write`/`writeBytes`/`resize`/`_cleanup` |
| `_socket` (SSHSocket?) | ソケット | `connect`/`_cleanup` |
| `_cachedSftp` | SFTP キャッシュ | `openSftp`/`_cleanup` |
| `_managedPty` | managed PTY | `startManagedPty`/`_cleanup` |
| `_state` | 接続状態 | `connect`/`disconnect`/`_handleDone`/`_updateState`/`_sendKeepAlive`/`state`/`isConnected` |
| `_events` | イベントハンドラ | `_handleData`/`_handleError`/`_handleDone`/`setEventHandlers`/`updateEventHandlers`/`disconnect`/`_sendKeepAlive` |
| `_lastError` | 直近エラー | `connect`/`_handleError`/`resize`/`_sendKeepAlive`/`_onVerifyHostKey`/`lastError` |
| `_l10n` | ローカライズ（**connect() 内 L345 `_l10n = l10n` で設定**・コンストラクタではない） | ほぼ全メソッド（エラーメッセージのフォールバック） |
| `_stdoutSubscription`/`_stderrSubscription` | シェル購読 | `startShell`/`_cleanup` |
| `_persistentShell`/`_inputShell` | 持続シェル2本 | `execute`/`_cleanup`/`persistentShell`/`inputShell`/`_startPersistentShell`/`restartInputShell` |
| `_execLock` | exec 排他（`_withExecLock` 専用） | `_withExecLock` |
| `_connectOptions` | 接続時オプション | `connectOptions`/`userExecutablePath` |
| `_pendingFingerprintMigration` | ホスト鍵移行保留 | `connect`/`_onVerifyHostKey` |
| `_keepAliveTimer` + カウンタ3種 | Keep-alive | keepalive 系メソッド一式 |
| `_connectionStateController` | 状態ストリーム | `_updateState`/`connectionStateStream` |
| `onInputShellRebooted` | 再起動通知 | `_startPersistentShell`/`restartInputShell`/`onInputTransportRebooted` |

**テスト注入点の実測（grep 数・v2 で確定）**:
- `connectionFactory`: **ssh_client_test に 14 箇所 + repro_bug2_latency_test に 1 箇所（計 15）**
- `persistentShellFactory`: **ssh_client_test に 6 箇所 + repro に 1 箇所（計 7）**
- `timerFactory`: **ssh_client_test に 1 箇所**（keepalive テスト）
- `test/helpers/fake_ssh_client.dart` は `class FakeSshClient extends SshClient implements TmuxCommandExecutor, TmuxPathDetector, BackendAdapter` — **24 箇所の @override**（state / isConnected / lastError / userExecutablePath / connectionStateStream / inputTransport / restartInputTransport / openSftp / execute / execWithExitCode / sendKeysCommand / setWindowRestoreTrap / restoreWindowsNoWait / write / writeBytes / resize / startShell / disconnect / dispose / setEventHandlers / updateEventHandlers / restartPersistentShell ほか）。→ **SshClient は final 化不可、継承可能な通常クラスが前提**。

**責務の整理（v2 分類）**:
1. DTO（SshConnectOptions / ShellOptions / SshEvents）
2. 接続確立（connect / バリデーション / ホスト鍵検証 / 鍵パース / fingerprint 移行）
3. 状態管理（state / stream / lastError の発行）
4. イベント配信（SshEvents の保持・発火）
5. インタラクティブシェル（startShell / write / writeBytes / resize / 購読）
6. コマンド実行（execute / ephemeral / persistent ルーティング / exec ロック）
7. Keep-alive（タイマー / 間隔調整 / 失敗閾値）
8. 持続シェル管理（2本の起動・再起動）
9. 資源ライフサイクル（SFTP キャッシュ / managed PTY / cleanup / dispose）
10. managed PTY プロセス（`ManagedPtyProcess` クラス定義）
11. ファクトリ（createSshClient）

### 1.2 persistent_shell.dart（HEAD 500行）— マーカープロトコルとトランスポートの混在

| 責務 | 実装 | 行数概算 |
|---|---|---|
| マーカー生成（nonce / START/END/RC / printf 版） | `_markerId`, `_startMarker` 等 8 フィールド + `_generateMarkerId`（**インスタンスフィールド、HEAD L30**） | ~40 |
| シェル初期化（bash 固定 / HISTFILE / PS1 / stty） | `start` 内 | ~60 |
| コマンド実行調整（exec / execWithExitCode / _execFramed / timeout / poison） | `_execFramed`, `_poisonAfterTimeout` | ~80 |
| マーカー解析（scanner feed / UTF8 / CR 正規化 / RC 抽出 / trim） | `_onData` 等 | ~70 |
| トランスポート（start / sendNoWait / restart / dispose / isStarted / subscription） | 本体 | ~80 |
| per-command 状態 | `PendingShellCommand` | ~30 |
| エラー型 | `PersistentShellError` | ~15 |

`ShellMarkerScanner` は既に独立ファイル（lib/services/ssh/shell_marker_scanner.dart、130行）。責務は「バイトストリームから start/end マーカー区間を **O(n) で抽出する汎用スキャナ**」（マーカーはコンストラクタ注入）。マーカー「文字列の構築」（nonce 込み）と「出力の後処理」（CR 正規化等）は PersistentShell 側に残っている。

### 1.3 herdr_caret_helper_manager.dart（HEAD 634行）— types / install / run / インフラの混在

| 責務 | 実装 |
|---|---|
| 型群（failure enum / exception / result / installation / runner interface / loader typedef） | 冒頭 ~90行 |
| シェル引数ユーティリティ（static public） | `deriveClientSocket` / `isValidPaneId` / `shellQuote` |
| install（platform 判定 / manifest 選定 / asset 検証 / cache base / sha256 照合 / SFTP upload / chmod / memo） | `_ensureInstalled` / `_install` / `_installRemote` / `_parseSha256Output` |
| run（protocol/socket/pane 検証 / コマンド構築 / 実行 / 出力検証） | `run` / `_runHelper` / `_doRunHelper` |
| SSH 実行インフラ（ephemeral execute + 失敗分類） | `_exec` / `_requireExitCodeZero` |
| 失敗報告（debug ログ + throw） | `_fail` / `_log` |

**外部依存の事実**:
- `HerdrCaretHelperManager` は `SshClient`（`openSftp`, `.execute`）と `SftpService`（`ensureDirectory` / `uploadStream`）に依存。
- `herdr_caret_snapshot_reader.dart` は `HerdrCaretHelperRunner` interface に依存（テスト `herdr_caret_snapshot_reader_test.dart` は `_FakeRunner implements HerdrCaretHelperRunner`）。
- `test/services/herdr/caret/herdr_caret_helper_manager_test.dart` は `deriveClientSocket` / `isValidPaneId` / `shellQuote` を直接呼ぶ（195〜227行・実測一致）。
- install memo（`_installMemo[_ssh]`）は **key が SshClient インスタンス自体**（HEAD L157/L260-268、`identical` で single-flight + 失敗時除去）。

---

## 2. 提案構成

### 2.1 ssh_client.dart → composition root（facade）+ 所有者3 + コラボレータ7

**v2 の中核方針**:
1. **facade の責務を1文で言える粒度にする**: `SshClient` は「公開 API を内部の所有者/コラボレータへ委譲する配線（composition root）」のみ。
2. **状態・イベント・資源ライフサイクルを独立クラス化**（critique 重大3 への対応）:
   - ①状態遷移の所有者 → `SshConnectionStateController`
   - ②イベント配信 → `SshEventBroker`
   - ③資源ライフサイクル（cleanup/dispose）→ `SshResourceManager`
3. **`_l10n` は SshClient の可変フィールドとして残し（connect() L345 が唯一の書込点）、全コラボレータへ「現在の l10n を返すクロージャ」を注入**（critique 重大1 への対応）。接続後に英語固定化しない。
4. **コラボレータ間はクロージャ注入のみで結合**（facade が配線）。引数集中・直接相互参照を避ける（critique 重大2 への対応）。

#### ファイル一覧

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `ssh_client.dart` | **公開 API（BackendAdapter 面）を所有者/コラボレータへ委譲する配線。** ファクトリ3・`_l10n`・`_connectOptions`・`onInputShellRebooted` を保持し、クロージャ（l10nProvider / restartCallback / probe / onDead 等）を用意して部品へ渡す。 | 既存公開 API を維持：connect / disconnect / execute / openSftp / startShell / startManagedPty / write / writeBytes / resize / persistentShell / inputShell / inputTransport / restartInputTransport / restartPersistentShell / restartInputShell / connectionStateStream / state / isConnected / lastError / connectOptions / userExecutablePath / onInputTransportRebooted / setEventHandlers / updateEventHandlers / dispose / createSshClient。コンストラクタ（3 ファクトリ）も維持。`SshConnectionError`/`SshAuthenticationError`/`SshConnectionState`/DTO/ManagedPtyProcess を再 export。 | ~200 |
| `ssh_models.dart` | SshConnectOptions / ShellOptions / SshEvents の DTO。 | 既存 DTO 3 型（公開） | ~120 |
| `ssh_connection_state_controller.dart` | **接続状態の単一所有者。** state / lastError / stream を保持し、遷移（connecting/connected/error/disconnected）と stream 発行のみを行う。 | `SshConnectionStateController`（internal。state / lastError / connectionStateStream / transition()） | ~60 |
| `ssh_event_broker.dart` | **イベント配信の単一所有者。** SshEvents を保持し、setEventHandlers / updateEventHandlers / onData / onClose / onError 発火のみを行う。 | `SshEventBroker`（internal） | ~60 |
| `ssh_resource_manager.dart` | **資源ライフサイクルの単一所有者。** SSHClient / SSHSocket / SSHSession / SftpClient / ManagedPty / 購読 / 持続シェル2本の attach・取得・cleanup・dispose を一括実行する。 | `SshResourceManager`（internal。attach / detach / disposeAll / client / socket / session / cachedSftp 等のアクセサ） | ~120 |
| `ssh_connector.dart` | ソケット接続・認証方式選択・ホスト鍵検証・key パース・fingerprint 移行を実行し、SSHClient/SSHSocket を生成する。 | `SshConnector`（internal。`connect()` が `({SSHSocket, SSHClient})` を返す。`connectionFactory` 注入受け・`_pendingFingerprintMigration` を内部保持） | ~200 |
| `ssh_command_executor.dart` | CommandRequest の transport/output に基づく ephemeral/persistent ルーティング・ephemeral チャネル実行・exec ロック・PersistentShellError からのフォールバック（再起動は注入されたコールバックへ依頼）。**`_execLock` の所有者。** | `SshCommandExecutor`（internal。`execute(CommandRequest)` のみ。引数は `CommandRequest`（公開 API と同じ1引数）） | ~230 |
| `ssh_keep_alive.dart` | Timer スケジュール・間隔の動的調整・失敗閾値判定。**カウンタ3種（failure/success/currentInterval）の所有者。** probe 実行・故障通知は注入クロージャ経由。 | `SshKeepAlive`（internal。`start/stop`、`timerFactory` 注入受け） | ~120 |
| `ssh_shell_manager.dart` | ポーリング用・入力用の持続シェル2本の生成・起動・再起動・破棄（2チャネル並列起動、onInputShellRebooted 発火）。 | `SshShellManager`（internal。`persistentShellFactory` 注入受け・`restartPolling`/`restartInput`） | ~120 |
| `ssh_interactive_shell.dart` | インタラクティブシェルの startShell / write / writeBytes / resize と、stream 購読からのイベント配信（onData/onError/onDone は注入クロージャで broker/controller へ）。 | `SshInteractiveShell`（internal） | ~130 |
| `ssh_sftp.dart` | SftpClient のキャッシュ管理（openSftp）。 | `SshSftpAccess`（internal） | ~40 |
| `ssh_managed_pty.dart` | ManagedPtyProcess：（SIGTERM→done 待ち→close、stdout discard、stderr tail、完了検知）。 | `ManagedPtyProcess`（既存公開型、保存） | ~120 |
| `ssh_factory.dart` | createSshClient()。 | 既存ファクトリ | ~10 |

合計 ~1530 行（各ファイル 500 行未満、facade は ~200 行に圧縮）。

#### 配線（クロージャ注入）一覧 — コラボレータ間結合の確定

| 注入先 | 注入されるクロージャ | 実体（facade が配線） | 責務上の意味 |
|---|---|---|---|
| 全コラボレータ | `l10n` | `() => _l10n`（SshClient の可変フィールド参照） | connect() で `_l10n` を更新するだけで全コラボレータのエラー文言が追随（**英語固定化しない**） |
| `SshCommandExecutor` | `restartPollingShell` | `() async => shellManager.restartPolling()` | **execute() の再起動フォールバック（HEAD L1049 `restartPersistentShell()` 相当）の依頼経路**。executor は shellManager を直接参照しない |
| `SshKeepAlive` | `probe` | `() => commandExecutor.execute(CommandRequest('echo ping', persistentPreferred, outputOnly, timeout 10s))` | keep-alive の実行経路（HEAD `_sendKeepAlive` 相当） |
| `SshKeepAlive` | `onDead` | `(error) { stateController.transition(error); eventBroker.onError; eventBroker.onClose; }` | 失敗閾値到達時の状態遷移・イベント発火を統括 |
| `SshKeepAlive` | `isConnected` | `() => stateController.state == connected` | probe 継続判定 |
| `SshInteractiveShell` | `onData`/`onError`/`onDone` | `(d) => eventBroker.onData(d)` 等 + `onDone => stateController.transition(disconnected)` | シェル購読結果の配信・切断遷移 |
| `SshConnector` | （無し。戻り値のみ） | — | 接続資源を返し、facade が `resourceManager.attach()` を行う |

全てのコラボレータは facade を直接参照せず、注入されたクロージャのみで外部（broker / controller / manager / 他コラボレータ）と通信する。→ **依存は一方向（facade → コラボレータ）＋ クロージャ（コラボレータが保持するだけ）で、循環なし**。

### 2.2 persistent_shell.dart → プロトコル構築と出力解析の分離

**v2 の中核方針（critique 重大5 への対応）**:
- 「マーカー文字列の生成」と「出力の後処理」を**別クラスに分離**。
- **nonce（SHELL-002、HEAD L30 `_markerId`）はインスタンスごとに生成が必須**。`ShellMarkerProtocol` は PersistentShell ごとに 1 インスタンス生成する前提を明記（シングルトン・static 共有禁止。共有すると偽装耐性が壊れる）。
- バイト走査は既存 `ShellMarkerScanner` のまま（下層）。

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `persistent_shell.dart` | SSH セッションのライフサイクル（start/dispose/restart/sendNoWait/isStarted）とコマンド実行の調整（exec/execWithExitCode/timeout/poison、PENDING 管理）を担い、protocol/parser/scanner を合成する。TmuxInputTransport 実装。 | `PersistentShell`（既存公開 API 維持：start / exec / execWithExitCode / sendNoWait / restart / dispose / isStarted / hasPendingCommand）。`PersistentShellError` も export。 | ~210 |
| `shell_marker_protocol.dart` | **マーカー構築のみ**：nonce 込みの START/END/RC・printf 版文字列の生成と、コマンドラップ文字列の構築。**PersistentShell ごとに 1 インスタンス（nonce はインスタンス毎、SHELL-002）**。 | `ShellMarkerProtocol`（internal。`buildCommand(command, {captureExitCode})` / マーカー getter） | ~90 |
| `shell_output_parser.dart` | **出力の後処理のみ**：スキャナ抽出結果の UTF8 デコード・CR 正規化・RC エコー抽出・trim。純関数（状態なし）。 | `ShellOutputParser`（internal。`parse(between, {required rcMarker, required captureExitCode})` → `(output, exitCode)`） | ~70 |
| `pending_shell_command.dart` | per-command 状態（captureExitCode / completer / scanner / exitCode）。 | `PendingShellCommand`（既存型・公開） | ~40 |
| `persistent_shell_error.dart` | PersistentShellError。 | 既存 | ~20 |
| `shell_marker_scanner.dart` | （既存・変更なし）バイトストリームからのマーカー区間 O(n) 抽出 | 既存公開 | 130 |

- 責務境界: **protocol = 「送る側の構築」、scanner = 「生バイトの区間抽出」、parser = 「抽出結果の意味解釈」**。3 層が各1責務。
- `_onData` 内の assert（UTF-8 境界分割デバッグ）は PersistentShell 本体に残す（parser の責務外・診断用途）。

### 2.3 herdr_caret_helper_manager.dart → manager / installer / executor / infra の分離

**v2 の変更点**: install memo のスコープ・生存期間を確定（key が SshClient インスタンスであることを明記）。Manager と installer の生成関係も確定。

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `herdr_caret_helper_types.dart` | helper の型群：failure enum / exception / run result / installation / binary loader typedef / runner interface。 | `HerdrCaretHelperFailure` / `HerdrCaretHelperException` / `HerdrCaretHelperRunResult` / `HerdrCaretInstallation` / `HerdrCaretBinaryLoader` / `HerdrCaretHelperRunner`（全て既存公開型、移動） | ~100 |
| `herdr_caret_shell_args.dart` | リモートシェルに安全な値を渡す静的ユーティリティ（client socket 導出 / paneId 検証 / POSIX single-quote）。 | `deriveClientSocket` / `isValidPaneId` / `shellQuote`（既存 static、移動） | ~60 |
| `herdr_caret_helper_installer.dart` | install フロー：platform 判定 / manifest 選定 / bundle バイト検証 / cache base / sha256sum 照合 / SFTP upload→検証→rename / chmod / memo。`HerdrCaretInstallation` を返す。 | `HerdrCaretInstaller`（internal。**memo は key = SshClient インスタンス（`_ssh` identity）で単一の future を single-flight、失敗時除去**） | ~210 |
| `herdr_caret_helper_executor.dart` | helper 1回実行：コマンド構築（shellQuote 済み）/ execute / 出力検証（json・64KB・exit code）。 | `HerdrCaretHelperExecutor`（internal） | ~100 |
| `herdr_caret_ssh.dart` | ephemeral SSH 実行 + 失敗分類（timeout/connectFailed）+ 失敗報告（debug ログ + throw）。 | `HerdrCaretSshRunner`（internal） | ~70 |
| `herdr_caret_helper_manager.dart` | runner interface 実装のオーケストレーター：protocol/socket/pane 検証 → installer → executor の順に実行し、結果を返す。**installer は Manager と 1:1 で生成され、SshClient 差し替え時も memo は `_ssh` identity で自動追従**。 | `HerdrCaretHelperManager`（既存公開 API 維持：`run(...)`、`maxStdoutBytes`/`defaultRunTimeout` 定数） | ~150 |

- **memo の生存期間**: installer が持つ `Map<Object, Future<HerdrCaretInstallation>>` の key は SshClient インスタンス（`identical` 比較）。Manager が複数 connection（`_CountingSshClient` 差替え）を扱っても、差し替えられた別インスタンスは別 key として new install → HEAD と同一挙動。memo のクリアは「connection が廃棄されても key が GC されない」問題を避けるため、installer は Manager と同一インスタンスでなくても良いが、**接続単位を「インスタンス単位」に読み替えない**（同一インスタンスへの再 install を防ぐだけ）。
- 静的ユーティリティの移動先はテスト（manager_test 195〜227行）の import 更新が必要（変更点 §5）。

---

## 3. 依存グラフ（v2：コールバック辺を明記）

```
                     ┌────────────────────────────────────────────────┐
        外部 │        │ ssh_client.dart (SshClient = composition root) │
        ───────▶      │ 公開API委譲のみ・_ l10n 可変・3ファクトリ保持     │
                     └────────────────────────────────────────────────┘
   │ 委譲(直接参照)      │ l10nクロージャ(全部品へ)  │ restartCallback / probe / onDead 等(注入)
   ▼                    ▼                         ▼
┌──────────────┐   ┌────────────┐   ┌──────────────────────────┐
│ssh_connection│◀──│ssh_event_  │   │ssh_command_executor.dart │──restartPollingShell コールバック──▶ facade 経由で shell_manager へ
│state_controller│  │broker      │   │(execute / execLock 所有) │
└──────────────┘   └────────────┘   └──────────────────────────┘
   ▲                    ▲                  │ probe コールバック(facade) ▲
   │ onDone 遷移        │ onData/onError    │                          │
┌───────────────┐       │                  ▼                          │
│ssh_interactive│       │            ┌───────────────┐                 │
│_shell         │───────┘            │ssh_keep_alive │──onDead──▶ facade
└───────────────┘                    │(カウンタ所有)  │
                                     └───────────────┘
┌────────────────┐   ┌──────────────┐   ┌──────────────┐
│ssh_resource_   │◀──│ssh_connector │   │ssh_shell_    │
│manager         │   │(接続確立)     │   │manager       │
│(cleanup所有者)  │   └──────────────┘   │(shell2本)     │
└────────────────┘                      └──────────────┘
   ▲                                            │
   │ 再 export/公開 API の提供元（DTO・PTY・factory）
┌───────────┐  ┌──────────┐  ┌───────────┐
│ssh_models │  │ssh_managed│  │ssh_sftp   │
│(DTO)      │  │_pty      │  │(sftp cache)│
└───────────┘  └──────────┘  └───────────┘
        ┌────────────────────────────────────────┐
        │ lib/services/ssh/persistent_shell.dart │ (PersistentShell = トランスポート)
        │  ├── shell_marker_protocol.dart        │ ← 構築（送る側・インスタンス毎 nonce）
        │  ├── shell_output_parser.dart          │ ← 意味解釈（受ける側・純関数）
        │  ├── pending_shell_command.dart        │ ← per-command 状態
        │  ├── persistent_shell_error.dart       │
        │  └── shell_marker_scanner.dart (既存)  │ ← バイト走査（下層・変更なし）
        └────────────────────────────────────────┘

┌───────────────────────────────────────────────────────┐
│ lib/services/herdr/caret/                              │
│  herdr_caret_helper_manager.dart (orchestrator)        │
│    ├── herdr_caret_helper_types.dart    (型・interface)│
│    ├── herdr_caret_shell_args.dart      (シェル引数)   │
│    ├── herdr_caret_helper_installer.dart (install+memo)│
│    ├── herdr_caret_helper_executor.dart (run)          │
│    └── herdr_caret_ssh.dart             (SSH実行基盤)  │
│        依存: ssh_client.dart (execute / openSftp)      │
│               sftp_service.dart (SftpService)          │
└───────────────────────────────────────────────────────┘
        │ implements / 注入
        ▼
  herdr_caret_snapshot_reader.dart (HerdrCaretHelperRunner 利用)
```

- **critique 重大2 への解答**: `ssh_command_executor →(restartPollingShell クロージャ)→ facade →(委譲)→ ssh_shell_manager` の辺が確定。executor 側は「再起動コールバックを呼ぶ」だけで、shell_manager を直接参照しない。execute() の引数は `CommandRequest` のみ（現公開 API と同一）で、routing 判定に必要な資源・l10n はコールバック/クロージャ注入で解決 → **引数集中にならない**。
- 依存はすべて一方向・非循環：`facade → コラボレータ`（＋コラボレータは facade が用意したクロージャを保持するだけ）。`interactive_shell → broker/controller`、`keep_alive → broker/controller`、`executor → persistent_shell`、`caret → ssh_client/sftp_service`。

---

## 4. API 変更点（before / after）

### 4.1 ssh_client 系（原則: 公開 API 維持。FakeSshClient の継承前提があるため破壊は最小化）

| Before | After | 影響 |
|---|---|---|
| `SshClient`（mixin で拡張された単一クラス） | `SshClient`（普通のクラス＋コンストラクタ委譲・~200行） | 変更なし（継承可能）。`extends SshClient` する FakeSshClient はそのまま |
| `SshConnectOptions` / `ShellOptions` / `SshEvents`（ssh_client.dart 内） | `ssh_models.dart` に移動し `ssh_client.dart` から再 export | import 元（多数）は現状のまま |
| `ManagedPtyProcess`（ssh_client.dart 内） | `ssh_managed_pty.dart` に移動し `ssh_client.dart` から再 export | `herdr_resize_bridge.dart` 他は現状のまま |
| `SshConnectionError` / `SshAuthenticationError` / `SshConnectionState` | 追加の再 export は不要（既存 export を継続） | 変更なし |
| `createSshClient()` | `ssh_factory.dart` に移動し再 export | import 現状のまま |
| 内部 mixin `_SshConnectMixin` 等（private） | 削除（所有者/コラボレータへ置換） | 外部・テストから参照不可（private なので影響なし） |
| `connectionFactory` / `persistentShellFactory` / `timerFactory` 引数 | SshClient コンストラクタに維持 | テスト・repro の注入点は変更なし |
| 内部の状態・イベント・資源（private） | `SshConnectionStateController` / `SshEventBroker` / `SshResourceManager` へ移譲 | 外部影響なし。**facade は委譲のみで状態を握らない** |

### 4.2 persistent_shell 系（公開 API 維持）

| Before | After | 影響 |
|---|---|---|
| `PersistentShell.exec` / `execWithExitCode` / `start` / `sendNoWait` / `restart` / `dispose` / `isStarted` | 維持（内部で protocol/parser を使用） | 変更なし |
| `PersistentShellError` | 維持（export も） | `SshClient.execute` の catch 対象も維持 |
| `PendingShellCommand` | `pending_shell_command.dart` に移動 | 公開型だが外部参照なし（grep で確認。persistent_shell.dart 内のみ）→ 維持して export |
| マーカー生成・CR 正規化・RC 抽出（private） | `ShellMarkerProtocol` / `ShellOutputParser` へ分離 | 外部参照なし |

### 4.3 caret manager 系（static ユーティリティの参照先変更のみ）

| Before | After | 影響 |
|---|---|---|
| `HerdrCaretHelperManager.run(...)` | 維持 | terminal_screen / reader は変更なし |
| `HerdrCaretHelperManager.deriveClientSocket` / `.isValidPaneId` / `.shellQuote`（static） | `herdr_caret_shell_args.dart` に移動 | manager_test 195〜227行 の import・レシーバ変更が必要 |
| `HerdrCaretHelperRunner` / 型群（manager 内） | `herdr_caret_helper_types.dart` に移動 | snapshot_reader・同テストの import 変更が必要 |
| `HerdrCaretHelperManager` 内部メソッド（private） | installer / executor / ssh_runner へ委譲 | 外部影響なし |

---

## 5. 呼出元・テスト更新リスト（v2：Fake override と内部委譲の相互作用検証を含む）

### 5.1 lib 側（コード変更を伴う可能性のある箇所）

| ファイル | 現状 | 変更 |
|---|---|---|
| `lib/services/ssh/*`（新規） | — | 新規12ファイル追加 + ssh_client.dart から再 export |
| `lib/services/herdr/caret/herdr_caret_helper_manager.dart` | runner 実装本体 | 内部を installer/executor/ssh runner へ委譲 |
| `lib/services/herdr/caret/herdr_caret_snapshot_reader.dart` | `import ...helper_manager.dart` | runner 型が移動 → import を `types.dart` に追加（export 互換なら不要の可能性） |
| `lib/screens/terminal/terminal_screen.dart` | `HerdrCaretHelperManager(ssh:..., manifest:...)` 生成 | **変更不要**（公開 API 維持） |
| `lib/services/herdr/herdr_resize_bridge.dart` | `client.startManagedPty` + `ManagedPtyProcess` | 変更不要（再 export で解決） |
| provider/screen 群（sshProvider 等） | SshClient 公開 API 使用 | 変更不要 |
| `lib/services/sftp/sftp_*.dart` | SftpService（caret manager に注入） | 変更不要 |

### 5.2 テスト側

| テスト | 現状 | 必要な更新 |
|---|---|---|
| `test/helpers/fake_ssh_client.dart` | `extends SshClient` + 24 箇所 override | **変更不要**（SshClient の公開形と継承可能性を維持するため） |
| `test/services/ssh/ssh_client_test.dart` | 3 ファクトリ注入（connectionFactory 14 / persistentShellFactory 6 / timerFactory 1）、DTO テスト、managed PTY テスト、fingerprint 移行テスト | import 追加以外のロジック変更不要（期待値不変） |
| `test/repro/repro_bug2_latency_test.dart` | `connectionFactory` + `persistentShellFactory` 注入（各1） | 変更不要 |
| `test/services/ssh/persistent_shell_test.dart` | Fake SSHClient/SSHSession、マーカー合致検証 | 変更不要（公開 API 維持。マーカー文字列の生成先が変わっても同一文字列を返すため期待値不変） |
| `test/services/ssh/shell_marker_scanner_test.dart` | Scanner 単体 | 変更不要 |
| `test/services/herdr/caret/herdr_caret_helper_manager_test.dart` | `deriveClientSocket`/`isValidPaneId`/`shellQuote` を Manager static で参照、`_CountingSshClient extends FakeSshClient` | **参照更新**: import 先を `herdr_caret_shell_args.dart` に変更（テスト期待値・挙動は不変） |
| `test/services/herdr/caret/herdr_caret_snapshot_reader_test.dart` | 型に依存 | import 更新のみ |

### 5.3 FakeSshClient の override と内部委譲の相互作用（critique 重大3 への検証）

想定: v2 では SshClient の公開メソッド（execute / openSftp / write 等）が内部でコラボレータ（SshCommandExecutor / SshSftpAccess 等）へ委譲する。Fake が「公開メソッドを override した stub」である場合、コラボレータ経由に変えると override が効かなくなる経路はあるか？

検証結果（Dart の動的ディスパッチに基づく）:
1. **外部から呼ばれる公開 API**: `fakeClient.execute(...)` 等は、Fake のオーバーライド実装が選ばれる（`SshClient` の委譲実装まで到達しない）。→ 従来の stub テストは不変。
2. **公開 API が内部で「他の公開 API」を呼ぶ経路（準委譲）**: 例として v1 では「execute() が restartPersistentShell() を内部で呼ぶ」。v2 ではこれは**コールバック注入（`restartPollingShell`）に置換**される。Fake は execute 自体を stub するためこの経路自体に入らない。
3. **コラボレータから「override される公開メソッド」へのバイパス**: 実コード（本番 SshClient）では、executor / keep_alive / shell_manager は facade を参照せず、facade が用意したクロージャのみを呼ぶ。Fake のテストではコラボレータへ到達しない（Fake は公開メソッドを stub）。→ バイパス経路なし。
4. **例外**: Fake が override していない公開メソッド（例: `connect`/`restartInputShell`）は実装が動くが、これは v1（現行）でも同じ挙動（現行 mixin 版でも Fake は connect を override していない）。→ 変化なし。
5. **結論**: 「公開 API は常に SshClient インスタンスメソッドとして残し、内部のコラボレータ間通信はクロージャ注入（facade が配線）のみ」という規約により、**Fake の stub 化と内部委譲の相互作用は発生しない**。この規約を実装規約として明文化する。

| Fake が override する公開メソッド | v2 での変更 | 検証 |
|---|---|---|
| execute / openSftp / execWithExitCode / write / writeBytes / resize / startShell / setEventHandlers / updateEventHandlers / disconnect / dispose / restartPersistentShell / inputTransport / restartInputTransport 等（計24） | 実装はコラボレータへ委譲、公開シグネチャ不変 | 外部呼び出しは Fake override が優先（動的ディスパッチ）。委譲実装へ到達しない。期待値不変 |
| connect（Fake は未 override） | state/machine + resource attach へ分解 | v1 でも Fake は connect を呼ばず setConnected() を使うため影響なし |
| persistentShell / inputShell / connectOptions / state / isConnected / lastError / connectionStateStream / userExecutablePath（getter） | controller / resource manager / facade フィールドからの委譲 | getter シグネチャ不変。Fake override が優先（Fake は state 等を override）。未 override の getter（persistentShell 等）は委譲実装がそのまま動く |

---

## 6. 移行手順

各ステップで `make analyze` + `make test` を実行し、緑のまま進める。

1. **基盤抽出（挙動不変・API 不変・ファイル追加のみ）**
   - `ssh_models.dart` / `ssh_managed_pty.dart` / `ssh_factory.dart` / `persistent_shell_error.dart` / `pending_shell_command.dart` に既存コードをそのまま移動し、元ファイルから再 export。この時点では SshClient / PersistentShell / Manager 本体は従来 mixin 構成のまま。
2. **サイレント検証**: analyze / test /（可能なら `make build-apk` のコンパイルまで）
3. **persistent_shell の分離**: `shell_marker_protocol.dart`（構築）と `shell_output_parser.dart`（後処理）を抽出。PersistentShell 本体からマーカー生成・CR 正規化・RC 抽出を移し、mixin を除去して単一クラス化。
4. **caret manager の分離**: types / shell_args / installer / executor / ssh_runner を抽出し、Manager をオーケストレーターに。テストの import 参照（manager_test 195〜227行）を更新。
5. **ssh_client のファサード化（最後に実施・最も risky）**
   - 5a. `ssh_connection_state_controller.dart` / `ssh_event_broker.dart` / `ssh_resource_manager.dart` への状態・イベント・資源の移譲（公開 getter の委譲先を controller へ変更）。
   - 5b. `ssh_command_executor.dart` / `ssh_keep_alive.dart` / `ssh_shell_manager.dart` / `ssh_interactive_shell.dart` / `ssh_connector.dart` / `ssh_sftp.dart` を順に抽出。各ステップで mixin が1つ不要になり、最後に `_SshClientCore` と全 mixin を除去。
   - 5c. クロージャ配線（l10nProvider / restartPollingShell / probe / onDead）を facade に集約。
6. **最終検証**: analyze / test / build-apk（コンパイルレベル）/ 手動 smoke（接続・持続シェル・keep-alive・TMUX 操作・herdr caret）。

---

## 7. リスクと代替案

### リスク（v2）

| リスク | 対策 |
|---|---|
| **l10n が英語固定化する（critique 重大1 の回帰）** | `_l10n` は SshClient の可変フィールド（connect() L345 が唯一の書込点）として残し、全コラボレータへ「`() => _l10n` クロージャ」を注入。テスト（connect() で l10n を渡す既存テスト ssh_client_test）が追随を保証。 |
| **execute() の再起動フォールバック経路の破綻（critique 重大2）** | `restartPollingShell` コールバックを facade が配線し executor へ注入。shell_manager 直接参照なし。`PersistentShellError` の closed/disposed 判定と再実行は既存テスト（ssh_client_test のフォールバック系）で担保。 |
| **facade の責務再集中（critique 重大3）** | 状態 → controller、イベント → broker、資源 → resource manager、keepalive → keep_alive、execLock → executor にすべて移譲。facade は ~200行の「委譲配線」に圧縮。実装時のレビュー項目として「facade に private フィールドが残っていないか」をチェックリスト化。 |
| **FakeSshClient の stub がバイパスされる** | §5.3 の規約（公開 API = インスタンスメソッド、コラボレータ間 = クロージャ注入のみ）を実装規約化。Fake が override する24メソッドは全て公開シグネチャ不変。 |
| **PersistentShellError の catch 分岐（closed/disposed 文字列判定）が壊れる** | エラー型・メッセージを不変に保つ。テスト（persistent_shell_test / ssh_client_test のフォールバック系）で担保。 |
| **非ce 共有による偽装耐性の喪失（critique 重大5）** | ShellMarkerProtocol は PersistentShell ごとに 1 インスタンス生成（nonce はインスタンス毎、SHELL-002）。プロトコルを static/シングルトンにしない旨をファイルヘッダに明記。persistent_shell_test のマーカー合致検証が担保。 |
| **install memo の生存期間（critique 中7）** | memo の key は SshClient インスタンス（`_ssh` identity・HEAD と同じ）。Manager が複数 connection を差し替えても別 key で new install。接続単位をインスタンス単位に読み替えない。 |
| **既存 working tree 分割で修正済みの挙動の回帰** | バグ2 対応（per-command scanner・stale frame 混入防止・timeout 時の shell 破棄）と keep-alive 閾値3 は **HEAD に既に存在**（persistent_shell L212/L241/L266、ssh_client `_keepAliveFailureThreshold=3`）。抽出対象は HEAD 版そのものなので、これらの挙動は設計として保持される（v1 の「working tree のコメントを再現」という記述は誤りを修正）。 |

### 代替案（検討済み・不採用）

| 代替案 | 不採用理由 |
|---|---|
| **mixin 分割を維持し、ファイル名だけ整える** | 責務境界が不十分（private フィールド共有のための mixin チェーン）とするレビュー判断に反する。設計原則2（合成優先）を満たさない。 |
| **コラボレータを private のまま part で接続** | part + private は実質 mixin と同じ共有（状態の所有者が曖昧）。独立クラス+クロージャ注入の方が依存が明示的。 |
| **SshClient を完全分解し、接続を独立オブジェクト化** | FakeSshClient の継承前提・公開 API 維持・既存テストの互換を優先。ファサード（composition root）型が現実的。 |
| **executor が shell_manager を直接注入参照** | 循環は起きないが、コラボレータ同士の直接依存が増え、Fake のバイパス経路検証が複雑化。facade 配線のクロージャ注入に統一する。 |
| **ShellMarkerProtocol に構築＋解析を同居（v1 案）** | critique 重大5（機械的分割の再発懸念・nonce インスタンス毎の明記不足）を受けて、protocol（構築）と parser（意味解釈）に分離。 |
| **caret の静的ユーティリティを Manager に残す** | 「シェル引数の安全な構築」という明確な1責務なので独立ファイルに。テスト参照更新（計3箇所）で吸収。 |

---

## 8. 事実と推測の区別（v2）

### 事実（grep / コード読解で直接確認）

- ssh_client.dart / persistent_shell.dart / herdr_caret_helper_manager.dart の HEAD 行数は 1298 / 500 / 634 行。
- working tree で ssh_client.dart は `_SshClientCore` + `_SshShellMixin`/`_SshExecMixin`/`_SshKeepAliveMixin`/`_SshConnectMixin`（相互 `on` 制約あり）に part 分割。persistent_shell.dart も `_PersistentShellCore` + 2 mixin。
- **`_l10n` の設定は connect() 内（HEAD L345 `_l10n = l10n`）**。コンストラクタでは設定されない。
- **execute() の PersistentShellError catch 内で `restartPersistentShell()` を呼ぶ（HEAD L1049）**。timeout では自動再実行しない。
- keep-alive の失敗閾値3（`_keepAliveFailureThreshold`）とバグ2 対応（per-command scanner / stale frame 防止 / timeout 時の shell 破棄）は **HEAD に存在**。
- SshClient の全フィールドと参照メソッドの対応（§1.1）は HEAD 元ファイルから読解（private 参照のため確定）。
- テスト注入の実測: `connectionFactory` = ssh_client_test 14 + repro 1 = 15、`persistentShellFactory` = ssh_client_test 6 + repro 1 = 7、`timerFactory` = 1。
- `test/helpers/fake_ssh_client.dart` は `extends SshClient implements TmuxCommandExecutor, TmuxPathDetector, BackendAdapter` で 24 箇所を override。
- `shell_marker_scanner.dart` は独立ファイル（130行）で責務はバイト走査の O(n) マーカー区間抽出。
- `herdr_resize_bridge.dart` は `SshClient.startManagedPty` と `ManagedPtyProcess` を利用。
- `herdr_caret_snapshot_reader.dart` は `HerdrCaretHelperRunner` interface を使用。`terminal_screen.dart` が `HerdrCaretHelperManager(ssh:, manifest:)` を生成。
- caret manager_test は `deriveClientSocket` / `isValidPaneId` / `shellQuote` を静的メソッドとして直接呼ぶ（195〜227行）。
- caret manager は `SshClient.openSftp` + `SftpService.ensureDirectory/uploadStream` に依存。install memo の key は SshClient インスタンス（`_ssh`）。
- SshClient は `SshConnectionError` / `SshAuthenticationError` / `SshConnectionState` を export し、tmux 層・herdr 層・providers が import。
- export 互換の要否: ManagedPtyProcess（再 export 必須）、Runner interface（再 export 必須）、PendingShellCommand（現状は同一ライブラリのみで利用。export すれば安全）。

### 推測（設計判断として提案・承認待ち）

- 各分割後の推定行数（§2 の数値は HEAD コードの責務規模からの見積もり。実装時は 500 行未満を満たすよう調整）。
- 「FakeSshClient が継承するため SshClient の公開系と継承可能性を維持する」という設計判断（テストが公開 API を握っている事実に基づく帰結）。
- 状態・イベント・資源の 3 独立クラス（controller / broker / resource manager）への分割は、critique 重大3 への設計回答（「接続の独立オブジェクト化」を部分採用した形）。
- keep-alive の probe / onDead 配線、execute の restartPollingShell 配線はクロージャ注入方式の設計上の推測（テストで挙動を保証）。
- 「テスト期待値・挙動は不変」という前提（変更は参照/import 更新のみを意図）。
- 移行手順のステップ順（リスクの高い SshClient ファサード化を最後に置く）は作業進行上の推測。
- facade の 24 override 対応・§5.3 の相互作用検証は、Dart の動的ディスパッチに基づく推測的帰結（実コードの Fake テスト実行で最終確認が必要）。
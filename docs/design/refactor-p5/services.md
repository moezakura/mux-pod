# P5 設計書：test/services の 500 行超 5 ファイル分割設計

対象チェックアウト: `/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines`（読み取り専用）
作成: teammate *p5-service-tests*（担当 #46）
測定方法: 対象 5 ファイルを `flutter test <file> --reporter=json` で実実行し、`testStart` イベントから
JSON レポーターの "loading" 疑似テスト 1 件を除いた件数を実測（全テスト pass を確認）。

---

## v2 改訂サマリ（critique.md §2・§5 反映）

本 v2 は `/tmp/p5-design/critique.md` の p5-service-tests 項（§2 の 2-6 / 2-7、§5 設計者別一覧、§4-(g)）を反映した改訂版。
critique §5 で確認済みのとおり **必須修正はなし**（ssh `setUp/tearDown` 移動は実測的に安全）。
反映は次の 4 点（＋検証コマンドの厳密化）。

1. **§5 検証計画 #4 の「helper ディレクトリへの `flutter test`」を削除／修正**（critique 2-6）。
   helper は `main()` を持たず `*_test.dart` 不在のディレクトリへ `flutter test` すると
   「No tests ran」で**非 0 終了**になるため誤検知の恐れ → 「分割後ディレクトリ全体の実行件数が
   （既存分＋分割分）に一致し、helper 分がカウントされない」ことで確認する方式へ変更。
2. **§5 に ssh 分割後の 9 件 pass 確認を明記**（critique 2-7）。`setUp/tearDown` を外れた
   `ssh_client_connection_test.dart`(5) ＋ `ssh_client_execute_test.dart`(4) の 9 件が独立に pass することを確認
   （managed PTY 4 件は元から setUp 対象外のため対象外）。
3. **§5 に「テスト本体行 diff（verbatim 移動検証）」を追加**（critique §4-(g)）。
   件数・fullName 一致はアサーション改変／削除を検出しないため、旧ファイルの各テストブロックと
   新ファイルの対応ブロックの行 diff が空であることを機械検証する（許容差分は private→public rename・import 差し替え・group ラッパーのみ）。
4. **§6 未確定点 1（connect/exec ヘルパー集約）は「差分ゼロ検証後に採用」の現方針を維持**と明記（方針変更なし）。

追加: 検証コマンドの判定を「EXIT=0・テスト失敗 0」と明記（件数は fail でも同数になるため）。

---

## 0. 実測サマリ（実行結果に基づく事実）

| ファイル | 行数(wc) | 実測テスト数 | 実行結果 |
|---|---|---|---|
| test/services/ssh/ssh_client_test.dart | 1032 | **30** | 全 pass (rc=0) |
| test/services/tmux/tmux_commands_test.dart | 899 | **94** | 全 pass (rc=0) |
| test/services/herdr/herdr_adapter_test.dart | 849 | **45** | 全 pass (rc=0) |
| test/services/terminal/font_calculator_test.dart | 587 | **48** | 全 pass (rc=0) |
| test/services/tmux/tmux_parser_test.dart | 525 | **54** | 全 pass (rc=0) |
| **計** | 3892 | **271** | - |

- 5 ファイルすべてに `@Tags` / `@Skip` / `@Timeout` / `@TestOn` は**一切なし**（grep 実測。唯一の
  `timeout` 一致は ssh_client_test.dart L228 の `SshConnectOptions(timeout: 12)` の引数でメタデータではない）。
- メタデータ的 head コメント:
  - tmux_commands_test.dart L3: `// ignore_for_file: deprecated_member_use_from_same_package`
  - tmux_parser_test.dart L1: 同上
  - どちらも分割後ファイルへ**必ず保持**（CI の `--exclude-tags=repro` には関係しないが lint 挙動を不変にするため）。

---

## 1. 現状分析（事実: 構造・行範囲・メタデータ）

### 1-1. `test/services/ssh/ssh_client_test.dart`（1032 行 / 30 テスト / 4 group）

| 範囲 | 種別 | 内容 |
|---|---|---|
| L1–L14 | import | dart:async / dart:convert / dart:typed_data / dartssh2 / flutter_test / backend_type / multiplexer_config / command_request / command_result / secure_storage / persistent_shell / ssh_client |
| L17–L41 | private class | `_FakeSocket implements SSHSocket`（StreamController×2, closed, stream/sink/done/close/destroy/flush） |
| L44–L83 | private class | `_FakeInteractiveSession implements SSHSession`（stdout/stderr StreamController, writes, emitData/emitError/finish/finishAll） |
| L86–L120 | private class | `_FakeRawSshClient implements SSHClient`（auth Completer, interactiveSession, execSessions, lastPty, shell/execute/close） |
| L123–L162 | private class | `_FakePersistentShell extends PersistentShell`（commands/error/disposed, isStarted/start/exec/execWithExitCode/sendNoWait/dispose） |
| L165–L183 | private class | `_FakeTimer implements Timer`（fire/cancel, duration/tick） |
| L191–L266 | group `SshClient DTOs` | **7 テスト**（SshConnectionError/SshAuthenticationError toString、SshConnectOptions 3、ShellOptions、SshEvents copyWith）。fake 不使用 |
| L267–L393 | group `SshClient no-connection` | **7 テスト**（createSshClient、state stream、disconnect/restart 安全、interactive/execute/openSftp throw、connect 引数検証）。fake 不使用（実 `createSshClient()`） |
| L394–L951 | group `SshClient lifecycle contracts` | **12 テスト**。L395–L396: `setUp(() => SecureStorageService.setTestValues({}))` / `tearDown(... setTestValues(null))`（**static テストフック**）。fake 多用（下記内訳） |
| L952–L1032 | group `SshClient managed PTY（hidden herdr TUI ホスト）` | **4 テスト**。group 内ヘルパー `connectedClient()`（L953–L973、`_FakeRawSshClient`+`_FakeSocket` を立てて connect 完了まで待つ）を使用 |

lifecycle group の内訳（12 件）と使用要素:

| テスト | 行 | fake 使用 | SecureStorage 依存 |
|---|---|---|---|
| SSH-020/024 connect exposes options/emits states | L406–L436 | RawClient/socket | なし |
| SSH-LIFE-003/004 input shell restart | L438–L478 | Raw/socket/persistentShell | なし |
| SSH-LIFE-008..012 keepalive | L480–L543 | Raw/socket/persistentShell/**FakeTimer** | なし |
| execute: persistentPreferred + exitCode | L546–L610 | Raw/socket/persistentShell | なし |
| execute: persistentPreferred restart/retry | L612–L662 | Raw/socket/persistentShell | なし |
| execute: ephemeralOnly separatedOutput | L664–L680 | Raw/socket | なし |
| execute: persistentPreferred routes | L682–L726 | Raw/socket/persistentShell | なし |
| SSH-LIFE-013..015 interactive forwarding | L728–L772 | Raw/socket | なし |
| SSH-LIFE-017 host-key TOFU | L774–L832 | Raw/socket + verify factory | **あり** |
| SSH-LIFE-017b MD5→SHA256 移行 | L834–L869 | 同上 | **あり**（自前 setTestValues） |
| SSH-LIFE-017c 認証失敗時は更新しない | L871–L919 | 同上 | **あり**（自前 setTestValues） |
| SSH-LIFE-018 authenticated callback | L923–L949 | Raw/socket | なし |

- 全テストが各テスト内で fake を**毎回 new**（グローバル状態なし）。static は SecureStorageService のみ。
- connect ヘルパーは managed PTY group に 1 個（L953–L973）のみ存在。lifecycle の execute 系 4 件は
  ほぼ同一の `connectionFactory`/`persistentShellFactory` ボイラーを各テストに直書き（事実）。

### 1-2. `test/services/tmux/tmux_commands_test.dart`（899 行 / 94 テスト / 1 大 group + 23 トップレベル group）

- import: dart:convert、flutter_test、lib/services/tmux/commands/{arg_quoting,content_commands,input_commands,layout,lifecycle_commands,list_commands,pane_commands,session_commands,window_commands}.dart、tmux_delimiters（L1–L13）
- L18–L490: group `TmuxCommands`（**49 テスト**）— 直下に TMUX-CMD-001（L20–L44、-F コマンドの区切り検証）と
  17 個のサブ group（表示名は `TmuxCommands <sub> <test>` になる = 実測の JSON testName で確認）
- L491 以降: トップレベル group 23 個（表示名に `TmuxCommands` プレフィクスなし）

group 一覧とテスト数（実測スキャン。行範囲はコード計測）:

| group | 行 | 件 | 対応 lib ビルダー |
|---|---|---|---|
| `TmuxCommands`（直下: TMUX-CMD-001） | L20–L44 | 1 | list (sessions/windows/panes/allPanes -F) |
| └ killPane | L45–L59 | 3 | pane_commands |
| └ setHistoryLimit | L60–L68 | 1 | content_commands |
| └ selectPane | L69–L74 | 1 | pane_commands |
| └ splitWindowHorizontal | L75–L110 | 4 | pane_commands |
| └ splitWindowVertical | L111–L119 | 1 | pane_commands |
| └ killSession | L120–L135 | 2 | session_commands |
| └ killWindow | L136–L144 | 1 | window_commands |
| └ renameWindow | L145–L167 | 3 | window_commands |
| └ resizePane | L168–L183 | 2 | pane_commands |
| └ resizePaneToSize | L184–L213 | 4 | pane_commands |
| └ resizeWindow | L214–L243 | 4 | window_commands |
| └ resizeWindowAuto | L244–L264 | 2 | window_commands |
| └ windowRestoreTrap | L265–L321 | 5 | lifecycle_commands |
| └ sendKeys | L322–L345 | 3 | input_commands |
| └ chain | L346–L357 | 1 | arg_quoting (ShellCommandComposer.join) |
| └ loadBufferAndPaste | L358–L468 | 9 | input_commands |
| └ loadBufferAndPasteNoBracketed | L469–L490 | 2 | input_commands |
| `SplitDirection` | L491–L497 | 1 | layout |
| `TmuxLayout` | L498–L507 | 1 | layout |
| `listSessions` | L508–L525 | 1 | list_commands |
| `listSessionsSimple` | L526–L534 | 1 | list_commands |
| `hasSession` | L535–L550 | 2 | session_commands |
| `newSession` | L551–L578 | 3 | session_commands |
| `renameSession` | L579–L594 | 2 | session_commands |
| `listWindows` | L595–L630 | 2 | list_commands |
| `listWindowsSimple` | L631–L639 | 1 | list_commands |
| `newWindow` | L640–L666 | 3 | window_commands |
| `selectWindow` | L667–L675 | 1 | window_commands |
| `listPanes` | L676–L697 | 1 | list_commands |
| `listPanesSimple` | L698–L706 | 1 | list_commands |
| `listAllPanes` | L707–L738 | 1 | list_commands |
| `sendEnter / sendInterrupt / sendEscape` | L739–L752 | 3 | input_commands |
| `copyMode commands` | L753–L765 | 2 | input_commands |
| `cursor and mode` | L766–L781 | 2 | content_commands |
| `capturePane` | L782–L811 | 4 | content_commands |
| `version / server commands` | L812–L829 | 4 | session_commands |
| `attach / detach` | L830–L846 | 3 | session_commands |
| `selectLayout` | L847–L855 | 1 | window_commands |
| `pipe` | L856–L864 | 1 | arg_quoting (ShellCommandComposer.pipeline) |
| `Image path injection via sendKeys` | L865–L899 | 4 | input_commands |

- setUp/tearDown/定数/トップレベル関数: **なし**。唯一のローカル関数は `loadBufferAndPaste` group 内の
  `String? extractBase64(String cmd)`（L360–L363、base64 ペイロード抽出）。dart:convert はこの group のみで使用。
- テスト名に重複あり（例: "escapes pane ID with special characters" が killPane と resizePaneToSize、
  "escapes session name with spaces" が 4 group、"includes window name and start directory" が newSession/newWindow）
  → **同一ファイル内では重複名は許容されるが、分割で表示名（group パス）を保つのが条件**。

### 1-3. `test/services/herdr/herdr_adapter_test.dart`（849 行 / 45 テスト / 7 group）

| 範囲 | 種別 | 内容 |
|---|---|---|
| L1–L6 | import | flutter_test / herdr_adapter / herdr_commands / herdr_errors / connection_error / `../../helpers/fake_ssh_client.dart`（**既存 helper 再利用: FakeSshClient**） |
| L8–L75 | トップレベル const（**9 件**） | `kStatusOk` / `kStatusProtocol16` / `kStatusNotRunning` / `kSnapshotOk` / `kMutationLayoutJson` / `kResizeOk` / `kFocusNoNeighbor` / `kEdgesOk` / `kZoomOk`（実測の fixtures/実応答） |
| L76–L169 | group `HerdrAdapter.preflight` | **6 テスト**（protocol17/16/not_running/binaryなし/エラーstderr/不正JSON） |
| L170–L295 | group `HerdrAdapter.snapshot` | **7 テスト**（成功、null-exit→SshConnectionError、null-exit+出力→成功扱い、workspace_not_found、internal_error、stderr からの errorCode、不正 JSON） |
| L296–L339 | group `HerdrAdapter executable resolution` | **3 テスト**（userExecutablePath 前置、plain herdr、コンストラクタ優先） |
| L340–L447 | group `HerdrAdapter.paneRead` | **7 テスト**（既定オプション、source/lines/--raw、ANSI 判定、非0 exit、path 前置、viaPersistent、viaPersistent の target-not-found 分類） |
| L448–L643 | group `HerdrAdapter mutation (_execMutation)` | **12 テスト**（sendText×3、sendKey invalid_key、focusDirection no_neighbor、resizePane layout、edges、zoomPane、closePane not_found、splitPane、null-exit→SshConnectionError、非0 exit） |
| L644–L721 | group `HerdrAdapter tab CRUD (T12)` | **5 テスト** |
| L722–L789 | group `HerdrAdapter workspace CRUD (T12)` | **5 テスト** |
| L790–L849 | private class ×3 | `_FakeSshClientWithStderr`（L793–L806）/ `_FakeSshClientNullExit`（L809–L819）/ `_FakeSshClientNullExitWithOutput`（L823–L843）— いずれも `FakeSshClient` を継承し `execWithExitCode` を override。preflight(1)・snapshot(2)・mutation(1) で使用 |

- setUp/tearDown/タグ: なし。k* const は「本ファイル内と他ファイルで重複定義なし」（grep 実測。
  画面側 `terminal_screen_herdr_mutation_sync_test.dart` の `kFocusNoNeighborFixture` は**別名**の自前定義）。

### 1-4. `test/services/terminal/font_calculator_test.dart`（587 行 / 48 テスト / 1 group `FontCalculator`）

- import: flutter_test / font_calculator（L1–L2）。`TestWidgetsFlutterBinding.ensureInitialized()`（L5）。setUp/fake/タグテーブルなし。
- 単一 group `FontCalculator`（L7–L587）内のサブ group（**表示名 `FontCalculator <sub> <test>`**）:

| サブ group | 行 | 件 |
|---|---|---|
| calculate | L8–L180 | 11 |
| measureCharWidthRatio | L181–L195 | 2 |
| calculateTerminalWidth | L196–L240 | 3 |
| getCharDisplayWidth | L241–L344 | 10 |
| getTextDisplayWidth | L345–L380 | 6 |
| columnToCharOffset | L381–L500 | 8 |
| calculateMaxCols | L501–L521 | 2 |
| calculateMaxRows | L522–L542 | 2 |
| getCharDisplayWidthWithContext | L543–L588 | 4 |

- 依存: measureCharWidthRatio / calculateTerminalWidth / calculate / calculateMaxCols/Rows は実フォント計測
  （TestWidgetsFlutterBinding 必須）。display width 系（getCharDisplayWidth 等）は純関数。共有状態なし。

### 1-5. `test/services/tmux/tmux_parser_test.dart`（525 行 / 54 テスト / 1 group `TmuxParser`）

- L1: `// ignore_for_file: deprecated_member_use_from_same_package`（DTO エイリアス用。**保持必須**）
- import: flutter_test / layout / tmux_delimiters / tmux_models / parsers/{content_parser,output_validator,pane_parser,session_parser,tree_parser,window_parser} / `../../fixtures/tmux/tmux_parser_fixtures.dart`（**既存 shared fixture: k*Output 14 件**）
- L14–L15: トップレベル const `_fs = TmuxDelimiters.legacyField` / `_rs = ...legacyRecord`
- group 構成（表示名 `TmuxParser <sub> <test>`。直下 3 件は `TmuxParser <test>`）:

| group | 行 | 件 | 使用 fixture |
|---|---|---|---|
| （直下）TMUX-PARSER-001 ×2 / TMUX-PARSER-022 | L21–L66 | 3 | kSessionOutput, kNoServerOutput |
| parseSessions | L68–L122 | 6 | kSessionOutput ほか（L111 で `_fs` 使用） |
| parseSessionsSimple | L123–L135 | 2 | kSessionOutputSimple, kNoServerOutput |
| parseWindows | L136–L167 | 4 | kWindowOutput |
| parseWindowsSimple | L168–L178 | 1 | kWindowOutputSimple |
| parsePanes | L179–L208 | 3 | kPaneOutput |
| parsePanesSimple | L209–L219 | 1 | kPaneOutputSimple |
| parseFullTree | L220–L276 | 6 | kFullTreeOutput（L245 で `_fs`/`_rs` 使用） |
| parsePaneContent | L277–L292 | 2 | kPaneContent* |
| stripAnsiCodes | L293–L303 | 2 | （inline） |
| isServerRunning | L304–L321 | 2 | kNoServerOutput |
| extractError | L322–L348 | 4 | kNoServerOutput, kSessionNotFoundOutput |
| DTO | L349–L453 | 13 | tmux_models + layout（TmuxLayout.name） |
| normalizeDelimiters | L454–L526 | 5 | inline（L462–L486 で `_fs`/`_rs` 使用） |

- setUp/tearDown/タグ: なし。`_fs`/`_rs` は session/tree/output_validator の 3 箇所で使用。

---

## 2. 目標構成（責務・行数見積り・group/import）

全ファイルを 500 行未満にする。見積りは「現行の該当 group 行範囲 + import/ヘッダ + group ラッパー」。
**helper は `main()` を持たない**ので `flutter test` の対象にならない。

### 2-1. ssh_client_test.dart → **6 テストファイル + 1 helper**

| 新ファイル | 責務（1文） | 見積り | 含める group／テスト |
|---|---|---|---|
| `test/services/ssh/helpers/ssh_client_fakes.dart` | fake 5 種を公開化して共有（`_FakeX`→`FakeX`。本文は verbatim） | ~175 | FakeSocket / FakeInteractiveSession / FakeRawSshClient / FakePersistentShell / FakeTimer |
| `ssh_client_dto_test.dart` | DTO の toString・既定値・copyWith の純単体テスト | ~100 | group `SshClient DTOs`(7) |
| `ssh_client_disconnected_test.dart` | 未接続時・切断時のクライアント契約テスト | ~145 | group `SshClient no-connection`(7) |
| `ssh_client_connection_test.dart` | 接続・再起動・keepalive・データ経路・認証コールバックのライフサイクル | ~245 | lifecycle の 5 件（SSH-020/024, LIFE-003/004, LIFE-008..012, LIFE-013..015, LIFE-018） |
| `ssh_client_execute_test.dart` | execute のトランスポート選定・再試行・結果分離 | ~165 | lifecycle の execute×4 件 |
| `ssh_client_host_key_test.dart` | ホスト鍵 TOFU・保存形式移行・失敗時非更新 | ~220 | lifecycle の SSH-LIFE-017 / 017b / 017c（**setUp/tearDown もここへ移動**） |
| `ssh_client_managed_pty_test.dart` | hidden herdr TUI 用 ManagedPtyProcess のライフサイクル | ~110 | group `SshClient managed PTY（…）`(4)。`connectedClient()` ヘルパーは本ファイル内に維持 |

- helper は dartsssh2 / PersistentShell を import。テスト側は `import '../../helpers/ssh_client_fakes.dart';`。
- `_FakePersistentShell(super.client)` は**位置引数の super パラメータ**なので名前変更不要（動作不変）。
- 参考（担当指示）: fake client / fake socket / exec ヘルパーの共有化 = 本構成。

### 2-2. tmux_commands_test.dart → **9 テストファイル**（helper 新設なし）

lib の `commands/*.dart` と 1:1 対応。`TmuxCommands` 内サブ group は**必ず `group('TmuxCommands',…)` でラップ**し表示名を維持。L3 の ignore ヘッダは各ファイルに保持。

| 新ファイル | 責務（1文） | 見積り | 含める group（表示名を保つラップに注意） |
|---|---|---|---|
| `tmux_pane_commands_test.dart` | TmuxPaneCommands の pane 破棄・選択・分割・リサイズ | ~150 | `TmuxCommands`＞ killPane(3)/selectPane(1)/splitWindowHorizontal(4)/splitWindowVertical(1)/resizePane(2)/resizePaneToSize(4) = 15 |
| `tmux_window_commands_test.dart` | TmuxWindowCommands の window 生成・破棄・リネーム・リサイズ・レイアウト | ~155 | `TmuxCommands`＞ killWindow(1)/renameWindow(3)/resizeWindow(4)/resizeWindowAuto(2) + トップレベル newWindow(3)/selectWindow(1)/selectLayout(1) = 15 |
| `tmux_session_commands_test.dart` | TmuxSessionCommands の session 生成・破棄・改名・検出・サーバ/接続 | ~140 | `TmuxCommands`＞ killSession(2) + トップレベル hasSession(2)/newSession(3)/renameSession(2)/version ・ server(4)/attach ・ detach(3) = 16 |
| `tmux_list_commands_test.dart` | TmuxListCommands の -F/simple 一覧コマンドと区切り整合 | ~190 | `TmuxCommands`＞ TMUX-CMD-001(1) + トップレベル listSessions/listSessionsSimple/listWindows/listWindowsSimple/listPanes/listPanesSimple/listAllPanes(各1–2) = 9 |
| `tmux_content_commands_test.dart` | TmuxContentCommands の表示メッセージ・capture | ~85 | `TmuxCommands`＞ setHistoryLimit(1) + トップレベル cursor and mode(2)/capturePane(4) = 7 |
| `tmux_input_commands_test.dart` | TmuxInputCommands のキー送信・コピーモード・ペースト(base64)・画像パス注入 | ~250 | `TmuxCommands`＞ sendKeys(3)/loadBufferAndPaste(9)/loadBufferAndPasteNoBracketed(2) + トップレベル sendEnter系(3)/copyMode commands(2)/Image path injection(4) = 23（dart:convert import はここへ） |
| `tmux_lifecycle_commands_test.dart` | TmuxLifecycleCommands の window 復元 trap | ~85 | `TmuxCommands`＞ windowRestoreTrap(5) = 5 |
| `tmux_arg_quoting_test.dart` | ShellCommandComposer の join/pipeline | ~45 | `TmuxCommands`＞ chain(1) + トップレベル pipe(1) = 2 |
| `tmux_layout_test.dart` | SplitDirection/TmuxLayout 列挙 | ~40 | トップレベル SplitDirection(1)/TmuxLayout(1) = 2 |

- `extractBase64`（L360–L363）は input ファイル内でそのまま維持（同じファイルへ移動するため helper 化不要）。
- 合計 9 ファイル / 94 テスト。

### 2-3. herdr_adapter_test.dart → **4 テストファイル + 2 helper**

| 新ファイル | 責務（1文） | 見積り | 含める group |
|---|---|---|---|
| `test/services/herdr/helpers/herdr_adapter_fixtures.dart` | 実測 JSON fixture（k* 9 件）を共有化 | ~75 | kStatusOk/kStatusProtocol16/kStatusNotRunning/kSnapshotOk/kMutationLayoutJson/kResizeOk/kFocusNoNeighbor/kEdgesOk/kZoomOk |
| `test/services/herdr/helpers/herdr_adapter_fakes.dart` | FakeSshClient のエラー系派生 3 種を公開化 | ~70 | FakeSshClientWithStderr / FakeSshClientNullExit / FakeSshClientNullExitWithOutput |
| `herdr_adapter_status_test.dart` | 接続前 status 検証と実行パス解決 | ~170 | `HerdrAdapter.preflight`(6) + `HerdrAdapter executable resolution`(3) = 9 |
| `herdr_adapter_read_test.dart` | 読み取り系（snapshot・pane read）のパースとエラー分類 | ~270 | `HerdrAdapter.snapshot`(7) + `HerdrAdapter.paneRead`(7) = 14 |
| `herdr_adapter_mutation_test.dart` | mutation 系コマンドの応答解釈と理由/layout パース | ~230 | `HerdrAdapter mutation (_execMutation)`(12) = 12 |
| `herdr_adapter_crud_test.dart` | tab/workspace CRUD のコマンド構築と not_found 分類 | ~180 | `HerdrAdapter tab CRUD (T12)`(5) + `HerdrAdapter workspace CRUD (T12)`(5) = 10 |

- group 名・テスト名は現行のトップレベル group のまま（表示名不変）。既存 helper `test/helpers/fake_ssh_client.dart` を再利用（重複定義は新設しない）。k* const は 4 ファイルで共用するため fixtures helper へ。

### 2-4. font_calculator_test.dart → **2 テストファイル**（helper 新設なし）

| 新ファイル | 責務（1文） | 見積り | 含めるサブ group（`FontCalculator` ラッパー維持） |
|---|---|---|---|
| `font_calculator_sizing_test.dart` | グリッド算出（文字幅比・端末幅・最大桁/行） | ~330 | calculate(11)/measureCharWidthRatio(2)/calculateTerminalWidth(3)/calculateMaxCols(2)/calculateMaxRows(2) = 20（`TestWidgetsFlutterBinding.ensureInitialized()` 維持） |
| `font_display_width_test.dart` | 表示幅・カラム→オフセット変換の純関数 | ~320 | getCharDisplayWidth(10)/getTextDisplayWidth(6)/columnToCharOffset(8)/getCharDisplayWidthWithContext(4) = 28 |

- どちらにも `TestWidgetsFlutterBinding.ensureInitialized()` を置く（sizing 側はフォント計測で必須。両方にあっても無害・現行と同一挙動）。

### 2-5. tmux_parser_test.dart → **7 テストファイル**（shared fixture は既存を再利用）

| 新ファイル | 責務（1文） | 見積り | 含める group（`TmuxParser` ラッパー維持） |
|---|---|---|---|
| `test/services/tmux/helpers/tmux_parser_shared.dart` | `_fs`/`_rs` エイリアスを公開定数化（kLegacyField/kLegacyRecord） | ~10 | 3 ファイルで共用 |
| `tmux_session_parser_test.dart` | セッション一覧のパースと legacy 区切り互換 | ~155 | 直下 TMUX-PARSER-001 ×2(2)/parseSessions(6)/parseSessionsSimple(2) = 10 |
| `tmux_window_parser_test.dart` | ウィンドウ一覧のパース | ~75 | parseWindows(4)/parseWindowsSimple(1) = 5 |
| `tmux_pane_parser_test.dart` | ペイン一覧のパース | ~70 | parsePanes(3)/parsePanesSimple(1) = 4 |
| `tmux_tree_parser_test.dart` | list-panes -a の木構造パースとジオメトリ保存 | ~90 | parseFullTree(6) = 6 |
| `tmux_content_parser_test.dart` | ペイン内容パースと ANSI 除去 | ~60 | parsePaneContent(2)/stripAnsiCodes(2) = 4 |
| `tmux_output_validator_test.dart` | 出力検証・エラー抽出・区切り正規化 | ~160 | 直下 TMUX-PARSER-022(1)/isServerRunning(2)/extractError(4)/normalizeDelimiters(5) = 12 |
| `tmux_models_dto_test.dart` | tmux モデル DTO とレイアウト列挙 | ~135 | DTO(13) = 13（**ignore ヘッダ保持**。layout.dart import が必要） |

- fixture は既存 `test/fixtures/tmux/tmux_parser_fixtures.dart` を再利用（新規 fixture を作らない）。

### 2-6. 数値根拠まとめ

| 元 | 現行 テスト数 | 分割後 ファイル数 | 分割後 合計テスト数 | 全ファイル 500 行未満（見積り最大 ~330） |
|---|---|---|---|---|
| ssh_client_test | 30 | 6+1 helper | 30 | ✓ |
| tmux_commands_test | 94 | 9 | 94 | ✓ |
| herdr_adapter_test | 45 | 4+2 helper | 45 | ✓ |
| font_calculator_test | 48 | 2 | 48 | ✓ |
| tmux_parser_test | 54 | 7+1 helper | 54 | ✓ |
| **計** | **271** | **28 テスト + 4 helper** | **271** | ✓ |

---

## 3. 移動マッピング

### ssh_client_test.dart
- **helper 抽出（行単位）**: L17–L183 の 5 fake を `helpers/ssh_client_fakes.dart` へ（名前 `Fake〜` に公開化、本体コピー）。import の一部（dart:async / dart:typed_data / dartssh2 / persistent_shell）も helper へ移動。
- **DTOs**: L191–L266 → `ssh_client_dto_test.dart`
- **no-connection**: L267–L393 → `ssh_client_disconnected_test.dart`
- **lifecycle**: L394–L951 を 3 分割。
  - 接続系 5 件（L406–L478, L480–L543, L728–L772, L923–L949）→ `ssh_client_connection_test.dart`
  - execute×4 件（L546–L726）→ `ssh_client_execute_test.dart`
  - ホスト鍵 3 件（L774–L919）＋ **L395–L396 の setUp/tearDown も移動** → `ssh_client_host_key_test.dart`
- **managed PTY**: L952–L1032（`connectedClient` 含む）→ `ssh_client_managed_pty_test.dart`

### tmux_commands_test.dart
- group 単位で移動（表 1-2 の対応 lib ビルダー通り）。`TmuxCommands` 内サブ group はラッパー込みで移動。
- TMUX-CMD-001(L20–L44) / list* 系(L508–L738) → `tmux_list_commands_test.dart`
- 全ファイルに L3 の ignore ヘッダを保持。

### herdr_adapter_test.dart
- k* const(L8–L75) → `helpers/herdr_adapter_fixtures.dart`
- 3 fake(L790–L848) → `helpers/herdr_adapter_fakes.dart`（`_Fake〜`→`Fake〜`公開化）
- preflight(L76–L169) + executable resolution(L296–L339) → status; snapshot(L170–L295) + paneRead(L340–L447) → read; mutation(L448–L643) → mutation; tab(L644–L721) + workspace(L722–L789) → crud

### font_calculator_test.dart
- L8–L240 ＋ L501–L542 → `font_calculator_sizing_test.dart`
- L241–L500 ＋ L543–L588 → `font_display_width_test.dart`
- `group('FontCalculator')` ラッパーと `ensureInitialized` を両ファイルに維持

### tmux_parser_test.dart
- L14–L15 の `_fs`/`_rs` → `helpers/tmux_parser_shared.dart`（`kLegacyField`/`kLegacyRecord`）
- 直下 3 件: TMUX-PARSER-001×2 → session ファイル / TMUX-PARSER-022 → output_validator ファイル
- group 単位で表 2-5 の通り 7 ファイルへ。全ファイルに L1 の ignore ヘッダを保持（DTO 以外にも置いて無害）。

---

## 4. リスクと対策

| リスク | 具体像 | 対策 |
|---|---|---|
| 表示名（group パス）の変化 | tmux_commands のサブ group は `TmuxCommands` プレフィクス、font は `FontCalculator` プレフィクスが表示名に入る。ラッパーを外すと JSON の testName が変わり「実行されるテスト集合」不一致に見える | 分割先でも元の group ネストを**そのまま**維持（ラッパー込みで移動）。事実確認済み: JSON testName 実測でプレフィクス構造を検証 |
| setUp/tearDown の共有範囲 | ssh lifecycle の SecureStorageService `setTestValues`(L395–L396) は static テストフック。3 分割で実行順が変わり他テストへ波及しないか | 消費者はホスト鍵 3 件のみ（grep 実測）。setUp/tearDown ごと host_key ファイルへ移動し、他 2 ファイルには置かない。`tearDown(→ null)` で復元するため残存はしない |
| グローバル状態・実行順序依存 | 全 5 ファイルで fake は各テスト毎に new（shared mutable なし）。SecureStorage を除き static キャッシュ/タイマーは _FakeTimer のみで実時間非依存 | 分割前後で実行順が変わっても結果不変（各テスト独立）。確認コマンドで件数+全 pass を担保 |
| helper の `main()` 混入 | `test/<dir>/helpers/*.dart` が flutter test の対象になると件数が増える | 全 helper は `main()` を持たない。既存規約（test/helpers/*.dart）と同様。ディレクトリ丸ごと実行を検証計画に含める |
| private 型の名前解決 | `_FakeX` を helper に出すと他ライブラリから参照不可 | 公開名 `FakeX` へ rename（BRIEF 禁止事項の private 基底共有には該当しない）。既存 `FakeSshClient`(test/helpers/fake_ssh_client.dart) との衝突は grep 実測でなし |
| `connectedClient()` ヘルパー | managed PTY group 内のローカル関数。共用化すると lightweight フラグ有無などの差異をパラメータ化する必要がある | 本設計では**同一ファイル内に留め**（verbatim 移動）、ライフサイクル 5 件側の冗長な inline factory は「任意の追加ヘルパー」として 6-未確定点 に挙げる |
| deprecation ignore ヘッダ | tmux_commands L3 / tmux_parser L1 の `// ignore_for_file: deprecated_member_use_from_same_package` は該当 API を使う分割先（DTO 等）が無いと消え得る | 分割先全ファイルに維持（lint 挙動を元ファイルと完全一致させる。テスト意味は不変） |
| dart:convert の import 切替 | tmux_commands の base64 は input ファイルのみで使用 | input ファイルにのみ import を残す |
| フォント計測 | measureCharWidthRatio 系は TestWidgetsFlutterBinding 必須 | `ensureInitialized()` を両 font ファイルへ維持（現行 L5 と同じ配置） |
| 件数カウント誤差 | JSON レポーターは "loading" 疑似テスト 1 件を含む | カウント時は `testStart` から loading を除く（本設計の実測でも採用） |

---

## 5. 検証計画

分割は読み取り専用フェーズのため**現時点では実施しない**。実施時の流れ:

```bash
# 1) 分割前ベースライン（実測済み）
flutter test test/services/ssh/ssh_client_test.dart    --reporter=json   # 30
flutter test test/services/tmux/tmux_commands_test.dart --reporter=json   # 94
flutter test test/services/herdr/herdr_adapter_test.dart --reporter=json  # 45
flutter test test/services/terminal/font_calculator_test.dart --reporter=json # 48
flutter test test/services/tmux/tmux_parser_test.dart --reporter=json     # 54
# → JSON の testStart 数（"loading" を除く）で件数比較

# 2) 分割後: ディレクトリ全体で件数一致 + 全 pass（EXIT=0・fail 0）を確認
flutter test test/services/ssh/ --reporter=json       # 30 + 既存ファイル（ssh_client 系の新 6 本含む）
flutter test test/services/tmux/ --reporter=json      # 94(commands) + 54(parser) + 既存
flutter test test/services/herdr/ --reporter=json     # 45 + 既存
flutter test test/services/terminal/ --reporter=json  # 48 + 既存
#    ★ helper 用の単独 flutter test は行わない（main() を持たないため "No tests ran" で非 0 終了になる）。
#      helper 分が件数に載らないことは、上記「ディレクトリ全体の件数 == 既存分 + 分割分」で確認する（v2 反映: critique 2-6）。
#    ★ ssh: setUp/tearDown を外れた 9 件（ssh_client_connection_test.dart 5 + ssh_client_execute_test.dart 4）が
#      独立に pass することを確認（v2 反映: critique 2-7。managed PTY 4 件は元から setUp 対象外）。
#    判定は EXIT=0 かつ JSON testDone の失敗 0 であること（件数は fail でも同数になり得るため）。

# 3) 名前集合の不変性（機械比較）
#    JSON の test['name'] 集合を分割前後で diff（null / 追加間違いなし）
#    ※ "loading ..." エントリは除外

# 4) テスト本体行 diff（verbatim 移動検証）★v2 追加（critique §4-(g)）
#    旧 5 ファイルの各 group／テスト本体ブロックと、新ファイルの対応ブロックの行 diff が空であること。
#    許容差分は「private→public rename（_FakeX→FakeX 等）」「import の差し替え」「group ラッパーの付け外し」
#    のみとし、アサーション／期待値／タイマー値／タグは 1 バイトも変えていないことを git diff で機械検証。
#    ※ 件数・fullName 一致だけではアサーションの改変／削除を検出できないため必須。

# 5) 静的解析
flutter analyze   # make analyze

# 6) 全体（リード実施）
flutter test --exclude-tags=repro   # 総件数 2,009 不変（EXIT=0・fail 0）
```

件数不変の判定基準: 「元ファイル 1 本の件数 = 分割後該当群の合計件数」かつ「名前集合が一致」。

---

## 6. 未確定点

1. **ssh: connect/exec ヘルパーの新設範囲**: `_FakeX` 5 種の verbatim 共有と、lifecycle テストに散在する
   `connectionFactory`+`persistentShellFactory` boilerplate（execute×4 等で重複）を共通ヘルパー
   `connectFakeSshClient(...)` に集約するか。集約する場合、`lightweight: true/false`・timerFactory・
   shellFactory の差異をパラメータ化する必要があり、テスト本文の書き換え量が増える。
   **推奨: fakes の verbatim 共有のみを確定とし、connect/exec ヘルパーは実装フェーズで差分ゼロ検証後に採用**。
   （v2 反映: critique §2-7／§5 で本方針への異議なし。**本 v2 でも「差分ゼロ検証後に採用」の現方針を維持**）
2. **tmux_parser の `_fs`/`_rs`**: 3 ファイルで使用するため helper（`helpers/tmux_parser_shared.dart`）化を
   提案するが、1 行エイリアスであり各ファイルで private 再定義（2 行）でも意味は不変。
   どちらでも問題ないため実装者に委ねる（本設計は helper 案を推奨）。
3. **上記以外**: なし。テスト名・件数・タグ・メタデータの不変に影響する判断は発生しない。
# Herdrキャレット位置スナップショット取得 実装計画

## 計画メタデータ

- モード: Production（実験機能として公開するが、配布物・失敗分離・観測性まで実装対象）
- 重心: L1のユーザー向け設定・外部契約と、L2のSSH/SFTP・wire helper統合
- ベース: `origin/main` の `6cf0d9a665e85c5f4d8f99596b88d6e3091881cf`
- worktree: `/home/mox/Projects/mux-pod/.claude/worktrees/herdr-caret-snapshot`
- branch: `feature/herdr-caret-snapshot`

### L0-a: ユーザー決定事項

| 決定 | 計画への反映 |
|---|---|
| Herdr本体は改造しない | 独立したremote wire helperとして実装する |
| 動作中のHerdrへ変更を加えない | socketの既存read-only観測契約だけを利用する |
| 最新`origin/main`をベースにする | 上記SHAからworktreeを作成済み |
| 設定画面で明示的にONにした場合だけ有効 | 既定OFFの実験設定とし、OFF時は追加通信0回にする |

### L0-b: 実装判断

- snapshot方式のみを初期対象とし、常駐監視は含めない。
- protocol 17/20だけをhelperの対応対象とし、通常のHerdr互換範囲とは別に判定する。
- helper非対応環境または取得失敗時は、既存表示・末尾スクロールを維持する。

## 目的

MuxPodの設定画面で実験機能を明示的にONにした場合だけ、SSH先で動くHerdrの`herdr-client.sock`へ補助クライアントから接続し、`SemanticFrame + TerminalAttach + ObserveTerminal`で現在のキャレットを取得する。

初期実装の保証範囲は「必要時に新規接続して1フレーム取得するスナップショット方式」とする。同一socketでの連続追従は再現実験で確認できていないため対象外とする。

## 前提と非目標

- Herdr本体と動作中のHerdrプロセスは改造しない。
- 設定は既定OFF。ONでもbest-effortであり、失敗時に本文表示や入力を止めない。
- 初期実装ではTerminalAnsi解析へ自動フォールバックしない。失敗時は従来のHerdr表示（カーソル不明、初回末尾スクロール）へ戻す。
- 未対応protocolで通常のHerdr接続可否を広げない。通常機能のprotocol判定と実験的caret codecの対応判定を分離する。
- 同一接続のpush監視、高頻度100ms取得、Herdr APIへの新規メソッド追加は行わない。

## 採用アーキテクチャ

MuxPodはSSH先のUnix socketへ直接接続できないため、Herdrとは独立した小さなwire helperをMuxPod側で管理する。

```text
Settings（既定OFF）
  ↓ ONかつHerdr接続
TerminalScreen / HerdrPaneFrameReader
  ↓ TTL・single-flight・pane identity確認
HerdrCaretSnapshotReader
  ↓
HerdrCaretHelperManager
  ├─ unameでSSH先platform/archを判定
  ├─ bundled helperをSFTPでcontent-addressed cacheへ配置
  └─ ephemeral SSH commandで1回実行
        ↓
  remote helper
    ├─ herdr-client.sockへ接続
    ├─ protocol 17または20でHello
    ├─ SemanticFrame + TerminalAttach
    ├─ ObserveTerminal{paneId}
    └─ 最初のFrameData.cursorをJSONLで返して終了
```

補助バイナリはHerdrのファイルやプロセスを変更しない。配置先はSSH先の`${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/<sha256>/`とし、ファイル名・権限・SHA-256を検証する。ユーザーが機能をOFFにしたときは新規実行を止める。キャッシュ削除UIは本機能の初期スコープ外だが、保存場所を説明文とログに明記する。

## データモデル

新規`HerdrCaretSnapshot`は少なくとも以下を持つ。

- `x`, `y`: 0-based pane内座標
- `visible`: Herdrのカーソル表示状態
- `shape`: DECSCUSR相当値
- `frameWidth`, `frameHeight`: 範囲検証用
- `protocolVersion`: 17または20
- `paneId`
- `capturedAt`

「不明」と正当な`(0, 0)`を区別するためnullableなsnapshotとして扱う。範囲外座標はclampせず失敗扱いにする。`visible=false`は描画層まで保持する。

既存tmux経路の`PaneFrame.cursorX/cursorY`契約は変更せず、新しいoptionalなcaret snapshotを共通frameへ追加する。Herdr経路だけが新契約を設定し、既存tmux変換とテストをそのまま維持する。

## L1: 外部仕様

- 画面: Display > Terminalに「実験的なHerdrキャレット位置取得」スイッチを追加する。
- 永続化: 既定値はOFF。既存設定データにkeyがなくてもOFFとして読み込む。
- 通信: ONかつHerdr接続かつターミナルカーソル表示ONの場合だけ、SSH先へhelperを配置・実行する。
- 互換性: OFF、非対応OS/arch、未知protocol、timeout、破損応答では従来挙動へ戻る。
- セキュリティ: socket path、pane本文、helper標準出力の未検証内容をログへ残さない。

## L2: 変更面

| 区分 | 変更 |
|---|---|
| API/内部契約 | `HerdrCaretSnapshotReader`とnullable caret snapshotを追加。tmux既存契約は維持 |
| 画面 | 設定スイッチ、説明文、設定検索、カーソル描画・初回スクロール |
| DB/永続化 | SharedPreferencesにbooleanを1件追加。schema migrationはN/A |
| 外部API/プロセス | SSH/SFTP、remote helper、Herdr wire protocol 17/20 |
| Job/Event | バックグラウンドjobはN/A。初期表示・再接続・pane切替時のsnapshot eventを追加 |

## L3: 状態・タイミング規則

- 初期表示: Herdr target確定後に1回強制取得する。
- pane切替・SSH再接続・Herdr adapter差替え: cache epochを更新し、旧in-flight結果を破棄して1回強制取得する。
- 通常更新: 設定ONかつ`showTerminalCursor=true`の間だけ、本文更新時にTTL切れなら取得する。初期定数はTTL 500ms、timeout 1000msとし、Podman/SSH実測で妥当性を記録する。
- single-flight: 同一connection/pane/epochでは同時に1要求だけ許可する。
- resize: wire取得を強制せず、保持中snapshotを新しい表示寸法で再検証・再描画する。次の本文更新でTTL切れなら再取得する。
- 設定OFFまたはカーソル表示OFFへの遷移: cacheを無効化し、新規配置・実行を即時停止する。

## 実装フェーズ

### Phase 1: 設定フラグと実験表示

対象:

- `lib/providers/settings_provider.dart`
- `lib/screens/settings/sections/display_section.dart`
- `lib/screens/settings/search/settings_search_provider.dart`およびDisplay sectionの検索descriptor
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ja.arb`
- `test/helpers/fake_settings_notifier.dart`

作業:

1. `experimentalHerdrCaretPositionEnabled`を`AppSettings`へ追加する。既定値は`false`。
2. SharedPreferences key、load、`copyWith`、setter、保存を追加する。
3. Display > TerminalへSwitchListTileを追加する。
4. タイトルと説明に「実験的」「Herdrのみ」「best-effort」「失敗時は従来表示」「SSH先へ補助クライアントを配置」を明記する。
5. 設定検索へ日英descriptorを追加する。専用Experimentalカテゴリは新設しない。

完了条件:

- 新規インストールと既存ユーザーはOFF。
- ON/OFFが再起動後も復元される。
- OFFではhelper配置・wire接続・追加SSH commandが一切発生しない。

### Phase 2: 独立wire helper

新規候補:

- `tools/herdr-caret-helper/`（Rust CLI）
- `assets/herdr-caret-helper/<platform>-<arch>/herdr-caret-helper`
- `assets/herdr-caret-helper/manifest.json`
- helper用fixture/testディレクトリ

作業:

1. Herdrをライブラリ依存にせず、`[u32 little-endian length][bincode 2 payload]`を実装する。
2. protocol 17と20で異なる`ClientLaunchMode::TerminalAttach` tagを明示する。
3. 引数は`--socket`、`--pane`、`--protocol`、`--cols`、`--rows`、`--timeout-ms`とする。
4. 最初のWelcomeとFrameDataを検証し、cursorを単一JSON行でstdoutへ出して終了する。
5. payload上限、部分frame、EOF、timeout、Welcome error、未知variantを安全に失敗させる。
6. Linux x86_64/aarch64向け静的または互換性の明確な成果物をCIで再現ビルドし、manifestへSHA-256を記録する。
7. `pubspec.yaml`へmanifestと対応バイナリをasset登録し、CI/release手順で両成果物の存在・hash一致を検証する。Linux以外または未知archでは設定を壊さず実験機能をunsupported扱いにする。

完了条件:

- v0.7.5 fixture（protocol 17）とv0.8.2 fixture（protocol 20）を同一CLIで復号できる。
- 未知protocolでは非ゼロ終了し、JSONエラーへ機密情報やsocket pathを不用意に含めない。
- helper単体のPodman結合試験で両版からsnapshotを取得できる。

### Phase 3: SSH先への配置と実行

新規候補:

- `lib/services/herdr/caret/herdr_caret_helper_manifest.dart`
- `lib/services/herdr/caret/herdr_caret_helper_manager.dart`
- `lib/services/herdr/caret/herdr_caret_command.dart`

既存利用:

- `lib/services/ssh/ssh_client.dart`
- `lib/services/sftp/sftp_service.dart`
- `lib/services/herdr/herdr_adapter.dart`

作業:

1. ephemeral SSHで`uname -s`/`uname -m`を取得し、対応assetを選ぶ。
2. SFTPで一時名へuploadし、サイズ・SHA-256を確認後にrename、`0700`へする。共有SFTP clientはcloseしない。
3. socket pathは既存`HerdrStatus.socket`、targetは`HerdrTargetResolver`が返す`HerdrPane.id`をopaque値としてそのまま使い、workspace/tab番号から再構築しない。現行fixtureの実値は`wN:pN`であり、`herdr_models.dart`の`wN:tN:pN`コメントとは一致しないため、実値とprotocol fixtureを正とする。
4. shell引数は既存の文字列連結へ流さず、長さ・制御文字を検証したpane IDをPOSIX shell quotingする。特定のID書式をクライアント側で捏造しない。
5. helper stdoutは最大長を制限して単一JSON行だけ受理する。
6. 配置・実行はconnection単位でmemoizeし、同時要求はsingle-flightにする。

完了条件:

- helperが既に正しいhashで存在する場合は再uploadしない。
- 不明arch、書込不可、実行不可、socket権限不足、切断を分類できる。
- 失敗はcaret取得だけを無効化し、通常のHerdr pane readを継続する。

### Phase 4: snapshot取得サービスとframe合成

新規候補:

- `lib/services/herdr/caret/herdr_caret_snapshot.dart`
- `lib/services/herdr/caret/herdr_caret_snapshot_reader.dart`

変更:

- `lib/services/herdr/herdr_pane_frame_reader.dart`
- `lib/services/herdr/herdr_models.dart`またはPaneFrame定義箇所

作業:

1. `HerdrCaretSnapshotReader`をinterface化し、helper managerを注入する。
2. `HerdrPaneFrameReader.read()`で本文・geometryとcaretを合成する。
3. OFF、`showTerminalCursor=false`、unsupported protocolではreaderを呼ばない。
4. timeout 1000ms、TTL 500ms、single-flightを初期値として設け、Podman/SSH実測結果により変更する場合は定数・根拠・回帰テストを同じPRに残す。
5. pane ID、connection/adapter identity、snapshot cache epochをawait前後で照合し、stale結果を破棄する。
6. geometry失敗とcaret成功を独立して扱う。

完了条件:

- 成功時だけnullable cursor snapshotが更新される。
- timeoutや不正値で本文取得の成功結果を失わない。
- ペイン切替後に旧ペインのcursorが表示されない。

### Phase 5: 描画とスクロール

変更:

- `lib/screens/terminal/terminal_screen.dart`
- `lib/screens/terminal/widgets/ansi_text_view.dart`
- cursorを保持するprovider/model

作業:

1. `visible=false`を`AnsiTextView`へ伝え、MuxPod側カーソルを描画しない。
2. `(0,0)`を有効座標として扱い、不明値はnullableで分離する。
3. frame寸法と表示内容に対する座標変換を1か所へ集約する。
4. Herdrの初回スクロールは、設定ONかつ有効snapshot取得済みの場合のみ`scrollToCaret()`を使う。それ以外は従来どおり`scrollToBottom()`。
5. CJK全角セル、空行、行末、recent scrollbackとのオフセットを既存font/cell計算に合わせる。

完了条件:

- OFF時の見た目とスクロールは現行と同一。
- ON成功時は可視カーソル位置へスクロールし、hidden時はカーソルを描かない。
- 取得失敗・範囲外では左上へ飛ばず、末尾フォールバックになる。

### Phase 6: 観測性・ドキュメント・段階導入

作業:

1. debug logへ`disabled/unsupported/installing/ready/timeout/invalid/stale`を記録する。socket pathや画面内容はログへ出さない。
2. 設定説明と開発者向け文書へ対応版（protocol 17/20）、配置先、削除方法、既知制約を記載する。
3. 実験機能ONユーザーだけを対象にし、クラッシュや通常接続失敗へ影響しないことを確認する。
4. 連続追従は別Issueとし、Herdr側の配信挙動が実証されるまで実装しない。

## テスト計画

### Unit

- 設定: default OFF、`copyWith`、保存、reload、再起動相当の復元。
- 検索/l10n: 日英タイトル・説明、検索件数、キーワード。
- wire codec: protocol 17/20、Welcome、FrameData、visible/hidden、shape、truncated、oversize、unknown、timeout。
- helper manager: arch選択、manifest/hash、upload skip、atomic rename、permission、shell quote、single-flight。
- snapshot reader: 成功、timeout、pane消滅、unsupported protocol、不正座標、stale破棄。
- 描画: `(0,0)`、hidden、範囲外、CJK全角、空行、行末以降。

### Widget/Provider

- `test/providers/settings_provider_test.dart`
- `test/screens/settings/category_display_test.dart`
- `test/screens/settings/settings_search_test.dart`
- `test/providers/settings_search_provider_test.dart`
- `test/screens/terminal/terminal_screen_herdr_test.dart`
- `test/screens/terminal/widgets/ansi_text_view_test.dart`

確認項目:

- OFF時にwire呼出し0回。
- ON成功時だけcursor/scrollを更新。
- geometryなしでもcaret成功を反映。
- 取得中にpaneを切り替えた場合は旧結果を破棄。
- helper失敗時もpane本文表示と入力を継続。
- 既存の「Herdrは末尾へスクロール」テストはOFF既定の回帰として維持。

### Integration

- Podman内のHerdr v0.7.5/protocol 17。
- Podman内のHerdr v0.8.2/protocol 20。
- visible/hidden、`(0,0)`、画面端、pane消滅、server再起動。
- SSH + SFTP経由の初回配置、キャッシュ再利用、hash不一致再配置。
- 実機またはエミュレータでIME候補位置と初回スクロールを確認。

## 実装順とPR分割

1. PR1: 設定フラグ、UI、l10n、検索、設定テスト（動作はまだ変えない）。
2. PR2: wire helper、protocol 17/20 codec、fixture、Podman結合試験、ビルド成果物manifest。
3. PR3: SSH/SFTP helper managerとsnapshot reader。UIへは未接続でservice testまで。
4. PR4: `HerdrPaneFrameReader`、TerminalScreen、AnsiTextView統合、回帰・widget test。
5. PR5: 実機検証、観測性、ドキュメント、実験公開。

各PRはDraftで作成し、前段の契約とfixtureを後段が参照する。PR2のhelper配布方式と対応platformが確定するまでPR3以降へ進まない。

## L5: Design rationale・運用

- remote helper方式を選ぶ理由: MuxPodプロセスからSSH先Unix socketへ直接接続できず、Herdr本体の変更も禁止されているため。
- snapshot方式を選ぶ理由: 再現実験で新規接続時の最初のSemanticFrame取得は確認済みだが、同一接続の継続pushは保証できないため。
- content-addressed配置を選ぶ理由: 毎回uploadを避けつつ、古い/改変済みバイナリをhashで区別できるため。
- nullable snapshotを選ぶ理由: 未取得と正当な`(0,0)`を区別し、取得失敗で左上へ誤表示しないため。
- ロールバック: 設定をOFFにすれば追加実行は止まる。remote cacheは機能停止に影響せず、文書化した明示手順で削除可能とする。
- 監視: 状態分類だけをdebug logへ記録し、画面内容・socket path・生wire payloadは記録しない。

## 最終受け入れ条件

- 設定OFFでは追加副作用・追加通信・表示差分がない。
- 設定ONかつprotocol 17/20の対応環境で、現在の`x/y/visible/shape`を取得できる。
- Herdr本体を変更しない。
- helper失敗、未知protocol、切断、stale応答が通常のpane表示・入力を壊さない。
- hidden cursor、不明座標、正当な`(0,0)`を区別する。
- `make analyze`と`make test`が成功する。
- Podman両版の再現手順とSHA-256付きfixtureをリポジトリへ残す。

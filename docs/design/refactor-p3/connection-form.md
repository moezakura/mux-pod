# 責務ベース再設計 — connection_form_screen.dart（1391行）

- 対象: `lib/screens/connections/connection_form_screen.dart`（HEAD 1391行）
- 出発点: HEAD（a86fbdd = P2 完了状態）と作業ツリーが同一（`git diff HEAD -- lib/screens/ test/` 空・実測 0 行）
- 方針: 設計のみ・リポジトリ編集禁止。責務ベースで 500 行未満へ分解。公開 API と import パスは維持し、既存テスト差分ゼロ。
- 前提知識: P2 設計書 `docs/design/refactor-p2/providers-conn.md`・`critique.md` を読了。P2 の「compat re-export 採用（呼出元 import 変更ゼロ）」方針を踏襲する。

---

## v2 改訂サマリ（critique 対応）

`/tmp/p3-design/critique.md` §3（3.2/3.3/3.4/3.5）・§6（connection-form.md の項）の推奨修正を反映した改訂版。**必須修正なし・設計方針維持**（composition root + 6 新規ファイル・挙動不変・テスト差分ゼロ）。

1. **§5 追加 — saver への notifier 受け渡し契約**（critique 3.2）: `ConnectionSaver.save(..., {required ConnectionsNotifier notifier})` とし、`ref.read(connectionsProvider.notifier)` は **State（`_save`）が取得して渡す**。saver/tester は `ref` / `WidgetRef` を一切持たない。
2. **§3 追加 — セクション内子順序不変**（critique 3.3）: `ConnectionServerSection` = name→host→port→username→backend toggle→path→deepLinkId（Port/Username の **Row 横並び** HEAD L242-267 含む）、`ConnectionAuthSection` = authMethod toggle→password or keyDropdown。
3. **§1.4 修正 — テスト行数の実測化**（critique 3.5）: 本改訂で再実測した結果、`connection_form_screen_test.dart` は `wc -l` で **456 行**（HEAD・作業ツリーとも一致・`git diff HEAD` 空）。critique 記載の「459 行」とは差分があるため、**実測値 456 を正とし、誤差 3 行（末尾空行の数え方等の推定）を本サマリ末尾に注記**する。
4. **§7 微修正 — クローム引数マッピングの diff 検証手順の具体化**（critique 3.4）。

> 注記（行数の再実測）: `cat -A` / `wc -l` / `awk 'END{print NR}'` / `git show HEAD:...` のいずれも **456**。critique の「459」は `testWidgets(` 数（10）や他ファイルと混同された可能性（推測）。

---

## 1. 現状分析（事実）

### 1.1 ファイル構造（行番号は作業ツリー実測）

| 行範囲 | 実測行数 | 現状の責務 |
|---|---|---|
| 1-25 | 25 | import 18 本（material / riverpod / google_fonts / uuid / providers ×2 / l10n / services ×9 / theme） |
| 26-28 | 3 | **責務A: テストシーム Provider** — `connectionFormSshClientFactoryProvider = Provider<SshClient Function()>` |
| 31-41 | 11 | **責務B: Widget facade** — `ConnectionFormScreen extends ConsumerStatefulWidget`（`connectionId` / `isEditing` getter） |
| 43-1391 | 1349 | **責務C-J: `_ConnectionFormScreenState`（全フォームロジック）** |

`_ConnectionFormScreenState` 内部の内訳:

| 行範囲 | 実測行数 | 責務 |
|---|---|---|
| 44-60 | 17 | **C. フォーム状態フィールド** — `_formKey`(GlobalKey) / TextEditingController ×7 / `_authMethod` / `_selectedKeyId` / `_isSaving` / `_isTesting` / `_obscurePassword` / `_backend` |
| 62-87 | 26 | **D. 読込** — initState / `_loadExistingConnection`（`connectionsProvider.notifier.getById` → 各 field へ反映） |
| 88-99 | 12 | **E. dispose**（controller 7 本を HEAD の順序で dispose） |
| 100-141 | 42 | **F. build** — Scaffold / AppBar / Form(`_formKey`) / Stack（背景グリッド + ListView + bottom action） |
| 142-191 | 50 | **G. AppBar** — Cancel / タイトル（edit/add）/ Save ボタン（`_isSaving` spinner） |
| 192-345 | 154 | **H. 共有UI部品** — `_buildSectionHeader` / `_buildServerSection` / `_buildAuthSection` / `_buildFieldLabel` |
| 346-714 | 369 | **I. サーバー設定フィールド群** — name / host / port / username / multiplexerPath / deepLinkId の TextFormField + validator 各 |
| 715-801 | 87 | **J. backend トグル**（Tmux / Herdr） |
| 802-1051 | 250 | **K. 認証セクション群** — authMethod トグル / password 入力（obscure 切替）/ key ドロップダウン / 破損キー警告 |
| 1052-1105 | 54 | **L. bottom action** — TEST CONNECTION ボタン（`_isTesting` spinner） |
| 1116-1285 | 170 | **M. 接続テスト** — `_testConnection`（認証情報準備 / SshClient.connect / herdr preflight / tmux version 検出 / エラー分類 / SnackBar） |
| 1286-1391 | 106 | **N. 保存** — `_save`（password の SecureStorage 保存 / Connection 構築 / add/update / Navigator.pop / エラー SnackBar / developer.log 12 箇所） |

→ **単一の State に「状態・読込・UI全体・テスト・保存」の 5 系統が同居**。UI が約 1000 行（F/G/H/I/J/K/L）、処理が約 280 行（M/N）。

### 1.2 状態・オブジェクト所有権インベントリ（現状）

| 所有物 | 生成・破棄 | 更新経路 |
|---|---|---|
| `_formKey` GlobalKey | State フィールド初期化・元素破棄 | `_testConnection` / `_save` で `validate()` |
| TextEditingController ×7 | State フィールド初期化・`dispose()`（L89-95 順: name/host/port/username/password/path/deepLinkId） | TextFormField が参照、host のみ `onChanged: setState` で dot インジケータ更新 |
| `_authMethod` / `_backend` / `_obscurePassword` / `_isSaving` / `_isTesting` / `_selectedKeyId` | State フィールド初期値 | `setState` |
| `SshClient`（`_testConnection` 内ローカル） | `ref.read(factory)()` で生成・`finally sshClient?.dispose()` | — |
| `SecureStorageService()`（テスト・保存内ローカル） | 各呼び出し内で生成 | — |

### 1.3 呼出元（rg 実測）

- `lib/screens/connections/connections_screen.dart:25` — `import 'connection_form_screen.dart';` → L501 `const ConnectionFormScreen()` / L519 `ConnectionFormScreen(connectionId: connection.id)`（MaterialPageRoute）
- `lib/screens/dashboard/dashboard_screen.dart:12` — `import '../connections/connection_form_screen.dart';` → L176 `const ConnectionFormScreen()`
- `test/repro/repro_bug5_readonly_test.dart:21` — import + L67 `connectionFormSshClientFactoryProvider.overrideWith(...)` + L75 `ConnectionFormScreen(connectionId: null)`
- `test/screens/connections/connection_migration_e2e_test.dart:10` — import + L71 override + L99 `ConnectionFormScreen(connectionId: 'c1')`
- `test/screens/connections/connection_form_screen_test.dart:10` — import + L112 override + L121 `ConnectionFormScreen(connectionId: connectionId)`

→ **外部が参照する公開シンボルは `ConnectionFormScreen` と `connectionFormSshClientFactoryProvider` の2つのみ**。import パスは `screens/connections/connection_form_screen.dart` のまま維持必須。

### 1.4 既存テストが固定する挙動（実測）

**`test/screens/connections/connection_form_screen_test.dart`（testWidgets 10 本 / **456**行・実測 `wc -l`）**:
1. `creates a new connection and saves it` — TextFormField を index 順（0=name/1=host/3=username/4=path/6=password）に入力し `find.text('Save')` → fake notifier の `add` が呼ばれ name / multiplexer.backend=tmux / executablePath 保存
2. `edits an existing connection with a custom path` — 編集中に field index 4 の `controller?.text == '/old/tmux'`（読込）→ 編集 → `update` 保存
3. `shows backend toggle with Tmux and Herdr options` — `find.text('Tmux')` / `find.text('Herdr')`
4. `selecting Herdr saves a herdr connection` — toggle 選択後 add で backend=herdr / path 保存
5. `herdr connection test runs preflight...` — `connectionFormSshClientFactoryProvider` を override、`SshConnectOptions.multiplexer!.backend == herdr`、exec に `herdr status --json`、SnackBar `connTestSuccessHerdr`（'Connection successful! Herdr is available.'）
6. `herdr connection test reports protocol mismatch` — SnackBar textContaining 'protocol 16 is not supported...'
7. `rejects relative multiplexer path and accepts empty` — 相対パスで validate 失敗（`added` 空）→ 空で再保存成功（executablePath null）
8. `connection test flow shows SnackBar success` — `connTestSuccessTmux`・`SshConnectOptions` 内容・`client.disposed == true`（テスト後 dispose）
9. `connection test with unreadable key shows re-import error` — 破損鍵で `connPrivateKeyUnreadable`（'Private key is not readable'）を SnackBar 表示
10. `shows damaged key warning when broken key is selected` — `connDamagedKeyWarning` / `DropdownButtonFormField<String>` タップ→破損鍵選択

固定する構造的条件: **TextFormField の出現順（0..6）と個数**・`find.text('Save')`/`find.text('TEST CONNECTION')`/`find.text('Tmux')`/`find.text('Herdr')`/`find.text('Private Key')`・`DropdownButtonFormField<String>` が 1 つ・SnackBar 文言・バリデーション発火タイミング（Save/Test 直後）。

**`test/screens/connections/connection_migration_e2e_test.dart`（1 本 / 127行）**: 実 Provider + `UncontrolledProviderScope` で `ConnectionFormScreen(connectionId:'c1')` → field index 4 の controller.text == `/legacy/tmux`（multiplexer 経由の読込）→ 編集 → `update` → reload で永続化確認。

**`test/repro/repro_bug5_readonly_test.dart`（2 本中 1 本が対象）**: herdr テスト成功 SnackBar が `'(read-only)'` を含まない（l10n.connTestSuccessHerdr 文言）。

---

## 2. 目標構成

**方針**: `ConnectionFormScreen` を含む元ファイルを「composition root（facade）+ 単一の状態所有者」として存続させ、重い 3 系統を責務ごとの協調オブジェクトへ分離する。

| ファイル | 責務（1文） | 公開シンボル | 推定行数 |
|---|---|---|---|
| `connection_form_screen.dart`（存続・再構成） | **フォーム画面の composition root**: widget facade + 単一 State（フォーム状態の唯一の所有者、読込/テスト/保存のオーケストレーション、Scaffold/AppBar/List/セクションの配線・SnackBar 表示） | `ConnectionFormScreen`（不変）+ `export ... show connectionFormSshClientFactoryProvider` | ~290 |
| `connection_form_server_section.dart`（新規） | **サーバー設定セクションの表示**: name/host/port/username/backendトグル/multiplexerPath/deepLinkId 入力と validator（コントローラ・値・コールバックは親から受領する stateless view） | `ConnectionServerSection`（新規 public、feature 内部利用） | ~430 |
| `connection_form_auth_section.dart`（新規） | **認証セクションの表示**: authMethod トグル / password 入力 / key ドロップダウン / 破損キー警告（stateless view） | `ConnectionAuthSection`（新規 public、feature 内部利用） | ~245 |
| `connection_form_components.dart`（新規） | **フォーム入力の共有クローム**: 8 フィールド共通の InputDecoration ファクトリ・セクションヘッダ・フィールドラベルの生成（重複 8 箇所 × ~32 行を 1 箇所へ） | `ConnectionInputStyle` / `ConnectionSectionHeader` / `ConnectionFieldLabel`（新規 public、feature 内部利用） | ~90 |
| `connection_form_values.dart`（新規） | **フォーム入力値の収集モデル**: コントローラから集めた入力値の不変集約と、テスト/保存で共通の `MultiplexerConfig` 組み立て（重複 2 箇所の統合） | `ConnectionFormValues`（新規 public、feature 内部利用） | ~60 |
| `connection_form_tester.dart`（新規） | **接続テスト実行**: `connectionFormSshClientFactoryProvider` 定義・SSH 認証情報準備・connect・herdr preflight / tmux version 検出・エラー分類・文言組み立て（SnackBar 表示は呼出元） | `ConnectionTester` / `ConnectionTestResult` / `connectionFormSshClientFactoryProvider`（移動先で定義、元ファイルから re-export） | ~140 |
| `connection_form_saver.dart`（新規） | **接続保存の永続化**: password の SecureStorage 保存・Connection 構築（id/createdAt 解決）・`add`/`update` ・developer.log（メッセージ不変） | `ConnectionSaver`（新規 public、feature 内部利用） | ~120 |

**500 行未満の数値根拠**:
- `connection_form_screen.dart`: 現行 State のうち セクションUI（約1000行）と処理 M/N（280行）が他へ移るため、State には「fields 17 + 読込 26 + dispose 12 + build 42 + AppBar 50 + bottom action 54 + テスト発火/結果表示 ~55 + 保存オーケストレーション ~40 + facade 11 + import/export ~25」≈ **290 行**。
- `connection_form_server_section.dart`: サーバーセクション実測 580 行（wrapper 92 + name 54 + host 75 + port 57 + username 53 + path 77 + deeplink 53 + backendトグル 87 + label 13 + header 19）から、共通クローム抽出（6 フィールド × ~24 行 = 148 行＋ label/header 32 行）を差し引いた残余 ≈ **400-430 行**。
- `connection_form_auth_section.dart`: 実測 280 行（wrapper 30 + toggle 87 + password 54 + dropdown 91 + warning 18）から共通クローム抽出 ≈ **230-245 行**。
- 他：tester ≈ 140 / saver ≈ 120 / values ≈ 60 / components ≈ 90。**全ファイル 500 行未満を満たす**（最悪値 430）。

**依存グラフ（循環なし）**:
```
connection_form_screen.dart ──▶ server_section / auth_section / components / values / tester / saver
                                        │                    │
server_section ──▶ components / values?（backend 値のみ受領・values は不要）/ theme / l10n / key_provider?（不要）
auth_section   ──▶ components / key_provider（KeysState・isKeyDamaged）/ theme / l10n
tester ──▶ values / services（ssh_client・herdr_*・tmux_*・keychain・backend）/ l10n / riverpod（provider 定義のみ）
saver  ──▶ values / connection_provider（ConnectionsNotifier）/ keychain / backend / uuid / dart:developer
values ──▶ services/backend（BackendType・MultiplexerConfig）
components ──▶ theme / google_fonts / l10n（l10n_ext）
```
- 下位層は上位を import しない（一方向）。`connection_form_screen.dart` が `export 'connection_form_tester.dart' show connectionFormSshClientFactoryProvider;` のみ re-export（P2 compat 方針と同型）。

---

## 3. 移動マッピング（既存メンバー毎）

| 既存メンバー（行範囲） | 移動先 | 移動種別 |
|---|---|---|
| `connectionFormSshClientFactoryProvider`（26-28） | `connection_form_tester.dart` へ定義移動。`connection_form_screen.dart` は `export ... show` で再供給 | 移動（定義場所変更・シンボル不変・import パス不変） |
| `ConnectionFormScreen`（31-41） | 元ファイルに残す | 維持 |
| State フィールド群（44-60） | 元ファイル State に残す（単一状態所有者） | 維持 |
| `initState`（62-69） + `_loadExistingConnection`（70-87） | 元ファイル State に残す | 維持 |
| `dispose`（88-99） | 元ファイル State に残す（controller 破棄順は HEAD と同一） | 維持 |
| `build`（100-141） | 元ファイル State に残す（`ref.watch(keysProvider)` → AuthSection へ渡す配線を追加） | 維持（子は section に置換） |
| `_buildAppBar`（142-191） | 元ファイル State に残す | 維持 |
| `_buildSectionHeader`（192-210） | `connection_form_components.dart` → `ConnectionSectionHeader` | 移動（実装 1:1） |
| `_buildServerSection`（211-302） | `connection_form_server_section.dart` → `ConnectionServerSection.build`。**子順序（name→host→port→username→backend toggle→path→deepLinkId）を現行どおり維持**。特に Port/Username の **Row 横並び（L242-267）**と backend toggle の配置位置は widget 化で崩れやすいため保持 | 移動（props 化のみ・子順序不変） |
| `_buildAuthSection`（303-332） | `connection_form_auth_section.dart` → `ConnectionAuthSection.build`。**子順序（authMethod toggle→password / keyDropdown）を現行どおり維持**（`if (_authMethod == 'password')` の切替分岐も写経） | 移動（props 化のみ・子順序不変） |
| `_buildFieldLabel`（333-345） | `connection_form_components.dart` → `ConnectionFieldLabel` | 移動（実装 1:1） |
| `_buildNameInput`（346-399） | server_section（decoration は components の `ConnectionInputStyle` を利用） | 移動＋共通クローム化 |
| `_buildHostInput`（400-474） | server_section（`onChanged` は `onHostChanged` コールバック経由） | 移動＋共通クローム化 |
| `_buildPortInput`（475-531） | server_section | 移動＋共通クローム化 |
| `_buildUsernameInput`（532-584） | server_section | 移動＋共通クローム化 |
| `_buildMultiplexerPathInput`（585-661） | server_section | 移動＋共通クローム化 |
| `_buildDeepLinkIdInput`（662-714） | server_section | 移動＋共通クローム化 |
| `_buildBackendToggle`（715-801） | server_section（`onTap` は `onBackendChanged` コールバック経由） | 移動（props 化のみ） |
| `_buildAuthMethodToggle`（802-888） | auth_section（`onTap` は `onAuthMethodChanged` 経由） | 移動（props 化のみ） |
| `_buildPasswordInput`（889-942） | auth_section（validator の `widget.isEditing` は `isEditing` props 化、obscure は props/コールバック化） | 移動（props 化のみ） |
| `_buildKeyDropdown`（943-1033） | auth_section（`keysState`/`_selectedKeyId` は props、`onChanged` は `onKeySelected` 経由） | 移動（props 化のみ） |
| `_buildDamagedKeyWarning`（1034-1051） | auth_section | 移動（実装 1:1） |
| `_buildBottomAction`（1052-1105） | 元ファイル State に残す | 維持 |
| `_testConnection`（1116-1285） | 本体を `connection_form_tester.dart` → `ConnectionTester.run(...)` へ。SnackBar 組み立て部分は元ファイル State の `_showConnectionTestResult(...)` として残す | 分割移動（発火・結果表示は State / 実行・文言組み立ては tester） |
| `_save`（1286-1391） | 本体（password 保存・Connection 構築・add/update・developer.log）を `connection_form_saver.dart` → `ConnectionSaver.save(...)` へ。**`ConnectionsNotifier` は §5 の契約どおり State が `ref.read(connectionsProvider.notifier)` で取得して注入**（saver は ref を持たない）。`validate` ゲート / `_isSaving` setState / `Navigator.pop(true)` / 失敗 SnackBar / finally は State に残す | 分割移動 |
| 入力値の収集（新規） | State の `_collectValues()`（文言・コントローラ優先度は現行の `_testConnection` / `_save` の読み方と同一）→ `connection_form_values.dart` の `ConnectionFormValues`（`buildMultiplexer()` を集約） | 新規作成（重複トリム/組み立ての統合） |
| InputDecoration ブロック（8 箇所の重複 ~32行×8） | `connection_form_components.dart` → `ConnectionInputStyle.decoration(...)` | 新規抽出（パラメータマッピングは HEAD と 1:1） |

**注意**: 移動は写経ベース。validator の文言（`context.l10n.*`）、hint、prefix/suffix icon、styled のフォント・色・角丸・padding、SnackBar の色（DesignColors.error/success/warning）と duration（4s/3s）はすべて現行値を維持する。

**注意（v2 追加・子順序不変）**: TextFormField の index 0..6 を固定する既存テスト（connection_form_screen_test L140-147 他）のため、**セクション内部の子の順序も**現行どおり維持する。`ConnectionServerSection` = name→host→**Row（port｜username）**→backend toggle→path→deepLinkId、`ConnectionAuthSection` = authMethod toggle→（password または keyDropdown の切替）。ListView の子を `[ConnectionServerSection, ConnectionAuthSection]` にした**だけ**では順序は保証されない点に注意し、各セクション内の配置を写経する。

---

## 4. 公開 API 維持表

| シンボル | 現状 | 維持方法 | 根拠（rg 実測） |
|---|---|---|---|
| `ConnectionFormScreen`（widget・コンストラクタ `{super.key, this.connectionId}`・`isEditing` getter） | public | 元ファイル「`lib/screens/connections/connection_form_screen.dart`」にそのまま残す | connections_screen L501/519・dashboard L176・テスト3ファイル |
| `connectionFormSshClientFactoryProvider` | public（`Provider<SshClient Function()>`） | 定義は tester へ移すが、元ファイルで `export 'connection_form_tester.dart' show connectionFormSshClientFactoryProvider;` し**同一パスから供給**（P2 の compat re-export と同型） | テスト3ファイルの `overrideWith` / 現行 L1157 の `ref.read` |
| import パス `screens/connections/connection_form_screen.dart` | 維持 | 上記2シンボルを同一パスから供給し続ける | 呼出元5ファイルの import 行 |
| `_ConnectionFormScreenState` ほか private メンバー | private | 外部参照なし（rg で確認）→ 自由に再編可 | 全リポジトリ grep |

新規 public シンボル（`ConnectionServerSection` / `ConnectionAuthSection` / `ConnectionTester` / `ConnectionTestResult` / `ConnectionSaver` / `ConnectionFormValues` / `ConnectionInputStyle` / `ConnectionSectionHeader` / `ConnectionFieldLabel`）は **feature 内部利用が前提**で、外部の import 変更は発生しない。テストが直接 import するのは従来どおり `connection_form_screen.dart` の 2 シンボルのみ。

**継承前提（テスト fake）**: `connection_form_screen_test.dart` の `_FakeConnectionsNotifier extends ConnectionsNotifier`（build/getById/add/update を @override）は **connection_provider 層の話であり本対象の影響外**（P2 で維持担保済み）。`_TestSshClient extends FakeSshClient` は services/ssh の話で影響なし。本対象の分割で `ConnectionFormScreen` 自体の継承は発生しない。

---

## 5. 状態所有権表（破棄責任の単一化）

| 状態 / オブジェクト | 所有者 | 生成 | 破棄 | 更新通知経路 |
|---|---|---|---|---|
| `_formKey` GlobalKey | `_ConnectionFormScreenState` | State フィールド初期化 | Form 要素破棄 | `_testConnection`/`_save` 冒頭の `validate()` |
| TextEditingController ×7 | `_ConnectionFormScreenState` | State フィールド初期化（`_portController` のみ `text:'22'`） | **State.dispose() で HEAD と同一順**（name→host→port→username→password→path→deepLink L89-95） | TextFormField が参照。host のみ `onHostChanged` → State setState |
| `_authMethod` / `_backend` / `_selectedKeyId` / `_obscurePassword` / `_isSaving` / `_isTesting` | `_ConnectionFormScreenState` | フィールド初期値（HEAD と同一） | State 破棄とともに | setState（セクションからのコールバック経由） |
| `ConnectionServerSection` / `ConnectionAuthSection` | なし（stateless view。状態を持たない） | State.build 毎 | なし | 親 setState で再構築（TextFormField の element は位置基準で維持されるため controller/フォーカスは保持） |
| `SecureStorageService`（テスト・保存内） | 各処理のローカル（`ConnectionTester`/`ConnectionSaver` 内で生成） | 呼び出し内 | なし（合成前のラッパー） | 戻り値のみ |
| `SshClient`（テスト内） | `_testConnection` の try ブロック | `ref.read(connectionFormSshClientFactoryProvider)()` | **`finally { await sshClient?.dispose(); }`（HEAD L1240 と同一）** | tester から返却（テストが `disposed == true` を検証） |
| `ConnectionsNotifier`（saver が使用） | **呼出側 State（`_save`）** が取得・注入（saver は notifier を保持しない） | `_save` 内で `ref.read(connectionsProvider.notifier)` を取得し `ConnectionSaver.save(..., notifier: notifier)` に渡す（HEAD L1336/L1343 の add/update と同一タイミング） | 破棄しない（Provider 層が管理） | add/update/getById の戻り値／スロー |
| `SshClient Function()` factory | 呼出側 State（`_testConnection`）が `ref.read(connectionFormSshClientFactoryProvider)` で取得し `ConnectionTester` へ注入 | `_testConnection` 内（HEAD L1157 と同一タイミング） | 破棄しない | tester の戻り値 |
| `HerdrAdapter` / `CommandRequest` / `TmuxVersionInfo.parse` 結果 | `ConnectionTester.run` 内ローカル | 実行内 | なし | 結果値（`ConnectionTestResult`） |

**契約（v2 追加・critique 3.2 対応）**: `ConnectionSaver.save(..., {required ConnectionsNotifier notifier})` — **ref の解決はすべて State 側**で行う（`ConnectionSaver` / `ConnectionTester` は `ref` も `WidgetRef` も持たない）。`SshClient Function()` の取得も同様に State の `_testConnection` が `ref.read` し、tester の `run(..., sshClientFactory: ...)` に渡す。これにより: ①Riverpod ライフサイクルと処理ロジックが分離され単体テストで実 notifier を直接渡せる ②テストの `_FakeConnectionsNotifier`（notifier 自体を override）と overrideWith 経由の fake client 差し込みが現行どおり機能する。

**ライフサイクル順序（HEAD との一致保証）**: 本 State は didUpdateWidget を持たない（HEAD も持たない・実測 L43-1391 に該当メソッドなし）。`initState（→ isEditing なら読込）→ build → 各 setState 再構築 → dispose（写経順）`を維持。async 後の `mounted` ガードは `_testConnection`/`_save` の State 側に残す（HEAD 実測: L1243 / L1365・L1376・L1385）。

---

## 6. リスクと対策

| # | リスク | 検出手段（既存テスト） | 対策 |
|---|---|---|---|
| 1 | **TextFormField の順序・個数が変わる**（テストは index 0..6 を固定） | connection_form_screen_test 全10本 | ListView の子を `[ConnectionServerSection, ConnectionAuthSection]` とし、フィールドの出現順を HEAD と同一（name/host/port/username/path/deepLinkId / password）に保つ。セクションの子配置も写経 |
| 2 | **validator の文言・付け忘れ** | テスト7（相対パス拒否）/ 全保存・テストフロー | validator は section 内 TextFormField に HEAD の実装をそのまま移設（`context.l10n`・`isEditing` は props 化して維持） |
| 3 | **SnackBar 文言・色・duration の変化** | テスト5/6/8/9・repro_bug5 | 文言組み立てを tester の結果オブジェクトへ、表示（色 success/warning/error・4s/3s）を State `_showConnectionTestResult` へ、HEAD の分岐（error→成功/警告・herdr/tmux）を忠実に移設 |
| 4 | **`connectionFormSshClientFactoryProvider` の経路断絶** | テスト5/6/8/9・migration・repro（overrideWith で差し込み） | 定義を tester に移しつつ元ファイルから re-export。`_testConnection` は `ref.read(connectionFormSshClientFactoryProvider)` を State から行い tester へ注入（現行 L1157 と同一タイミング） |
| 5 | **読込（migration E2E）で controller を正しく満たさない** | connection_migration_e2e_test（field4 の `/legacy/tmux`） | `_loadExistingConnection` は State に残し写経。`getById` 参照・null ガード・multiplexer.executablePath / deepLinkId 反映を不変に |
| 6 | **追加時の password 必須・編集時の任意（`widget.isEditing`）が壊れる** | テスト1/4（パスワード入力） | AuthSection に `isEditing` props を渡し、validator の条件を写経 |
| 7 | **controller 破棄順・二重 dispose** | なし（ランタイムエラー） | dispose は State 単一所有・HEAD 順序を維持（§5） |
| 8 | **async ギャップ中の破棄**（但し `mounted` ガード・dispose 順序） | なし | `_testConnection` / `_save` の `if (mounted)` を State 側に残す（HEAD L1229/L1378 等） |
| 9 | **IME/フォーカス・リビルド範囲** | なし | コントローラを同一インスタンスのまま props で受領するため element 位置基準で状態保持。フォーム言語切り替え時の再構築も HEAD と同一（ListView+Form 構成不変） |
| 10 | **共通クローム抽出による見た目の変化**（border 角丸12・filled・contentPadding 等） | なし（テストは decoration 非検証） | `ConnectionInputStyle.decoration` の引数→InputDecoration のマッピングを HEAD と 1:1 で定義し、実装レビューで差分確認。visual regression は既存テストでは検出不可のため、写経レビューを必須に |
| 11 | **`initialValue` セマンティクス**（DropdownButtonFormField） | テスト9/10（破損鍵選択） | `initialValue: _selectedKeyId` の使い方を変更しない。authMethod 切替時の再生成（`if (_authMethod == 'key')`）も HEAD どおり |
| 12 | **過分割（P2 critique の再発）** | — | 6新規ファイルはすべて「複数フィールドのセクション」「共有クローム」「テスト/保存の処理」という実質的な責務。単一用途のマイクロウィジェット化はしない（bottom action / AppBar / 破損キー警告は State・セクション内に残す） |

---

## 7. 検証計画

実装フェーズで以下を順に実行（＝設計の受け入れ基準）:

1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze`（未使用 import、export の競合が出ないこと）
3. `flutter test test/screens/connections/`（connection_form 系 3 本 + connections_screen 系 4 本。期待値不変＝テスト変更ゼロで pass）
4. `flutter test --exclude-tags=repro`（全体回帰）
5. `flutter test test/repro/repro_bug5_readonly_test.dart`（repro タグ分は別途）
6. `git diff HEAD -- test/` が **空** であること（テストファイル非変更の機械検証）
7. `dart tool/generate_herdr_protocols.dart --check`（生成物未変更の確認）
8. 写経レビュー: §3 の移動マッピング表と §6-10 のクローム引数マッピングを実装レビューの必須項目とする。`ConnectionInputStyle.decoration` の引数→InputDecoration のマッピングは、HEAD の 8 フィールドの decoration 実装ブロック（L346-399 / 400-474 / 475-531 / 532-584 / 585-661 / 662-714 / 889-942 / 943-1033 内）と新実装を diff で照合し視覚等価性を確認する（例: `diff <(git show HEAD:lib/screens/connections/connection_form_screen.dart | sed -n '400,474p') <(新実装ファイル)` 相当の差分レビュー）

**新規テスト（追加可・回帰用の提案）**:
- `ConnectionSaver`: fake notifier に対する add/update・password 保存条件・`createdAt`（編集時は既存値）/ `MultiplexerConfig` 組み立ての単体テスト
- `ConnectionTester`: fake ssh client で tmux 成功 / herdr preflight 成功 / protocol mismatch / 認証エラーの結果マッピング単体テスト（`connectionFormSshClientFactoryProvider` シームを利用）

---

## 8. 未確定点

- **なし**（決定事項は以下のとおり）
  - `connectionFormSshClientFactoryProvider` の定義を tester へ移し、元ファイルの re-export で供給する（P2 compat 方針から導出）
  - AppBar / bottom action / `_loadExistingConnection` は composition root である State の配線責務として残す（P2 critique「残り物の寄せ集め」回避のため、各残存メンバーが「状態所有・配線・表示面」に属することを §5/§3 で明示）
  - `part` / `mixin` / private 基底クラスは不使用。全分割は「公開クラス（feature 内部利用）への合成」で行う
  - **付記（v2）**: テスト行数は実測 `wc -l` = 456（critique の「459」と不一致のため実測値に統一。§1.4・v2 サマリ参照）
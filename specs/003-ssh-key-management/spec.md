# Feature Specification: SSH鍵管理機能

**Feature Branch**: `003-ssh-key-management`
**Created**: 2026-01-11
**Status**: Draft
**Input**: User description: "SSH鍵管理機能を実装してください。lib/screens/keys/以下のTODOコメントを解決: key_generate_screen.dart(鍵生成)、key_import_screen.dart(ファイルピッカーとインポート)、keys_screen.dart(画面遷移)。lib/services/keychain/secure_storage.dartを活用。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - SSH鍵の生成 (Priority: P1)

ユーザーがアプリ内で新しいSSH鍵ペア（Ed25519またはRSA）を生成し、セキュアストレージに保存できる。

**Why this priority**: SSH接続の基本機能であり、鍵がなければ認証できないため最優先。

**Independent Test**: 鍵生成画面で名前と鍵タイプを選択し「Generate」をタップすると、新しい鍵が作成され一覧に表示される。

**Acceptance Scenarios**:

1. **Given** 鍵一覧画面にいる, **When** FABをタップし「Generate New Key」を選択, **Then** 鍵生成画面に遷移する
2. **Given** 鍵生成画面にいる, **When** 名前「MyKey」を入力しEd25519を選択して「Generate」をタップ, **Then** 鍵が生成され一覧画面に戻り「Key generated successfully」と表示される
3. **Given** 鍵生成画面にいる, **When** RSAを選択, **Then** 鍵サイズ（2048/3072/4096ビット）を選択できるスライダーが表示される
4. **Given** 鍵生成画面にいる, **When** 名前を空のまま「Generate」をタップ, **Then** バリデーションエラー「Please enter a name」が表示される

---

### User Story 2 - SSH鍵のインポート (Priority: P1)

ユーザーが既存の秘密鍵ファイルを選択、またはPEM形式でペーストしてインポートできる。

**Why this priority**: 既存の鍵を使いたいユーザーにとって必須の機能。

**Independent Test**: インポート画面でファイルを選択またはPEMをペーストし「Import」をタップすると、鍵が保存され一覧に表示される。

**Acceptance Scenarios**:

1. **Given** 鍵一覧画面にいる, **When** FABをタップし「Import Key」を選択, **Then** 鍵インポート画面に遷移する
2. **Given** 鍵インポート画面にいる, **When** 「Select Private Key File」をタップ, **Then** ファイルピッカーが開き秘密鍵ファイルを選択できる
3. **Given** 秘密鍵ファイルを選択済み, **When** 名前を入力して「Import」をタップ, **Then** 鍵がインポートされ一覧画面に戻り「Key imported successfully」と表示される
4. **Given** 鍵インポート画面にいる, **When** PEM形式の秘密鍵をテキストフィールドにペースト, **Then** ファイル選択なしでもインポート可能になる
5. **Given** パスフレーズ付き秘密鍵を選択, **When** 正しいパスフレーズを入力してインポート, **Then** 鍵が正常にインポートされる
6. **Given** パスフレーズ付き秘密鍵を選択, **When** 誤ったパスフレーズでインポート, **Then** エラーメッセージが表示される

---

### User Story 3 - SSH鍵一覧の表示 (Priority: P2)

ユーザーが保存済みの全SSH鍵を一覧で確認できる。

**Why this priority**: 鍵の管理・選択に必要だが、生成/インポートより後でも機能する。

**Independent Test**: 鍵一覧画面を開くと、保存済みの鍵が名前・タイプと共にリスト表示される。

**Acceptance Scenarios**:

1. **Given** SSH鍵が1つ以上保存されている, **When** 鍵一覧画面を開く, **Then** 各鍵の名前と鍵タイプが表示される
2. **Given** SSH鍵が0個, **When** 鍵一覧画面を開く, **Then** 「No SSH keys yet」と表示される

---

### User Story 4 - SSH鍵の削除 (Priority: P3)

ユーザーが不要になったSSH鍵を削除できる。

**Why this priority**: 運用上必要だが、初期リリースでは優先度低。

**Independent Test**: 鍵をスワイプまたは長押しで削除メニューを表示し、確認後に削除される。

**Acceptance Scenarios**:

1. **Given** 鍵一覧に鍵がある, **When** 鍵を長押しまたはスワイプして削除を選択, **Then** 確認ダイアログが表示される
2. **Given** 削除確認ダイアログが表示されている, **When** 「Delete」をタップ, **Then** 鍵が削除され一覧から消える

---

### Edge Cases

- 鍵生成中にアプリがバックグラウンドに移動した場合 → 生成完了後に結果を反映、エラー時は次回表示時に通知
- 不正な形式の秘密鍵ファイルをインポートしようとした場合 → バリデーションエラーを表示
- ストレージ容量不足時の鍵保存 → 適切なエラーメッセージを表示
- 同じ名前の鍵が既に存在する場合 → 重複を許可（IDで区別）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムはEd25519形式のSSH鍵ペアを生成できなければならない
- **FR-002**: システムはRSA形式のSSH鍵ペア（2048/3072/4096ビット）を生成できなければならない
- **FR-003**: ユーザーは生成する鍵に任意の名前を付けられなければならない
- **FR-004**: システムはファイルピッカーを通じて秘密鍵ファイルをインポートできなければならない
- **FR-005**: ユーザーはPEM形式の秘密鍵を直接テキスト入力でインポートできなければならない
- **FR-006**: システムはパスフレーズ付き秘密鍵のインポートをサポートしなければならない
- **FR-007**: システムは秘密鍵をデバイスの暗号化ストレージに保存しなければならない
- **FR-008**: ユーザーは保存済みの全SSH鍵を一覧で確認できなければならない
- **FR-009**: ユーザーは保存済みのSSH鍵を削除できなければならない
- **FR-010**: 鍵一覧画面から鍵生成画面・インポート画面へ遷移できなければならない
- **FR-011**: システムは不正な形式の秘密鍵インポートを拒否し、エラーメッセージを表示しなければならない

### Key Entities

- **SSHKey**: SSH鍵を表すエンティティ。ID、名前、鍵タイプ（ed25519/rsa）、作成日時、公開鍵フィンガープリントを持つ。秘密鍵本体はセキュアストレージに別途保存される。
- **KeyType**: 鍵の種類（Ed25519、RSA-2048、RSA-3072、RSA-4096）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ユーザーは30秒以内にEd25519鍵を生成できる
- **SC-002**: ユーザーは60秒以内にRSA-4096鍵を生成できる
- **SC-003**: ユーザーは1分以内にファイルから秘密鍵をインポートできる
- **SC-004**: 鍵一覧画面は保存済み全鍵を2秒以内に表示する
- **SC-005**: 生成・インポートした鍵でSSH接続認証が成功する

## Assumptions

- デバイスはAndroid 6.0以上を使用している（flutter_secure_storageの要件）
- ファイルピッカーはfile_pickerパッケージを使用する
- SSH鍵生成にはdartssh2またはpointycstleパッケージを使用する
- 鍵のメタデータ（名前、タイプ、作成日時）はshared_preferencesに保存し、秘密鍵本体のみflutter_secure_storageに保存する

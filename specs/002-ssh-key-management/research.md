# Research: SSH鍵管理機能

**Feature**: 002-ssh-key-management
**Date**: 2026-01-10

## 1. ED25519鍵生成 in React Native

### Decision
`react-native-ssh-sftp` ライブラリのネイティブ機能を使用してED25519鍵を生成する。

### Rationale
- `react-native-ssh-sftp` は既にプロジェクトの依存関係に含まれている
- ネイティブコードでの鍵生成により、JavaScript層での暗号化ライブラリ依存を回避
- Android Keystore との連携が容易

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| `tweetnacl-js` | Pure JS は遅く、セキュアでない。Secure Enclave連携不可 |
| `expo-crypto` | ED25519鍵生成をサポートしていない |
| `react-native-crypto` | メンテナンス停止、Expo SDK 52非対応 |

### Implementation Notes
- `react-native-ssh-sftp` の `SSHClient.generateKey()` メソッドを使用
- 生成された鍵はOpenSSH形式で出力される
- 公開鍵はauthorized_keys形式で提供

## 2. 秘密鍵のセキュアストレージ

### Decision
`expo-secure-store` を使用し、Android Keystore でハードウェアバックアップされたキーチェーンに保存する。

### Rationale
- `expo-secure-store` は既に `auth.ts` でパスワード保存に使用されている
- Android Keystore は Secure Enclave 相当のハードウェアセキュリティを提供
- 生体認証との統合が容易（`expo-local-authentication` 連携）

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| AsyncStorage + 暗号化 | ソフトウェア暗号化のみ、ハードウェアバックアップなし |
| react-native-keychain | expo-secure-store と機能重複、追加依存不要 |

### Implementation Notes
- 秘密鍵は `muxpod-ssh-key-{keyId}` キーで保存
- メタデータ（名前、タイプ、フィンガープリント）は別途 AsyncStorage に保存
- 鍵アクセス時に生体認証を要求する設定をサポート

## 3. 鍵インポートとパスフレーズ処理

### Decision
PEM/OpenSSH形式の秘密鍵をパースし、パスフレーズ付き鍵は復号してからセキュアストレージに保存する。

### Rationale
- ユーザーは既存の鍵を持っている可能性が高い
- 一度復号してセキュアストレージに保存することで、接続時の UX を向上
- パスフレーズを毎回入力する必要がない

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| パスフレーズ付きで保存 | 接続のたびにパスフレーズ入力が必要、UX低下 |
| パスフレーズを別途保存 | セキュリティリスク増大、複雑化 |

### Implementation Notes
- `sshpk` または類似ライブラリで鍵パース
- サポート形式: PEM (RSA, ECDSA, ED25519), OpenSSH
- インポート時にパスフレーズ入力ダイアログを表示
- 復号後、平文の秘密鍵をセキュアストレージに保存

## 4. 既知ホスト管理

### Decision
AsyncStorage に既知ホストを JSON 形式で保存し、接続時にフィンガープリントを検証する。

### Rationale
- 既知ホストはセキュリティ情報だが、暗号化保存は不要（公開情報）
- AsyncStorage で十分なパフォーマンス
- known_hosts ファイル形式との互換性を維持

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| SecureStore | 容量制限あり、公開情報に過剰 |
| SQLite | 追加依存、この規模では過剰 |

### Implementation Notes
- ホスト識別子: `{host}:{port}`
- 保存形式: `{ identifier, keyType, fingerprint, addedAt, lastVerifiedAt }`
- 検証失敗時は警告ダイアログを表示し、ユーザーに選択肢を提示

## 5. ファイルインポートUI

### Decision
`expo-document-picker` を使用してデバイスまたはクラウドストレージから秘密鍵ファイルを選択する。

### Rationale
- Expo SDK に含まれる公式ライブラリ
- iCloud, Google Drive, Dropbox などのクラウドストレージに対応
- プラットフォーム標準のファイルピッカー UI を提供

### Implementation Notes
- MIME タイプ: `*/*` または `text/plain`
- 選択後、ファイル内容を読み込み、鍵形式を検証
- 無効な形式の場合はエラーメッセージを表示

## 6. 生体認証

### Decision
`expo-local-authentication` を使用し、鍵使用時に生体認証を要求する。

### Rationale
- Expo SDK の公式ライブラリ
- 指紋認証、顔認証の両方に対応
- SecureStore のアクセス制御と連携可能

### Implementation Notes
- 認証は鍵アクセス時（接続開始時）に要求
- 認証失敗時はパスワード認証へのフォールバックを提供しない（セキュリティ優先）
- ユーザー設定で生体認証の有効/無効を切替可能

## Technology Stack Summary

| Concern | Technology | Status |
|---------|------------|--------|
| 鍵生成 | react-native-ssh-sftp | 既存依存 |
| セキュアストレージ | expo-secure-store | 既存依存 |
| メタデータ保存 | AsyncStorage | 既存依存 |
| ファイルピッカー | expo-document-picker | 追加必要 |
| 生体認証 | expo-local-authentication | 追加必要 |

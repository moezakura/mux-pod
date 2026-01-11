# Quickstart: SSH鍵管理機能

**Feature**: 003-ssh-key-management
**Date**: 2026-01-11

## Prerequisites

- Flutter SDK 3.24+
- Android Studio / VS Code with Flutter extension
- Android実機またはエミュレータ（API 23+）

## Setup

### 1. 依存関係の追加

```bash
flutter pub add file_picker cryptography pointycastle
```

または `pubspec.yaml` に直接追加:

```yaml
dependencies:
  file_picker: ^8.0.3
  cryptography: ^2.7.0
  pointycastle: ^3.9.1
```

### 2. Android権限（すでに設定済みの場合は不要）

`android/app/src/main/AndroidManifest.xml`:

```xml
<!-- ファイルピッカー用（Android 10以下の場合） -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

### 3. 依存関係のインストール

```bash
flutter pub get
```

## Quick Verification

### 鍵生成のテスト

```dart
import 'package:cryptography/cryptography.dart';

void main() async {
  // Ed25519鍵生成テスト
  final ed25519 = Ed25519();
  final keyPair = await ed25519.newKeyPair();

  final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  print('Private key length: ${privateKeyBytes.length}'); // 32
  print('Public key length: ${publicKey.bytes.length}');   // 32
}
```

### ファイルピッカーのテスト

```dart
import 'package:file_picker/file_picker.dart';

void pickFile() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles();

  if (result != null) {
    print('Selected: ${result.files.single.name}');
  } else {
    print('Cancelled');
  }
}
```

## Development Flow

### 1. SshKeyServiceの実装

```bash
# 新規ファイル作成
touch lib/services/keychain/ssh_key_service.dart
```

### 2. 画面のTODO解決

```bash
# 修正対象ファイル
lib/screens/keys/keys_screen.dart       # 画面遷移追加
lib/screens/keys/key_generate_screen.dart  # 鍵生成ロジック
lib/screens/keys/key_import_screen.dart # ファイルピッカー・インポート
```

### 3. テスト実行

```bash
flutter test test/services/keychain/ssh_key_service_test.dart
flutter test test/screens/keys/
```

### 4. 動作確認

```bash
flutter run -d android
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/services/keychain/ssh_key_service.dart` | 鍵生成・パースロジック（新規） |
| `lib/services/keychain/secure_storage.dart` | セキュアストレージ（既存） |
| `lib/providers/key_provider.dart` | 状態管理（既存） |
| `lib/screens/keys/keys_screen.dart` | 鍵一覧画面（修正） |
| `lib/screens/keys/key_generate_screen.dart` | 鍵生成画面（修正） |
| `lib/screens/keys/key_import_screen.dart` | インポート画面（修正） |

## Troubleshooting

### file_pickerがクラッシュする

Android 11以上でスコープストレージの問題が発生する場合:

```xml
<!-- AndroidManifest.xml -->
<application
    android:requestLegacyExternalStorage="true"
    ...>
```

### cryptographyパッケージのビルドエラー

```bash
flutter clean
flutter pub get
```

### RSA鍵生成が遅い

RSA-4096は計算量が多いため、UIスレッドをブロックしないよう`compute()`を使用:

```dart
final keyPair = await compute(_generateRsaKeyPair, bits);
```

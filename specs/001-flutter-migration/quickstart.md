# Quickstart: Flutter Migration

**Feature**: 001-flutter-migration
**Date**: 2026-01-11

## Prerequisites

- Flutter SDK 3.24+
- Dart SDK 3.x
- Android Studio / VS Code with Flutter extension
- Android device or emulator (API 21+)

## Project Setup

### 1. Create Flutter Project

```bash
# リポジトリルートで実行
cd /home/mox/Projects/mux-pod

# Flutter プロジェクト作成
flutter create --org com.muxpod --project-name muxpod flutter

# プロジェクトディレクトリへ移動
cd flutter
```

### 2. Configure pubspec.yaml

```yaml
name: muxpod
description: SSH tmux client for Android
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter

  # SSH
  dartssh2: ^2.13.0

  # Terminal
  xterm: ^4.0.0

  # State Management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0

  # Navigation
  go_router: ^14.0.0

  # Storage
  flutter_secure_storage: ^9.2.0
  shared_preferences: ^2.3.0

  # Model
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0

  # Utils
  uuid: ^4.5.0
  collection: ^1.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

  # Codegen
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0

  # Testing
  mockito: ^5.4.0
  build_runner: ^2.4.0

flutter:
  uses-material-design: true

  fonts:
    - family: JetBrainsMono
      fonts:
        - asset: assets/fonts/JetBrainsMono-Regular.ttf
    - family: HackGen
      fonts:
        - asset: assets/fonts/HackGen-Regular.ttf
```

### 3. Configure analysis_options.yaml

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - prefer_const_constructors
    - prefer_const_declarations
    - prefer_final_fields
    - prefer_final_locals
    - avoid_print: true
    - require_trailing_commas: true
```

### 4. Create Directory Structure

```bash
mkdir -p lib/{router,models,providers,services/{ssh,tmux,terminal,keychain,notification},screens/{connections,terminal,keys,notifications,settings},widgets,theme}
mkdir -p test/{unit/{services,providers},widget/screens,integration}
mkdir -p integration_test
mkdir -p assets/fonts
```

### 5. Install Dependencies

```bash
flutter pub get
```

## Development Workflow

### Code Generation (Freezed/Riverpod)

```bash
# 一回実行
dart run build_runner build --delete-conflicting-outputs

# 監視モード（開発中推奨）
dart run build_runner watch --delete-conflicting-outputs
```

### Run Tests

```bash
# Unit/Widget tests
flutter test

# Integration tests
flutter test integration_test

# With coverage
flutter test --coverage
```

### Lint & Analyze

```bash
# 静的解析
dart analyze

# フォーマット
dart format lib test
```

### Build & Run

```bash
# 開発ビルド（デバッグ）
flutter run

# リリースビルド
flutter build apk --release

# APK 分割ビルド（サイズ最適化）
flutter build apk --split-per-abi
```

## Key Implementation Patterns

### 1. SSH Connection with Riverpod

```dart
// lib/providers/ssh_provider.dart
@riverpod
class SshConnectionController extends _$SshConnectionController {
  @override
  FutureOr<SshShellSession?> build(String connectionId) async {
    ref.onDispose(() async {
      // クリーンアップ
      await state.value?.close();
    });
    return null; // 初期状態は未接続
  }

  Future<void> connect() async {
    state = const AsyncValue.loading();
    try {
      final connection = await ref.read(connectionProvider(connectionId).future);
      final session = await _sshService.connect(connection);
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
```

### 2. Terminal Integration

```dart
// lib/screens/terminal/terminal_screen.dart
class TerminalScreen extends ConsumerStatefulWidget {
  final String connectionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late final Terminal terminal;

  @override
  void initState() {
    super.initState();
    terminal = Terminal();
  }

  @override
  Widget build(BuildContext context) {
    final sshState = ref.watch(sshConnectionControllerProvider(widget.connectionId));

    return sshState.when(
      data: (session) => TerminalView(
        terminal: terminal,
        autoResize: true,
        onResize: (w, h) => session?.resize(w, h),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
```

### 3. Secure Storage

```dart
// lib/services/keychain/secure_storage.dart
class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> savePrivateKey(String keyId, String pem) async {
    await _storage.write(key: 'ssh_private_key_$keyId', value: pem);
  }

  Future<String?> getPrivateKey(String keyId) async {
    return await _storage.read(key: 'ssh_private_key_$keyId');
  }
}
```

## Testing Strategy

### Unit Tests (services/)

```dart
// test/unit/services/tmux_commands_test.dart
void main() {
  group('TmuxCommands', () {
    late MockSshService mockSsh;
    late TmuxService tmuxService;

    setUp(() {
      mockSsh = MockSshService();
      tmuxService = TmuxServiceImpl(mockSsh);
    });

    test('listSessions parses output correctly', () async {
      when(mockSsh.exec(any, 'tmux list-sessions ...'))
          .thenAnswer((_) async => SshExecResult(
                stdout: 'main\t1234567890\t1\t2\n',
                stderr: '',
                exitCode: 0,
              ));

      final sessions = await tmuxService.listSessions('conn-1');

      expect(sessions, hasLength(1));
      expect(sessions.first.name, equals('main'));
    });
  });
}
```

### Widget Tests (screens/)

```dart
// test/widget/screens/connections_screen_test.dart
void main() {
  testWidgets('ConnectionsScreen displays connection list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith((ref) => [
            Connection(id: '1', name: 'Test', host: 'example.com', ...),
          ]),
        ],
        child: const MaterialApp(home: ConnectionsScreen()),
      ),
    );

    expect(find.text('Test'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });
}
```

## Common Commands

| Task | Command |
|------|---------|
| Run app | `flutter run` |
| Hot reload | `r` (in terminal) |
| Hot restart | `R` (in terminal) |
| Run tests | `flutter test` |
| Generate code | `dart run build_runner build` |
| Analyze | `dart analyze` |
| Format | `dart format lib test` |
| Build APK | `flutter build apk` |
| Clean | `flutter clean` |

## Troubleshooting

### Build Runner Conflicts

```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Flutter SDK Version Issues

```bash
flutter channel stable
flutter upgrade
```

### Android Build Issues

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

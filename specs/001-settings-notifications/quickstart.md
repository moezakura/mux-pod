# Quickstart: Settings and Notifications Implementation

**Feature**: 001-settings-notifications
**Date**: 2026-01-11

## Prerequisites

- Flutter 3.24+
- 既存のMuxPodプロジェクトがビルド可能な状態

## Setup

### 1. 依存関係追加

```bash
flutter pub add url_launcher
```

### 2. 実行確認

```bash
flutter analyze
flutter test
flutter run
```

## Implementation Overview

### 修正対象ファイル

| File | Changes |
|------|---------|
| `lib/main.dart` | MyAppをConsumerWidgetに変更、テーマを動的に |
| `lib/screens/settings/settings_screen.dart` | TODOコメント解決（6箇所） |
| `lib/screens/notifications/notification_rules_screen.dart` | ルール保存実装、リスト表示 |
| `lib/providers/settings_provider.dart` | themeMode対応（オプション） |

### 新規作成ファイル

| File | Purpose |
|------|---------|
| `lib/widgets/dialogs/font_size_dialog.dart` | フォントサイズ選択ダイアログ |
| `lib/widgets/dialogs/font_family_dialog.dart` | フォントファミリー選択ダイアログ |
| `lib/widgets/dialogs/theme_dialog.dart` | テーマ選択ダイアログ |

## Key Implementation Points

### 1. SettingsScreen TODOs

```dart
// Font Size Dialog (line 24)
onTap: () async {
  final size = await showDialog<double>(
    context: context,
    builder: (context) => FontSizeDialog(
      currentSize: ref.read(settingsProvider).fontSize,
    ),
  );
  if (size != null) {
    ref.read(settingsProvider.notifier).setFontSize(size);
  }
}

// Haptic Feedback Toggle (line 43)
value: ref.watch(settingsProvider).enableVibration,
onChanged: (value) {
  ref.read(settingsProvider.notifier).setEnableVibration(value);
}

// External URL (line 93)
onTap: () async {
  final uri = Uri.parse('https://github.com/muxpod');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

### 2. NotificationRulesScreen

```dart
// Watch notification rules
final state = ref.watch(notificationProvider);

// Build rule list
ListView.builder(
  itemCount: state.rules.length,
  itemBuilder: (context, index) {
    final rule = state.rules[index];
    return Dismissible(
      key: Key(rule.id),
      onDismissed: (_) => ref.read(notificationProvider.notifier).removeRule(rule.id),
      child: ListTile(
        title: Text(rule.name),
        subtitle: Text(rule.pattern),
        trailing: Switch(
          value: rule.enabled,
          onChanged: (_) => ref.read(notificationProvider.notifier).toggleRule(rule.id),
        ),
      ),
    );
  },
)

// Save rule in dialog
void _save() {
  if (_formKey.currentState!.validate()) {
    final rule = NotificationRule(
      id: widget.ruleId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      pattern: _patternController.text,
      isRegex: _isRegex,
      vibrate: _vibrate,
    );
    if (widget.ruleId != null) {
      ref.read(notificationProvider.notifier).updateRule(rule);
    } else {
      ref.read(notificationProvider.notifier).addRule(rule);
    }
    Navigator.pop(context);
  }
}
```

### 3. Dynamic Theme in main.dart

```dart
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'MuxPod',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
```

## Testing

### Run All Tests

```bash
flutter test
```

### Run Specific Test

```bash
flutter test test/screens/settings_screen_test.dart
flutter test test/screens/notification_rules_screen_test.dart
```

## Verification Checklist

- [ ] Font Size変更が保存され、再起動後も保持される
- [ ] Font Family変更が保存され、再起動後も保持される
- [ ] Haptic Feedbackトグルが保存される
- [ ] Keep Screen Onトグルが保存される
- [ ] Theme変更がアプリ全体に即座に反映される
- [ ] Source CodeタップでGitHubが外部ブラウザで開く
- [ ] 通知ルールが作成・保存される
- [ ] 通知ルールが編集・削除できる
- [ ] ルールの有効/無効切り替えが保存される
- [ ] アプリ再起動後もルールが保持される

## Common Issues

### url_launcher not working

Android: `AndroidManifest.xml` にintent-filter追加が必要な場合あり

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="https" />
  </intent>
</queries>
```

### SharedPreferences not persisting

テスト環境ではモックが必要:

```dart
SharedPreferences.setMockInitialValues({});
```

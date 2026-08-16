// inventory: TEST-SETTINGS-PROVIDER-000
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SettingsNotifier.build() は fire-and-forget で _loadSettings() を開始するため、
/// 素の ProviderContainer テストでは dispose 前に非同期完了が保証されない。
/// testWidgets + pumpAndSettle で確実に完了させてから検証する。
// inventory: TEST-SETTINGS-PROVIDER-001
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings scrollSendInput / invertScrollSendDirection', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<ProviderContainer> pumpContainer(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      // read で build() をトリガーしてから、fire-and-forget の _loadSettings を
      // pumpAndSettle で確実に完了させる（read は同期でデフォルトを返すため、
      // この直後の read は更新後の state を返す）
      container.read(settingsProvider);
      await tester.pumpAndSettle();
      return container;
    }

    // inventory: TEST-SETTINGS-PROVIDER-002
    testWidgets('defaults are wheel and false', (tester) async {
      final container = await pumpContainer(tester);

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'wheel');
      expect(settings.invertScrollSendDirection, isFalse);
    });

    // inventory: TEST-SETTINGS-PROVIDER-003
    testWidgets('loads persisted values from prefs', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_scroll_send_input': 'key',
        'settings_invert_scroll_send_direction': true,
      });
      final container = await pumpContainer(tester);

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'key');
      expect(settings.invertScrollSendDirection, isTrue);
    });

    // inventory: TEST-SETTINGS-PROVIDER-004
    testWidgets('setScrollSendInput updates state and persists', (tester) async {
      final container = await pumpContainer(tester);

      await container.read(settingsProvider.notifier).setScrollSendInput('key');
      await tester.pump();

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_scroll_send_input'), 'key');
    });

    // inventory: TEST-SETTINGS-PROVIDER-005
    testWidgets('setInvertScrollSendDirection updates state and persists', (tester) async {
      final container = await pumpContainer(tester);

      await container.read(settingsProvider.notifier).setInvertScrollSendDirection(true);
      await tester.pump();

      final settings = container.read(settingsProvider);
      expect(settings.invertScrollSendDirection, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_invert_scroll_send_direction'), isTrue);
    });

    // inventory: TEST-SETTINGS-PROVIDER-006
    test('copyWith preserves other settings', () {
      const base = AppSettings();
      final updated = base.copyWith(
        scrollSendInput: 'key',
        invertScrollSendDirection: true,
      );
      expect(updated.scrollSendInput, 'key');
      expect(updated.invertScrollSendDirection, isTrue);
      expect(updated.invertPaneNavigation, isFalse);
      expect(updated.darkMode, isTrue);
    });
  });

  group('wheelSendVerifiedProvider', () {
    // inventory: TEST-SETTINGS-PROVIDER-007
    test('defaults to true (verified via Phase 0 B1/B2)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(wheelSendVerifiedProvider), isTrue);
    });
  });
}

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/sections/background_power_section.dart';
import '../../helpers/fake_settings_notifier.dart';

void main() {
  testWidgets('three network settings can independently change modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(settings: const AppSettings()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: BackgroundPowerSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final network in NetworkKind.values) {
      final tile = find.byKey(ValueKey('background-${network.name}'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-connection')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BackgroundPowerSection)),
      );
      expect(
        container.read(settingsProvider).backgroundModeFor(network),
        BackgroundMode.connection,
      );
    }
  });
}

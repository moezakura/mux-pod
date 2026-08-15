import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/keys/keys_screen.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues({});
  });

  Future<void> pumpKeysScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KeysScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows damaged keys dialog when a damaged key exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'k1',
          'name': 'damaged-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    // 秘密鍵が保存されていない → 破損鍵として検出される
    SecureStorageService.setTestValues({});

    await pumpKeysScreen(tester);

    expect(find.text('破損した鍵が見つかりました'), findsOneWidget);
    expect(find.text('damaged-key'), findsWidgets);
  });

  testWidgets('does not show damaged keys dialog when all keys are healthy',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'k1',
          'name': 'healthy-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    SecureStorageService.setTestValues({'privatekey_k1': 'PRIVATE_KEY'});

    await pumpKeysScreen(tester);

    expect(find.text('破損した鍵が見つかりました'), findsNothing);
  });

  testWidgets('deleting a damaged key from the dialog removes it',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'k1',
          'name': 'damaged-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    SecureStorageService.setTestValues({});

    await pumpKeysScreen(tester);

    // 破損鍵を選択して削除
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選択した鍵を削除'));
    await tester.pumpAndSettle();

    // モーダルが閉じ、一覧から削除される
    expect(find.text('破損した鍵が見つかりました'), findsNothing);
    expect(find.text('damaged-key'), findsNothing);
    expect(SecureStorageService().getPrivateKey('k1'), completion(isNull));
  });

  testWidgets('keeping a damaged key from the dialog leaves it in the list',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'k1',
          'name': 'damaged-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    SecureStorageService.setTestValues({});

    await pumpKeysScreen(tester);

    // そのままにする → モーダルが閉じ、鍵は一覧に残る
    await tester.tap(find.text('そのままにする'));
    await tester.pumpAndSettle();

    expect(find.text('破損した鍵が見つかりました'), findsNothing);
    expect(find.text('damaged-key'), findsWidgets);
  });
}

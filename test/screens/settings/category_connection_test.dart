import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

import 'test_helpers.dart';

void main() {
  group('Connection category', () {
    testWidgets('displays Image Transfer settings', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Connection & Transfer');

      // グループ見出し（toUpperCase 廃止後の新 l10n 文言）
      await scrollUntilFound(tester, find.text('Image Transfer'));
      expect(find.text('Image Transfer'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Remote Path'));
      expect(find.text('Remote Path'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Output Format'));
      expect(find.text('Output Format'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Path Format'));
      expect(find.text('Path Format'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Auto Enter'));
      expect(find.text('Auto Enter'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Bracketed Paste'));
      expect(find.text('Bracketed Paste'), findsOneWidget);
    });

    testWidgets('Clear SSH Host Keys clears stored fingerprints after confirm', (
      tester,
    ) async {
      SecureStorageService.setTestValues({
        'hostkey_192.168.1.3_22_ssh-ed25519': 'aa:bb:cc',
        'password_conn1': 'secret',
      });
      addTearDown(() => SecureStorageService.setTestValues(null));

      await buildSettingsApp(tester);
      await openCategory(tester, 'Connection & Transfer');

      await scrollUntilFound(tester, find.text('Clear SSH Host Keys'));
      await tester.tap(find.text('Clear SSH Host Keys'));
      await tester.pumpAndSettle();

      // 確認ダイアログ
      expect(find.text('Clear SSH host keys?'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      final service = SecureStorageService();
      expect(
        await service.getHostKeyFingerprint('192.168.1.3', 22, 'ssh-ed25519'),
        isNull,
      );
      // 認証情報は残る
      expect(await service.getPassword('conn1'), 'secret');
      expect(find.text('SSH host keys cleared'), findsOneWidget);
    });

    testWidgets('Clear SSH Host Keys cancel keeps fingerprints', (
      tester,
    ) async {
      SecureStorageService.setTestValues({
        'hostkey_192.168.1.3_22_ssh-ed25519': 'aa:bb:cc',
      });
      addTearDown(() => SecureStorageService.setTestValues(null));

      await buildSettingsApp(tester);
      await openCategory(tester, 'Connection & Transfer');

      await scrollUntilFound(tester, find.text('Clear SSH Host Keys'));
      await tester.tap(find.text('Clear SSH Host Keys'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        await SecureStorageService().getHostKeyFingerprint(
          '192.168.1.3',
          22,
          'ssh-ed25519',
        ),
        'aa:bb:cc',
      );
    });
  });
}
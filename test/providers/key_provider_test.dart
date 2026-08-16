import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/key_provider.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SshKeyMeta', () {
    test('defaults isAvailable to true when missing from json', () {
      final meta = SshKeyMeta.fromJson({
        'id': 'k1',
        'name': 'test',
        'type': 'ed25519',
        'createdAt': '2026-01-01T00:00:00.000',
      });

      expect(meta.isAvailable, isTrue);
    });

    test('reads isAvailable from json', () {
      final meta = SshKeyMeta.fromJson({
        'id': 'k1',
        'name': 'test',
        'type': 'ed25519',
        'createdAt': '2026-01-01T00:00:00.000',
        'isAvailable': false,
      });

      expect(meta.isAvailable, isFalse);
    });

    test('round-trips isAvailable through toJson/fromJson', () {
      final meta = SshKeyMeta(
        id: 'k1',
        name: 'test',
        type: 'ed25519',
        createdAt: DateTime(2026, 1, 1),
        isAvailable: false,
      );

      final restored = SshKeyMeta.fromJson(meta.toJson());
      expect(restored.isAvailable, isFalse);
    });
  });

  group('KeysNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SecureStorageService.setTestValues({});
    });

    test('add sorts keys by createdAt descending (newest first)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(keysProvider.notifier);
      // 非同期ロードを明示的に完了させてから操作する
      await notifier.reload();

      final older = SshKeyMeta(
        id: 'a',
        name: 'older',
        type: 'ed25519',
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = SshKeyMeta(
        id: 'b',
        name: 'newer',
        type: 'ed25519',
        createdAt: DateTime(2026, 1, 2),
      );

      // 古い鍵を先に追加 → 新しい鍵を後から追加
      await notifier.add(older);
      await notifier.add(newer);

      final keys = container.read(keysProvider).keys;
      expect(
        keys.map((k) => k.id).toList(),
        ['b', 'a'],
        reason: 'add 直後に createdAt 降順（新しい鍵が先頭）でなければならない',
      );
    });

    test('marks key as damaged when private key is missing', () async {
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
      // 秘密鍵が保存されていない → 復号不能（破損鍵）と判定される
      SecureStorageService.setTestValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(keysProvider.notifier);
      // 非同期ロードを明示的に完了させてから確認する
      await notifier.reload();

      final state = container.read(keysProvider);
      expect(state.keys, hasLength(1));
      expect(state.keys.single.isAvailable, isFalse);
      expect(state.damagedKeys, hasLength(1));
      expect(state.damagedKeys.single.id, 'k1');
    });

    test('does not mark key as damaged when private key exists', () async {
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

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(keysProvider.notifier);
      // 非同期ロードを明示的に完了させてから確認する
      await notifier.reload();

      final state = container.read(keysProvider);
      expect(state.keys.single.isAvailable, isTrue);
      expect(state.damagedKeys, isEmpty);
    });

    test(
      'recovers isAvailable to true when private key becomes readable',
      () async {
        // 保存済み JSON に isAvailable=false が残っていても、読み取り成功なら true に戻す
        SharedPreferences.setMockInitialValues({
          'ssh_keys_meta': jsonEncode([
            {
              'id': 'k1',
              'name': 'recovered-key',
              'type': 'ed25519',
              'createdAt': '2026-01-01T00:00:00.000',
              'isAvailable': false,
            },
          ]),
        });
        SecureStorageService.setTestValues({'privatekey_k1': 'PRIVATE_KEY'});

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(keysProvider.notifier);
        await notifier.reload();

        final state = container.read(keysProvider);
        expect(state.keys.single.isAvailable, isTrue);
        expect(state.damagedKeys, isEmpty);
      },
    );
  });
}

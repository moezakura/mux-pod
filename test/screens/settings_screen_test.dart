import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

Widget _buildApp({TargetPlatform? platform}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // CJK ModeトグルのiOS限定表示を検証するためプラットフォームを上書きできる
      theme: platform == null ? null : ThemeData(platform: platform),
      home: const SettingsScreen(),
    ),
  );
}

/// Scrolls until [finder] is visible in the first Scrollable of the tree.
///
/// 探索前にスクロール位置を先頭へ戻すことで、直前の `scrollUntilVisible` が
/// 最後に呼ぶ `Scrollable.ensureVisible` による位置ずれ（探索対象が画面上方へ
/// 通り過ぎてレイジービルドから外れる）に依存しない検証にする。
///
/// P1-C2 のセクション再編（表示順変更）後は、スリバーのレイジービルドにより
/// ターゲットが「ビルドされただけで画面外」の状態で停止しうるため、
/// 最後に `Scrollable.ensureVisible` で画面内へ完全に収めてから返す。
Future<void> scrollUntilFound(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  if (position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  await Scrollable.ensureVisible(
    finder.evaluate().single,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
}

void main() {
  group('SettingsScreen', () {
    testWidgets('displays Settings title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays Adjust Mode setting', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Adjust Mode'), findsOneWidget);
      expect(find.text('Auto Fit'), findsOneWidget);
    });

    testWidgets('displays Haptic Feedback toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Haptic Feedback is in the Behavior section - may need scroll
      await scrollUntilFound(tester, find.text('Haptic Feedback'));
      expect(find.text('Haptic Feedback'), findsOneWidget);
    });

    testWidgets('displays Keep Screen On toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      expect(find.text('Keep Screen On'), findsOneWidget);
    });

    testWidgets('behavior toggles are interactive', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Haptic Feedback'));
      final hapticSwitch = find.ancestor(
        of: find.text('Haptic Feedback'),
        matching: find.byType(SwitchListTile),
      );
      expect(hapticSwitch, findsOneWidget);

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      final keepScreenSwitch = find.ancestor(
        of: find.text('Keep Screen On'),
        matching: find.byType(SwitchListTile),
      );
      expect(keepScreenSwitch, findsOneWidget);
    });

    testWidgets('displays Source Code link', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Source Code'));
      expect(find.text('Source Code'), findsOneWidget);
      expect(find.text('github.com/moezakura/mux-pod'), findsOneWidget);
    });

    testWidgets('displays Image Transfer settings', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Image Transfer section header (rendered in uppercase by _SectionHeader)
      await scrollUntilFound(tester, find.text('IMAGE TRANSFER'));
      expect(find.text('IMAGE TRANSFER'), findsOneWidget);

      // Individual settings
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

    // inventory: TEST-SETTINGS-UI-001
    testWidgets('displays Scroll Send Input setting', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(find.text('Scroll Send Input'), findsOneWidget);
      expect(find.text('Wheel (mouse scroll)'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-002
    testWidgets('Scroll Send Input picker selects Key', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むため、このテストのみモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      await tester.tap(find.text('Scroll Send Input'));
      await tester.pumpAndSettle();

      // SimpleDialog 内の選択肢（RadioListTile は不使用・ListTile 方式）
      expect(find.text('Wheel'), findsOneWidget);
      expect(find.text('Key'), findsOneWidget);

      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      expect(find.text('Key (Page Up / Page Down)'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-003
    testWidgets('hides fallback note by default (wheel verified)', (
      tester,
    ) async {
      // wheelSendVerifiedProvider はデフォルト true（Phase 0 実測 B1/B2 PASS 済み）
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(
        find.text('Wheel send is unverified; falling back to key send.'),
        findsNothing,
      );
    });

    // inventory: TEST-SETTINGS-UI-004
    testWidgets('displays fallback note when wheel is unverified', (
      tester,
    ) async {
      // riverpod 3.x では Override 型は公開 export されないため、
      // テスト側で ProviderScope を直接構築して override する。
      // l10n 化に伴い delegates/supportedLocales も必要（_buildApp と同構成）。
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wheelSendVerifiedProvider.overrideWith((ref) => false)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to the note itself: asserting on a sibling below the tile makes
      // the test depend on where the section lands in the list.
      await scrollUntilFound(
        tester,
        find.text('Wheel send is unverified; falling back to key send.'),
      );
      expect(
        find.text('Wheel send is unverified; falling back to key send.'),
        findsOneWidget,
      );
    });

    // inventory: TEST-SETTINGS-UI-005
    testWidgets('displays Invert Scroll Send Direction toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Invert Scroll Send Direction'));
      expect(find.text('Invert Scroll Send Direction'), findsOneWidget);

      final tile = find.ancestor(
        of: find.text('Invert Scroll Send Direction'),
        matching: find.byType(SwitchListTile),
      );
      expect(tile, findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-007
    testWidgets('displays Fit terminal on Scroll Send toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Fit terminal on Scroll Send'));
      expect(find.text('Fit terminal on Scroll Send'), findsOneWidget);

      final tile = find.ancestor(
        of: find.text('Fit terminal on Scroll Send'),
        matching: find.byType(SwitchListTile),
      );
      expect(tile, findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-008
    testWidgets('fit toggle is interactive', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むため、このテストのみモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Fit terminal on Scroll Send'));
      final tile = find.ancestor(
        of: find.text('Fit terminal on Scroll Send'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      // タップ中心が画面内に収まるよう完全に画面内へスクロール
      // （上流のBehaviorセクションにタイルが追加されると下段が押し下げられ、
      //   scrollUntilFound 後のタイル中心が画面外になり得るため）
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    // inventory: TEST-SETTINGS-UI-006
    testWidgets('invert toggle is interactive', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むため、このテストのみモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Invert Scroll Send Direction'));
      final tile = find.ancestor(
        of: find.text('Invert Scroll Send Direction'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    testWidgets('displays Language setting and opens the picker', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Language is in the Appearance section - may need scroll
      await scrollUntilFound(tester, find.text('Language'));
      expect(find.text('Language'), findsOneWidget);
      // 初期値は 'system' なので説明付き表記が表示される
      expect(find.text('System (follow device)'), findsOneWidget);

      // タップ位置が画面端にならないよう完全に画面内へスクロール
      await tester.ensureVisible(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      // 3択ダイアログ
      expect(find.text('System'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('CJK Mode toggle is hidden on non-iOS platforms', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.text('CJK Mode'), findsNothing);
    });

    testWidgets('CJK Mode toggle is shown and interactive on iOS', (
      tester,
    ) async {
      // setter が _saveSetting で SharedPreferences へ書き込むためモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('CJK Mode'));
      final tile = find.ancestor(
        of: find.text('CJK Mode'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      // タップ中心が画面内に収まるよう完全に画面内へスクロール
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_cjk_mode'), isTrue);
    });

    testWidgets(
      'Keep Keyboard on Enter toggle is shown and interactive (Android)',
      (tester) async {
        // setter が _saveSetting で SharedPreferences へ書き込むためモックする
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        // 全プラットフォーム表示（ソフトキーボードはiOS/Android双方にある問題）
        await scrollUntilFound(
          tester,
          find.text('Keep Keyboard Open on Enter'),
        );
        final tile = find.ancestor(
          of: find.text('Keep Keyboard Open on Enter'),
          matching: find.byType(SwitchListTile),
        );
        expect(tile, findsOneWidget);
        // デフォルトは OFF
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);

        // タップ中心が画面内に収まるよう完全に画面内へスクロール
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(tile).value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('settings_keep_keyboard_on_enter'), isTrue);
      },
    );

    testWidgets(
      'Keep Keyboard on Enter toggle is shown and interactive (iOS)',
      (tester) async {
        // setter が _saveSetting で SharedPreferences へ書き込むためモックする
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(_buildApp(platform: TargetPlatform.iOS));
        await tester.pumpAndSettle();

        await scrollUntilFound(
          tester,
          find.text('Keep Keyboard Open on Enter'),
        );
        final tile = find.ancestor(
          of: find.text('Keep Keyboard Open on Enter'),
          matching: find.byType(SwitchListTile),
        );
        expect(tile, findsOneWidget);
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);

        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(tile).value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('settings_keep_keyboard_on_enter'), isTrue);
      },
    );

    testWidgets(
      'Clear SSH Host Keys clears stored fingerprints after confirm',
      (tester) async {
        SecureStorageService.setTestValues({
          'hostkey_192.168.1.3_22_ssh-ed25519': 'aa:bb:cc',
          'password_conn1': 'secret',
        });
        addTearDown(() => SecureStorageService.setTestValues(null));

        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        await scrollUntilFound(tester, find.text('Clear SSH Host Keys'));
        await tester.ensureVisible(find.text('Clear SSH Host Keys'));
        await tester.pumpAndSettle();
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
        expect(find.text('Cleared 1 saved host key'), findsOneWidget);
      },
    );

    testWidgets('Clear SSH Host Keys cancel keeps fingerprints', (
      tester,
    ) async {
      SecureStorageService.setTestValues({
        'hostkey_192.168.1.3_22_ssh-ed25519': 'aa:bb:cc',
      });
      addTearDown(() => SecureStorageService.setTestValues(null));

      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Clear SSH Host Keys'));
      await tester.ensureVisible(find.text('Clear SSH Host Keys'));
      await tester.pumpAndSettle();
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

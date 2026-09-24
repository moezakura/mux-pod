import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_persistence.dart';
import 'package:flutter_muxpod/providers/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsPersistence キー互換', () {
    test('41 キーの文字列が既存定義と完全互換である', () {
      // テストはキー文字列直書きで検証するため、ここで互換を固定する。
      expect(SettingsPersistence.darkModeKey, 'settings_dark_mode');
      expect(SettingsPersistence.fontSizeKey, 'settings_font_size');
      expect(SettingsPersistence.fontFamilyKey, 'settings_font_family');
      expect(SettingsPersistence.biometricKey, 'settings_biometric_auth');
      expect(SettingsPersistence.notificationsKey, 'settings_notifications');
      expect(SettingsPersistence.keepScreenOnKey, 'settings_keep_screen_on');
      expect(
        SettingsPersistence.screenOrientationKey,
        'settings_screen_orientation',
      );
      expect(SettingsPersistence.refreshRateKey, 'settings_refresh_rate');
      expect(SettingsPersistence.scrollbackKey, 'settings_scrollback');
      expect(SettingsPersistence.minFontSizeKey, 'settings_min_font_size');
      expect(SettingsPersistence.zoomFactorKey, 'settings_zoom_factor');
      expect(SettingsPersistence.adjustModeKey, 'settings_adjust_mode');
      expect(
        SettingsPersistence.directInputEnabledKey,
        'settings_direct_input_enabled',
      );
      expect(SettingsPersistence.cjkModeKey, 'settings_cjk_mode');
      expect(
        SettingsPersistence.keepKeyboardOnEnterKey,
        'settings_keep_keyboard_on_enter',
      );
      expect(
        SettingsPersistence.showTerminalCursorKey,
        'settings_show_terminal_cursor',
      );
      expect(
        SettingsPersistence.openLinksDirectlyKey,
        'settings_open_links_directly',
      );
      expect(
        SettingsPersistence.experimentalHerdrCaretPositionEnabledKey,
        'settings_experimental_herdr_caret_position_enabled',
      );
      expect(SettingsPersistence.invertPaneNavKey, 'settings_invert_pane_nav');
      expect(
        SettingsPersistence.scrollSendInputKey,
        'settings_scroll_send_input',
      );
      expect(
        SettingsPersistence.invertScrollSendDirectionKey,
        'settings_invert_scroll_send_direction',
      );
      expect(
        SettingsPersistence.autoFitZoomOnScrollSendKey,
        'settings_auto_fit_zoom_on_scroll_send',
      );
      expect(SettingsPersistence.languageKey, 'settings_language');
      expect(
        SettingsPersistence.imageRemotePathKey,
        'settings_image_remote_path',
      );
      expect(
        SettingsPersistence.imageOutputFormatKey,
        'settings_image_output_format',
      );
      expect(
        SettingsPersistence.imageJpegQualityKey,
        'settings_image_jpeg_quality',
      );
      expect(
        SettingsPersistence.imageResizePresetKey,
        'settings_image_resize_preset',
      );
      expect(SettingsPersistence.imageMaxWidthKey, 'settings_image_max_width');
      expect(
        SettingsPersistence.imageMaxHeightKey,
        'settings_image_max_height',
      );
      expect(
        SettingsPersistence.imagePathFormatKey,
        'settings_image_path_format',
      );
      expect(
        SettingsPersistence.imageAutoEnterKey,
        'settings_image_auto_enter',
      );
      expect(
        SettingsPersistence.imageBracketedPasteKey,
        'settings_image_bracketed_paste',
      );
      expect(
        SettingsPersistence.showKeyOverlayKey,
        'settings_show_key_overlay',
      );
      expect(
        SettingsPersistence.keyOverlayModifierKey,
        'settings_key_overlay_modifier',
      );
      expect(
        SettingsPersistence.keyOverlaySpecialKey,
        'settings_key_overlay_special',
      );
      expect(
        SettingsPersistence.keyOverlayArrowKey,
        'settings_key_overlay_arrow',
      );
      expect(
        SettingsPersistence.keyOverlayShortcutKey,
        'settings_key_overlay_shortcut',
      );
      expect(
        SettingsPersistence.keyOverlayPositionKey,
        'settings_key_overlay_position',
      );
      expect(
        SettingsPersistence.uploadConflictPolicyKey,
        'settings_upload_conflict_policy',
      );
      expect(
        SettingsPersistence.uploadConcurrencyKey,
        'settings_upload_concurrency',
      );
      expect(SettingsPersistence.uploadChunkKbKey, 'settings_upload_chunk_kb');
    });
  });

  group('SettingsPersistence.load', () {
    test('未保存時はデフォルト値で構築する', () async {
      final persistence = SettingsPersistence();

      final settings = await persistence.load();

      // 代表フィールドのデフォルト値（AppSettings は == 非実装のため個別比較）。
      expect(settings.darkMode, true);
      expect(settings.fontSize, 14.0);
      expect(settings.language, 'system');
      expect(settings.scrollbackLines, 10000);
      expect(settings.uploadConflictPolicy, TransferConflictPolicy.prompt);
      expect(settings.uploadConcurrency, 2);
      expect(settings.uploadChunkKb, 256);
      // Issue #61: default false = 確認モーダル表示（後方互換）。
      expect(settings.openLinksDirectly, false);
    });

    test('保存済みの値（bool/double/int/String）を復元する', () async {
      SharedPreferences.setMockInitialValues({
        'settings_dark_mode': false,
        'settings_font_size': 16.0,
        'settings_zoom_factor': 1.5,
        'settings_scrollback': 5000,
        'settings_language': 'ja',
        'settings_upload_conflict_policy': 'autoRename',
      });
      final persistence = SettingsPersistence();

      final settings = await persistence.load();

      expect(settings.darkMode, isFalse);
      expect(settings.fontSize, 16.0);
      expect(settings.zoomFactor, 1.5);
      expect(settings.scrollbackLines, 5000);
      expect(settings.language, 'ja');
      expect(settings.uploadConflictPolicy, TransferConflictPolicy.autoRename);
    });

    test('uploadConflictPolicy の不正値は prompt にフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        'settings_upload_conflict_policy': 'invalid_value',
      });
      final persistence = SettingsPersistence();

      final settings = await persistence.load();

      expect(settings.uploadConflictPolicy, TransferConflictPolicy.prompt);
    });
  });

  group('SettingsPersistence.save', () {
    test('bool を保存して再読込で復元する', () async {
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.darkModeKey, false);
      final settings = await persistence.load();

      expect(settings.darkMode, isFalse);
    });

    test('openLinksDirectly を保存して再読込で復元する（Issue #61）', () async {
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.openLinksDirectlyKey, true);
      final settings = await persistence.load();

      expect(settings.openLinksDirectly, isTrue);
    });

    test('double を保存して再読込で復元する', () async {
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.fontSizeKey, 18.0);
      final settings = await persistence.load();

      expect(settings.fontSize, 18.0);
    });

    test('int を保存して再読込で復元する', () async {
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.uploadConcurrencyKey, 4);
      final settings = await persistence.load();

      expect(settings.uploadConcurrency, 4);
    });

    test('String を保存して再読込で復元する', () async {
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.languageKey, 'en');
      final settings = await persistence.load();

      expect(settings.language, 'en');
    });

    test('他キーへの保存は既存の保存値を上書きしない', () async {
      SharedPreferences.setMockInitialValues({'settings_language': 'ja'});
      final persistence = SettingsPersistence();

      await persistence.save(SettingsPersistence.darkModeKey, false);
      final settings = await persistence.load();

      expect(settings.language, 'ja');
      expect(settings.darkMode, isFalse);
    });
  });

  group('TransferConflictPolicy 永続化値変換', () {
    test('persistedValue は autoRename/prompt で双方向変換できる', () {
      expect(TransferConflictPolicy.autoRename.persistedValue, 'autoRename');
      expect(TransferConflictPolicy.prompt.persistedValue, 'prompt');
      expect(
        TransferConflictPolicy.fromPersisted('autoRename'),
        TransferConflictPolicy.autoRename,
      );
      expect(
        TransferConflictPolicy.fromPersisted('prompt'),
        TransferConflictPolicy.prompt,
      );
      expect(
        TransferConflictPolicy.fromPersisted(null),
        TransferConflictPolicy.prompt,
      );
      expect(
        TransferConflictPolicy.fromPersisted('unknown'),
        TransferConflictPolicy.prompt,
      );
    });
  });
}

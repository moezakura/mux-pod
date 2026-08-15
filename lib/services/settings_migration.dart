import 'package:shared_preferences/shared_preferences.dart';

/// 設定マイグレーションの基底クラス
abstract class SettingsMigration {
  int get version;
  Future<void> migrate(SharedPreferences prefs);
}

/// v1: autoFitEnabled + autoResizeEnabled → adjustMode
class MigrateAutoFitToAdjustMode extends SettingsMigration {
  @override
  int get version => 1;

  @override
  Future<void> migrate(SharedPreferences prefs) async {
    final hasLegacyAutoFit = prefs.containsKey('settings_auto_fit_enabled');
    final hasLegacyAutoResize = prefs.containsKey(
      'settings_auto_resize_enabled',
    );
    if (!hasLegacyAutoFit && !hasLegacyAutoResize) return;

    final autoFit = prefs.getBool('settings_auto_fit_enabled') ?? true;
    final autoResize = prefs.getBool('settings_auto_resize_enabled') ?? false;
    String adjustMode;
    if (autoResize) {
      adjustMode = 'autoResize';
    } else if (autoFit) {
      adjustMode = 'autoFit';
    } else {
      adjustMode = 'none';
    }
    await prefs.setString('settings_adjust_mode', adjustMode);
    await prefs.remove('settings_auto_fit_enabled');
    await prefs.remove('settings_auto_resize_enabled');
  }
}

/// マイグレーションランナー
class SettingsMigrationRunner {
  static const String _versionKey = 'settings_migration_version';

  static final List<SettingsMigration> _migrations = [
    MigrateAutoFitToAdjustMode(),
  ];

  static Future<void> run(SharedPreferences prefs) async {
    final currentVersion = prefs.getInt(_versionKey) ?? 0;
    for (final migration in _migrations) {
      if (migration.version > currentVersion) {
        await migration.migrate(prefs);
        await prefs.setInt(_versionKey, migration.version);
      }
    }
  }
}

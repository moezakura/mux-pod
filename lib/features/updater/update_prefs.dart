import 'package:shared_preferences/shared_preferences.dart';

/// Updater preferences, stored under their own keys so the feature does not
/// touch the app-wide settings model.
class UpdatePrefs {
  static const autoCheckKey = 'updater_auto_check';
  static const lastCheckKey = 'updater_last_check_ms';
  static const skippedTagKey = 'updater_skipped_tag';

  Future<bool?> autoCheck() async =>
      (await SharedPreferences.getInstance()).getBool(autoCheckKey);

  Future<void> setAutoCheck(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(autoCheckKey, value);

  Future<DateTime?> lastCheck() async {
    final ms = (await SharedPreferences.getInstance()).getInt(lastCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastCheck(DateTime value) async =>
      (await SharedPreferences.getInstance()).setInt(
        lastCheckKey,
        value.millisecondsSinceEpoch,
      );

  Future<String?> skippedTag() async =>
      (await SharedPreferences.getInstance()).getString(skippedTagKey);

  Future<void> setSkippedTag(String tag) async =>
      (await SharedPreferences.getInstance()).setString(skippedTagKey, tag);
}

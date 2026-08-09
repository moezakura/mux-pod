import 'package:flutter_muxpod/providers/settings_provider.dart';

/// 非同期の SharedPreferences / platform channel 呼び出しを避けるスタブ。
///
/// テスト中に `keepScreenOn` などを固定したい場合は [settings] パラメータを使う。
class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings settings;

  FakeSettingsNotifier({this.settings = const AppSettings(keepScreenOn: false)});

  @override
  AppSettings build() => settings;

  @override
  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
  }
}

import 'package:flutter_muxpod/providers/settings_provider.dart';

/// 非同期の SharedPreferences / platform channel 呼び出しを避けるスタブ。
///
/// テスト中に `keepScreenOn` などを固定したい場合は [settings] パラメータを使う。
class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings settings;

  FakeSettingsNotifier({
    this.settings = const AppSettings(keepScreenOn: false),
  });

  @override
  AppSettings build() => settings;

  @override
  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
  }

  @override
  Future<void> setScrollSendInput(String value) async {
    state = state.copyWith(scrollSendInput: value);
  }

  @override
  Future<void> setInvertScrollSendDirection(bool value) async {
    state = state.copyWith(invertScrollSendDirection: value);
  }

  @override
  Future<void> setAutoFitZoomOnScrollSend(bool value) async {
    state = state.copyWith(autoFitZoomOnScrollSend: value);
  }

  @override
  Future<void> setZoomFactor(double value) async {
    state = state.copyWith(zoomFactor: value);
  }
}

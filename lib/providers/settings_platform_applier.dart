import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// 設定値（向き・リフレッシュレート）を OS / デバイスへ適用する。
///
/// binding 未初期化の環境（テスト等）や、プラットフォームが対応していない場合は
/// no-op（try/catch・Android ガード）で設定値自体は保持される。
class SettingsPlatformApplier {
  /// 画面の向き設定をプラットフォームへ適用
  Future<void> applyOrientation(String value) async {
    const portrait = [DeviceOrientation.portraitUp];
    const landscape = [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    final List<DeviceOrientation> orientations;
    switch (value) {
      case 'portrait':
        // portraitUp のみ: 上下逆さま表示を防ぐ（端末アプリでは逆さUIは望ましくない）。
        // landscape は左右両方の握りを許可するのに対し、この非対称は意図的。
        orientations = portrait;
      case 'landscape':
        orientations = landscape;
      default:
        orientations = const <DeviceOrientation>[]; // すべて許可
    }
    // テスト等、binding が未初期化の環境では platform channel が利用できないため無視する。
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {
      // no-op: 向き設定の適用に失敗しても設定値自体は保持される
    }
  }

  /// リフレッシュレート上限をプラットフォームへ適用（Androidのみ）。
  /// 'auto' は最高レート、数値指定は「その値以下で最高」のモードを選ぶ。
  /// LTPO/ProMotion パネルや iOS では効果がないことがある（最終判断はシステム）。
  Future<void> applyRefreshRate(String value) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      if (value == 'auto') {
        await FlutterDisplayMode.setHighRefreshRate();
        return;
      }
      final cap = double.tryParse(value);
      if (cap == null) {
        await FlutterDisplayMode.setHighRefreshRate();
        return;
      }
      final modes = await FlutterDisplayMode.supported;
      if (modes.isEmpty) {
        return;
      }
      final active = await FlutterDisplayMode.active;
      bool ok(DisplayMode m) => m.refreshRate > 0 && m.refreshRate <= cap + 0.5;
      // まず同一解像度で上限以下、無ければ全体から上限以下を選ぶ
      var pool = modes
          .where(
            (m) =>
                m.width == active.width && m.height == active.height && ok(m),
          )
          .toList();
      if (pool.isEmpty) {
        pool = modes.where(ok).toList();
      }
      if (pool.isEmpty) {
        return; // 上限以下のモードが無ければ現状維持
      }
      pool.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
      await FlutterDisplayMode.setPreferredMode(pool.first);
    } catch (_) {
      // ディスプレイモード制御が使えない端末では無視
    }
  }
}

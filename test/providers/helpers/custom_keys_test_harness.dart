import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';

/// custom_keys テスト共通の手順（実測の 33 テストが踏む最小パス）。
///
/// `setMockInitialValues` → container 生成 → `addTearDown(dispose)` →
/// 非同期 load の待ち → `read(customKeysProvider)`（build + `_load` 起動）までを
/// 1 関数にまとめる。テスト本文の検証行はこの後に行われる。
Future<ProviderContainer> createCustomKeysContainer({
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await Future<void>.delayed(Duration.zero);
  container.read(customKeysProvider);
  return container;
}

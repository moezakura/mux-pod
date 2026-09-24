import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// connection provider 系テストの setUp 共通手順（SharedPreferences と
/// SecureStorageService のテスト値をリセットする）。
void resetConnectionStorage() {
  SharedPreferences.setMockInitialValues({});
  SecureStorageService.setTestValues({});
}

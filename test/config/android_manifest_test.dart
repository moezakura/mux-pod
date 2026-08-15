import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AndroidManifest.xml disables backup with allowBackup=false', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('android:allowBackup="false"'),
      reason: '鍵データのバックアップ復元（破損鍵の発生）を防ぐため allowBackup="false" が必要',
    );
  });
}

/// 設定画面のレイアウト分岐を定義する定数群。
abstract final class SettingsBreakpoints {
  /// この論理幅以上でマスター / ディテールの2ペイン表示になる。
  ///
  /// 根拠: マスターペイン280 + ディテールペイン最小操作幅320 = 600。
  /// Material 3 の compact(<600) / medium(>=600) 境界と一致する。
  /// テスト（settings_breakpoints_test.dart）からも参照される。
  static const double masterDetail = 600.0;
}

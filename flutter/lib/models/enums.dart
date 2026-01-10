/// SSH鍵タイプ
enum KeyType {
  rsa,
  ed25519,
  ecdsa,
}

/// フォントファミリー
enum FontFamily {
  jetBrainsMono,
  firaCode,
  meslo,
  hackGen,
  plemolJP,
}

/// カラーテーマ
enum ColorTheme {
  dracula,
  solarized,
  monokai,
  nord,
  custom,
}

/// 通知アクション
enum NotificationAction {
  inApp,
  sound,
  vibrate,
}

/// 通知頻度
enum NotificationFrequency {
  always,
  oncePerSession,
  oncePerMatch,
}

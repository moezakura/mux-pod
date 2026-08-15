import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// `context.l10n.keyName` でローカライズ済み文字列へアクセスするための拡張。
///
/// 使い方:
/// ```dart
/// Text(context.l10n.settingsLanguage)
/// ```
///
/// `nullable-getter: false` 設定のため `AppLocalizations.of(context)` は
/// 非null を返し、`!` は不要。
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

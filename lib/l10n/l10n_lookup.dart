import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// 言語指定文字列から [AppLocalizations] を解決する。
///
/// 引数 [language] は settingsProvider の `language` 値
/// （`'system'` / `'ja'` / `'en'`）を想定する。
///
/// - `'system'` の場合は [PlatformDispatcher.instance.locale]
///   （端末のロケール）で解決する。
/// - 解決は生成済みの [lookupAppLocalizations] に委譲する。
///   同関数は未対応言語（fr / zh 等）に対して [FlutterError] を throw する
///   ため、catch して en へフォールバックする（英語圏の表示を維持し、
///   null を返さない）。
///
/// BuildContext を持たない層（services / providers）から
/// `l10nForLanguage(ref.read(settingsProvider).language)` のように利用する。
AppLocalizations l10nForLanguage(String language) {
  final locale = language == 'system'
      ? PlatformDispatcher.instance.locale
      : Locale(language);
  try {
    return lookupAppLocalizations(locale);
  } on FlutterError {
    // 未対応言語は生成済み lookup で en に解決し直す。
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// [l10nForLanguage] に settings の `language` を渡せない文脈
/// （SharedPreferences へのアクセスや platform channel の初期化を
/// 前提としない純粋な Dart テストなど）のためのキャッシュ。
///
/// [setCachedLanguage] は settingsProvider の読み込み・変更時に呼ばれる。
/// 未設定の間は `'system'` 扱い（端末ロケールで解決）となる。
String? _cachedLanguage;

/// settings の言語設定をキャッシュへ反映する（null でクリア）。
void setCachedLanguage(String? language) => _cachedLanguage = language;

/// キャッシュされた言語設定から [AppLocalizations] を解決する。
///
/// settingsProvider を読まないため副作用がなく、provider の単体テスト等
/// でも安全に利用できる。キャッシュ未設定時は 'system' と同じ挙動。
AppLocalizations lookupL10n() => l10nForLanguage(_cachedLanguage ?? 'system');

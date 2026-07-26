import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// フォントライセンスを登録するサービス
class LicenseService {
  static bool _initialized = false;

  /// ライセンスを登録する（一度だけ実行）
  static void registerLicenses() {
    if (_initialized) return;
    _initialized = true;

    LicenseRegistry.addLicense(() async* {
      final hackgenLicense =
          await rootBundle.loadString('assets/fonts/HackGenConsole-LICENSE.txt');
      yield LicenseEntryWithLineBreaks(['HackGen Console'], hackgenLicense);

      final udevLicense =
          await rootBundle.loadString('assets/fonts/UDEVGothicNF-LICENSE.txt');
      yield LicenseEntryWithLineBreaks(['UDEV Gothic NF'], udevLicense);

      // バンドルしたGoogle Fonts（実行時のネットワーク取得を回避）のライセンス
      const googleFonts = <String, String>{
        'JetBrains Mono': 'JetBrainsMono',
        'Space Grotesk': 'SpaceGrotesk',
        'Fira Code': 'FiraCode',
        'Source Code Pro': 'SourceCodePro',
        'Roboto Mono': 'RobotoMono',
        'Ubuntu Mono': 'UbuntuMono',
        'Inconsolata': 'Inconsolata',
      };
      for (final entry in googleFonts.entries) {
        final text = await rootBundle
            .loadString('assets/google_fonts/${entry.value}-LICENSE.txt');
        yield LicenseEntryWithLineBreaks([entry.key], text);
      }
    });
  }
}

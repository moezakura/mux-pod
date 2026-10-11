/// In-app updater (Android): checks GitHub Releases, downloads the APK,
/// verifies checksum + signing certificate, hands it to Android's installer.
///
/// Integration points in the rest of the app (keep this list in sync):
/// - `lib/main.dart`: `home: UpdateCheckGate(child: HomeScreen())`
/// - `lib/screens/settings/sections/about_section.dart`: `UpdateSettingsTile()`
///   and `updaterSearchDescriptors()` in `aboutSearchDescriptors`
/// - `MainActivity.kt`: registers `UpdaterPlugin`
/// - `AndroidManifest.xml`: `REQUEST_INSTALL_PACKAGES`
/// - `.github/workflows/release.yml`: publishes `<apk>.sha256`, passes `UPDATE_REPO`
library;

export 'ui/update_check_gate.dart' show UpdateCheckGate;
export 'ui/update_screen.dart' show UpdateScreen;
export 'ui/update_search.dart' show updaterSearchDescriptors;
export 'ui/update_settings_tile.dart' show UpdateSettingsTile;
export 'update_controller.dart' show updateControllerProvider, UpdatePhase;

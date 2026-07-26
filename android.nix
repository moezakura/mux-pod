# Android build toolchain for the MuxPod Flutter app.
#
# Kept separate from shell.nix so the fast analyze/test shell stays lean; this
# one additionally pulls the Android SDK + NDK + JDK needed to assemble an APK.
#
# Usage:
#   nix-shell android.nix --run "flutter build apk --debug"
#
# Versions are pinned to what Flutter 3.38 / this project require:
#   compileSdk = 36, minSdk = 24, NDK = 28.2.13676358 (flutter.ndkVersion),
#   AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, JDK 17.
{ pkgs ? import <nixpkgs> {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  }
}:

let
  android = pkgs.androidenv.composeAndroidPackages {
    # 36 = app compileSdk; 33/34/35 = various plugins' compileSdk
    # (flutter_displaymode = 33, connectivity_plus = 34/35).
    platformVersions = [ "33" "34" "35" "36" ];
    buildToolsVersions = [ "35.0.0" ];
    # Required: AGP resolves flutter.ndkVersion at configuration time and uses
    # the NDK's llvm-strip on the bundled .so files. Must be the nix-patched NDK
    # (an AGP-auto-installed one would be an unpatched ELF that can't run here).
    ndkVersions = [ "28.2.13676358" ];
    includeNDK = true;
    # A plugin ships native C/C++ built via CMake (task :app:configureCMake*).
    cmakeVersions = [ "3.22.1" ];
    includeEmulator = false;
    includeSystemImages = false;
  };
  sdk = android.androidsdk;
  sdkRoot = "${sdk}/libexec/android-sdk";
in
pkgs.mkShell {
  name = "muxpod-android";

  packages = [
    pkgs.flutter338
    pkgs.jdk17
    sdk
    pkgs.git
  ];

  ANDROID_HOME = sdkRoot;
  ANDROID_SDK_ROOT = sdkRoot;
  JAVA_HOME = "${pkgs.jdk17}";

  shellHook = ''
    echo "MuxPod android shell: $(flutter --version 2>/dev/null | head -n1)"
    echo "ANDROID_HOME=$ANDROID_HOME"
  '';
}

# Development shell for the MuxPod Flutter app.
#
# Usage:
#   nix-shell                          # interactive shell with the toolchain
#   nix-shell --run "flutter pub get"
#   nix-shell --run "flutter analyze"
#   nix-shell --run "flutter test"
#
# Provides the Flutter 3.38 toolchain (bundles Dart 3.10.x, satisfying
# pubspec.yaml `sdk: ^3.10.7` and matching the .mise.toml flutter 3.38.x pin)
# plus the CLI tools Flutter shells out to. Android/iOS SDKs are intentionally
# omitted: this shell targets `flutter pub get`, `flutter analyze` and the
# `flutter test` unit/widget suites, which run on the Dart VM.
{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

pkgs.mkShell {
  name = "muxpod-dev";

  packages = [
    pkgs.flutter338 # Flutter 3.38.x + bundled Dart 3.10.x
    pkgs.git        # Flutter invokes git for version resolution
  ];

  shellHook = ''
    echo "MuxPod dev shell: $(flutter --version 2>/dev/null | head -n1)"
  '';
}

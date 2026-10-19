import 'dart:async';

import 'package:flutter/services.dart';

/// Package identity as reported by Android's PackageManager.
class PackageIdentity {
  const PackageIdentity({
    required this.packageName,
    required this.versionCode,
    required this.signerSha256,
    this.signerHistorySha256 = const {},
  });

  final String packageName;
  final int versionCode;

  /// SHA-256 of each signing certificate, lowercase hex.
  final Set<String> signerSha256;

  /// Certificates in the APK's signing lineage (APK Signature Scheme v3 key
  /// rotation), including the current one. Empty when unavailable.
  final Set<String> signerHistorySha256;

  static PackageIdentity fromMap(Map<Object?, Object?> map) => PackageIdentity(
    packageName: map['packageName'] as String,
    versionCode: (map['versionCode'] as num).toInt(),
    signerSha256: {
      for (final s in (map['signers'] as List? ?? const []))
        (s as String).toLowerCase(),
    },
    signerHistorySha256: {
      for (final s in (map['signerHistory'] as List? ?? const []))
        (s as String).toLowerCase(),
    },
  );
}

/// Final installer status pushed from native when the install does not
/// replace the app (aborted by the user, or failed).
class InstallStatus {
  const InstallStatus({required this.aborted, this.message});

  final bool aborted;
  final String? message;
}

/// Native side of the updater (`UpdaterPlugin.kt`).
abstract class UpdaterPlatform {
  /// Identity of the running app.
  Future<PackageIdentity> installedApp();

  /// Identity of an APK on disk, or null if Android can't parse it.
  Future<PackageIdentity?> inspectApk(String path);

  /// Whether the user has allowed this app to install packages.
  Future<bool> canRequestInstalls();

  /// Opens the system "Install unknown apps" screen for this app.
  Future<void> openInstallPermissionSettings();

  /// Hands [path] to Android's PackageInstaller. The system then shows its
  /// own confirmation; on success the app process is replaced.
  Future<void> install(String path);

  /// Install outcomes that come back to the app (abort / failure).
  Stream<InstallStatus> get installStatus;
}

class MethodChannelUpdaterPlatform implements UpdaterPlatform {
  MethodChannelUpdaterPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installStatus') {
        final args = call.arguments as Map<Object?, Object?>;
        _statusController.add(
          InstallStatus(
            aborted: args['aborted'] == true,
            message: args['message'] as String?,
          ),
        );
      }
    });
  }

  static const _channel = MethodChannel('si.mox.mux_pod/updater');
  final _statusController = StreamController<InstallStatus>.broadcast();

  @override
  Future<PackageIdentity> installedApp() async => PackageIdentity.fromMap(
    (await _channel.invokeMapMethod<Object?, Object?>('installedApp'))!,
  );

  @override
  Future<PackageIdentity?> inspectApk(String path) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('inspectApk', {
      'path': path,
    });
    return map == null ? null : PackageIdentity.fromMap(map);
  }

  @override
  Future<bool> canRequestInstalls() async =>
      await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;

  @override
  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});

  @override
  Stream<InstallStatus> get installStatus => _statusController.stream;
}

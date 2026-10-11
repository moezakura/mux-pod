import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_muxpod/features/updater/update_controller.dart';
import 'package:flutter_muxpod/features/updater/update_failure.dart';
import 'package:flutter_muxpod/features/updater/update_http.dart';
import 'package:flutter_muxpod/features/updater/update_prefs.dart';
import 'package:flutter_muxpod/features/updater/update_source.dart';
import 'package:flutter_muxpod/features/updater/updater_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apkBytes = [1, 2, 3, 4];
final _apkSha = sha256.convert(_apkBytes).toString();

class _FakeHttp implements UpdateHttp {
  String tag = 'v0.3.0';
  bool withChecksum = true;
  String checksum = _apkSha;
  int jsonCalls = 0;

  @override
  Future<Object?> getJson(Uri url) async {
    jsonCalls++;
    const base = 'https://github.com/moezakura/mux-pod/releases/download';
    return jsonDecode(
      jsonEncode({
        'tag_name': tag,
        'body': 'notes',
        'html_url': 'https://github.com/moezakura/mux-pod/releases/tag/$tag',
        'assets': [
          {
            'name': 'app-release.apk',
            'size': _apkBytes.length,
            'browser_download_url': '$base/$tag/app-release.apk',
          },
          if (withChecksum)
            {
              'name': 'app-release.apk.sha256',
              'browser_download_url': '$base/$tag/app-release.apk.sha256',
            },
        ],
      }),
    );
  }

  @override
  Future<String> getText(Uri url) async => '$checksum  app-release.apk\n';

  @override
  Future<void> download(
    Uri url,
    File dest, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    await dest.writeAsBytes(_apkBytes);
    onProgress?.call(_apkBytes.length, _apkBytes.length);
  }
}

class _FakePlatform implements UpdaterPlatform {
  PackageIdentity installed = const PackageIdentity(
    packageName: 'si.mox.mux_pod',
    versionCode: 201,
    signerSha256: {'aaaa'},
  );
  PackageIdentity? apk = const PackageIdentity(
    packageName: 'si.mox.mux_pod',
    versionCode: 300,
    signerSha256: {'aaaa'},
  );
  bool canInstall = true;
  bool openedSettings = false;
  String? installedPath;
  final status = StreamController<InstallStatus>.broadcast();

  @override
  Future<PackageIdentity> installedApp() async => installed;
  @override
  Future<PackageIdentity?> inspectApk(String path) async => apk;
  @override
  Future<bool> canRequestInstalls() async => canInstall;
  @override
  Future<void> openInstallPermissionSettings() async => openedSettings = true;
  @override
  Future<void> install(String path) async => installedPath = path;
  @override
  Stream<InstallStatus> get installStatus => status.stream;
}

void main() {
  late Directory tmp;
  late _FakeHttp http;
  late _FakePlatform platform;
  late ProviderContainer container;

  UpdateController ctrl() => container.read(updateControllerProvider.notifier);
  UpdateState st() => container.read(updateControllerProvider);

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('updater_ctrl');
    http = _FakeHttp();
    platform = _FakePlatform();
    container = ProviderContainer(
      overrides: [
        updaterSupportedProvider.overrideWithValue(true),
        updateSourceProvider.overrideWithValue(
          const UpdateSource(
            repo: 'moezakura/mux-pod',
            apkAssetName: 'app-release.apk',
            isReleaseBuild: true,
          ),
        ),
        updateHttpProvider.overrideWithValue(http),
        updaterPlatformProvider.overrideWithValue(platform),
        updatePrefsProvider.overrideWithValue(UpdatePrefs()),
        updateDownloadDirProvider.overrideWithValue(
          () async => Directory('${tmp.path}/updates'),
        ),
      ],
    );
    container.listen(updateControllerProvider, (_, _) {});
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await tmp.delete(recursive: true);
  });

  test('unsupported platform stays inert', () async {
    final c = ProviderContainer(
      overrides: [updaterSupportedProvider.overrideWithValue(false)],
    );
    addTearDown(c.dispose);
    expect(c.read(updateControllerProvider).phase, UpdatePhase.unsupported);
    await c.read(updateControllerProvider.notifier).check();
    expect(c.read(updateControllerProvider).phase, UpdatePhase.unsupported);
  });

  test('check finds a newer release', () async {
    await ctrl().check();
    expect(st().phase, UpdatePhase.available);
    expect(st().release?.tag, 'v0.3.0');
    expect(st().lastChecked, isNotNull);
  });

  test('check reports up to date for same version', () async {
    http.tag = 'v0.2.1';
    await ctrl().check();
    expect(st().phase, UpdatePhase.upToDate);
  });

  test('download verifies checksum and signature, then installs', () async {
    await ctrl().check();
    await ctrl().download();
    expect(st().phase, UpdatePhase.ready);
    expect(st().report?.checksumVerified, isTrue);

    await ctrl().install();
    expect(st().phase, UpdatePhase.installing);
    expect(platform.installedPath, endsWith('muxpod-300.apk'));

    platform.status.add(const InstallStatus(aborted: true));
    await settle();
    expect(st().phase, UpdatePhase.ready);

    await ctrl().install();
    platform.status.add(const InstallStatus(aborted: false, message: 'boom'));
    await settle();
    expect(st().phase, UpdatePhase.failed);
    expect(st().error?.failure, UpdateFailure.installFailed);
  });

  test('missing checksum still installs on signature alone', () async {
    http.withChecksum = false;
    await ctrl().check();
    await ctrl().download();
    expect(st().phase, UpdatePhase.ready);
    expect(st().report?.checksumVerified, isFalse);
  });

  test('checksum mismatch fails and deletes the download', () async {
    http.checksum = 'f' * 64;
    await ctrl().check();
    await ctrl().download();
    expect(st().phase, UpdatePhase.failed);
    expect(st().error?.failure, UpdateFailure.checksumMismatch);
    expect(Directory('${tmp.path}/updates').existsSync(), isFalse);
  });

  test('foreign signature fails', () async {
    platform.apk = const PackageIdentity(
      packageName: 'si.mox.mux_pod',
      versionCode: 300,
      signerSha256: {'bbbb'},
    );
    await ctrl().check();
    await ctrl().download();
    expect(st().error?.failure, UpdateFailure.signatureMismatch);
    expect(Directory('${tmp.path}/updates').existsSync(), isFalse);
  });

  test('install without permission opens settings instead', () async {
    platform.canInstall = false;
    await ctrl().check();
    await ctrl().download();
    await ctrl().install();
    expect(platform.openedSettings, isTrue);
    expect(platform.installedPath, isNull);
    expect(st().phase, UpdatePhase.ready);
    expect(st().needsInstallPermission, isTrue);
  });

  group('autoCheckIfDue', () {
    test('prompts once, then throttles for 24h', () async {
      final now = DateTime.now();
      expect((await ctrl().autoCheckIfDue(now: now))?.tag, 'v0.3.0');
      expect(
        await ctrl().autoCheckIfDue(now: now.add(const Duration(hours: 1))),
        isNull,
      );
      expect(http.jsonCalls, 1);
      expect(
        await ctrl().autoCheckIfDue(now: now.add(const Duration(hours: 25))),
        isNotNull,
      );
    });

    test('skipped version is not prompted', () async {
      await ctrl().skip('v0.3.0');
      expect(await ctrl().autoCheckIfDue(), isNull);
      expect(st().phase, UpdatePhase.available);
    });

    test('disabled auto-check does nothing', () async {
      await ctrl().setAutoCheck(false);
      expect(await ctrl().autoCheckIfDue(), isNull);
      expect(http.jsonCalls, 0);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'apk_verifier.dart';
import 'release_info.dart';
import 'update_failure.dart';
import 'update_http.dart';
import 'update_prefs.dart';
import 'update_source.dart';
import 'updater_platform.dart';

// Dependencies — each one overridable in tests.
final updaterSupportedProvider = Provider<bool>(
  (_) => UpdateSource.isPlatformSupported,
);
final updateSourceProvider = Provider<UpdateSource>(
  (_) => UpdateSource.fromEnvironment(),
);
final updateHttpProvider = Provider<UpdateHttp>((_) => IoUpdateHttp());
final updaterPlatformProvider = Provider<UpdaterPlatform>(
  (_) => MethodChannelUpdaterPlatform(),
);
final updatePrefsProvider = Provider<UpdatePrefs>((_) => UpdatePrefs());
final updateDownloadDirProvider = Provider<Future<Directory> Function()>(
  (_) =>
      () async =>
          Directory(p.join((await getTemporaryDirectory()).path, 'updates')),
);

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

enum UpdatePhase {
  /// Not Android — the updater UI is hidden.
  unsupported,
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,

  /// Downloaded and verified; waiting for the user to tap Install.
  ready,

  /// Handed to Android's installer.
  installing,
  failed,
}

class UpdateState {
  const UpdateState({
    required this.phase,
    this.release,
    this.progress,
    this.report,
    this.error,
    this.needsInstallPermission = false,
    this.lastChecked,
    this.autoCheck = false,
  });

  final UpdatePhase phase;
  final ReleaseInfo? release;

  /// 0..1 while downloading.
  final double? progress;
  final VerificationReport? report;
  final UpdateException? error;

  /// Install was blocked because "Install unknown apps" is off.
  final bool needsInstallPermission;

  // Persistent fields — carried across transitions by [next].
  final DateTime? lastChecked;
  final bool autoCheck;

  bool get isBusy => const {
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(phase);

  /// A new phase. Transient fields reset unless given.
  UpdateState next({
    required UpdatePhase phase,
    ReleaseInfo? release,
    double? progress,
    VerificationReport? report,
    UpdateException? error,
    bool needsInstallPermission = false,
    DateTime? lastChecked,
    bool? autoCheck,
  }) => UpdateState(
    phase: phase,
    release: release,
    progress: progress,
    report: report,
    error: error,
    needsInstallPermission: needsInstallPermission,
    lastChecked: lastChecked ?? this.lastChecked,
    autoCheck: autoCheck ?? this.autoCheck,
  );
}

class UpdateController extends Notifier<UpdateState> {
  /// Minimum time between automatic checks.
  static const checkInterval = Duration(hours: 24);

  late UpdateSource _source;
  late UpdateHttp _http;
  late UpdaterPlatform _platform;
  late UpdatePrefs _prefs;

  PackageIdentity? _installed;
  File? _apkFile;
  Completer<void>? _cancel;

  UpdateSource get source => _source;

  @override
  UpdateState build() {
    _source = ref.watch(updateSourceProvider);
    if (!ref.watch(updaterSupportedProvider)) {
      return const UpdateState(phase: UpdatePhase.unsupported);
    }
    _http = ref.watch(updateHttpProvider);
    _platform = ref.watch(updaterPlatformProvider);
    _prefs = ref.watch(updatePrefsProvider);

    final sub = _platform.installStatus.listen(_onInstallStatus);
    ref.onDispose(sub.cancel);
    _loadPrefs();
    return UpdateState(
      phase: UpdatePhase.idle,
      autoCheck: _source.isReleaseBuild,
    );
  }

  Future<void> _loadPrefs() async {
    final autoCheck = await _prefs.autoCheck() ?? _source.isReleaseBuild;
    final lastChecked = await _prefs.lastCheck();
    if (!ref.mounted) return;
    state = UpdateState(
      phase: state.phase,
      release: state.release,
      progress: state.progress,
      report: state.report,
      error: state.error,
      needsInstallPermission: state.needsInstallPermission,
      lastChecked: lastChecked ?? state.lastChecked,
      autoCheck: autoCheck,
    );
  }

  /// Runs a check if automatic checks are on and the last one is older than
  /// [checkInterval]. Returns the release if the user should be prompted
  /// (newer and not skipped).
  Future<ReleaseInfo?> autoCheckIfDue({DateTime? now}) async {
    if (state.phase == UpdatePhase.unsupported) return null;
    if (!(await _prefs.autoCheck() ?? _source.isReleaseBuild)) return null;
    final last = await _prefs.lastCheck();
    now ??= DateTime.now();
    if (last != null && now.difference(last) < checkInterval) return null;

    await check();
    final release = state.release;
    if (state.phase != UpdatePhase.available || release == null) return null;
    if (await _prefs.skippedTag() == release.tag) return null;
    return release;
  }

  Future<void> check() async {
    if (state.phase == UpdatePhase.unsupported || state.isBusy) return;
    state = state.next(phase: UpdatePhase.checking);
    try {
      _installed ??= await _platform.installedApp();
      final json = await _http.getJson(_source.latestReleaseApi);
      if (json is! Map<String, dynamic>) {
        throw const UpdateException(UpdateFailure.noRelease, 'bad response');
      }
      final release = ReleaseInfo.fromGitHubJson(json, _source);
      final now = DateTime.now();
      await _prefs.setLastCheck(now);
      if (!ref.mounted) return;
      state = state.next(
        phase: release.versionCode > _installed!.versionCode
            ? UpdatePhase.available
            : UpdatePhase.upToDate,
        release: release,
        lastChecked: now,
      );
    } catch (e) {
      _fail(e);
    }
  }

  /// Downloads and verifies the available release.
  Future<void> download() async {
    final release = state.release;
    if (release == null || state.isBusy) return;
    final cancel = _cancel = Completer<void>();
    Directory? dir;
    state = state.next(
      phase: UpdatePhase.downloading,
      release: release,
      progress: 0,
    );
    try {
      dir = await ref.read(updateDownloadDirProvider)();
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'muxpod-${release.versionCode}.apk'));

      String? expected;
      final checksumUrl = release.checksumUrl;
      if (checksumUrl != null) {
        expected = parseChecksumFile(await _http.getText(checksumUrl));
        if (expected == null) {
          throw const UpdateException(
            UpdateFailure.checksumMismatch,
            'unreadable checksum file',
          );
        }
      }

      var lastPercent = -1;
      await _http.download(
        release.apkUrl,
        file,
        cancel: cancel.future,
        onProgress: (received, total) {
          total ??= release.apkSize > 0 ? release.apkSize : null;
          if (total == null || !ref.mounted) return;
          final percent = (received * 100 ~/ total).clamp(0, 100);
          if (percent == lastPercent) return;
          lastPercent = percent;
          state = state.next(
            phase: UpdatePhase.downloading,
            release: release,
            progress: percent / 100,
          );
        },
      );
      if (!ref.mounted) return;

      state = state.next(phase: UpdatePhase.verifying, release: release);
      if (expected != null) {
        verifyChecksum(expected: expected, actual: await sha256OfFile(file));
      }
      final keyRotated = verifyApkIdentity(
        apk: await _platform.inspectApk(file.path),
        installed: _installed ??= await _platform.installedApp(),
        pinnedCertSha256: _source.pinnedCertSha256,
      );
      _apkFile = file;
      if (!ref.mounted) return;
      state = state.next(
        phase: UpdatePhase.ready,
        release: release,
        report: VerificationReport(
          checksumVerified: expected != null,
          keyRotated: keyRotated,
        ),
      );
    } catch (e) {
      await _discardDownload(dir);
      if (cancel.isCompleted) {
        if (ref.mounted) {
          state = state.next(phase: UpdatePhase.available, release: release);
        }
        return;
      }
      _fail(e);
    } finally {
      _cancel = null;
    }
  }

  void cancelDownload() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  /// Hands the verified APK to Android's installer. If installs from this
  /// app aren't allowed yet, opens the system setting instead.
  Future<void> install() async {
    final file = _apkFile;
    final release = state.release;
    if (state.phase != UpdatePhase.ready || file == null) return;

    if (!await _platform.canRequestInstalls()) {
      state = state.next(
        phase: UpdatePhase.ready,
        release: release,
        report: state.report,
        needsInstallPermission: true,
      );
      await _platform.openInstallPermissionSettings();
      return;
    }

    final report = state.report;
    state = state.next(
      phase: UpdatePhase.installing,
      release: release,
      report: report,
    );
    try {
      await _platform.install(file.path);
    } catch (e) {
      _fail(UpdateException(UpdateFailure.installFailed, e.toString()));
    }
  }

  void _onInstallStatus(InstallStatus status) {
    if (!ref.mounted || state.phase != UpdatePhase.installing) return;
    if (status.aborted) {
      state = state.next(
        phase: UpdatePhase.ready,
        release: state.release,
        report: state.report,
      );
    } else {
      _fail(UpdateException(UpdateFailure.installFailed, status.message));
    }
  }

  /// Retries whatever failed: the download if a release is known, else the check.
  Future<void> retry() async {
    if (state.phase != UpdatePhase.failed) return;
    if (state.release != null &&
        state.release!.versionCode > (_installed?.versionCode ?? 0)) {
      state = state.next(phase: UpdatePhase.available, release: state.release);
      await download();
    } else {
      await check();
    }
  }

  /// Don't prompt automatically for [tag] again (manual checks still show it).
  Future<void> skip(String tag) => _prefs.setSkippedTag(tag);

  Future<void> setAutoCheck(bool value) async {
    state = state.next(
      phase: state.phase,
      release: state.release,
      progress: state.progress,
      report: state.report,
      error: state.error,
      needsInstallPermission: state.needsInstallPermission,
      autoCheck: value,
    );
    await _prefs.setAutoCheck(value);
  }

  Future<void> _discardDownload(Directory? dir) async {
    _apkFile = null;
    try {
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Cache dir; the OS reclaims it eventually.
    }
  }

  void _fail(Object e) {
    if (!ref.mounted) return;
    state = state.next(
      phase: UpdatePhase.failed,
      release: state.release,
      error: e is UpdateException
          ? e
          : UpdateException(UpdateFailure.unknown, e.toString()),
    );
  }
}

/// `HerdrCaretComposer` のテスト用 fake と補助関数。
///
/// 手書き fake（[FakeHerdrCaretHost]）で `HerdrCaretHost` を実装し、
/// [pumpRefFor] で得た本物の `WidgetRef` を `ref` に渡す。
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/herdr/herdr_caret.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show HerdrScrollbackLinkHelperRunner;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_settings_notifier.dart';
import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/fake_ssh_notifier.dart';

/// [HerdrCaretHelperManager]/[HerdrHyperlinkHelperManager] の配置確認と
/// 同型の最小 manifest（`.load()`（アセットバンドル読込）を経由せずに
/// [HerdrCaretComposer.ensureInstaller] を直接検証するため）。
HerdrCaretHelperManifest testManifest() => HerdrCaretHelperManifest.fromJson(
  jsonEncode({
    'version': 1,
    'helperName': 'herdr-caret-helper',
    'platforms': [
      {
        'id': 'linux-x86_64',
        'os': 'linux',
        'arch': 'x86_64',
        'asset': 'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
        'size': 1,
        'sha256': ''.padLeft(64, '0'),
      },
    ],
  }),
);

class FakeHerdrCaretHost implements HerdrCaretHost {
  FakeHerdrCaretHost({required this.ref});

  bool isDisposedValue = false;

  HerdrStatus? caretStatusValue;

  /// null 固定ではなくテストから差し込めるようにする（
  /// setupHyperlinkProduction / setupProduction は snapshotCache /
  /// frameAdapter が非 null であることを要求する）。
  HerdrSnapshotCache? snapshotCacheValue;
  HerdrAdapter? frameAdapterValue;

  int setFrameReaderCalls = 0;

  @override
  final WidgetRef ref;

  @override
  bool get isMounted => true;

  @override
  bool get isDisposed => isDisposedValue;

  @override
  MultiplexerBackendKind get backendKind => MultiplexerBackendKind.herdr;

  @override
  HerdrAdapter? get frameAdapter => frameAdapterValue;

  /// [snapshotCache] の読み出し回数。
  int snapshotCacheReads = 0;

  /// 非 null なら、[snapshotCache] の [swapSnapshotCacheOnRead] 回目の読み出し
  /// でこの cache へ差し替える（以降の読み出しも差し替え後を返す）。await
  /// 中に再接続（cache 差し替え）が起きた状況を模す。
  HerdrSnapshotCache? swapSnapshotCacheTo;
  int swapSnapshotCacheOnRead = 0;

  @override
  HerdrSnapshotCache? get snapshotCache {
    snapshotCacheReads++;
    if (swapSnapshotCacheTo != null &&
        snapshotCacheReads == swapSnapshotCacheOnRead) {
      snapshotCacheValue = swapSnapshotCacheTo;
    }
    return snapshotCacheValue;
  }

  @override
  HerdrCaretSnapshotReader? get injectedReader => null;

  @override
  HerdrHyperlinkReader? get injectedHyperlinkReader => null;

  @override
  HerdrCaretSnapshotReader? caretReader;

  @override
  HerdrStatus? get caretStatus => caretStatusValue;

  @override
  set caretStatus(HerdrStatus? value) => caretStatusValue = value;

  @override
  HerdrHyperlinkReader? hyperlinkReader;

  @override
  void setFrameReader(HerdrPaneFrameReader reader) => setFrameReaderCalls++;

  @override
  void clearViewCaret() {}

  // ---- スクロールモードのリンク読取用 ----
  String? currentPaneIdValue;

  @override
  String? get currentPaneId => currentPaneIdValue;

  @override
  ScrollbackLinkCache? scrollbackLinkCache;

  @override
  HerdrScrollbackLinkReader? scrollbackLinkReader;

  HerdrScrollbackLinkHelperRunner? injectedScrollbackLinkHelperRunnerValue;

  @override
  HerdrScrollbackLinkHelperRunner? get injectedScrollbackLinkHelperRunner =>
      injectedScrollbackLinkHelperRunnerValue;

  List<String> bodyLinesForValue = const [];

  @override
  List<String> Function() get bodyLinesFor =>
      () => bodyLinesForValue;

  bool isActiveValue = true;

  @override
  bool Function() get isActive =>
      () => isActiveValue;

  bool isSelectModeActiveValue = true;

  @override
  bool Function() get isSelectModeActive =>
      () => isSelectModeActiveValue;

  int notifyScrollbackLinksUpdatedCalls = 0;

  @override
  void Function() get notifyScrollbackLinksUpdated =>
      () => notifyScrollbackLinksUpdatedCalls++;

  ({Object? identity, int generation})? currentSnapshotIdentityValue;

  @override
  ({Object? identity, int generation})? Function()
  get currentSnapshotIdentity =>
      () => currentSnapshotIdentityValue;

  @override
  DateTime Function()? scrollbackLinkClock;
}

/// [sshProvider] を [client] で上書きした最小の widget を pump し、その
/// widget から得た本物の [WidgetRef] を返す（[FakeHerdrCaretHost.ref] 用）。
///
/// [settings] が非 null なら [settingsProvider] も上書きする（
/// `experimentalHerdrHyperlinksEnabled` の判定に使う）。
Future<WidgetRef> pumpRefFor(
  WidgetTester tester,
  FakeSshClient client, {
  AppSettings? settings,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
        if (settings != null)
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(settings: settings),
          ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

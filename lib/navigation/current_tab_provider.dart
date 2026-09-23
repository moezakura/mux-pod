import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 現在のタブインデックス Notifier
/// タブ順序: 0=Servers, 1=Keys, 2=Dashboard, 3=Notify, 4=Settings
///
/// home シェル・各タブ画面のどちらにも属さない中立モジュール。
/// screens 配下を一切 import しない（画面間の相互循環参照を防ぐ）。
class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 2; // Dashboard（中央）をデフォルトに

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

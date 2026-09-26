import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/power_policy.dart';

/// ネットワーク状態
enum NetworkStatus {
  /// ネットワーク利用可能
  online,

  /// ネットワーク利用不可
  offline,
}

NetworkKind classifyNetwork(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return NetworkKind.wifi;
  }
  if (results.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
  return NetworkKind.unknown;
}

/// ネットワーク状態を監視するサービス
///
/// connectivity_plusを使用してネットワークの接続/切断を検知し、
/// SSH再接続のトリガーとして使用する。
class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _statusController = StreamController<NetworkStatus>.broadcast();

  final _changes =
      StreamController<({NetworkStatus status, NetworkKind kind})>.broadcast();
  NetworkKind _kind = NetworkKind.unknown;
  NetworkKind get kind => _kind;
  Stream<({NetworkStatus status, NetworkKind kind})> get changes =>
      _changes.stream;

  NetworkStatus _currentStatus = NetworkStatus.online;

  /// 現在のネットワーク状態
  NetworkStatus get currentStatus => _currentStatus;

  /// ネットワーク状態のストリーム
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  /// ネットワークが利用可能か
  bool get isOnline => _currentStatus == NetworkStatus.online;

  /// 監視を開始
  Future<void> start() async {
    // 初期状態を取得
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);

    // 変化を監視
    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  /// 監視を停止
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// ステータスを更新
  void _updateStatus(List<ConnectivityResult> results) {
    final newStatus = _determineStatus(results);
    final newKind = classifyNetwork(results);
    if (newKind != _kind || newStatus != _currentStatus) {
      _kind = newKind;
      _changes.add((status: newStatus, kind: newKind));
    }

    if (newStatus != _currentStatus) {
      final oldStatus = _currentStatus;
      _currentStatus = newStatus;
      _statusController.add(newStatus);

      // オフラインからオンラインへの復帰を検知
      if (oldStatus == NetworkStatus.offline &&
          newStatus == NetworkStatus.online) {
        // 復帰イベントは statusStream で通知される
      }
    }
  }

  /// ConnectivityResultからNetworkStatusを判定
  NetworkStatus _determineStatus(List<ConnectivityResult> results) {
    // none以外の接続があればオンライン
    for (final result in results) {
      if (result != ConnectivityResult.none) {
        return NetworkStatus.online;
      }
    }
    return NetworkStatus.offline;
  }

  /// リソースを解放
  Future<void> dispose() async {
    await stop();
    await _statusController.close();
    await _changes.close();
  }
}

/// ネットワークモニターのプロバイダー
final networkMonitorProvider = Provider<NetworkMonitor>((ref) {
  final monitor = NetworkMonitor();

  // 自動的に監視を開始
  monitor.start();

  ref.onDispose(() {
    monitor.dispose();
  });

  return monitor;
});

/// ネットワーク状態のストリームプロバイダー
final networkStatusProvider = StreamProvider<NetworkStatus>((ref) {
  final monitor = ref.watch(networkMonitorProvider);
  return monitor.statusStream;
});

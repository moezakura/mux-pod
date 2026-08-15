import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

// inventory: DEEPLINK-001
/// ディープリンクのパース結果
final class DeepLinkData {
  // inventory: DEEPLINK-002
  // inventory: LEGACY-0093
  final String? server;
  // inventory: DEEPLINK-003
  // inventory: LEGACY-0094
  final String? session;
  // inventory: DEEPLINK-004
  // inventory: LEGACY-0095
  final String? window;
  // inventory: DEEPLINK-005
  // inventory: LEGACY-0096
  final int? pane;

  const DeepLinkData({this.server, this.session, this.window, this.pane});

  // inventory: DEEPLINK-006
  // inventory: LEGACY-0097
  bool get hasTarget => server != null;

  @override
  // inventory: DEEPLINK-007
  // inventory: LEGACY-0098
  String toString() =>
      'DeepLinkData(server: $server, session: $session, window: $window, pane: $pane)';
}

// inventory: DEEPLINK-008
/// `muxpod://` URLスキームのディープリンクを処理するサービス
///
/// URL形式: `muxpod://connect?server=id&session=name&window=name&pane=index`
final class DeepLinkService {
  static const _tag = 'DeepLinkService';
  // inventory: DEEPLINK-009
  static const _channel = MethodChannel('com.muxpod.app/deeplink');

  final _linkController = StreamController<DeepLinkData>.broadcast();

  // inventory: DEEPLINK-010
  // inventory: LEGACY-0099
  Stream<DeepLinkData> get linkStream => _linkController.stream;

  DeepLinkData? _initialLink;
  // inventory: DEEPLINK-011
  // inventory: LEGACY-0100
  DeepLinkData? get initialLink => _initialLink;

  bool _initialized = false;

  // inventory: DEEPLINK-012
  // inventory: LEGACY-0101
  /// 初期化。コールドスタート時のリンクとホットリンクの両方を処理する。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // MethodChannelでネイティブからのディープリンクを受信
    // inventory: DEEPLINK-013
    _channel.setMethodCallHandler(_handleMethodCall);

    // コールドスタート時の初期リンクを取得
    try {
      final initialUri = await _channel.invokeMethod<String>('getInitialLink');
      if (initialUri != null) {
        final data = parseUri(initialUri);
        if (data.hasTarget) {
          _initialLink = data;
          developer.log('Initial deep link: $data', name: _tag);
        }
      }
    } on MissingPluginException {
      // プラットフォームチャネル未実装（テスト時など）
      developer.log('Deep link channel not available', name: _tag);
    } catch (e) {
      developer.log('Error getting initial link: $e', name: _tag);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onDeepLink') {
      final uri = call.arguments as String?;
      if (uri != null) {
        final data = parseUri(uri);
        if (data.hasTarget) {
          developer.log('Hot deep link received: $data', name: _tag);
          _linkController.add(data);
        }
      }
    }
  }

  // inventory: DEEPLINK-014
  // inventory: LEGACY-0102
  /// URI文字列をDeepLinkDataにパース
  static DeepLinkData parseUri(String uriString) {
    try {
      final uri = Uri.parse(uriString);

      // muxpod://connect?... の形式のみ受け付け
      if (uri.scheme != 'muxpod') {
        return const DeepLinkData();
      }

      final server = uri.queryParameters['server'];
      final session = uri.queryParameters['session'];
      final window = uri.queryParameters['window'];
      final paneStr = uri.queryParameters['pane'];
      final pane = paneStr != null ? int.tryParse(paneStr) : null;

      return DeepLinkData(
        server: server,
        session: session,
        window: window,
        pane: pane,
      );
    } catch (e) {
      developer.log('Failed to parse deep link URI: $e', name: _tag);
      return const DeepLinkData();
    }
  }

  // inventory: DEEPLINK-015
  // inventory: LEGACY-0103
  void dispose() {
    _linkController.close();
  }
}

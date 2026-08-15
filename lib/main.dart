import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/home_screen.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/deep_link/deep_link_service.dart';
import 'package:flutter_muxpod/services/license_service.dart';
import 'package:flutter_muxpod/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // リリースビルドでは debugPrint を無効化（ログI/Oとスロットルの主スレッド負荷を排除）
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // フォントライセンスを登録
  LicenseService.registerLicenses();

  // ステータスバーを透明に
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _deepLinkService = DeepLinkService();
  StreamSubscription<DeepLinkData>? _linkSubscription;
  bool _initialLinkHandled = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // ホットリンクの監視は初期化の成否に関わらず設定
    _linkSubscription = _deepLinkService.linkStream.listen(_handleDeepLink);

    await _deepLinkService.initialize();

    // コールドスタートの初期リンクは接続データロード後に処理
    if (_deepLinkService.initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _waitForConnectionsAndHandleInitialLink();
      });
    }
  }

  Future<void> _waitForConnectionsAndHandleInitialLink() async {
    if (_initialLinkHandled) return;

    // 接続データがロードされるまで待つ（最大3秒）
    for (int i = 0; i < 30; i++) {
      final state = ref.read(connectionsProvider);
      if (!state.isLoading) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // ナビゲーターが準備完了するまで待つ（最大1秒）
    for (int i = 0; i < 10; i++) {
      if (_navigatorKey.currentState != null) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final initialLink = _deepLinkService.initialLink;
    if (initialLink != null && !_initialLinkHandled) {
      _initialLinkHandled = true;
      _handleDeepLink(initialLink);
    }
  }

  void _handleDeepLink(DeepLinkData data) {
    if (!data.hasTarget) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final connection = ref
        .read(connectionsProvider.notifier)
        .findByDeepLinkIdOrName(data.server!);

    if (connection == null) {
      ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
        SnackBar(
          content: Text('Server not found: ${data.server}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // まず既存ルートをホームまで戻す
    navigator.popUntil((route) => route.isFirst);

    // 次フレームでpushする（popUntilによるTerminalScreen.dispose()が
    // 完了してからでないとref.readが_elements assertionで失敗する）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navigatorKey.currentState;
      if (nav == null) return;

      nav.push(
        MaterialPageRoute(
          builder: (context) => TerminalScreen(
            connectionId: connection.id,
            sessionName: data.session,
            deepLinkWindowName: data.window,
            deepLinkPaneIndex: data.pane,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'MuxPod',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

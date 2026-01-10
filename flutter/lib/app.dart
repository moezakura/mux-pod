import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'widgets/error_boundary.dart';

/// MuxPod アプリケーションルート
class MuxPodApp extends ConsumerWidget {
  const MuxPodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ErrorBoundary(
      child: MaterialApp.router(
        title: 'MuxPod',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          // グローバルなエラー表示やオーバーレイをここに追加可能
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}

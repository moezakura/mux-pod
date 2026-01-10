import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/error/error_handler.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorHandler.instance.reportError(
        details.exception,
        details.stack,
        context: 'FlutterError',
      );
    };

    // Platform dispatcher errors (async errors not caught by Flutter)
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorHandler.instance.reportError(
        error,
        stack,
        context: 'PlatformDispatcher',
      );
      return true;
    };

    runApp(
      ProviderScope(
        observers: kDebugMode ? [_ProviderLogger()] : [],
        child: const MuxPodApp(),
      ),
    );
  }, (error, stack) {
    // Zoned errors (uncaught async errors)
    ErrorHandler.instance.reportError(
      error,
      stack,
      context: 'ZonedGuarded',
    );
  });
}

/// Debug mode provider observer
class _ProviderLogger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint('[Provider] ${provider.name ?? provider.runtimeType} updated');
    }
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    ErrorHandler.instance.reportError(
      error,
      stackTrace,
      context: 'Provider: ${provider.name ?? provider.runtimeType}',
    );
  }
}

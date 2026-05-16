import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/network/network_monitor.dart';
import '../../services/ssh/input_queue.dart';
import '../../services/ssh/ssh_client.dart' show SshConnectOptions;
import '../../services/tmux/pane_navigator.dart';
import '../../services/terminal/font_calculator.dart';
import '../../services/tmux/tmux_commands.dart';
import '../../services/tmux/tmux_parser.dart';
import '../../services/tmux/tmux_version.dart';
import '../../widgets/dialogs/resize_dialog.dart';
import '../../theme/design_colors.dart';
import '../../services/terminal/tmux_key_display.dart';
import '../../widgets/key_overlay_widget.dart';
import '../../widgets/scroll_to_bottom_button.dart';
import '../../widgets/special_keys_bar.dart';
import '../../widgets/image_transfer_confirm_dialog.dart';
import '../../widgets/tmux_tiles.dart';
import '../../providers/terminal_display_provider.dart';
import '../../providers/image_transfer_provider.dart';
import '../file_browser/file_browser_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../settings/settings_screen.dart';
import 'widgets/ansi_text_view.dart';

/// スクロールモードのソース
enum ScrollModeSource {
  /// 通常モード（スクロールモードではない）
  none,

  /// ユーザーがUIから手動で有効化
  manual,

  /// tmux copy-modeを自動検出
  tmux,
}

/// ポーリングで頻繁に更新されるターミナル表示データ
///
/// ValueNotifierで管理し、親ウィジェットのsetState()を回避する。
/// これによりBottomSheet表示中の親リビルドを防ぎ、
/// isDismissible: trueでも安定して動作する。
class _TerminalViewData {
  final String content;
  final int latency;
  final int paneWidth;
  final int paneHeight;

  const _TerminalViewData({
    this.content = '',
    this.latency = 0,
    this.paneWidth = 80,
    this.paneHeight = 24,
  });

  _TerminalViewData copyWith({
    String? content,
    int? latency,
    int? paneWidth,
    int? paneHeight,
  }) =>
      _TerminalViewData(
        content: content ?? this.content,
        latency: latency ?? this.latency,
        paneWidth: paneWidth ?? this.paneWidth,
        paneHeight: paneHeight ?? this.paneHeight,
      );
}

/// ターミナル画面（HTMLデザイン仕様準拠）
class TerminalScreen extends ConsumerStatefulWidget {
  final String connectionId;
  final String? sessionName;

  /// 復元用: 最後に開いていたウィンドウインデックス
  final int? lastWindowIndex;

  /// 復元用: 最後に開いていたペインID
  final String? lastPaneId;

  /// ディープリンク用: ウィンドウ名で指定（インデックスではなく名前で検索）
  final String? deepLinkWindowName;

  /// ディープリンク用: ペインインデックス
  final int? deepLinkPaneIndex;

  const TerminalScreen({
    super.key,
    required this.connectionId,
    this.sessionName,
    this.lastWindowIndex,
    this.lastPaneId,
    this.deepLinkWindowName,
    this.deepLinkPaneIndex,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  final _secureStorage = SecureStorageService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _ansiTextViewKey = GlobalKey<AnsiTextViewState>();
  final _scrollToBottomKey = GlobalKey<ScrollToBottomButtonState>();
  final _terminalScrollController = ScrollController();

  // 接続状態（ローカルで管理）
  bool _isConnecting = false;
  String? _connectionError;
  SshState _sshState = const SshState();

  // ポーリングで頻繁に更新されるターミナル表示データ（ValueNotifierで管理）
  // 親のsetState()を回避し、ValueListenableBuilderでサブツリーのみリビルドする
  final _viewNotifier = ValueNotifier<_TerminalViewData>(const _TerminalViewData());

  // キーオーバーレイ
  final KeyOverlayState _keyOverlayState = KeyOverlayState();
  Timer? _keyOverlayTimer;

  // ポーリング用タイマー
  Timer? _pollTimer;
  Timer? _treeRefreshTimer;
  bool _isPolling = false;
  bool _isDisposed = false;

  // フレームスキップ用（高頻度更新の最適化）
  static const _minFrameInterval = Duration(milliseconds: 16); // ~60fps
  DateTime _lastFrameTime = DateTime.now();
  bool _pendingUpdate = false;
  String _pendingContent = '';
  int _pendingLatency = 0;

  // 適応型ポーリング用
  int _currentPollingInterval = 100;
  static const int _minPollingInterval = 50;
  static const int _maxPollingInterval = 2000;

  // 選択状態保持用（スクロールモード中の更新抑制）
  String _bufferedContent = '';
  int _bufferedLatency = 0;
  bool _hasBufferedUpdate = false;

  // 初回スクロール完了フラグ
  bool _hasInitialScrolled = false;

  // ターミナルモード
  TerminalMode _terminalMode = TerminalMode.normal;

  // スクロールモードのソース（none / manual / tmux）
  ScrollModeSource _scrollModeSource = ScrollModeSource.none;

  // ズームスケール
  double _zoomScale = 1.0;

  // EnterCommand入力内容保持（ボトムシートを閉じても保持）
  String _savedCommandInput = '';

  // 入力キュー（切断中の入力を保持）
  final _inputQueue = InputQueue();

  // バックグラウンド状態
  bool _isInBackground = false;

  // directInput設定のローカルキャッシュ（ref.watch回避）
  bool _directInputEnabled = true;

  // ウィンドウ作成中フラグ（連打防止）
  bool _isCreatingWindow = false;

  // リサイズ中フラグ（排他制御）
  bool _isResizing = false;

  // 自動リサイズのdebounceタイマー（画面サイズ変更時）
  Timer? _autoResizeDebounceTimer;

  // tmuxバージョン情報（リサイズ機能判定用）
  TmuxVersionInfo? _tmuxVersion;

  // Riverpodリスナー
  ProviderSubscription<SshState>? _sshSubscription;
  ProviderSubscription<TmuxState>? _tmuxSubscription;
  ProviderSubscription<AppSettings>? _settingsSubscription;
  ProviderSubscription<AsyncValue<NetworkStatus>>? _networkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // スクロール時にスクロールボタンを表示
    _terminalScrollController.addListener(_onTerminalScroll);

    // 次フレームでリスナーを設定（ref使用のため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupListeners();
      _connectAndSetup();
      _applyKeepScreenOn();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pausePolling();
        break;
      case AppLifecycleState.resumed:
        _resumePolling();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final settings = ref.read(settingsProvider);
    if (!settings.isAutoResize) return;

    // debounce: 画面回転・折りたたみの連続サイズ変更を抑制
    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isDisposed) return;
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        _executeAutoResize(activePane);
      }
    });
  }

  /// バックグラウンド移行時にポーリングを停止
  void _pausePolling() {
    _isInBackground = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = null;
    WakelockPlus.disable();
  }

  /// フォアグラウンド復帰時にポーリングを再開
  void _resumePolling() {
    if (!_isInBackground || _isDisposed) return;
    _isInBackground = false;
    _startPolling();
    _startTreeRefresh();
    _applyKeepScreenOn();
  }

  /// Keep screen on設定を適用
  void _applyKeepScreenOn() {
    final settings = ref.read(settingsProvider);
    if (settings.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Providerのリスナーを設定
  void _setupListeners() {
    // SSH状態の変化を監視
    _sshSubscription = ref.listenManual<SshState>(
      sshProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        setState(() {
          _sshState = next;
        });
      },
      fireImmediately: true,
    );

    // Tmux状態の変化を監視
    // 注意: 親のsetState()は不要。ブレッドクラムやペインインジケーターは
    // Consumer widgetでtmuxProviderを直接watchするため、
    // サブツリー内でのみリビルドされる。
    _tmuxSubscription = ref.listenManual<TmuxState>(
      tmuxProvider,
      (previous, next) {
        // Consumer widgets が直接 tmuxProvider を watch しているため、
        // 親の setState() は不要（BottomSheet安定化のため除去）
      },
      fireImmediately: true,
    );

    // 設定の変化を監視（Keep screen on / directInput用）
    _settingsSubscription = ref.listenManual<AppSettings>(
      settingsProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        if (previous?.keepScreenOn != next.keepScreenOn) {
          _applyKeepScreenOn();
        }
        if (previous?.directInputEnabled != next.directInputEnabled) {
          setState(() {
            _directInputEnabled = next.directInputEnabled;
          });
        }
      },
      fireImmediately: false,
    );

    // 初期値を明示的に設定
    _directInputEnabled = ref.read(settingsProvider).directInputEnabled;

    // ネットワーク状態の変化を監視（実際の接続状態変化時のみ更新）
    _networkSubscription = ref.listenManual<AsyncValue<NetworkStatus>>(
      networkStatusProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        final prevStatus = previous?.value;
        final nextStatus = next.value;
        if (prevStatus != nextStatus) {
          setState(() {});
        }
      },
      fireImmediately: true,
    );

    // 再接続成功時の処理を設定
    final sshNotifier = ref.read(sshProvider.notifier);
    sshNotifier.onReconnectSuccess = _onReconnectSuccess;
  }

  /// 再接続成功時の処理
  Future<void> _onReconnectSuccess() async {
    if (!mounted || _isDisposed) return;

    // ポーリングフラグをリセット
    _isPolling = false;

    // ポーリングを再開
    _startPolling();

    // セッションツリーを再取得
    _startTreeRefresh();

    // キューされた入力を送信
    await _flushInputQueue();

    // UIを更新
    if (mounted) setState(() {});
  }

  /// キューされた入力を送信
  Future<void> _flushInputQueue() async {
    if (_inputQueue.isEmpty) return;

    final queuedInput = _inputQueue.flush();
    if (queuedInput.isNotEmpty) {
      await _sendKeyData(queuedInput);
    }
  }

  /// SSH接続してtmuxセッションをセットアップ
  Future<void> _connectAndSetup() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      // 1. 接続情報を取得
      final connection = ref.read(connectionsProvider.notifier).getById(widget.connectionId);
      if (connection == null) {
        throw Exception('Connection not found');
      }

      // 2. 認証情報を取得
      final options = await _getAuthOptions(connection);
      if (!mounted || _isDisposed) {
        return;
      }

      // 3. SSH接続（シェルは起動しない - execのみ使用）
      final sshNotifier = ref.read(sshProvider.notifier);
      await sshNotifier.connectWithoutShell(connection, options);
      if (!mounted || _isDisposed) {
        return;
      }

      // 3.5. tmuxバー��ョン取得（リサイズ機能判定用）
      try {
        final versionOutput = await sshNotifier.client?.exec(TmuxCommands.version());
        if (versionOutput != null) {
          _tmuxVersion = TmuxVersionInfo.parse(versionOutput);
        }
      } catch (_) {
        _tmuxVersion = null;
      }

      // 4. セ���ションツリー全体を取得
      await _refreshSessionTree();
      if (!mounted || _isDisposed) {
        return;
      }

      final tmuxState = ref.read(tmuxProvider);
      final sessions = tmuxState.sessions;

      // 5. セッションを選択または新規作成
      String sessionName;
      if (widget.sessionName != null) {
        // セッション名が指定されている場合
        final existingIndex = sessions.indexWhere(
          (s) => s.name == widget.sessionName,
        );
        if (existingIndex >= 0) {
          // 既存セッションに接続
          sessionName = sessions[existingIndex].name;
        } else {
          // 新規セッション作成
          final sshClient = ref.read(sshProvider.notifier).client;
          await sshClient?.exec(TmuxCommands.newSession(
            name: widget.sessionName!,
            detached: true,
          ));
          if (!mounted || _isDisposed) return;
          await _refreshSessionTree();
          if (!mounted || _isDisposed) return;
          sessionName = widget.sessionName!;
        }
      } else if (sessions.isNotEmpty) {
        // セッション名が指定されていない場合は最初のセッションに接続
        sessionName = sessions.first.name;
      } else {
        // セッションがない場合は自動生成名で新規作成
        final sshClient = ref.read(sshProvider.notifier).client;
        sessionName = 'muxpod-${DateTime.now().millisecondsSinceEpoch}';
        await sshClient?.exec(TmuxCommands.newSession(name: sessionName, detached: true));
        if (!mounted || _isDisposed) return;
        await _refreshSessionTree();
        if (!mounted || _isDisposed) return;
      }

      // 6. アクティブセッション/ウィンドウ/ペインを設定
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

      // 6.1 ディープリンクまたは保存されたウィンドウ/ペイン位置を復元
      if (widget.deepLinkWindowName != null) {
        // ディープリンク: ウィンドウ名で検索
        final tmuxState = ref.read(tmuxProvider);
        final session = tmuxState.activeSession;
        if (session != null) {
          final targetName = widget.deepLinkWindowName!;
          // ウィンドウ名で検索（"index:name" 形式の名前部分にも対応）
          TmuxWindow? window;
          for (final w in session.windows) {
            if (w.name == targetName || w.name.endsWith(':$targetName')) {
              window = w;
              break;
            }
          }
          if (window != null) {
            ref.read(tmuxProvider.notifier).setActiveWindow(window.index);

            // ペインインデックスが指定されている場合
            if (widget.deepLinkPaneIndex != null && widget.deepLinkPaneIndex! < window.panes.length) {
              final pane = window.panes[widget.deepLinkPaneIndex!];
              ref.read(tmuxProvider.notifier).setActivePane(pane.id);
            }
          }
        }
      } else if (widget.lastWindowIndex != null) {
        // 通常の復元: インデックスで検索
        final tmuxState = ref.read(tmuxProvider);
        final session = tmuxState.activeSession;
        if (session != null) {
          // 指定されたウィンドウが存在するか確認
          final window = session.windows.firstWhere(
            (w) => w.index == widget.lastWindowIndex,
            orElse: () => session.windows.first,
          );
          ref.read(tmuxProvider.notifier).setActiveWindow(window.index);

          // ペインIDが指定されていて存在する場合は復元
          if (widget.lastPaneId != null) {
            final pane = window.panes.firstWhere(
              (p) => p.id == widget.lastPaneId,
              orElse: () => window.panes.first,
            );
            ref.read(tmuxProvider.notifier).setActivePane(pane.id);
          }
        }
      }

      // 7. TerminalDisplayProviderにペイン情報を通知（フォントサイズ計算用）
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        debugPrint('[Terminal] Pane size: ${activePane.width}x${activePane.height}');
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
        _viewNotifier.value = _viewNotifier.value.copyWith(
          paneWidth: activePane.width,
          paneHeight: activePane.height,
        );

        // ペインにフォーカスインを送信（Claude Code等のアプリがフォーカスを検知できるようにする）
        await sshNotifier.client?.exec(TmuxCommands.sendKeys(activePane.id, '\x1b[I', literal: true));
      }

      // 8. 100msポーリング開始
      _startPolling();

      // 9. 5秒ごとにセッションツリーを更新
      _startTreeRefresh();

      if (!mounted) return;
      setState(() {
        _isConnecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionError = e.toString();
      });
      _showErrorSnackBar(e.toString());
    }
  }

  /// セッションツリー全体を取得して更新
  Future<void> _refreshSessionTree() async {
    if (_isDisposed) {
      return;
    }
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      return;
    }

    try {
      final cmd = TmuxCommands.listAllPanes();
      final output = await sshClient.exec(cmd);
      if (!mounted || _isDisposed) return;
      ref.read(tmuxProvider.notifier).parseAndUpdateFullTree(output);
    } catch (_) {
      // ツリー更新エラーは静かに無視（次回ポーリングで再試行）
    }
  }

  /// 10秒ごとにセッションツリーを更新
  void _startTreeRefresh() {
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        // ポーリング中はSSH競合を回避するためスキップ
        if (!_isPolling) {
          _refreshSessionTree();
        }
      },
    );
  }

  /// 適応型ポーリングでcapture-paneを実行してターミナル内容を更新
  ///
  /// コンテンツの変化頻度に応じてポーリング間隔を動的に調整:
  /// - 高頻度更新時（htop等）: 50ms
  /// - 通常時: 100ms
  /// - アイドル時: 500ms
  void _startPolling() {
    _pollTimer?.cancel();
    _scheduleNextPoll();
  }

  /// 次のポーリングをスケジュール
  void _scheduleNextPoll() {
    if (_isDisposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(
      Duration(milliseconds: _currentPollingInterval),
      () async {
        await _pollPaneContent();
        _scheduleNextPoll();
      },
    );
  }

  /// キー入力後にポーリングを即座にブースト（アイドル時の応答性改善）
  void _boostPolling() {
    _currentPollingInterval = _minPollingInterval;
    _pollTimer?.cancel();
    _scheduleNextPoll();
  }

  /// ポーリング間隔を更新
  void _updatePollingInterval() {
    final ansiTextViewState = _ansiTextViewKey.currentState;
    if (ansiTextViewState != null) {
      final recommended = ansiTextViewState.recommendedPollingInterval;
      // tmux copy-mode 検出中はポーリング間隔の上限を500msに制限
      // copy-mode終了の検出遅延を最大0.5秒に改善
      final maxInterval = _scrollModeSource == ScrollModeSource.tmux ? 500 : _maxPollingInterval;
      _currentPollingInterval = recommended.clamp(
        _minPollingInterval,
        maxInterval,
      );
    }
  }

  /// ペイン内容をポーリング取得
  Future<void> _pollPaneContent() async {
    if (_isPolling || _isDisposed) return; // 前回のポーリングがまだ実行中 or disposed
    _isPolling = true;

    try {
      final sshNotifier = ref.read(sshProvider.notifier);
      final sshClient = sshNotifier.client;

      // 接続が切れている場合は自動再接続を試みる
      if (sshClient == null || !sshClient.isConnected) {
        // すでに再接続中でなければ再接続を開始
        final currentState = ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          _attemptReconnect();
        }
        _isPolling = false;
        return;
      }

      // tmux_providerからターゲットを取得
      final target = ref.read(tmuxProvider.notifier).currentTarget;
      if (target == null) {
        _isPolling = false;
        return;
      }

      final startTime = DateTime.now();

      // 3つのコマンドを1つに統合して実行（持続的シェルは同時に1コマンドのみ）
      // capture-pane + カーソル位置情報 + ペインモード を1回で取得
      // 出力形式: [ペイン内容]\n[カーソル情報]\n[ペインモード]
      final combinedCommand =
          '${TmuxCommands.capturePane(target, escapeSequences: true, startLine: -1000)}; '
          '${TmuxCommands.getCursorPosition(target)}; '
          '${TmuxCommands.getPaneMode(target)}';

      final combinedOutput = await sshClient.execPersistent(
        combinedCommand,
        timeout: const Duration(seconds: 2),
      );

      // 出力を分割（最後の行がペインモード、その前がカーソル情報）
      final lines = combinedOutput.split('\n');
      final paneModeOutput = lines.isNotEmpty ? lines.removeLast() : '';
      final cursorOutput = lines.isNotEmpty ? lines.removeLast() : '';
      final output = lines.join('\n');

      // capture-paneの出力末尾にある改行を削除
      final processedOutput = output.endsWith('\n')
          ? output.substring(0, output.length - 1)
          : output;

      final endTime = DateTime.now();

      // アンマウント済みならスキップ
      if (!mounted || _isDisposed) return;

      // カーソル位置とペインサイズを更新
      if (cursorOutput.isNotEmpty) {
        final parts = cursorOutput.trim().split(',');
        if (parts.length >= 4) {
          final x = int.tryParse(parts[0]);
          final y = int.tryParse(parts[1]);
          final w = int.tryParse(parts[2]);
          final h = int.tryParse(parts[3]);

          // ペインサイズの更新検知
          if (w != null && h != null && (w != _viewNotifier.value.paneWidth || h != _viewNotifier.value.paneHeight)) {
            _viewNotifier.value = _viewNotifier.value.copyWith(paneWidth: w, paneHeight: h);
            // フォントサイズ再計算のために通知
            final currentActivePane = ref.read(tmuxProvider).activePane;
            if (currentActivePane != null) {
              ref.read(terminalDisplayProvider.notifier).updatePane(
                    currentActivePane.copyWith(width: w, height: h),
                  );
            }
          }

          final activePaneId = ref.read(tmuxProvider).activePaneId;
          if (activePaneId != null && x != null && y != null) {
            ref.read(tmuxProvider.notifier).updateCursorPosition(activePaneId, x, y);
          }
        }
      }

      // レイテンシを更新
      final latency = endTime.difference(startTime).inMilliseconds;

      // 差分があれば更新（スロットリング適用）
      final currentView = _viewNotifier.value;
      if (processedOutput != currentView.content || latency != currentView.latency) {
        // 手動スクロールモード中のみ更新をバッファリングして選択状態を保持
        // tmux copy-mode中はcapture-paneがスクロール位置の内容を返すためリアルタイム表示
        if (_terminalMode == TerminalMode.scroll && _scrollModeSource == ScrollModeSource.manual) {
          _bufferedContent = processedOutput;
          _bufferedLatency = latency;
          _hasBufferedUpdate = true;
          // レイテンシのみ更新（選択に影響しない）
          if (mounted && !_isDisposed) {
            _viewNotifier.value = currentView.copyWith(latency: latency);
          }
        } else {
          _scheduleUpdate(processedOutput, latency);
        }
      }

      // tmux copy-mode 検出による自動モード切替
      if (mounted && !_isDisposed) {
        final paneMode = paneModeOutput.trim();
        final isTmuxCopyMode = paneMode.isNotEmpty;

        if (isTmuxCopyMode && _scrollModeSource == ScrollModeSource.none) {
          // tmux copy-mode に入った → スクロールモードに自動切替
          setState(() {
            _terminalMode = TerminalMode.scroll;
            _scrollModeSource = ScrollModeSource.tmux;
          });
        } else if (!isTmuxCopyMode && _scrollModeSource == ScrollModeSource.tmux) {
          // tmux copy-mode が終了した → 自動で通常モードに復帰
          setState(() {
            _terminalMode = TerminalMode.normal;
            _scrollModeSource = ScrollModeSource.none;
          });
          _applyBufferedUpdate();
        }
      }

      // 適応型ポーリング間隔を更新
      _updatePollingInterval();
    } catch (e) {
      // 通信エラーの場合は自動再接続を試みる
      if (!_isDisposed) {
        final currentState = ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          _attemptReconnect();
        }
      }
    } finally {
      _isPolling = false;
    }
  }

  /// バッファリングされた更新を適用（スクロールモード終了時に呼び出し）
  void _applyBufferedUpdate() {
    if (_hasBufferedUpdate) {
      _scheduleUpdate(_bufferedContent, _bufferedLatency);
      _hasBufferedUpdate = false;
      _bufferedContent = '';
      _bufferedLatency = 0;
    }
  }

  /// フレームスキップを考慮して更新をスケジュール
  ///
  /// 高頻度更新時（htop等）に毎フレーム更新しないようスロットリングを行う。
  /// 16ms（約60fps）以内の連続更新は次フレームに延期される。
  void _scheduleUpdate(String content, int latency) {
    _pendingContent = content;
    _pendingLatency = latency;

    // すでに更新がスケジュール済みなら何もしない
    if (_pendingUpdate) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastFrameTime);

    if (elapsed >= _minFrameInterval) {
      // 十分な時間が経過しているので即時更新
      _applyUpdate();
    } else {
      // フレームスキップ: 次のフレームで更新
      _pendingUpdate = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _pendingUpdate = false;
        _applyUpdate();
      });
    }
  }

  /// 保留中の更新を適用
  void _applyUpdate() {
    if (!mounted || _isDisposed) return;
    _lastFrameTime = DateTime.now();
    // ValueNotifier更新（親のsetState()を回避し、ValueListenableBuilderのみリビルド）
    _viewNotifier.value = _viewNotifier.value.copyWith(
      content: _pendingContent,
      latency: _pendingLatency,
    );

    // 初回コンテンツ受信時に一番下へスクロール
    if (!_hasInitialScrolled && _pendingContent.isNotEmpty) {
      _hasInitialScrolled = true;
      _scrollToCaret();
    }
  }

  /// 自動再接続を試みる
  Future<void> _attemptReconnect() async {
    if (_isDisposed) return;

    final sshNotifier = ref.read(sshProvider.notifier);
    final success = await sshNotifier.reconnect();

    if (!mounted || _isDisposed) return;

    if (!success) {
      // 再接続失敗時は再試行（最大回数に達するまで）
      final currentState = ref.read(sshProvider);
      if (currentState.reconnectAttempt < 5) {
        // 次のポーリングで再試行される
      }
    }
  }

  /// 認証オプションを取得
  Future<SshConnectOptions> _getAuthOptions(Connection connection) async {
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await _secureStorage.getPrivateKey(connection.keyId!);
      final passphrase = await _secureStorage.getPassphrase(connection.keyId!);
      return SshConnectOptions(privateKey: privateKey, passphrase: passphrase);
    } else {
      final password = await _secureStorage.getPassword(connection.id);
      return SshConnectOptions(password: password);
    }
  }

  /// エラーSnackBar表示
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _connectAndSetup,
        ),
      ),
    );
  }

  /// スクロール時にスクロールボタンを表示
  void _onTerminalScroll() {
    _scrollToBottomKey.currentState?.show();
  }

  @override
  @override
  void deactivate() {
    // ref.readはdeactivateまでは安全（disposeでは_elementsから外れている）
    final sshNotifier = ref.read(sshProvider.notifier);
    sshNotifier.onReconnectSuccess = null;
    sshNotifier.onDisconnectDetected = null;

    // popUntil等で_disconnect()を経由せずにpopされた場合もSSHを切断
    if (sshNotifier.checkConnection()) {
      sshNotifier.disconnect();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    // まず_isDisposedをセットして非同期処理を停止
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // WakeLockを無効化
    WakelockPlus.disable();
    // Riverpodサブスクリプションをキャンセル
    _sshSubscription?.close();
    _sshSubscription = null;
    _tmuxSubscription?.close();
    _tmuxSubscription = null;
    _settingsSubscription?.close();
    _settingsSubscription = null;
    _networkSubscription?.close();
    _networkSubscription = null;
    _imageTransferSub?.close();
    _imageTransferSub = null;
    // タイマーを停止
    _pollTimer?.cancel();
    _pollTimer = null;
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = null;
    // キーオーバーレイ
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = null;
    _keyOverlayState.dispose();
    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = null;
    // ValueNotifierを破棄
    _viewNotifier.dispose();
    // スクロールコントローラーのリスナーを削除して破棄
    _terminalScrollController.removeListener(_onTerminalScroll);
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ローカル状態を使用（ref.watchは使わない）
    // 注意: tmuxProviderは各Consumer内でref.watchして取得する
    // これにより親build()がポーリングで呼ばれず、BottomSheetが安定する
    final sshState = _sshState;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // ブレッドクラム: ConsumerでtmuxProviderを直接watch（親リビルド不要）
              Consumer(
                builder: (context, ref, _) {
                  final tmuxState = ref.watch(tmuxProvider);
                  return _buildBreadcrumbHeader(tmuxState);
                },
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _terminalMode == TerminalMode.scroll
                          ? DesignColors.warning
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // ターミナル表示: ValueListenableBuilder + Consumer
                      // ポーリング更新はValueNotifier経由でこのサブツリーのみリビルド
                      RepaintBoundary(
                        child: ValueListenableBuilder<_TerminalViewData>(
                          valueListenable: _viewNotifier,
                          builder: (context, viewData, _) {
                            return Consumer(
                              builder: (context, ref, _) {
                                final cursor = ref.watch(tmuxProvider.select((s) => (
                                  x: s.activePane?.cursorX ?? 0,
                                  y: s.activePane?.cursorY ?? 0,
                                )));
                                return AnsiTextView(
                                  key: _ansiTextViewKey,
                                  text: viewData.content,
                                  paneWidth: viewData.paneWidth,
                                  paneHeight: viewData.paneHeight,
                                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                                  onKeyInput: _handleKeyInput,
                                  onTap: () {
                                    _scrollToBottomKey.currentState?.show();
                                  },
                                  mode: _terminalMode,
                                  zoomEnabled: true,
                                  onZoomChanged: (scale) {
                                    setState(() {
                                      _zoomScale = scale;
                                    });
                                  },
                                  verticalScrollController: _terminalScrollController,
                                  cursorX: cursor.x,
                                  cursorY: cursor.y,
                                  onArrowSwipe: _sendSpecialKeyWithOverlay,
                                  onTwoFingerSwipe: _handleTwoFingerSwipe,
                                  navigableDirections: _getNavigableDirections(),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      // Pane indicator: ConsumerでtmuxProviderを直接watch
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final tmuxState = ref.watch(tmuxProvider);
                            return _buildPaneIndicator(tmuxState);
                          },
                        ),
                      ),
                      // スクロールボタン: ターミナルエリア右下
                      Positioned(
                        bottom: 8,
                        right: 16,
                        child: ScrollToBottomButton(
                          key: _scrollToBottomKey,
                          onPressed: () {
                            _ansiTextViewKey.currentState?.scrollToBottom();
                          },
                        ),
                      ),
                      // キーオーバーレイ
                      KeyOverlayWidget(
                        overlayState: _keyOverlayState,
                        position: _keyOverlayPosition,
                      ),
                    ],
                  ),
                ),
              ),
              // 画像アップロード進捗バー
              Consumer(
                builder: (context, ref, _) {
                  final transfer = ref.watch(imageTransferProvider);
                  final isActive = transfer.phase == ImageTransferPhase.uploading ||
                      transfer.phase == ImageTransferPhase.converting;
                  if (!isActive) return const SizedBox.shrink();
                  return LinearProgressIndicator(
                    value: transfer.uploadProgress > 0 ? transfer.uploadProgress : null,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                  );
                },
              ),
              SpecialKeysBar(
                onKeyPressed: _sendKeyWithOverlay,
                onSpecialKeyPressed: _sendSpecialKeyWithOverlay,
                onInputTap: _showInputDialog,
                directInputEnabled: _directInputEnabled,
                onDirectInputToggle: () {
                  ref.read(settingsProvider.notifier).toggleDirectInput();
                },
                onImagePickRequested: _handleImageTransfer,
              ),
            ],
          ),
          // ローディングオーバーレイ
          if (_isConnecting || sshState.isConnecting)
            Container(
              color: isDark ? Colors.black54 : Colors.white70,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          // エラーオーバーレイ
          if (_connectionError != null || sshState.hasError)
            _buildErrorOverlay(sshState.error ?? _connectionError),
        ],
      ),
    );
  }

  // --- キーオーバーレイ ラッパー ---

  KeyOverlayPosition get _keyOverlayPosition {
    final pos = ref.read(settingsProvider).keyOverlayPosition;
    return switch (pos) {
      'center' => KeyOverlayPosition.center,
      'belowHeader' => KeyOverlayPosition.belowHeader,
      _ => KeyOverlayPosition.aboveKeyboard,
    };
  }

  /// 特殊キー送信 + オーバーレイ表示
  void _sendSpecialKeyWithOverlay(String tmuxKey) {
    _sendSpecialKey(tmuxKey);
    _showKeyOverlay(tmuxKey);
  }

  /// リテラルキー送信 + ショートカットキーのオーバーレイ表示
  void _sendKeyWithOverlay(String key) {
    _sendKey(key);
    if (TmuxKeyDisplay.isShortcutKey(key)) {
      _showKeyOverlay(key);
    }
  }

  /// オーバーレイ表示ロジック
  void _showKeyOverlay(String key) {
    final settings = ref.read(settingsProvider);
    if (!settings.showKeyOverlay) return;

    final category = TmuxKeyDisplay.categoryOf(key);
    if (category == null) return;

    final enabled = switch (category) {
      KeyOverlayCategory.modifier => settings.keyOverlayModifier,
      KeyOverlayCategory.special => settings.keyOverlaySpecial,
      KeyOverlayCategory.arrow => settings.keyOverlayArrow,
      KeyOverlayCategory.shortcut => settings.keyOverlayShortcut,
    };
    if (!enabled) return;

    _keyOverlayState.show(TmuxKeyDisplay.displayText(key));
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = Timer(const Duration(milliseconds: 1500), () {
      _keyOverlayState.hide();
    });
  }

  /// AnsiTextViewからのキー入力を処理
  void _handleKeyInput(KeyInputEvent event) {
    // 特殊キーの場合はtmux形式で送信（オーバーレイ付き）
    if (event.isSpecialKey && event.tmuxKeyName != null) {
      _sendSpecialKeyWithOverlay(event.tmuxKeyName!);
    } else {
      // 通常の文字はリテラル送信
      _sendKeyData(event.data);
    }
  }

  /// 2本指スワイプによるペイン切り替え
  void _handleTwoFingerSwipe(SwipeDirection direction) {
    final tmuxState = ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return;

    // 設定に応じてスワイプ方向を反転
    final settings = ref.read(settingsProvider);
    final actualDirection = settings.invertPaneNavigation
        ? direction.inverted
        : direction;

    final targetPane = PaneNavigator.findAdjacentPane(
      panes: window.panes,
      current: activePane,
      direction: actualDirection,
    );

    if (targetPane != null) {
      _selectPane(targetPane.id);
    }
  }

  /// 現在のペインからナビゲーション可能な方向を取得
  Map<SwipeDirection, bool>? _getNavigableDirections() {
    final tmuxState = ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return null;

    final rawDirections = PaneNavigator.getNavigableDirections(
      panes: window.panes,
      current: activePane,
    );

    // 反転設定が有効な場合、方向キーを入れ替える
    final settings = ref.read(settingsProvider);
    if (settings.invertPaneNavigation) {
      return {
        for (final dir in SwipeDirection.values)
          dir: rawDirections[dir.inverted] ?? false,
      };
    }

    return rawDirections;
  }

  /// キーデータをtmux send-keysで送信
  Future<void> _sendKeyData(String data) async {
    final sshClient = ref.read(sshProvider.notifier).client;

    // 接続が切れている場合はキューに追加
    if (sshClient == null || !sshClient.isConnected) {
      _inputQueue.enqueue(data);
      if (mounted) setState(() {}); // キューイング状態を更新
      return;
    }

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      // エスケープシーケンスや特殊キーはリテラルで送信
      await sshClient.exec(TmuxCommands.sendKeys(target, data, literal: true));
      _boostPolling();
    } catch (_) {
      // キー送信エラーは静かに無視
    }
  }

  /// セッションを選択
  Future<void> _selectSession(String sessionName) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // tmux_providerでアクティブセッションを更新
    ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

    // アクティブなペインを選択状態にする（select-paneコマンドを実行）
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await _selectPane(activePaneId);
    } else {
      // ターミナル内容をクリアして再取得
      _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
      _hasInitialScrolled = false;
    }
  }

  /// ウィンドウを選択
  Future<void> _selectWindow(String sessionName, int windowIndex) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    // セッションが異なる場合はセッションも切り替え
    final currentSession = ref.read(tmuxProvider).activeSessionName;
    if (currentSession != sessionName) {
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);
    }

    try {
      // tmux select-windowを実行
      await sshClient.exec(TmuxCommands.selectWindow(sessionName, windowIndex));
    } catch (e) {
      // SSH接続が閉じている場合は無視
      debugPrint('[Terminal] Failed to select window: $e');
      return;
    }
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブウィンドウを更新
    ref.read(tmuxProvider.notifier).setActiveWindow(windowIndex);

    // アクティブなペインを選択状態にする（select-paneコマンドを実行）
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await _selectPane(activePaneId);
    } else {
      // ターミナル内容をクリアして再取得
      _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
      _hasInitialScrolled = false;
    }
  }

  /// ペインを選択
  Future<void> _selectPane(String paneId) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final oldPaneId = ref.read(tmuxProvider).activePaneId;

    try {
      // 前のペインにフォーカスアウトを送信
      if (oldPaneId != null && oldPaneId != paneId) {
        await sshClient.exec(TmuxCommands.sendKeys(oldPaneId, '\x1b[O', literal: true));
      }

      // tmux select-paneを実行
      await sshClient.exec(TmuxCommands.selectPane(paneId));

      // 新しいペインにフォーカスインを送信（Claude Code等のアプリがフォーカスを検知できるようにする）
      await sshClient.exec(TmuxCommands.sendKeys(paneId, '\x1b[I', literal: true));
    } catch (e) {
      // SSH接続が閉じている場合は無視
      debugPrint('[Terminal] Failed to select pane: $e');
      return;
    }
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブペインを更新
    ref.read(tmuxProvider.notifier).setActivePane(paneId);

    // TerminalDisplayProviderにペイン情報を通知（フォントサイズ計算用）
    final activePane = ref.read(tmuxProvider).activePane;
    final tmuxState = ref.read(tmuxProvider);
    if (activePane != null) {
      ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      _viewNotifier.value = _viewNotifier.value.copyWith(
        paneWidth: activePane.width,
        paneHeight: activePane.height,
        content: '',
      );
      // ペイン切り替え時は初回スクロールフラグをリセット
      // 次のコンテンツ受信時に最下部へスクロールされる
      _hasInitialScrolled = false;

      // 自動リサイズ: ペイン選択時に画面サイズに合わせてtmuxペインをリサイズ
      final settings = ref.read(settingsProvider);
      if (settings.isAutoResize) {
        await _executeAutoResize(activePane);
      }

      // セッション情報を保存（復元用）
      final sessionName = tmuxState.activeSessionName;
      final windowIndex = tmuxState.activeWindowIndex;
      if (sessionName != null && windowIndex != null) {
        ref.read(activeSessionsProvider.notifier).updateLastPane(
              connectionId: widget.connectionId,
              sessionName: sessionName,
              windowIndex: windowIndex,
              paneId: paneId,
            );
      }
    }
  }

  /// キャレット位置にスクロール
  ///
  /// パネル/ウィンドウ切り替え後の初回表示時に呼ばれ、
  /// カーソル行が画面中央付近に来るようスクロールする
  void _scrollToCaret() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || _isDisposed) return;
      _ansiTextViewKey.currentState?.scrollToCaret();
    });
  }

  /// エラーオーバーレイ
  Widget _buildErrorOverlay(String? error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final queuedCount = _inputQueue.length;
    final isWaitingForNetwork = _sshState.isWaitingForNetwork;

    return Container(
      color: isDark ? Colors.black87 : Colors.white.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWaitingForNetwork ? Icons.signal_wifi_off : Icons.error_outline,
              color: isWaitingForNetwork ? DesignColors.warning : colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isWaitingForNetwork
                  ? 'Waiting for network...'
                  : (error ?? 'Connection error'),
              style: TextStyle(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),

            // キューイング状態
            if (queuedCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: DesignColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard,
                      size: 16,
                      color: DesignColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$queuedCount chars queued',
                      style: TextStyle(
                        color: DesignColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        _inputQueue.clear();
                        setState(() {});
                      },
                      child: Icon(
                        Icons.clear,
                        size: 16,
                        color: DesignColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    ref.read(sshProvider.notifier).reconnectNow();
                  },
                  child: const Text('Retry Now'),
                ),
                if (_sshState.isReconnecting) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 上部のパンくずナビゲーションヘッダー
  Widget _buildBreadcrumbHeader(TmuxState tmuxState) {
    final currentSession = tmuxState.activeSessionName ?? '';
    final activeWindow = tmuxState.activeWindow;
    final currentWindow = activeWindow?.name ?? '';
    final activePane = tmuxState.activePane;
    final colorScheme = Theme.of(context).colorScheme;

    // SafeAreaを外側に配置してステータスバー分のスペースを確保
    return SafeArea(
      bottom: false,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.9),
          border: Border(
            bottom: BorderSide(color: colorScheme.outline, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Breadcrumb navigation
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // セッション名（タップで切り替え）
                    _buildBreadcrumbItem(
                      currentSession,
                      icon: Icons.folder,
                      isActive: true,
                      onTap: () => _showSessionSelector(tmuxState),
                    ),
                    _buildBreadcrumbSeparator(),
                    // ウィンドウ名（タップで切り替え）
                    _buildBreadcrumbItem(
                      currentWindow,
                      icon: Icons.tab,
                      isSelected: true,
                      onTap: () => _showWindowSelector(tmuxState),
                    ),
                    // ペインがあれば表示
                    if (activePane != null) ...[
                      _buildBreadcrumbSeparator(),
                      _buildBreadcrumbItem(
                        'Pane ${activePane.index}',
                        icon: Icons.terminal,
                        isActive: false,
                        onTap: () => _showPaneSelector(tmuxState),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Scroll mode indicator
            if (_terminalMode == TerminalMode.scroll)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: DesignColors.warning.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.unfold_more, size: 12, color: DesignColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      'Scroll',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: DesignColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            // Zoom indicator
            if (_zoomScale != 1.0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(_zoomScale * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: DesignColors.warning,
                  ),
                ),
              ),
            // Latency / Reconnect indicator（ValueListenableBuilderでポーリング更新をスコープ）
            ValueListenableBuilder<_TerminalViewData>(
              valueListenable: _viewNotifier,
              builder: (context, viewData, _) => _buildConnectionIndicator(viewData.latency),
            ),
            // File browser button
            IconButton(
              onPressed: _handleFileBrowser,
              icon: Icon(
                Icons.folder_outlined,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              tooltip: 'File Browser',
            ),
            // Settings button
            IconButton(
              onPressed: _showTerminalMenu,
              icon: Icon(
                Icons.settings,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// セッション選択ダイアログを表示
  void _showSessionSelector(TmuxState tmuxState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.6;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.folder, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Session',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outline),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tmuxState.sessions.length,
                    itemBuilder: (context, index) {
                      final session = tmuxState.sessions[index];
                      final isActive = session.name == tmuxState.activeSessionName;
                      return TmuxSessionTile(
                        session: session,
                        isActive: isActive,
                        onTap: () {
                          Navigator.pop(context);
                          _selectSession(session.name);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// ウィンドウ選択ダイアログを表示
  void _showWindowSelector(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    if (session == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.6;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.tab, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Window',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.open_in_full, color: colorScheme.primary),
                        tooltip: 'Resize Window',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Future.delayed(const Duration(milliseconds: 200), () {
                            if (mounted) _showResizeWindowChooser(tmuxState);
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.add, color: colorScheme.primary),
                        tooltip: 'New Window',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Future.delayed(const Duration(milliseconds: 200), () {
                            if (mounted) _showCreateWindowDialog(session);
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outline),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: session.windows.length,
                    itemBuilder: (context, index) {
                      final window = session.windows[index];
                      final isActive = window.index == tmuxState.activeWindowIndex;
                      return TmuxWindowTile(
                        window: window,
                        isActive: isActive,
                        onTap: () {
                          Navigator.pop(context);
                          _selectWindow(session.name, window.index);
                        },
                        onResize: () {
                          Navigator.pop(context);
                          _handleResizeWindow(window);
                        },
                        onClose: () {
                          Navigator.pop(context);
                          _confirmAndKillWindow(
                            sessionName: session.name,
                            windowIndex: window.index,
                            windowName: window.name,
                            isLastWindow: session.windows.length == 1,
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// ウィンドウ作成ダイアログを表示
  void _showCreateWindowDialog(TmuxSession session) {
    final existingNames = session.windows.map((w) => w.name).toList();
    showDialog<String>(
      context: context,
      builder: (dialogContext) => _NewWindowDialog(
        existingWindowNames: existingNames,
      ),
    ).then((windowName) {
      if (windowName != null) {
        _createWindow(windowName.isEmpty ? null : windowName);
      }
    });
  }

  /// 新しいウィンドウを作成
  Future<void> _createWindow(String? windowName) async {
    if (_isCreatingWindow) return;
    _isCreatingWindow = true;
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SSH connection is not available')),
          );
        }
        return;
      }
      final session = ref.read(tmuxProvider).activeSession;
      if (session == null) return;

      await sshClient.exec(TmuxCommands.newWindow(
        sessionName: session.name,
        windowName: windowName,
      ));
      await _refreshSessionTree();
      if (!mounted) return;

      // active=1のウィンドウを検出して自動切替
      final updatedSession = ref.read(tmuxProvider).activeSession;
      final activeWindow =
          updatedSession?.windows.where((w) => w.active).firstOrNull;
      if (activeWindow != null) {
        ref.read(tmuxProvider.notifier).setActiveWindow(activeWindow.index);
        _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
        _hasInitialScrolled = false;
        final activePaneId = ref.read(tmuxProvider).activePaneId;
        if (activePaneId != null) {
          await _selectPane(activePaneId);
        }
      }
      _boostPolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create window: $e')),
        );
      }
    } finally {
      _isCreatingWindow = false;
    }
  }

  /// ペインを分割
  Future<void> _splitPane(String paneId, SplitDirection direction) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    try {
      final command = direction == SplitDirection.horizontal
          ? TmuxCommands.splitWindowHorizontal(target: paneId)
          : TmuxCommands.splitWindowVertical(target: paneId);
      await sshClient.exec(command);
      await _refreshSessionTree();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to split pane: $e')),
        );
      }
    }
  }

  /// ペインを閉じる確認ダイアログを表示
  void _confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastWindow,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
          title: Text(
            'Close Pane?',
            style: TextStyle(
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
          ),
          content: Text(
            isLastPane && isLastWindow
                ? 'This is the last pane in the last window. Closing it will end the session and disconnect from the server.'
                : isLastPane
                    ? 'This is the last pane in this window. Closing it will also close the window.'
                    : 'Are you sure you want to close pane "$paneTitle"?',
            style: TextStyle(
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // 実行直前にペインがまだ存在するか再検証
                final currentWindow = ref.read(tmuxProvider).activeWindow;
                if (currentWindow == null ||
                    !currentWindow.panes.any((p) => p.id == paneId)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('This pane no longer exists')),
                    );
                  }
                  return;
                }
                _killPane(
                  paneId: paneId,
                  isLastPane: isLastPane,
                  isLastWindow: isLastWindow,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// リサイズ対象のペインをグラフィカルに選択するダイアログ
  void _showResizePaneChooser(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    if (window == null || window.panes.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _ResizePaneChooserDialog(
          panes: window.panes,
          activePaneId: tmuxState.activePaneId,
          onResize: (selectedPane) {
            Navigator.pop(dialogContext);
            _handleResizePane(selectedPane);
          },
        );
      },
    );
  }

  /// リサイズ対象のウィンドウをグラフィカルに選択するダイアログ
  void _showResizeWindowChooser(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    if (session == null || session.windows.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _ResizeWindowChooserDialog(
          windows: session.windows,
          activeWindowIndex: tmuxState.activeWindowIndex,
          onResize: (selectedWindow) {
            Navigator.pop(dialogContext);
            _handleResizeWindow(selectedWindow);
          },
        );
      },
    );
  }

  /// 自動リサイズ: 画面サイズに合わせてtmuxペインをリサイズ
  Future<void> _executeAutoResize(TmuxPane pane) async {
    if (_isResizing) return;
    if (_tmuxVersion != null && !_tmuxVersion!.supportsResizePaneToSize) return;

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);

    final fontSize = settings.fontSize;
    final targetCols = FontCalculator.calculateMaxCols(
      screenWidth: displayState.screenWidth,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );
    final targetRows = FontCalculator.calculateMaxRows(
      screenHeight: displayState.screenHeight,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );

    debugPrint('[AutoResize] screenWidth=${displayState.screenWidth} '
        'screenHeight=${displayState.screenHeight} '
        'fontSize=$fontSize '
        'fontFamily=${settings.fontFamily} '
        'pane=${pane.id} current=${pane.width}x${pane.height} '
        'target=${targetCols}x$targetRows');

    // 既存サイズと同一ならスキップ
    if (pane.width == targetCols && pane.height == targetRows) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) return;
      await sshClient.exec(
        TmuxCommands.resizePaneToSize(pane.id, cols: targetCols, rows: targetRows),
      );
      await _refreshSessionTree();
      final updatedPane = ref.read(tmuxProvider).activePane;
      if (updatedPane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(updatedPane);
      }
    } catch (e) {
      debugPrint('[AutoResize] Failed: $e');
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// ペインをリサイズ
  Future<void> _handleResizePane(TmuxPane pane) async {
    if (_isResizing) return;

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);
    final tmuxState = ref.read(tmuxProvider);

    // 現在のウィンドウの全ペインを取���
    final activeWindow = tmuxState.activeWindow;
    final allPanes = activeWindow?.panes ?? [pane];

    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (context) => ResizePaneDialog(
        targetPane: pane,
        allPanesInWindow: allPanes,
        currentCols: pane.width,
        currentRows: pane.height,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
      ),
    );

    if (result == null || !mounted) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null) return;
      await sshClient.exec(
        TmuxCommands.resizePaneToSize(pane.id, cols: result.cols, rows: result.rows),
      );
      await _refreshSessionTree();
      // 明示的にupdatePaneを呼んでフォント再計算
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resize failed: $e')),
        );
      }
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// ウィンドウをリサイズ
  Future<void> _handleResizeWindow(TmuxWindow window) async {
    if (_isResizing) return;

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);

    // ウィンドウサイズはペインのwidth+leftの最大値で推定
    final panes = window.panes;
    int windowCols = 80;
    int windowRows = 24;
    if (panes.isNotEmpty) {
      windowCols = panes.map((p) => p.left + p.width).reduce((a, b) => a > b ? a : b);
      windowRows = panes.map((p) => p.top + p.height).reduce((a, b) => a > b ? a : b);
    }

    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (context) => ResizeWindowDialog(
        window: window,
        panes: panes,
        currentCols: windowCols,
        currentRows: windowRows,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
        supportsResizeWindow: _tmuxVersion?.supportsResizeWindow ?? false,
      ),
    );

    if (result == null || !mounted) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null) return;
      final tmuxState = ref.read(tmuxProvider);
      final target = '${tmuxState.activeSessionName}:${window.index}';
      await sshClient.exec(
        TmuxCommands.resizeWindow(target, cols: result.cols, rows: result.rows),
      );
      await _refreshSessionTree();
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resize failed: $e')),
        );
      }
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// ペインを閉じる（SSH経由でkill-pane実行）
  Future<void> _killPane({
    required String paneId,
    required bool isLastPane,
    required bool isLastWindow,
  }) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    // ポーリング停止（SSH競合回避）
    _pollTimer?.cancel();

    try {
      await sshClient.exec(TmuxCommands.killPane(paneId));
      await _refreshSessionTree();
      if (!mounted || _isDisposed) return;

      // セッション消滅確認（最後のウィンドウの最後のペインだった場合）
      if (isLastPane && isLastWindow) {
        final sessionsOutput =
            await sshClient.exec('tmux list-sessions 2>/dev/null || true');
        if (!mounted || _isDisposed) return;
        if (sessionsOutput.trim().isEmpty) {
          await _disconnect();
          return;
        }
      }

      // 最後のペインだった場合→tmuxが自動選択した新ウィンドウに同期
      if (isLastPane) {
        final newTmuxState = ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow =
              newSession.windows.where((w) => w.active).firstOrNull ??
                  newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _selectWindow(newSession.name, newActiveWindow.index);
          }
        }
      } else {
        // 同じウィンドウ内の残りペインに同期
        final newTmuxState = ref.read(tmuxProvider);
        final activeWindow = newTmuxState.activeWindow;
        if (activeWindow != null) {
          final newActivePane =
              activeWindow.panes.where((p) => p.active).firstOrNull ??
                  activeWindow.panes.firstOrNull;
          if (newActivePane != null) {
            await _selectPane(newActivePane.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill pane: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to close pane: $e')),
        );
      }
    } finally {
      // ポーリング再開
      if (mounted && !_isDisposed) {
        _startPolling();
      }
    }
  }

  /// ペイン選択ダイアログを表示
  void _showPaneSelector(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    if (window == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.terminal, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Pane',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.open_in_full, color: colorScheme.primary),
                        tooltip: 'Resize Pane',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Future.delayed(const Duration(milliseconds: 200), () {
                            if (mounted) _showResizePaneChooser(tmuxState);
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outline),
                // ペインレイアウトのビジュアル表示
                _PaneLayoutVisualizer(
                  panes: window.panes,
                  activePaneId: tmuxState.activePaneId,
                  onPaneSelected: (paneId) {
                    Navigator.pop(sheetContext);
                    _selectPane(paneId);
                  },
                  onSplitRequested: (paneId, direction) {
                    Navigator.pop(sheetContext);
                    _splitPane(paneId, direction);
                  },
                ),
                Divider(height: 1, color: colorScheme.outline),
                // ペイン一覧
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: window.panes.length,
                    itemBuilder: (context, index) {
                      final pane = window.panes[index];
                      final isActive = pane.id == tmuxState.activePaneId;
                      // タイトルを優先表示、なければコマンド名、それもなければPaneインデックス
                      final paneTitle = pane.title?.isNotEmpty == true
                          ? pane.title!
                          : (pane.currentCommand?.isNotEmpty == true
                              ? pane.currentCommand!
                              : 'Pane ${pane.index}');
                      return TmuxPaneTile(
                        pane: pane,
                        paneTitle: paneTitle,
                        isActive: isActive,
                        onTap: () {
                          Navigator.pop(context);
                          _selectPane(pane.id);
                        },
                        onLongPress: () {
                          Navigator.pop(context);
                          _confirmAndKillPane(
                            paneId: pane.id,
                            paneTitle: paneTitle,
                            isLastPane: window.panes.length == 1,
                            isLastWindow:
                                (tmuxState.activeSession?.windows.length ??
                                        0) ==
                                    1,
                          );
                        },
                        onResize: () {
                          Navigator.pop(context);
                          _handleResizePane(pane);
                        },
                        onClose: () {
                          Navigator.pop(context);
                          _confirmAndKillPane(
                            paneId: pane.id,
                            paneTitle: paneTitle,
                            isLastPane: window.panes.length == 1,
                            isLastWindow:
                                (tmuxState.activeSession?.windows.length ??
                                        0) ==
                                    1,
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  Widget _buildBreadcrumbItem(
    String label, {
    IconData? icon,
    bool isActive = false,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.05)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: isActive
                    ? colorScheme.primary
                    : (isSelected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label.isEmpty ? '...' : label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: isActive || isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isActive
                    ? colorScheme.primary
                    : (isSelected ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: isActive
                    ? colorScheme.primary.withValues(alpha: 0.7)
                    : colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbSeparator() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '/',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w300,
          color: colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// ターミナルメニューを表示
  void _showTerminalMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBgColor = isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedTextColor = isDark ? Colors.white38 : Colors.black38;
    final inactiveIconColor = isDark ? Colors.white60 : Colors.black45;

    showModalBottomSheet(
      context: context,
      backgroundColor: menuBgColor,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: DesignColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Terminal Options',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300),
              // モード切り替え（Normal / Scroll & Select）
              ListTile(
                leading: Icon(
                  _terminalMode == TerminalMode.scroll
                      ? Icons.unfold_more
                      : Icons.keyboard,
                  color: _terminalMode == TerminalMode.scroll
                      ? DesignColors.warning
                      : inactiveIconColor,
                ),
                title: Text(
                  _terminalMode == TerminalMode.scroll
                      ? 'Scroll & Select Mode'
                      : 'Normal Mode',
                  style: TextStyle(
                    color: _terminalMode == TerminalMode.scroll
                        ? DesignColors.warning
                        : textColor,
                    fontWeight: _terminalMode == TerminalMode.scroll
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  _terminalMode == TerminalMode.scroll
                      ? 'Tap to return to normal mode'
                      : 'Tap to enable text selection',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                trailing: Switch(
                  value: _terminalMode == TerminalMode.scroll,
                  onChanged: (value) {
                    final newMode = value
                        ? TerminalMode.scroll
                        : TerminalMode.normal;
                    setState(() {
                      _terminalMode = newMode;
                      _scrollModeSource = value ? ScrollModeSource.manual : ScrollModeSource.none;
                    });
                    if (newMode == TerminalMode.scroll) {
                      _enterTmuxCopyMode();
                    } else {
                      _cancelTmuxCopyMode();
                      _applyBufferedUpdate();
                    }
                    Navigator.pop(context);
                  },
                  activeThumbColor: DesignColors.warning,
                ),
                onTap: () {
                  final isScrolling = _terminalMode == TerminalMode.scroll;
                  final newMode = isScrolling
                      ? TerminalMode.normal
                      : TerminalMode.scroll;
                  setState(() {
                    _terminalMode = newMode;
                    _scrollModeSource = isScrolling ? ScrollModeSource.none : ScrollModeSource.manual;
                  });
                  if (newMode == TerminalMode.scroll) {
                    _enterTmuxCopyMode();
                  } else {
                    _cancelTmuxCopyMode();
                    _applyBufferedUpdate();
                  }
                  Navigator.pop(context);
                },
              ),
              // ズームリセット
              ListTile(
                leading: Icon(
                  Icons.zoom_out_map,
                  color: _zoomScale != 1.0 ? DesignColors.warning : inactiveIconColor,
                ),
                title: Text(
                  'Reset Zoom',
                  style: TextStyle(
                    color: _zoomScale != 1.0 ? textColor : mutedTextColor,
                  ),
                ),
                subtitle: Text(
                  _zoomScale != 1.0
                      ? 'Current: ${(_zoomScale * 100).toStringAsFixed(0)}%'
                      : 'Pinch to zoom in/out',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                enabled: _zoomScale != 1.0,
                onTap: _zoomScale != 1.0
                    ? () {
                        _ansiTextViewKey.currentState?.resetZoom();
                        setState(() {
                          _zoomScale = 1.0;
                        });
                        Navigator.pop(context);
                      }
                    : null,
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300),
              // 設定画面へ
              ListTile(
                leading: Icon(
                  Icons.settings,
                  color: inactiveIconColor,
                ),
                title: Text(
                  'Settings',
                  style: TextStyle(color: textColor),
                ),
                subtitle: Text(
                  'Font, theme, and other options',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300),
              // 切断ボタン
              ListTile(
                leading: Icon(
                  Icons.power_settings_new,
                  color: DesignColors.error,
                ),
                title: Text(
                  'Disconnect',
                  style: TextStyle(
                    color: DesignColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Close SSH connection',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDisconnectConfirmation();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// ウィンドウ閉じる確認ダイアログを表示
  void _confirmAndKillWindow({
    required String sessionName,
    required int windowIndex,
    required String windowName,
    required bool isLastWindow,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
          title: Text(
            'Close Window?',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            isLastWindow
                ? 'This is the last window in the session. Closing it will end the session and disconnect from the server.'
                : 'Are you sure you want to close window "$windowName"?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final wasActive = windowIndex == ref.read(tmuxProvider).activeWindowIndex;
                _killWindow(
                  sessionName: sessionName,
                  windowIndex: windowIndex,
                  wasActiveWindow: wasActive,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// ウィンドウを閉じる
  Future<void> _killWindow({
    required String sessionName,
    required int windowIndex,
    required bool wasActiveWindow,
  }) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    try {
      debugPrint('[Terminal] Killing window: $sessionName:$windowIndex');
      await sshClient.exec(TmuxCommands.killWindow(sessionName, windowIndex));
      await _refreshSessionTree();

      if (!mounted || _isDisposed) return;

      // セッション消滅判定: list-sessionsで直接確認
      final sessionsOutput = await sshClient.exec('tmux list-sessions 2>/dev/null || true');
      if (sessionsOutput.trim().isEmpty) {
        debugPrint('[Terminal] Last window closed, session terminated. Disconnecting...');
        await _disconnect();
        return;
      }

      // アクティブウィンドウを閉じた場合、tmuxが自動選択した新ウィンドウに同期
      if (wasActiveWindow) {
        final newTmuxState = ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow = newSession.windows.where((w) => w.active).firstOrNull
              ?? newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _selectWindow(newSession.name, newActiveWindow.index);
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill window: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to close window: $e')),
        );
      }
    }
  }

  /// 切断確認ダイアログを表示
  void _showDisconnectConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
          title: Text(
            'Disconnect?',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            'Are you sure you want to disconnect from the server?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // ダイアログを閉じる
                await _disconnect();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Disconnect'),
            ),
          ],
        );
      },
    );
  }

  /// SSH接続を切断して前の画面に戻る
  Future<void> _disconnect() async {
    // ポーリングを停止
    _pollTimer?.cancel();
    _treeRefreshTimer?.cancel();

    // SSH切断
    await ref.read(sshProvider.notifier).disconnect();

    // 前の画面に戻る
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// 接続状態インジケーター（レイテンシまたは再接続状態を表示）
  Widget _buildConnectionIndicator(int latency) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: _sshState.isReconnecting
          ? _buildReconnectingIndicator()
          : _buildLatencyIndicator(latency),
    );
  }

  /// レイテンシ表示
  Widget _buildLatencyIndicator(int latency) {
    // レイテンシに応じた色を決定
    Color indicatorColor;
    if (latency < 100) {
      indicatorColor = DesignColors.success; // 緑: 良好
    } else if (latency < 300) {
      indicatorColor = DesignColors.primary; // シアン: 普通
    } else if (latency < 500) {
      indicatorColor = DesignColors.warning; // オレンジ: やや遅い
    } else {
      indicatorColor = DesignColors.error; // 赤: 遅い
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bolt,
          size: 10,
          color: indicatorColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '${latency}ms',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: indicatorColor.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  /// 再接続中インジケーター
  Widget _buildReconnectingIndicator() {
    final attempt = _sshState.reconnectAttempt;
    final isWaitingForNetwork = _sshState.isWaitingForNetwork;
    final nextRetryAt = _sshState.nextRetryAt;
    final queuedCount = _inputQueue.length;

    // 次回リトライまでの秒数を計算
    String? countdownText;
    if (nextRetryAt != null && !isWaitingForNetwork) {
      final remaining = nextRetryAt.difference(DateTime.now()).inSeconds;
      if (remaining > 0) {
        countdownText = '${remaining}s';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // スピナーまたは圏外アイコン
        if (isWaitingForNetwork)
          Icon(
            Icons.signal_wifi_off,
            size: 12,
            color: DesignColors.warning.withValues(alpha: 0.8),
          )
        else
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: DesignColors.warning.withValues(alpha: 0.8),
            ),
          ),
        const SizedBox(width: 6),

        // ステータステキスト
        Text(
          isWaitingForNetwork
              ? 'Offline'
              : 'Reconnecting${attempt > 1 ? ' ($attempt)' : ''}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: DesignColors.warning.withValues(alpha: 0.8),
          ),
        ),

        // カウントダウン
        if (countdownText != null) ...[
          const SizedBox(width: 4),
          Text(
            countdownText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: DesignColors.textMuted,
            ),
          ),
        ],

        // キューイング状態
        if (queuedCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: DesignColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$queuedCount chars',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.primary,
              ),
            ),
          ),
        ],

        // 今すぐ再接続ボタン
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            ref.read(sshProvider.notifier).reconnectNow();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: DesignColors.warning.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.warning,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// tmux send-keysでキーを送信
  ///
  /// [key] 送信するキー
  /// [literal] trueの場合はリテラル送信（-l フラグ）
  Future<void> _sendKey(String key, {bool literal = true}) async {
    final sshClient = ref.read(sshProvider.notifier).client;

    // 接続が切れている場合はキューに追加（リテラルの場合のみ）
    if (sshClient == null || !sshClient.isConnected) {
      if (literal) {
        _inputQueue.enqueue(key);
        if (mounted) setState(() {}); // キューイング状態を更新
      }
      return;
    }

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      await sshClient.exec(TmuxCommands.sendKeys(target, key, literal: literal));
      _boostPolling();
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  /// tmux copy-modeに入る
  Future<void> _enterTmuxCopyMode() async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;
    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;
    try {
      await sshClient.exec(TmuxCommands.enterCopyMode(target));
      _boostPolling();
    } catch (_) {}
  }

  /// tmux copy-modeを終了
  Future<void> _cancelTmuxCopyMode() async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;
    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;
    try {
      await sshClient.exec(TmuxCommands.cancelCopyMode(target));
      _boostPolling();
    } catch (_) {}
  }

  /// tmux特殊キーを送信（Ctrl+C, Escape等）
  Future<void> _sendSpecialKey(String tmuxKey) async {
    final sshClient = ref.read(sshProvider.notifier).client;

    // 特殊キーは接続が切れている場合は送信しない（キューしない）
    if (sshClient == null || !sshClient.isConnected) return;

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      // 特殊キーはリテラルではなくtmux形式で送信
      await sshClient.exec(TmuxCommands.sendKeys(target, tmuxKey, literal: false));
      _boostPolling();
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  ProviderSubscription? _imageTransferSub;

  /// 画像転送の状態リスナーを初期化（1回のみ）
  void _ensureImageTransferListener() {
    if (_imageTransferSub != null) return;
    _imageTransferSub = ref.listenManual(imageTransferProvider, (prev, next) async {

      if (next.phase == ImageTransferPhase.confirming &&
          next.pickedImageBytes != null &&
          next.pendingRemotePath != null &&
          (prev?.phase == ImageTransferPhase.picking)) {
        if (!mounted) return;
        final settings = ref.read(settingsProvider);
        final options = await ImageTransferConfirmDialog.show(
          context,
          remotePath: next.pendingRemotePath!,
          imageBytes: next.pickedImageBytes!,
          imageName: next.pickedImageName,
          settings: settings,
        );

        if (options != null) {
          final uploadedPath = await ref
              .read(imageTransferProvider.notifier)
              .confirmAndUpload(options: options);

          if (uploadedPath != null && mounted) {
            await _injectImagePath(uploadedPath, options);
          }
        } else {
          ref.read(imageTransferProvider.notifier).cancel();
        }
      }

      if (next.phase == ImageTransferPhase.error && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Image transfer failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      if (next.phase == ImageTransferPhase.completed &&
          next.lastUploadedPath != null &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded: ${next.lastUploadedPath}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  /// ファイルブラウザを開く
  void _handleFileBrowser() {
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileBrowserScreen(
          connectionId: widget.connectionId,
          paneId: activePaneId,
        ),
      ),
    );
  }

  /// 画像転送フローを開始
  void _handleImageTransfer() {
    _ensureImageTransferListener();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(imageTransferProvider.notifier).pickImage(
                      ImageSource.gallery,
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(imageTransferProvider.notifier).pickImage(
                      ImageSource.camera,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// アップロード済み画像のパスをターミナルに注入
  Future<void> _injectImagePath(String remotePath, ImageTransferOptions options) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final activePaneId = ref.read(tmuxProvider).activePaneId;
    if (activePaneId == null) return;

    // パスフォーマット適用（optionsから取得）
    final formattedPath = options.pathFormat.replaceAll('{path}', remotePath);

    if (options.bracketedPaste) {
      sshClient.write('\x1b[200~$formattedPath\x1b[201~');
    } else {
      await sshClient.exec(
        TmuxCommands.sendKeys(activePaneId, formattedPath, literal: true),
      );
    }

    if (options.autoEnter) {
      await sshClient.exec(
        TmuxCommands.sendKeys(activePaneId, 'Enter'),
      );
    }

    _boostPolling();
  }

  void _showInputDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _InputDialogContent(
        initialValue: _savedCommandInput,
        onValueChanged: (value) {
          // 入力内容をリアルタイムで保存
          _savedCommandInput = value;
        },
        onSend: (value) async {
          await _sendMultilineText(value);
          // 送信成功したら入力内容をクリア
          _savedCommandInput = '';
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// 複数行テキストを送信（行ごとにテキスト+Enterを送信）
  ///
  /// 注: _sendKey/_sendSpecialKeyを直接呼び出す。
  /// オーバーレイラッパーを経由しないため、複数行送信時にオーバーレイは表示されない。
  /// これは意図的な動作。
  Future<void> _sendMultilineText(String text) async {
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty) {
        await _sendKey(line);
      }
      // 最後の行以外はEnterを送信、または空行でもEnterを送信
      if (i < lines.length - 1 || line.isEmpty) {
        await _sendSpecialKey('Enter');
      }
    }
    // 最後の行が空でなければEnterを送信
    if (lines.isNotEmpty && lines.last.isNotEmpty) {
      await _sendSpecialKey('Enter');
    }
  }

  /// 右上のペインインジケーター
  ///
  /// ペインの実際のサイズ比率に基づいてレイアウトを表示
  Widget _buildPaneIndicator(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    final panes = window?.panes ?? [];
    final activePaneId = tmuxState.activePaneId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (panes.isEmpty) {
      return const SizedBox.shrink();
    }

    // インジケーター全体のサイズ
    const double indicatorSize = 48.0;

    return GestureDetector(
      onTap: () => _showPaneSelector(tmuxState),
      child: Opacity(
        opacity: 0.5,
        child: Container(
          width: indicatorSize,
          height: indicatorSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: Size(indicatorSize - 4, indicatorSize - 4),
            painter: _PaneLayoutPainter(
              panes: panes,
              activePaneId: activePaneId,
              activeColor: colorScheme.primary,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// ペインレイアウトを描画するCustomPainter
///
/// tmuxから取得したpane_left/pane_topを使用して
/// 実際のレイアウトを正確に再現する
class _PaneLayoutPainter extends CustomPainter {
  final List<TmuxPane> panes;
  final String? activePaneId;
  final Color activeColor;
  final bool isDark;

  _PaneLayoutPainter({
    required this.panes,
    this.activePaneId,
    required this.activeColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (panes.isEmpty) return;

    // ウィンドウ全体のサイズを計算（全ペインを含む範囲）
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    if (maxRight == 0 || maxBottom == 0) return;

    // スケール係数を計算
    final scaleX = size.width / maxRight;
    final scaleY = size.height / maxBottom;
    final gap = 1.0;

    // ペインごとに描画
    for (final pane in panes) {
      final isActive = pane.id == activePaneId;

      // 実際の位置とサイズからRectを計算
      final left = pane.left * scaleX;
      final top = pane.top * scaleY;
      final width = pane.width * scaleX - gap;
      final height = pane.height * scaleY - gap;

      final rect = Rect.fromLTWH(left, top, width, height);

      // 背景
      final bgPaint = Paint()
        ..color = isActive
            ? activeColor.withValues(alpha: 0.3)
            : (isDark ? Colors.black45 : Colors.grey.shade300);
      canvas.drawRect(rect, bgPaint);

      // 枠線
      final borderPaint = Paint()
        ..color = isActive ? activeColor : (isDark ? Colors.white30 : Colors.grey.shade500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.5 : 1.0;
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaneLayoutPainter oldDelegate) {
    return panes != oldDelegate.panes ||
        activePaneId != oldDelegate.activePaneId ||
        activeColor != oldDelegate.activeColor ||
        isDark != oldDelegate.isDark;
  }
}

/// ペインレイアウトをインタラクティブに表示するウィジェット
///
/// 各ペインをタップで選択可能。ペイン番号も表示。
class _PaneLayoutVisualizer extends StatefulWidget {
  final List<TmuxPane> panes;
  final String? activePaneId;
  final void Function(String paneId) onPaneSelected;
  final void Function(String paneId, SplitDirection direction)? onSplitRequested;

  const _PaneLayoutVisualizer({
    required this.panes,
    this.activePaneId,
    required this.onPaneSelected,
    this.onSplitRequested,
  });

  @override
  State<_PaneLayoutVisualizer> createState() => _PaneLayoutVisualizerState();
}

class _PaneLayoutVisualizerState extends State<_PaneLayoutVisualizer> {
  /// 分割モードが有効なペインID（nullなら通常表示）
  String? _splitModeActivePaneId;

  @override
  Widget build(BuildContext context) {
    if (widget.panes.isEmpty) return const SizedBox.shrink();

    // ウィンドウ全体のサイズを計算（全ペインを含む範囲）
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in widget.panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    if (maxRight == 0 || maxBottom == 0) return const SizedBox.shrink();

    // アスペクト比を計算
    final aspectRatio = maxRight / maxBottom;

    return Container(
      padding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: aspectRatio.clamp(0.5, 3.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth;
            final containerHeight = constraints.maxHeight;

            // スケール係数を計算
            final scaleX = containerWidth / maxRight;
            final scaleY = containerHeight / maxBottom;
            const gap = 2.0;

            return Stack(
              children: widget.panes.map((pane) {
                final isActive = pane.id == widget.activePaneId;
                final isSplitMode = _splitModeActivePaneId == pane.id;

                // 実際の位置とサイズからRectを計算
                final left = pane.left * scaleX;
                final top = pane.top * scaleY;
                final width = pane.width * scaleX - gap;
                final height = pane.height * scaleY - gap;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: GestureDetector(
                    onTap: () => _handlePaneTap(pane, isActive, width, height),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isActive
                            ? DesignColors.primary.withValues(alpha: 0.3)
                            : Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? DesignColors.primary
                              : Colors.white.withValues(alpha: 0.3),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: _buildPaneContent(
                          pane: pane,
                          isActive: isActive,
                          isSplitMode: isSplitMode,
                          width: width,
                          height: height,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  /// インライン分割アイコンが収まる最小サイズ
  static const _minInlineWidth = 80.0;
  static const _minInlineHeight = 60.0;

  void _handlePaneTap(TmuxPane pane, bool isActive, double width, double height) {
    if (isActive && widget.onSplitRequested != null) {
      if (width < _minInlineWidth || height < _minInlineHeight) {
        // 小さいペイン → モーダルダイアログで分割方向を選択
        _showSplitDialog(pane);
      } else {
        // 大きいペイン → インラインで分割モード切り替え
        setState(() {
          _splitModeActivePaneId =
              _splitModeActivePaneId == pane.id ? null : pane.id;
        });
      }
    } else {
      // 非アクティブペインをタップ → ペイン選択
      widget.onPaneSelected(pane.id);
    }
  }

  void _showSplitDialog(TmuxPane pane) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            'Split Pane ${pane.index}',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CustomPaint(
                  size: const Size(24, 24),
                  painter: _SplitRightIconPainter(color: colorScheme.primary),
                ),
                title: const Text('Split Right'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  widget.onSplitRequested!(pane.id, SplitDirection.horizontal);
                },
              ),
              ListTile(
                leading: CustomPaint(
                  size: const Size(24, 24),
                  painter: _SplitDownIconPainter(color: colorScheme.primary),
                ),
                title: const Text('Split Down'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  widget.onSplitRequested!(pane.id, SplitDirection.vertical);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaneContent({
    required TmuxPane pane,
    required bool isActive,
    required bool isSplitMode,
    required double width,
    required double height,
  }) {
    if (isActive && isSplitMode) {
      // 分割モード: アイコンボタン表示
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${pane.index}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: width > 60 ? 18 : 14,
              fontWeight: FontWeight.w700,
              color: DesignColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSplitButton(
                painter: _SplitRightIconPainter(color: DesignColors.primary),
                onTap: () => widget.onSplitRequested!(
                  pane.id,
                  SplitDirection.horizontal,
                ),
              ),
              const SizedBox(width: 8),
              _buildSplitButton(
                painter: _SplitDownIconPainter(color: DesignColors.primary),
                onTap: () => widget.onSplitRequested!(
                  pane.id,
                  SplitDirection.vertical,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 通常表示
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${pane.index}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: width > 60 ? 18 : 14,
            fontWeight: FontWeight.w700,
            color: isActive
                ? DesignColors.primary
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
        if (isActive && widget.onSplitRequested != null && width > 60 && height > 40) ...[
          const SizedBox(height: 2),
          Text(
            'Tap to split',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              color: DesignColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ] else if (width > 80 && height > 50) ...[
          const SizedBox(height: 2),
          Text(
            '${pane.width}x${pane.height}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSplitButton({
    required CustomPainter painter,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: DesignColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: DesignColors.primary.withValues(alpha: 0.4),
            ),
          ),
          child: CustomPaint(
            size: const Size(20, 20),
            painter: painter,
          ),
        ),
      ),
    );
  }
}

/// 右分割アイコン: 左に既存ペイン、右に新ペイン（+マーク付き）
class _SplitRightIconPainter extends CustomPainter {
  final Color color;

  _SplitRightIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = w * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央縦線）
    canvas.drawLine(Offset(mid, pad), Offset(mid, h - pad), paint);

    // 右側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = mid + (w - pad - mid) / 2;
    final cy = h / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(Offset(cx - plusSize, cy), Offset(cx + plusSize, cy), plusPaint);
    canvas.drawLine(Offset(cx, cy - plusSize), Offset(cx, cy + plusSize), plusPaint);
  }

  @override
  bool shouldRepaint(covariant _SplitRightIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 下分割アイコン: 上に既存ペイン、下に新ペイン（+マーク付き）
class _SplitDownIconPainter extends CustomPainter {
  final Color color;

  _SplitDownIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = h * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央横線）
    canvas.drawLine(Offset(pad, mid), Offset(w - pad, mid), paint);

    // 下側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = w / 2;
    final cy = mid + (h - pad - mid) / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(Offset(cx - plusSize, cy), Offset(cx + plusSize, cy), plusPaint);
    canvas.drawLine(Offset(cx, cy - plusSize), Offset(cx, cy + plusSize), plusPaint);
  }

  @override
  bool shouldRepaint(covariant _SplitDownIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 入力ダイアログのコンテンツ（複数行対応、Shift+Enterで改行）
class _InputDialogContent extends StatefulWidget {
  final String initialValue;
  final void Function(String value) onValueChanged;
  final Future<void> Function(String value) onSend;

  const _InputDialogContent({
    this.initialValue = '',
    required this.onValueChanged,
    required this.onSend,
  });

  @override
  State<_InputDialogContent> createState() => _InputDialogContentState();
}

class _InputDialogContentState extends State<_InputDialogContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    // キーイベントをハンドルするためにonKeyEventを設定
    _focusNode.onKeyEvent = _handleKeyEvent;
    // テキスト変更時に親へ通知
    _controller.addListener(_onTextChanged);
    // 自動フォーカス（カーソルを末尾に）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // カーソルを末尾に移動
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onTextChanged() {
    widget.onValueChanged(_controller.text);
  }

  /// Returns true when an IME composition range is open.
  bool get _isImeActive {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.onKeyEvent = null;
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// キーイベントをハンドル（Shift+Enterで改行、Enterで送信）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_isImeActive) {
        return KeyEventResult.ignored;
      }
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      if (isShiftPressed) {
        // Shift+Enter: 改行を挿入
        _insertNewline();
        return KeyEventResult.handled;
      } else {
        // Enterのみ: 送信
        _handleSend();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 現在のカーソル位置に改行を挿入
  void _insertNewline() {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\n');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  Future<void> _handleSend() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSend(_controller.text);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Enter Command',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Shift+Enter: 改行',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 200, // 最大高さを制限してスクロール可能に
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              maxLines: null, // 無制限にして内部スクロール
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline, // ペースト時の複数行対応
              style: GoogleFonts.jetBrainsMono(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Type your command... (Enter to send)',
                hintStyle: GoogleFonts.jetBrainsMono(
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                ),
                filled: true,
                fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _handleSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          'Execute',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// ウィンドウ名入力ダイアログ
class _NewWindowDialog extends StatefulWidget {
  final List<String> existingWindowNames;

  const _NewWindowDialog({required this.existingWindowNames});

  @override
  State<_NewWindowDialog> createState() => _NewWindowDialogState();
}

class _NewWindowDialogState extends State<_NewWindowDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateWindowName(String? value) {
    if (value == null || value.isEmpty) {
      return null; // 空入力はtmuxデフォルト名で許容
    }
    if (value.length > 50) {
      return 'Window name must be 50 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - and _ allowed';
    }
    if (widget.existingWindowNames.contains(value)) {
      return 'Window "$value" already exists';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        'New Window',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: 'Window Name',
            hintText: 'Leave empty for default',
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
            filled: true,
            fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateWindowName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// ====================================================================
// _ResizePaneChooserDialog
// ====================================================================

/// リサイズ対象ペインをグラフィカルに選択するダイアログ
class _ResizePaneChooserDialog extends StatefulWidget {
  final List<TmuxPane> panes;
  final String? activePaneId;
  final void Function(TmuxPane selectedPane) onResize;

  const _ResizePaneChooserDialog({
    required this.panes,
    this.activePaneId,
    required this.onResize,
  });

  @override
  State<_ResizePaneChooserDialog> createState() =>
      _ResizePaneChooserDialogState();
}

class _ResizePaneChooserDialogState extends State<_ResizePaneChooserDialog> {
  late String? _selectedPaneId;

  @override
  void initState() {
    super.initState();
    // デフォルト: 現在アクティブなペインが選択状態
    _selectedPaneId = widget.activePaneId;
  }

  TmuxPane? get _selectedPane {
    if (_selectedPaneId == null) return null;
    try {
      return widget.panes.firstWhere((p) => p.id == _selectedPaneId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPane;

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Resize Pane',
        style: TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ペインレイアウトのグリッドプレビュー
            _buildSelectablePaneGrid(),
            const SizedBox(height: 12),
            // 選択中のペイン情報
            if (selected != null)
              Text(
                'Selected: Pane ${selected.index} (${selected.width}x${selected.height})',
                style: const TextStyle(
                  fontSize: 13,
                  color: DesignColors.textSecondary,
                ),
              )
            else
              const Text(
                'Tap a pane to select',
                style: TextStyle(
                  fontSize: 13,
                  color: DesignColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected != null ? () => widget.onResize(selected) : null,
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: const Text('Resize'),
        ),
      ],
    );
  }

  Widget _buildSelectablePaneGrid() {
    if (widget.panes.isEmpty) return const SizedBox.shrink();

    // ウィンドウ全体のサイズを計算
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in widget.panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxRight == 0) maxRight = 1;
    if (maxBottom == 0) maxBottom = 1;

    return Container(
      height: 150,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: DesignColors.canvasDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DesignColors.borderDark),
      ),
      child: LayoutBuilder(
          builder: (context, constraints) {
            const pad = 4.0;
            final areaW = constraints.maxWidth - pad * 2;
            final areaH = constraints.maxHeight - pad * 2;
            final scaleX = areaW / maxRight;
            final scaleY = areaH / maxBottom;

            return Padding(
              padding: const EdgeInsets.all(pad),
              child: Stack(
                children: [
                  SizedBox(width: areaW, height: areaH),
                  ...widget.panes.map((pane) {
                  final isSelected = pane.id == _selectedPaneId;
                  final left = pane.left * scaleX;
                  final top = pane.top * scaleY;
                  final width = (pane.width * scaleX).clamp(20.0, areaW - left);
                  final height = (pane.height * scaleY).clamp(14.0, areaH - top);

                  return Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPaneId = pane.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? DesignColors.primary.withValues(alpha: 0.25)
                              : DesignColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? DesignColors.primary
                                : DesignColors.borderDark,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '${pane.index}\n${pane.width}x${pane.height}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? DesignColors.primary
                                    : DesignColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ]),
            );
          },
        ),
      );
  }
}

// ====================================================================
// _ResizeWindowChooserDialog
// ====================================================================

/// リサイズ対象ウィンドウをグラフィカルに選択するダイアログ
class _ResizeWindowChooserDialog extends StatefulWidget {
  final List<TmuxWindow> windows;
  final int? activeWindowIndex;
  final void Function(TmuxWindow selectedWindow) onResize;

  const _ResizeWindowChooserDialog({
    required this.windows,
    this.activeWindowIndex,
    required this.onResize,
  });

  @override
  State<_ResizeWindowChooserDialog> createState() =>
      _ResizeWindowChooserDialogState();
}

class _ResizeWindowChooserDialogState
    extends State<_ResizeWindowChooserDialog> {
  late int? _selectedWindowIndex;

  @override
  void initState() {
    super.initState();
    // デフォルト: 現在アクティブなウィンドウが選択状態
    _selectedWindowIndex = widget.activeWindowIndex;
  }

  TmuxWindow? get _selectedWindow {
    if (_selectedWindowIndex == null) return null;
    try {
      return widget.windows
          .firstWhere((w) => w.index == _selectedWindowIndex);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedWindow;

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Resize Window',
        style: TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ウィンドウカード一覧
              ...widget.windows.map((window) {
                final isSelected = window.index == _selectedWindowIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildWindowCard(window, isSelected),
                );
              }),
              const SizedBox(height: 4),
              // 選択中のウィンドウ情報
              if (selected != null) ...[
                Text(
                  'Selected: ${selected.name} (${_windowSizeString(selected)})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
              ] else
                const Text(
                  'Tap a window to select',
                  style: TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              selected != null ? () => widget.onResize(selected) : null,
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: const Text('Resize'),
        ),
      ],
    );
  }

  String _windowSizeString(TmuxWindow window) {
    final panes = window.panes;
    if (panes.isEmpty) return '?x?';
    final cols =
        panes.map((p) => p.left + p.width).reduce((a, b) => a > b ? a : b);
    final rows =
        panes.map((p) => p.top + p.height).reduce((a, b) => a > b ? a : b);
    return '${cols}x$rows';
  }

  Widget _buildWindowCard(TmuxWindow window, bool isSelected) {
    final panes = window.panes;
    return GestureDetector(
      onTap: () => setState(() => _selectedWindowIndex = window.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: DesignColors.canvasDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? DesignColors.primary : DesignColors.borderDark,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ウィンドウヘッダー
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignColors.primary.withValues(alpha: 0.15)
                    : DesignColors.surfaceDark,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Text(
                '${window.name}  ${_windowSizeString(window)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? DesignColors.primary
                      : DesignColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // ペインレイアウトプレビュー
            if (panes.isNotEmpty)
              SizedBox(
                height: 60,
                child: _buildPaneLayoutPreview(panes),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaneLayoutPreview(List<TmuxPane> panes) {
    int maxRight = 0;
    int maxBottom = 0;
    for (final p in panes) {
      final right = p.left + p.width;
      final bottom = p.top + p.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxRight == 0) maxRight = 1;
    if (maxBottom == 0) maxBottom = 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth - 8;
        final areaH = constraints.maxHeight - 8;

        return Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              SizedBox(width: areaW, height: areaH),
              ...panes.map((pane) {
              final left = (pane.left / maxRight) * areaW;
              final top = (pane.top / maxBottom) * areaH;
              final width = (pane.width / maxRight) * areaW;
              final height = (pane.height / maxBottom) * areaH;

              return Positioned(
                left: left,
                top: top,
                width: width.clamp(16.0, areaW),
                height: height.clamp(10.0, areaH),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: DesignColors.borderDark,
                      width: 1,
                    ),
                  ),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

/// Factory that exposes [_InputDialogContent] for widget tests.
///
/// Production code must never call this function.
@visibleForTesting
Widget buildInputDialogContentForTesting({
  String initialValue = '',
  required void Function(String value) onValueChanged,
  required Future<void> Function(String value) onSend,
}) {
  return _InputDialogContent(
    initialValue: initialValue,
    onValueChanged: onValueChanged,
    onSend: onSend,
  );
}

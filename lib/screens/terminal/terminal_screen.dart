import 'dart:async';

import 'package:flutter/material.dart';
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
import '../../services/ssh/ssh_client.dart' show SshConnectOptions;
import '../../services/tmux/tmux_commands.dart';
import '../../services/tmux/tmux_parser.dart';
import '../../theme/design_colors.dart';
import '../../widgets/special_keys_bar.dart';
import '../../providers/terminal_display_provider.dart';
import '../settings/settings_screen.dart';
import 'widgets/ansi_text_view.dart';

/// ターミナル画面（HTMLデザイン仕様準拠）
class TerminalScreen extends ConsumerStatefulWidget {
  final String connectionId;
  final String? sessionName;

  /// 復元用: 最後に開いていたウィンドウインデックス
  final int? lastWindowIndex;

  /// 復元用: 最後に開いていたペインID
  final String? lastPaneId;

  const TerminalScreen({
    super.key,
    required this.connectionId,
    this.sessionName,
    this.lastWindowIndex,
    this.lastPaneId,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _secureStorage = SecureStorageService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _ansiTextViewKey = GlobalKey<AnsiTextViewState>();
  final _terminalScrollController = ScrollController();

  // 接続状態（ローカルで管理）
  bool _isConnecting = false;
  String? _connectionError;
  SshState _sshState = const SshState();

  // レイテンシ表示用
  int _latency = 0;

  // ポーリング用タイマー
  Timer? _pollTimer;
  Timer? _treeRefreshTimer;
  String _terminalContent = '';
  bool _isPolling = false;
  bool _isDisposed = false;

  // 現在のペインサイズ
  int _paneWidth = 80;
  int _paneHeight = 24;

  // ターミナルモード
  TerminalMode _terminalMode = TerminalMode.normal;

  // ズームスケール
  double _zoomScale = 1.0;

  // Riverpodリスナー
  ProviderSubscription<SshState>? _sshSubscription;
  ProviderSubscription<TmuxState>? _tmuxSubscription;
  ProviderSubscription<AppSettings>? _settingsSubscription;

  @override
  void initState() {
    super.initState();

    // 次フレームでリスナーを設定（ref使用のため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupListeners();
      _connectAndSetup();
      _applyKeepScreenOn();
    });
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

    // Tmux状態の変化を監視（UIリビルド用）
    _tmuxSubscription = ref.listenManual<TmuxState>(
      tmuxProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        setState(() {
          // tmuxStateはbuild内で直接読み取る
        });
      },
      fireImmediately: true,
    );

    // 設定の変化を監視（Keep screen on用）
    _settingsSubscription = ref.listenManual<AppSettings>(
      settingsProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        // keepScreenOn設定が変更された場合に適用
        if (previous?.keepScreenOn != next.keepScreenOn) {
          _applyKeepScreenOn();
        }
      },
      fireImmediately: false,
    );
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

      // 4. セッションツリー全体を取得
      await _refreshSessionTree();
      if (!mounted || _isDisposed) {
        return;
      }

      final tmuxState = ref.read(tmuxProvider);
      final sessions = tmuxState.sessions;

      // 5. セッションを選択または新規作成
      String sessionName;
      if (sessions.isNotEmpty) {
        sessionName = widget.sessionName ?? sessions.first.name;
      } else {
        // セッションがない場合は新規作成
        final sshClient = ref.read(sshProvider.notifier).client;
        sessionName = 'muxpod-${DateTime.now().millisecondsSinceEpoch}';
        await sshClient?.exec(TmuxCommands.newSession(name: sessionName, detached: true));
        if (!mounted || _isDisposed) return;
        await _refreshSessionTree(); // ツリーを再取得
        if (!mounted || _isDisposed) return;
      }

      // 6. アクティブセッション/ウィンドウ/ペインを設定
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

      // 6.1 保存されたウィンドウ/ペイン位置を復元
      if (widget.lastWindowIndex != null) {
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
        setState(() {
          _paneWidth = activePane.width;
          _paneHeight = activePane.height;
        });
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

  /// 5秒ごとにセッションツリーを更新
  void _startTreeRefresh() {
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshSessionTree(),
    );
  }

  /// 100msごとにcapture-paneを実行してターミナル内容を更新
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _pollPaneContent());
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
      // 履歴を多く取得するため、-S -1000で過去1000行を含める
      final output = await sshClient.exec(
        TmuxCommands.capturePane(target, escapeSequences: true, startLine: -1000),
        timeout: const Duration(milliseconds: 500),
      );
      final endTime = DateTime.now();

      // アンマウント済みならスキップ
      if (!mounted || _isDisposed) return;

      // レイテンシを更新
      final latency = endTime.difference(startTime).inMilliseconds;

      // 差分があれば更新
      if (output != _terminalContent || latency != _latency) {
        setState(() {
          _latency = latency;
          _terminalContent = output;
        });
      }
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

  @override
  void dispose() {
    // まず_isDisposedをセットして非同期処理を停止
    _isDisposed = true;
    // WakeLockを無効化
    WakelockPlus.disable();
    // Riverpodサブスクリプションをキャンセル
    _sshSubscription?.close();
    _sshSubscription = null;
    _tmuxSubscription?.close();
    _tmuxSubscription = null;
    _settingsSubscription?.close();
    _settingsSubscription = null;
    // タイマーを停止
    _pollTimer?.cancel();
    _pollTimer = null;
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = null;
    // スクロールコントローラーを破棄
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ローカル状態を使用（ref.watchは使わない）
    final sshState = _sshState;
    final tmuxState = ref.read(tmuxProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: DesignColors.backgroundDark,
      body: Stack(
        children: [
          Column(
            children: [
              _buildBreadcrumbHeader(tmuxState),
              Expanded(
                child: Stack(
                  children: [
                    AnsiTextView(
                      key: _ansiTextViewKey,
                      text: _terminalContent,
                      paneWidth: _paneWidth,
                      paneHeight: _paneHeight,
                      backgroundColor: DesignColors.backgroundDark,
                      foregroundColor: Colors.white.withValues(alpha: 0.9),
                      onKeyInput: _handleKeyInput,
<<<<<<< HEAD
                      mode: _terminalMode,
                      zoomEnabled: true,
                      onZoomChanged: (scale) {
                        setState(() {
                          _zoomScale = scale;
                        });
                      },
=======
                      verticalScrollController: _terminalScrollController,
>>>>>>> feat-navigation
                    ),
                    // Pane indicator (右上)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _buildPaneIndicator(tmuxState),
                    ),
                  ],
                ),
              ),
              SpecialKeysBar(
                onKeyPressed: _sendKey,
                onSpecialKeyPressed: _sendSpecialKey,
                onInputTap: _showInputDialog,
                directInputEnabled: ref.watch(settingsProvider).directInputEnabled,
                onDirectInputToggle: () {
                  ref.read(settingsProvider.notifier).toggleDirectInput();
                },
              ),
            ],
          ),
          // ローディングオーバーレイ
          if (_isConnecting || sshState.isConnecting)
            Container(
              color: Colors.black54,
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

  /// AnsiTextViewからのキー入力を処理
  void _handleKeyInput(KeyInputEvent event) {
    // 特殊キーの場合はtmux形式で送信
    if (event.isSpecialKey && event.tmuxKeyName != null) {
      _sendSpecialKey(event.tmuxKeyName!);
    } else {
      // 通常の文字はリテラル送信
      _sendKeyData(event.data);
    }
  }

  /// キーデータをtmux send-keysで送信
  Future<void> _sendKeyData(String data) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      // エスケープシーケンスや特殊キーはリテラルで送信
      await sshClient.exec(TmuxCommands.sendKeys(target, data, literal: true));
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

    // ターミナル内容をクリアして再取得
    setState(() {
      _terminalContent = '';
    });
  }

  /// ウィンドウを選択
  Future<void> _selectWindow(String sessionName, int windowIndex) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // セッションが異なる場合はセッションも切り替え
    final currentSession = ref.read(tmuxProvider).activeSessionName;
    if (currentSession != sessionName) {
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);
    }

    // tmux select-windowを実行
    await sshClient.exec(TmuxCommands.selectWindow(sessionName, windowIndex));
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブウィンドウを更新
    ref.read(tmuxProvider.notifier).setActiveWindow(windowIndex);

    // ターミナル内容をクリアして再取得
    setState(() {
      _terminalContent = '';
    });
  }

  /// ペインを選択
  Future<void> _selectPane(String paneId) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // tmux select-paneを実行
    await sshClient.exec(TmuxCommands.selectPane(paneId));
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブペインを更新
    ref.read(tmuxProvider.notifier).setActivePane(paneId);

    // TerminalDisplayProviderにペイン情報を通知（フォントサイズ計算用）
    final activePane = ref.read(tmuxProvider).activePane;
    final tmuxState = ref.read(tmuxProvider);
    if (activePane != null) {
      ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      setState(() {
        _paneWidth = activePane.width;
        _paneHeight = activePane.height;
        _terminalContent = '';
      });

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

      // ペイン選択後は一番下へスクロール
      _scrollToBottom();
    }
  }

  /// 一番下までスクロール
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// エラーオーバーレイ
  Widget _buildErrorOverlay(String? error) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              error ?? 'Connection error',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _connectAndSetup,
              child: const Text('Retry'),
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

    // SafeAreaを外側に配置してステータスバー分のスペースを確保
    return SafeArea(
      bottom: false,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: DesignColors.surfaceDark.withValues(alpha: 0.9),
          border: const Border(
            bottom: BorderSide(color: Color(0xFF2A2B36), width: 1),
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
            // Copy/Paste mode indicator
            if (_terminalMode == TerminalMode.copyPaste)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: DesignColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: DesignColors.primary.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.content_copy, size: 12, color: DesignColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: DesignColors.primary,
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
            // Latency / Reconnect indicator
            _buildConnectionIndicator(),
            // Settings button
            IconButton(
<<<<<<< HEAD
              onPressed: _showTerminalMenu,
=======
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
>>>>>>> feat-navigation
              icon: Icon(
                Icons.settings,
                size: 16,
                color: Colors.white.withValues(alpha: 0.6),
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
      backgroundColor: DesignColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.6;
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
                      Icon(Icons.folder, color: DesignColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Session',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF2A2B36)),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tmuxState.sessions.length,
                    itemBuilder: (context, index) {
                      final session = tmuxState.sessions[index];
                      final isActive = session.name == tmuxState.activeSessionName;
                      return ListTile(
                        leading: Icon(
                          Icons.folder,
                          color: isActive ? DesignColors.primary : Colors.white60,
                        ),
                        title: Text(
                          session.name,
                          style: TextStyle(
                            color: isActive ? DesignColors.primary : Colors.white,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${session.windowCount} windows',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: isActive
                            ? Icon(Icons.check, color: DesignColors.primary)
                            : null,
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
    );
  }

  /// ウィンドウ選択ダイアログを表示
  void _showWindowSelector(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    if (session == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: DesignColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.6;
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
                      Icon(Icons.tab, color: DesignColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Window',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF2A2B36)),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: session.windows.length,
                    itemBuilder: (context, index) {
                      final window = session.windows[index];
                      final isActive = window.index == tmuxState.activeWindowIndex;
                      return ListTile(
                        leading: Icon(
                          Icons.tab,
                          color: isActive ? DesignColors.primary : Colors.white60,
                        ),
                        title: Text(
                          '${window.index}: ${window.name}',
                          style: TextStyle(
                            color: isActive ? DesignColors.primary : Colors.white,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${window.paneCount} panes',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: isActive
                            ? Icon(Icons.check, color: DesignColors.primary)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _selectWindow(session.name, window.index);
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
    );
  }

  /// ペイン選択ダイアログを表示
  void _showPaneSelector(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    if (window == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: DesignColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
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
                      Icon(Icons.terminal, color: DesignColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Select Pane',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF2A2B36)),
                // ペインレイアウトのビジュアル表示
                if (window.panes.length > 1)
                  _PaneLayoutVisualizer(
                    panes: window.panes,
                    activePaneId: tmuxState.activePaneId,
                    onPaneSelected: (paneId) {
                      Navigator.pop(context);
                      _selectPane(paneId);
                    },
                  ),
                const Divider(height: 1, color: Color(0xFF2A2B36)),
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
                      return ListTile(
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isActive
                                ? DesignColors.primary.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive
                                  ? DesignColors.primary.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${pane.index}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isActive ? DesignColors.primary : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          paneTitle,
                          style: TextStyle(
                            color: isActive ? DesignColors.primary : Colors.white,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${pane.width}x${pane.height}',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: isActive
                            ? Icon(Icons.check, color: DesignColors.primary)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _selectPane(pane.id);
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
    );
  }

  Widget _buildBreadcrumbItem(
    String label, {
    IconData? icon,
    bool isActive = false,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                    ? DesignColors.primary
                    : (isSelected ? Colors.white : Colors.white60),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label.isEmpty ? '...' : label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: isActive || isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isActive
                    ? DesignColors.primary
                    : (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5)),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: isActive
                    ? DesignColors.primary.withValues(alpha: 0.7)
                    : Colors.white38,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '/',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w300,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// ターミナルメニューを表示
  void _showTerminalMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DesignColors.surfaceDark,
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
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2A2B36)),
              // コピペモード切り替え
              ListTile(
                leading: Icon(
                  _terminalMode == TerminalMode.copyPaste
                      ? Icons.content_copy
                      : Icons.keyboard,
                  color: _terminalMode == TerminalMode.copyPaste
                      ? DesignColors.primary
                      : Colors.white60,
                ),
                title: Text(
                  _terminalMode == TerminalMode.copyPaste
                      ? 'Copy/Paste Mode (Active)'
                      : 'Normal Mode',
                  style: TextStyle(
                    color: _terminalMode == TerminalMode.copyPaste
                        ? DesignColors.primary
                        : Colors.white,
                    fontWeight: _terminalMode == TerminalMode.copyPaste
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  _terminalMode == TerminalMode.copyPaste
                      ? 'Tap to return to normal mode'
                      : 'Tap to enable text selection',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: Switch(
                  value: _terminalMode == TerminalMode.copyPaste,
                  onChanged: (value) {
                    setState(() {
                      _terminalMode = value
                          ? TerminalMode.copyPaste
                          : TerminalMode.normal;
                    });
                    Navigator.pop(context);
                  },
                  activeColor: DesignColors.primary,
                ),
                onTap: () {
                  setState(() {
                    _terminalMode = _terminalMode == TerminalMode.copyPaste
                        ? TerminalMode.normal
                        : TerminalMode.copyPaste;
                  });
                  Navigator.pop(context);
                },
              ),
              // ズームリセット
              ListTile(
                leading: Icon(
                  Icons.zoom_out_map,
                  color: _zoomScale != 1.0 ? DesignColors.warning : Colors.white60,
                ),
                title: Text(
                  'Reset Zoom',
                  style: TextStyle(
                    color: _zoomScale != 1.0 ? Colors.white : Colors.white38,
                  ),
                ),
                subtitle: Text(
                  _zoomScale != 1.0
                      ? 'Current: ${(_zoomScale * 100).toStringAsFixed(0)}%'
                      : 'Pinch to zoom in/out',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
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
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 接続状態インジケーター（レイテンシまたは再接続状態を表示）
  Widget _buildConnectionIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF2A2B36), width: 1),
        ),
      ),
      child: _sshState.isReconnecting
          ? _buildReconnectingIndicator()
          : _buildLatencyIndicator(),
    );
  }

  /// レイテンシ表示
  Widget _buildLatencyIndicator() {
    // レイテンシに応じた色を決定
    Color indicatorColor;
    if (_latency < 100) {
      indicatorColor = DesignColors.success; // 緑: 良好
    } else if (_latency < 300) {
      indicatorColor = DesignColors.primary; // シアン: 普通
    } else if (_latency < 500) {
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
          '${_latency}ms',
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
    final delayMs = _sshState.reconnectDelayMs ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: DesignColors.warning.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Reconnecting${attempt > 1 ? ' ($attempt)' : ''}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: DesignColors.warning.withValues(alpha: 0.8),
          ),
        ),
        if (delayMs > 0) ...[
          const SizedBox(width: 4),
          Text(
            '${delayMs}ms',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: DesignColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  /// tmux send-keysでキーを送信
  ///
  /// [key] 送信するキー
  /// [literal] trueの場合はリテラル送信（-l フラグ）
  Future<void> _sendKey(String key, {bool literal = true}) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      await sshClient.exec(TmuxCommands.sendKeys(target, key, literal: literal));
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  /// tmux特殊キーを送信（Ctrl+C, Escape等）
  Future<void> _sendSpecialKey(String tmuxKey) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;

    try {
      // 特殊キーはリテラルではなくtmux形式で送信
      await sshClient.exec(TmuxCommands.sendKeys(target, tmuxKey, literal: false));
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  void _showInputDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DesignColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _InputDialogContent(
        onSend: (value) async {
          await _sendMultilineText(value);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  /// 複数行テキストを送信（行ごとにテキスト+Enterを送信）
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
            color: Colors.black26,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: Size(indicatorSize - 4, indicatorSize - 4),
            painter: _PaneLayoutPainter(
              panes: panes,
              activePaneId: activePaneId,
              activeColor: DesignColors.primary,
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

  _PaneLayoutPainter({
    required this.panes,
    this.activePaneId,
    required this.activeColor,
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
            : Colors.black45;
      canvas.drawRect(rect, bgPaint);

      // 枠線
      final borderPaint = Paint()
        ..color = isActive ? activeColor : Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.5 : 1.0;
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaneLayoutPainter oldDelegate) {
    return panes != oldDelegate.panes ||
        activePaneId != oldDelegate.activePaneId ||
        activeColor != oldDelegate.activeColor;
  }
}

/// ペインレイアウトをインタラクティブに表示するウィジェット
///
/// 各ペインをタップで選択可能。ペイン番号も表示。
class _PaneLayoutVisualizer extends StatelessWidget {
  final List<TmuxPane> panes;
  final String? activePaneId;
  final void Function(String paneId) onPaneSelected;

  const _PaneLayoutVisualizer({
    required this.panes,
    this.activePaneId,
    required this.onPaneSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (panes.isEmpty) return const SizedBox.shrink();

    // ウィンドウ全体のサイズを計算（全ペインを含む範囲）
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in panes) {
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
              children: panes.map((pane) {
                final isActive = pane.id == activePaneId;

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
                    onTap: () => onPaneSelected(pane.id),
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
                        child: Column(
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
                            if (width > 80 && height > 50) ...[
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
}

/// 入力ダイアログのコンテンツ（複数行対応、Shift+Enterで改行）
class _InputDialogContent extends StatefulWidget {
  final Future<void> Function(String value) onSend;

  const _InputDialogContent({
    required this.onSend,
  });

  @override
  State<_InputDialogContent> createState() => _InputDialogContentState();
}

class _InputDialogContentState extends State<_InputDialogContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    // キーイベントをハンドルするためにonKeyEventを設定
    _focusNode.onKeyEvent = _handleKeyEvent;
    // 自動フォーカス
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.onKeyEvent = null;
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// キーイベントをハンドル（Shift+Enterで改行、Enterで送信）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
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
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DesignColors.keyBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Shift+Enter: 改行',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: DesignColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            style: GoogleFonts.jetBrainsMono(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type your command... (Enter to send)',
              hintStyle: GoogleFonts.jetBrainsMono(
                color: DesignColors.textMuted,
              ),
              filled: true,
              fillColor: DesignColors.inputDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DesignColors.primary),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
                    backgroundColor: DesignColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
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

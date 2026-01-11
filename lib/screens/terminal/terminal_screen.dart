import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
import 'widgets/ansi_text_view.dart';

/// ターミナル画面（HTMLデザイン仕様準拠）
class TerminalScreen extends ConsumerStatefulWidget {
  final String connectionId;
  final String? sessionName;

  const TerminalScreen({
    super.key,
    required this.connectionId,
    this.sessionName,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _secureStorage = SecureStorageService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) {
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
      // ポーリングエラーは静かに無視（接続エラーは別途ハンドリング）
    } finally {
      _isPolling = false;
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
                      text: _terminalContent,
                      paneWidth: _paneWidth,
                      paneHeight: _paneHeight,
                      backgroundColor: DesignColors.backgroundDark,
                      foregroundColor: Colors.white.withValues(alpha: 0.9),
                      onKeyInput: _handleKeyInput,
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
    if (activePane != null) {
      ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      setState(() {
        _paneWidth = activePane.width;
        _paneHeight = activePane.height;
        _terminalContent = '';
      });
    }
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
            // Latency indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF2A2B36), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt,
                    size: 10,
                    color: DesignColors.primary.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_latency}ms',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: DesignColors.primary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Settings button
            IconButton(
              onPressed: () {},
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
                        leading: Icon(
                          Icons.terminal,
                          color: isActive ? DesignColors.primary : Colors.white60,
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
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: DesignColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
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
            Text(
              'Enter Command',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.jetBrainsMono(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your command...',
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
              ),
              onSubmitted: (value) async {
                if (value.isNotEmpty) {
                  await _sendKey(value);
                  await _sendSpecialKey('Enter');
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final value = controller.text;
                if (value.isNotEmpty) {
                  await _sendKey(value);
                  await _sendSpecialKey('Enter');
                }
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Execute',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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

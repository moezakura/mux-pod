import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';

import '../../providers/connection_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/tmux/tmux_commands.dart';
import '../../theme/design_colors.dart';
import '../../widgets/special_keys_bar.dart';
import 'widgets/session_drawer.dart';

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
  late Terminal _terminal;
  final _terminalController = TerminalController();
  final _secureStorage = SecureStorageService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // 接続状態
  bool _isConnecting = false;
  String? _connectionError;

  // レイテンシ表示用
  int _latency = 0;

  // ポーリング用タイマー
  Timer? _pollTimer;
  Timer? _treeRefreshTimer;
  String _lastContent = '';
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _connectAndSetup();
  }

  /// SSH接続してtmuxセッションをセットアップ
  Future<void> _connectAndSetup() async {
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

      // 3. SSH接続（シェルは起動しない - execのみ使用）
      final sshNotifier = ref.read(sshProvider.notifier);
      await sshNotifier.connectWithoutShell(connection, options);

      // 4. セッションツリー全体を取得
      await _refreshSessionTree();

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
        await _refreshSessionTree(); // ツリーを再取得
      }

      // 6. アクティブセッション/ウィンドウ/ペインを設定
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

      // 7. 100msポーリング開始
      _startPolling();

      // 8. 5秒ごとにセッションツリーを更新
      _startTreeRefresh();

      setState(() {
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = e.toString();
      });
      _showErrorSnackBar(e.toString());
    }
  }

  /// セッションツリー全体を取得して更新
  Future<void> _refreshSessionTree() async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    try {
      final output = await sshClient.exec(TmuxCommands.listAllPanes());
      ref.read(tmuxProvider.notifier).parseAndUpdateFullTree(output);
    } catch (e) {
      debugPrint('Failed to refresh session tree: $e');
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
    if (_isPolling) return; // 前回のポーリングがまだ実行中
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
      final output = await sshClient.exec(
        TmuxCommands.capturePane(target, escapeSequences: true),
        timeout: const Duration(milliseconds: 500),
      );
      final endTime = DateTime.now();

      // レイテンシを更新
      setState(() {
        _latency = endTime.difference(startTime).inMilliseconds;
      });

      // 差分があれば更新
      if (output != _lastContent) {
        _lastContent = output;
        // ターミナルをクリアして新しい内容を書き込む
        _terminal.write('\x1b[2J\x1b[H'); // 画面クリア + カーソルホーム
        _terminal.write(output);
      }
    } catch (e) {
      // ポーリングエラーは静かに無視（接続エラーは別途ハンドリング）
      debugPrint('Poll error: $e');
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
    // タイマーを停止
    _pollTimer?.cancel();
    _treeRefreshTimer?.cancel();
    _terminalController.dispose();
    // SSH接続をクリーンアップ
    ref.read(sshProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sshState = ref.watch(sshProvider);
    final tmuxState = ref.watch(tmuxProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: DesignColors.backgroundDark,
      drawer: _buildSessionDrawer(tmuxState),
      drawerEdgeDragWidth: 40,
      body: Stack(
        children: [
          Column(
            children: [
              _buildBreadcrumbHeader(tmuxState),
              Expanded(
                child: Stack(
                  children: [
                    TerminalView(
                      _terminal,
                      controller: _terminalController,
                      autofocus: true,
                      backgroundOpacity: 1.0,
                      theme: _buildTerminalTheme(),
                      textStyle: TerminalStyle.fromTextStyle(
                        GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
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

  /// セッションドロワーを構築
  Widget _buildSessionDrawer(TmuxState tmuxState) {
    final sessions = tmuxState.sessions.map((session) {
      return SessionItem(
        name: session.name,
        windows: session.windows.map((window) {
          return WindowItem(
            index: window.index,
            name: window.name,
            panes: window.panes.map((pane) {
              return PaneItem(
                index: pane.index,
                id: pane.id,
                width: pane.width,
                height: pane.height,
              );
            }).toList(),
          );
        }).toList(),
      );
    }).toList();

    return Drawer(
      backgroundColor: DesignColors.surfaceDark,
      child: SafeArea(
        child: Column(
          children: [
            // ドロワーヘッダー
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF2A2B36)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree,
                    color: DesignColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sessions',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _refreshSessionTree,
                    icon: const Icon(Icons.refresh, size: 20),
                    color: Colors.white60,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            // セッションツリー
            Expanded(
              child: SessionDrawer(
                sessions: sessions,
                activeSessionName: tmuxState.activeSessionName,
                activeWindowIndex: tmuxState.activeWindowIndex,
                activePaneId: tmuxState.activePaneId,
                onSessionTap: (sessionName) => _selectSession(sessionName),
                onWindowTap: (sessionName, windowIndex) =>
                    _selectWindow(sessionName, windowIndex),
                onPaneTap: (paneId) => _selectPane(paneId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// セッションを選択
  Future<void> _selectSession(String sessionName) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // tmux_providerでアクティブセッションを更新
    ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

    // ドロワーを閉じる
    _scaffoldKey.currentState?.closeDrawer();

    // ターミナル内容をクリアして再取得
    _lastContent = '';
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

    // tmux_providerでアクティブウィンドウを更新
    ref.read(tmuxProvider.notifier).setActiveWindow(windowIndex);

    // ドロワーを閉じる
    _scaffoldKey.currentState?.closeDrawer();

    // ターミナル内容をクリアして再取得
    _lastContent = '';
  }

  /// ペインを選択
  Future<void> _selectPane(String paneId) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // tmux select-paneを実行
    await sshClient.exec(TmuxCommands.selectPane(paneId));

    // tmux_providerでアクティブペインを更新
    ref.read(tmuxProvider.notifier).setActivePane(paneId);

    // ドロワーを閉じる
    _scaffoldKey.currentState?.closeDrawer();

    // ターミナル内容をクリアして再取得
    _lastContent = '';
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

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: DesignColors.surfaceDark.withValues(alpha: 0.9),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2B36), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // ハンバーガーメニュー
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu, size: 18),
              color: Colors.white70,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              tooltip: 'Open session drawer',
            ),
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
              ...tmuxState.sessions.map((session) {
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
              }),
              const SizedBox(height: 16),
            ],
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
              ...session.windows.map((window) {
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
              }),
              const SizedBox(height: 16),
            ],
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
              ...window.panes.map((pane) {
                final isActive = pane.id == tmuxState.activePaneId;
                return ListTile(
                  leading: Icon(
                    Icons.terminal,
                    color: isActive ? DesignColors.primary : Colors.white60,
                  ),
                  title: Text(
                    'Pane ${pane.index}',
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
              }),
              const SizedBox(height: 16),
            ],
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

  /// 右上のペインインジケーター
  Widget _buildPaneIndicator(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    final panes = window?.panes ?? [];
    final activePaneId = tmuxState.activePaneId;

    if (panes.isEmpty) {
      return const SizedBox.shrink();
    }

    // 簡易的なペインレイアウト表示（最大4ペイン）
    return GestureDetector(
      onTap: () => _showPaneSelector(tmuxState),
      child: Opacity(
        opacity: 0.4,
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 上段
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < panes.length.clamp(0, 2); i++)
                    Container(
                      width: 18,
                      height: 14,
                      margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: panes[i].id == activePaneId
                              ? DesignColors.primary
                              : Colors.white30,
                        ),
                        color: panes[i].id == activePaneId
                            ? DesignColors.primary.withValues(alpha: 0.3)
                            : Colors.black26,
                      ),
                    ),
                ],
              ),
              // 下段（3ペイン以上の場合）
              if (panes.length > 2) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 2; i < panes.length.clamp(0, 4); i++)
                      Container(
                        width: 18,
                        height: 14,
                        margin: EdgeInsets.only(left: i > 2 ? 2 : 0),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: panes[i].id == activePaneId
                                ? DesignColors.primary
                                : Colors.white30,
                          ),
                          color: panes[i].id == activePaneId
                              ? DesignColors.primary.withValues(alpha: 0.3)
                              : Colors.black26,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  TerminalTheme _buildTerminalTheme() {
    return TerminalTheme(
      cursor: DesignColors.primary,
      selection: DesignColors.primary.withValues(alpha: 0.3),
      foreground: Colors.white.withValues(alpha: 0.9),
      background: DesignColors.backgroundDark,
      black: const Color(0xFF000000),
      red: DesignColors.terminalRed,
      green: DesignColors.terminalGreen,
      yellow: DesignColors.terminalYellow,
      blue: DesignColors.terminalBlue,
      magenta: DesignColors.terminalMagenta,
      cyan: DesignColors.terminalCyan,
      white: const Color(0xFFE0E0E0),
      brightBlack: const Color(0xFF808080),
      brightRed: const Color(0xFFFF6B6B),
      brightGreen: const Color(0xFF69FF94),
      brightYellow: const Color(0xFFFFF36D),
      brightBlue: const Color(0xFF76A9FA),
      brightMagenta: const Color(0xFFD4A5FF),
      brightCyan: const Color(0xFF7FDBFF),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: DesignColors.primary.withValues(alpha: 0.3),
      searchHitBackgroundCurrent: DesignColors.primary.withValues(alpha: 0.5),
      searchHitForeground: Colors.white,
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
    } catch (e) {
      debugPrint('Send key error: $e');
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
    } catch (e) {
      debugPrint('Send special key error: $e');
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
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';

import '../../providers/connection_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/tmux/tmux_commands.dart';
import '../../services/tmux/tmux_parser.dart';
import '../../theme/design_colors.dart';
import '../../widgets/special_keys_bar.dart';

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
  final _secureStorage = const FlutterSecureStorage();

  // 接続状態
  bool _isConnecting = false;
  String? _connectionError;

  // UI表示用
  String _currentSession = '';
  String _currentWindow = '';
  int _currentWindowIndex = 0;
  int _currentPaneIndex = 0;
  int _latency = 0;

  // ポーリング用タイマー
  Timer? _pollTimer;
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

      // 4. tmuxセッション一覧を取得
      final sshClient = sshNotifier.client;
      final sessionsOutput = await sshClient?.exec(TmuxCommands.listSessions());
      if (sessionsOutput != null) {
        final sessions = TmuxParser.parseSessions(sessionsOutput);
        ref.read(tmuxProvider.notifier).updateSessions(sessions);

        // 5. セッションを選択または新規作成
        String sessionName;
        if (sessions.isNotEmpty) {
          sessionName = widget.sessionName ?? sessions.first.name;
        } else {
          // セッションがない場合は新規作成
          sessionName = 'muxpod-${DateTime.now().millisecondsSinceEpoch}';
          await sshClient?.exec(TmuxCommands.newSession(name: sessionName, detached: true));
        }

        ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

        // 6. ウィンドウ・ペイン情報を取得
        final windowsOutput = await sshClient?.exec(TmuxCommands.listWindows(sessionName));
        if (windowsOutput != null) {
          final windows = TmuxParser.parseWindows(windowsOutput);
          if (windows.isNotEmpty) {
            final activeWindow = windows.firstWhere((w) => w.active, orElse: () => windows.first);
            setState(() {
              _currentSession = sessionName;
              _currentWindow = activeWindow.name;
              _currentWindowIndex = activeWindow.index;
              _currentPaneIndex = 0; // デフォルトで最初のペイン
            });
          }
        }

        // 7. 100msポーリング開始
        _startPolling();
      }

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

      // ペインIDを構築: session:window.pane
      final paneId = '$_currentSession:$_currentWindowIndex.$_currentPaneIndex';
      final startTime = DateTime.now();
      final output = await sshClient.exec(
        TmuxCommands.capturePane(paneId, escapeSequences: true),
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
      final privateKey = await _secureStorage.read(
        key: 'ssh_key_${connection.keyId}_private',
      );
      final passphrase = await _secureStorage.read(
        key: 'ssh_key_${connection.keyId}_passphrase',
      );
      return SshConnectOptions(privateKey: privateKey, passphrase: passphrase);
    } else {
      final password = await _secureStorage.read(
        key: 'connection_${connection.id}_password',
      );
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
    // ポーリングタイマーを停止
    _pollTimer?.cancel();
    _terminalController.dispose();
    // SSH接続をクリーンアップ
    ref.read(sshProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sshState = ref.watch(sshProvider);

    return Scaffold(
      backgroundColor: DesignColors.backgroundDark,
      body: Stack(
        children: [
          Column(
            children: [
              _buildBreadcrumbHeader(),
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
                      child: _buildPaneIndicator(),
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
  Widget _buildBreadcrumbHeader() {
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
            const SizedBox(width: 8),
            // Server icon
            Icon(
              Icons.dns,
              size: 14,
              color: DesignColors.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            // Breadcrumb navigation
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildBreadcrumbItem(_currentSession, isActive: true),
                    _buildBreadcrumbSeparator(),
                    _buildBreadcrumbItem(_currentWindow, isSelected: true),
                    _buildBreadcrumbSeparator(),
                    _buildBreadcrumbItem('htop', isActive: false),
                    _buildBreadcrumbSeparator(),
                    _buildBreadcrumbItem('nvim', isActive: false),
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

  Widget _buildBreadcrumbItem(String label, {bool isActive = false, bool isSelected = false}) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: isSelected
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
            : EdgeInsets.zero,
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              )
            : null,
        child: Row(
          children: [
            if (isSelected)
              Icon(
                Icons.article,
                size: 12,
                color: DesignColors.primary,
              ),
            if (isSelected) const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: isActive || isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isActive
                    ? DesignColors.primary
                    : (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5)),
              ),
            ),
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
  Widget _buildPaneIndicator() {
    return Opacity(
      opacity: 0.3,
      child: Column(
        children: [
          Container(
            width: 24,
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: DesignColors.primary),
              color: DesignColors.primary.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
        ],
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

    try {
      final paneId = '$_currentSession:$_currentWindowIndex.$_currentPaneIndex';
      await sshClient.exec(TmuxCommands.sendKeys(paneId, key, literal: literal));
    } catch (e) {
      debugPrint('Send key error: $e');
    }
  }

  /// tmux特殊キーを送信（Ctrl+C, Escape等）
  Future<void> _sendSpecialKey(String tmuxKey) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    try {
      final paneId = '$_currentSession:$_currentWindowIndex.$_currentPaneIndex';
      // 特殊キーはリテラルではなくtmux形式で送信
      await sshClient.exec(TmuxCommands.sendKeys(paneId, tmuxKey, literal: false));
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

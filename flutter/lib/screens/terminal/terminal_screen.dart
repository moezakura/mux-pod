import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../models/connection.dart';
import '../../providers/connection_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/ssh/ssh_client.dart';
import '../../widgets/special_keys_bar.dart';
import '../../widgets/terminal_toolbar.dart';
import '../../widgets/terminal_view.dart';
import 'widgets/session_list_drawer.dart';

/// ターミナル画面
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    super.key,
    required this.connectionId,
  });

  final String connectionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late final Terminal _terminal;
  SshShellSession? _shellSession;
  StreamSubscription<dynamic>? _stdoutSubscription;
  StreamSubscription<dynamic>? _stderrSubscription;
  Connection? _connection;
  String? _errorMessage;
  bool _isConnecting = true;
  bool _showSpecialKeys = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
    );
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // 接続情報を取得
      _connection = await ref.read(connectionProvider(widget.connectionId).future);
      if (_connection == null) {
        throw Exception('Connection not found');
      }

      // SSH接続
      final controller = ref.read(sshConnectionControllerProvider(widget.connectionId).notifier);
      await controller.connect();

      // シェルセッション開始
      _shellSession = await controller.startShell(
        width: 80,
        height: 24,
      );

      // 出力ストリームを購読
      _stdoutSubscription = _shellSession!.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      _stderrSubscription = _shellSession!.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Terminalからの入力をSSHに送る
      _terminal.onOutput = (data) {
        _shellSession?.writeString(data);
      };

      // シェル終了時の処理
      _shellSession!.done.then((_) {
        if (mounted) {
          _handleDisconnect();
        }
      });

      setState(() => _isConnecting = false);
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleDisconnect() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection closed')),
      );
      context.pop();
    }
  }

  void _handleKeyPress(TerminalKey key, {bool ctrl = false, bool alt = false, bool shift = false}) {
    // keyInputはTerminalのonOutputを呼び出し、SSHに送信される
    _terminal.keyInput(key, ctrl: ctrl, alt: alt, shift: shift);
  }

  void _handleTextInput(String text) {
    // 直接SSHに送信
    _shellSession?.writeString(text);
  }

  void _handleResize(int width, int height) {
    _shellSession?.resize(width, height);
  }

  void _disconnect() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();

    if (_shellSession != null) {
      await _shellSession!.close();
    }

    final controller = ref.read(sshConnectionControllerProvider(widget.connectionId).notifier);
    await controller.disconnect();

    if (mounted) {
      context.pop();
    }
  }

  void _openSessionsDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _TerminalSettingsSheet(
        showSpecialKeys: _showSpecialKeys,
        onShowSpecialKeysChanged: (value) {
          setState(() => _showSpecialKeys = value);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sshClient = ref.watch(sshClientProvider);
    final status = sshClient.getStatus(widget.connectionId);

    return Scaffold(
      key: _scaffoldKey,
      body: SafeArea(
        child: Column(
          children: [
            // ツールバー
            TerminalToolbar(
              connectionName: _connection?.name ?? 'Connecting...',
              status: status,
              onSessionsTap: _openSessionsDrawer,
              onDisconnect: _disconnect,
              onSettings: _openSettings,
            ),

            // メインコンテンツ
            Expanded(
              child: _buildContent(status),
            ),

            // 特殊キーバー
            if (_showSpecialKeys && status == ConnectionStatus.connected)
              SpecialKeysBar(
                onKeyPressed: _handleKeyPress,
                onTextInput: _handleTextInput,
              ),
          ],
        ),
      ),
      endDrawer: _buildSessionsDrawer(),
    );
  }

  Widget _buildContent(ConnectionStatus status) {
    if (_errorMessage != null) {
      return _buildErrorView();
    }

    if (_isConnecting) {
      return _buildConnectingView(status);
    }

    return _buildTerminalView();
  }

  Widget _buildConnectingView(ConnectionStatus status) {
    String message;
    switch (status) {
      case ConnectionStatus.connecting:
        message = 'Connecting to ${_connection?.host ?? 'server'}...';
      case ConnectionStatus.authenticating:
        message = 'Authenticating...';
      case ConnectionStatus.connected:
        message = 'Starting shell...';
      default:
        message = 'Initializing...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Connection Failed',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalView() {
    return GestureDetector(
      onTap: () {
        // ターミナルにフォーカス
      },
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: Container(
        color: Colors.black,
        child: TerminalViewWidget(
          terminal: _terminal,
          onResize: _handleResize,
          autoResize: true,
        ),
      ),
    );
  }

  Widget _buildSessionsDrawer() {
    return SessionListDrawer(
      connectionId: widget.connectionId,
      onSessionSelected: (sessionName) async {
        final controller = ref.read(tmuxControllerProvider(widget.connectionId).notifier);
        await controller.selectSession(sessionName);
      },
      onWindowSelected: (sessionName, windowIndex) async {
        final controller = ref.read(tmuxControllerProvider(widget.connectionId).notifier);
        await controller.selectSession(sessionName);
        await controller.selectWindow(windowIndex);
      },
      onPaneSelected: (sessionName, windowIndex, paneIndex) async {
        final controller = ref.read(tmuxControllerProvider(widget.connectionId).notifier);
        await controller.selectSession(sessionName);
        await controller.selectWindow(windowIndex);
        await controller.selectPane(paneIndex);
      },
    );
  }

  /// スワイプでウィンドウ切り替え
  void _handleHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return; // 十分な速度がない場合は無視

    final controller = ref.read(tmuxControllerProvider(widget.connectionId).notifier);

    if (velocity > 0) {
      // 右スワイプ: 前のウィンドウ
      controller.previousWindow();
    } else {
      // 左スワイプ: 次のウィンドウ
      controller.nextWindow();
    }
  }
}

/// ターミナル設定シート
class _TerminalSettingsSheet extends StatelessWidget {
  const _TerminalSettingsSheet({
    required this.showSpecialKeys,
    required this.onShowSpecialKeysChanged,
  });

  final bool showSpecialKeys;
  final void Function(bool) onShowSpecialKeysChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Terminal Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Show Special Keys Bar'),
            subtitle: const Text('ESC, Tab, Ctrl+C, arrows, etc.'),
            value: showSpecialKeys,
            onChanged: onShowSpecialKeysChanged,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

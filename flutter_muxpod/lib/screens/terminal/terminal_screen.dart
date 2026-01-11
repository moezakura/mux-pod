import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';

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
  final String _currentSession = 'ses-01';
  final String _currentWindow = 'logs';
  final int _latency = 12;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _connectAndAttach();
  }

  Future<void> _connectAndAttach() async {
    // TODO: SSH接続してtmuxにアタッチ
    // デモ用にサンプルテキストを表示
    _terminal.write('\x1b[32muser@prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ tail -f /var/log/nginx/access.log\r\n');
    _terminal.write('127.0.0.1 - - [10/Jan/2024:14:32:01 +0000] "GET /api/v1/status HTTP/1.1" 200 132\r\n');
    _terminal.write('127.0.0.1 - - [10/Jan/2024:14:32:05 +0000] "POST /auth/login HTTP/1.1" 200 456\r\n');
    _terminal.write('\x1b[32muser@prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ ');
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignColors.backgroundDark,
      body: Column(
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
            onInputTap: _showInputDialog,
          ),
        ],
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

  void _sendKey(String key) {
    // TODO: SSH経由でキーを送信
    _terminal.write(key);
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
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _terminal.write('$value\r\n');
                }
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final value = controller.text;
                if (value.isNotEmpty) {
                  _terminal.write('$value\r\n');
                }
                Navigator.pop(context);
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

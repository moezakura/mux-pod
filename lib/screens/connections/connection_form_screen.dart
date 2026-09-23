import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../services/backend/backend_type.dart';
import '../../theme/design_colors.dart';
import 'connection_form_auth_section.dart';
import 'connection_form_saver.dart';
import 'connection_form_server_section.dart';
import 'connection_form_tester.dart';
import 'connection_form_values.dart';

export 'connection_form_tester.dart'
    show connectionFormSshClientFactoryProvider;

/// 接続編集画面（composition root）。
///
/// フォーム状態（controller・選択値）の単一所有者として、入力値の
/// 収集・接続テスト・保存をオーケストレーションする。
/// セクション表示は [ConnectionServerSection] / [ConnectionAuthSection] へ、
/// 接続テスト実行は [ConnectionTester] へ、保存は [ConnectionSaver] へ委譲する。
class ConnectionFormScreen extends ConsumerStatefulWidget {
  final String? connectionId;

  const ConnectionFormScreen({super.key, this.connectionId});

  bool get isEditing => connectionId != null;

  @override
  ConsumerState<ConnectionFormScreen> createState() =>
      _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends ConsumerState<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _multiplexerPathController = TextEditingController();
  final _deepLinkIdController = TextEditingController();

  String _authMethod = 'password';
  String? _selectedKeyId;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;

  /// 選択中の backend（Tmux / Herdr）。
  BackendType _backend = BackendType.tmux;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadExistingConnection();
    }
  }

  void _loadExistingConnection() {
    final connection = ref
        .read(connectionsProvider.notifier)
        .getById(widget.connectionId!);
    if (connection != null) {
      _nameController.text = connection.name;
      _hostController.text = connection.host;
      _portController.text = connection.port.toString();
      _usernameController.text = connection.username;
      _authMethod = connection.authMethod;
      _selectedKeyId = connection.keyId;
      _backend = connection.multiplexer.backend;
      _multiplexerPathController.text =
          connection.multiplexer.executablePath ?? '';
      _deepLinkIdController.text = connection.deepLinkId ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _multiplexerPathController.dispose();
    _deepLinkIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(keysProvider);

    return Scaffold(
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Background grid pattern
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.5,
                  colors: [
                    DesignColors.primary.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Form content
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                ConnectionServerSection(
                  nameController: _nameController,
                  hostController: _hostController,
                  portController: _portController,
                  usernameController: _usernameController,
                  multiplexerPathController: _multiplexerPathController,
                  deepLinkIdController: _deepLinkIdController,
                  backend: _backend,
                  onBackendChanged: (backend) =>
                      setState(() => _backend = backend),
                  onHostChanged: () => setState(() {}),
                ),
                const SizedBox(height: 24),
                ConnectionAuthSection(
                  keysState: keysState,
                  isEditing: widget.isEditing,
                  authMethod: _authMethod,
                  selectedKeyId: _selectedKeyId,
                  obscurePassword: _obscurePassword,
                  passwordController: _passwordController,
                  onAuthMethodChanged: (method) =>
                      setState(() => _authMethod = method),
                  onObscurePasswordChanged: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  onKeySelected: (keyId) =>
                      setState(() => _selectedKeyId = keyId),
                ),
              ],
            ),
          ),
          // Bottom action button
          _buildBottomAction(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      surfaceTintColor: Colors.transparent,
      leading: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          context.l10n.connCancel,
          style: GoogleFonts.spaceGrotesk(
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      leadingWidth: 80,
      title: Text(
        widget.isEditing
            ? context.l10n.connEditTitle
            : context.l10n.connAddTitle,
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  context.l10n.connSave,
                  style: GoogleFonts.spaceGrotesk(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomAction() {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isTesting ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isTesting
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.terminal, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          context.l10n.connTestConnection,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isTesting = true);

    final values = ConnectionFormValues.fromControllers(
      nameController: _nameController,
      hostController: _hostController,
      portController: _portController,
      usernameController: _usernameController,
      passwordController: _passwordController,
      multiplexerPathController: _multiplexerPathController,
      deepLinkIdController: _deepLinkIdController,
      authMethod: _authMethod,
      keyId: _selectedKeyId,
      backend: _backend,
    );

    final sshClientFactory = ref.read(connectionFormSshClientFactoryProvider);
    final result = await const ConnectionTester().run(
      sshClientFactory: sshClientFactory,
      values: values,
      l10n: l10n,
    );

    if (mounted) {
      setState(() => _isTesting = false);
      _showConnectionTestResult(result, l10n);
    }
  }

  /// 接続テスト結果の SnackBar 表示（文言・色・duration は HEAD と同一）。
  void _showConnectionTestResult(
    ConnectionTestResult result,
    AppLocalizations l10n,
  ) {
    if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          backgroundColor: DesignColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (_backend == BackendType.herdr) {
      final message = result.herdrReady
          ? l10n.connTestSuccessHerdr
          : l10n.connTestSuccessWarning(
              result.herdrWarning ?? l10n.connHerdrNotFound,
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.herdrReady
              ? DesignColors.success
              : DesignColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      final message = result.tmuxInstalled
          ? l10n.connTestSuccessTmux
          : l10n.connTestSuccessWarning(
              result.tmuxWarning ?? l10n.connTmuxNotFound,
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.tmuxInstalled
              ? DesignColors.success
              : DesignColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _save() async {
    developer.log('_save() called', name: 'ConnectionForm');

    if (!_formKey.currentState!.validate()) {
      developer.log('Form validation failed', name: 'ConnectionForm');
      return;
    }

    setState(() => _isSaving = true);
    developer.log('Starting save process...', name: 'ConnectionForm');

    try {
      final connectionId = widget.connectionId ?? const Uuid().v4();
      developer.log(
        'Connection ID: $connectionId (isEditing: ${widget.isEditing})',
        name: 'ConnectionForm',
      );

      final values = ConnectionFormValues.fromControllers(
        nameController: _nameController,
        hostController: _hostController,
        portController: _portController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        multiplexerPathController: _multiplexerPathController,
        deepLinkIdController: _deepLinkIdController,
        authMethod: _authMethod,
        keyId: _selectedKeyId,
        backend: _backend,
      );

      final notifier = ref.read(connectionsProvider.notifier);
      await const ConnectionSaver().save(
        connectionId: connectionId,
        isEditing: widget.isEditing,
        values: values,
        notifier: notifier,
      );

      developer.log(
        'Save completed, popping navigator...',
        name: 'ConnectionForm',
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        developer.log('Navigator popped', name: 'ConnectionForm');
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error saving connection: $e',
        name: 'ConnectionForm',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.connSaveError('$e')),
            backgroundColor: DesignColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        developer.log('_isSaving set to false', name: 'ConnectionForm');
      }
    }
  }
}

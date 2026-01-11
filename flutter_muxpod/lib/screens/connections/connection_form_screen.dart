import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../services/keychain/secure_storage.dart';
import '../../theme/design_colors.dart';

/// 接続編集画面
class ConnectionFormScreen extends ConsumerStatefulWidget {
  final String? connectionId;

  const ConnectionFormScreen({
    super.key,
    this.connectionId,
  });

  bool get isEditing => connectionId != null;

  @override
  ConsumerState<ConnectionFormScreen> createState() => _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends ConsumerState<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _timeoutController = TextEditingController(text: '10');

  String _authMethod = 'password';
  String _protocol = 'ssh'; // ssh or mosh
  String? _selectedKeyId;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadExistingConnection();
    }
  }

  void _loadExistingConnection() {
    final connection = ref.read(connectionsProvider.notifier).getById(widget.connectionId!);
    if (connection != null) {
      _nameController.text = connection.name;
      _hostController.text = connection.host;
      _portController.text = connection.port.toString();
      _usernameController.text = connection.username;
      _authMethod = connection.authMethod;
      _selectedKeyId = connection.keyId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(keysProvider);

    return Scaffold(
      backgroundColor: DesignColors.backgroundDark,
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
                _buildGeneralSection(),
                const SizedBox(height: 24),
                _buildNetworkSection(),
                const SizedBox(height: 24),
                _buildSecuritySection(keysState),
                const SizedBox(height: 24),
                _buildAdvancedToggle(),
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
    return AppBar(
      backgroundColor: DesignColors.backgroundDark.withValues(alpha: 0.9),
      surfaceTintColor: Colors.transparent,
      leading: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          'Cancel',
          style: GoogleFonts.spaceGrotesk(
            color: DesignColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      leadingWidth: 80,
      title: Text(
        widget.isEditing ? 'Edit Connection' : 'Add Connection',
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
                  'Save',
                  style: GoogleFonts.spaceGrotesk(
                    color: DesignColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {IconData? trailingIcon}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: DesignColors.textMuted,
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 16, color: DesignColors.textMuted),
        ],
      ),
    );
  }

  Widget _buildGeneralSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('General Info', trailingIcon: Icons.info_outline),
        Container(
          decoration: BoxDecoration(
            color: DesignColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.all(4),
          child: _buildInputField(
            controller: _nameController,
            label: 'CONNECTION NAME',
            hint: 'e.g. Production AWS',
            prefixIcon: Icons.label_outline,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Network'),
        Container(
          decoration: BoxDecoration(
            color: DesignColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Host field
              _buildFieldLabel('HOST / IP ADDRESS'),
              const SizedBox(height: 8),
              _buildHostInput(),
              const SizedBox(height: 16),
              // Port & Timeout row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('PORT'),
                        const SizedBox(height: 8),
                        _buildPortInput(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('TIMEOUT'),
                        const SizedBox(height: 8),
                        _buildTimeoutInput(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecuritySection(KeysState keysState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SECURITY & AUTH',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: DesignColors.textMuted,
                ),
              ),
              // Protocol toggle
              Row(
                children: [
                  _buildProtocolBadge('SSH', _protocol == 'ssh'),
                  const SizedBox(width: 8),
                  _buildProtocolBadge('MOSH', _protocol == 'mosh'),
                ],
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: DesignColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Username field
              _buildUsernameInput(),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
              const SizedBox(height: 16),
              // Auth method toggle
              _buildAuthMethodToggle(),
              const SizedBox(height: 16),
              // Password or Key selection
              if (_authMethod == 'password')
                _buildPasswordInput()
              else
                _buildKeyDropdown(keysState),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProtocolBadge(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _protocol = label.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? DesignColors.primary : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: DesignColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.black : DesignColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        color: DesignColors.textMuted,
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Stack(
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.spaceGrotesk(color: DesignColors.textMuted),
            prefixIcon: Icon(prefixIcon, color: DesignColors.textMuted),
            filled: true,
            fillColor: DesignColors.inputDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: validator,
        ),
        Positioned(
          left: 16,
          top: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: DesignColors.surfaceDark,
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: DesignColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHostInput() {
    return TextFormField(
      controller: _hostController,
      keyboardType: TextInputType.url,
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        hintText: '192.168.1.1 or example.com',
        hintStyle: GoogleFonts.jetBrainsMono(color: DesignColors.textMuted.withValues(alpha: 0.5)),
        filled: true,
        fillColor: DesignColors.inputDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: Container(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _hostController.text.isNotEmpty
                  ? DesignColors.success
                  : DesignColors.textMuted,
              shape: BoxShape.circle,
              boxShadow: _hostController.text.isNotEmpty
                  ? [
                      BoxShadow(
                        color: DesignColors.success.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a host';
        }
        return null;
      },
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildPortInput() {
    return TextFormField(
      controller: _portController,
      keyboardType: TextInputType.number,
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        hintText: '22',
        hintStyle: GoogleFonts.jetBrainsMono(color: DesignColors.textMuted.withValues(alpha: 0.5)),
        filled: true,
        fillColor: DesignColors.inputDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Required';
        }
        final port = int.tryParse(value);
        if (port == null || port < 1 || port > 65535) {
          return 'Invalid';
        }
        return null;
      },
    );
  }

  Widget _buildTimeoutInput() {
    return Stack(
      children: [
        TextFormField(
          controller: _timeoutController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: '10',
            hintStyle: GoogleFonts.jetBrainsMono(color: DesignColors.textMuted.withValues(alpha: 0.5)),
            filled: true,
            fillColor: DesignColors.inputDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: Text(
              's',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: DesignColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameInput() {
    return Stack(
      children: [
        TextFormField(
          controller: _usernameController,
          style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'root',
            hintStyle: GoogleFonts.jetBrainsMono(color: DesignColors.textMuted.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.person_outline, color: DesignColors.textMuted, size: 20),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a username';
            }
            return null;
          },
        ),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Center(
            child: Text(
              'USER',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: DesignColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthMethodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _authMethod = 'password'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _authMethod == 'password'
                      ? DesignColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _authMethod == 'password'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Password',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _authMethod == 'password'
                        ? Colors.black
                        : DesignColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _authMethod = 'key'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _authMethod == 'key'
                      ? DesignColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _authMethod == 'key'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Private Key',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _authMethod == 'key'
                        ? Colors.black
                        : DesignColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        hintText: '••••••••••••',
        hintStyle: GoogleFonts.jetBrainsMono(color: DesignColors.textMuted.withValues(alpha: 0.5)),
        prefixIcon: const Icon(Icons.key, color: DesignColors.textMuted, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: DesignColors.textMuted,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) {
        if (!widget.isEditing && (value == null || value.isEmpty)) {
          return 'Please enter a password';
        }
        return null;
      },
    );
  }

  Widget _buildKeyDropdown(KeysState keysState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedKeyId,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.vpn_key_outlined, color: DesignColors.textMuted, size: 20),
            filled: true,
            fillColor: DesignColors.inputDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          dropdownColor: DesignColors.surfaceDark,
          style: GoogleFonts.spaceGrotesk(fontSize: 14, color: Colors.white),
          items: keysState.keys.map((key) {
            return DropdownMenuItem(
              value: key.id,
              child: Text(key.name),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedKeyId = value),
          validator: (value) {
            if (_authMethod == 'key' && value == null) {
              return 'Please select an SSH key';
            }
            return null;
          },
          hint: Text(
            keysState.keys.isEmpty ? 'No keys available' : 'Select a key',
            style: GoogleFonts.spaceGrotesk(color: DesignColors.textMuted),
          ),
        ),
        if (_authMethod == 'key' && keysState.keys.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'No SSH keys found. Add keys in the Keys section.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: DesignColors.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedToggle() {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          // TODO: Show advanced options
        },
        icon: Text(
          'Show Advanced Options',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: DesignColors.textMuted,
          ),
        ),
        label: const Icon(
          Icons.expand_more,
          size: 16,
          color: DesignColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildBottomAction() {
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
              DesignColors.backgroundDark.withValues(alpha: 0),
              DesignColors.backgroundDark,
              DesignColors.backgroundDark,
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
                backgroundColor: DesignColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isTesting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.terminal, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'TEST CONNECTION',
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isTesting = true);

    // Simulate connection test
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isTesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection test successful!'),
          backgroundColor: DesignColors.success,
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
      developer.log('Connection ID: $connectionId (isEditing: ${widget.isEditing})', name: 'ConnectionForm');

      if (_authMethod == 'password' && _passwordController.text.isNotEmpty) {
        developer.log('Saving password to secure storage...', name: 'ConnectionForm');
        final storage = SecureStorageService();
        await storage.savePassword(connectionId, _passwordController.text);
        developer.log('Password saved successfully', name: 'ConnectionForm');
      }

      final connection = Connection(
        id: connectionId,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.parse(_portController.text),
        username: _usernameController.text.trim(),
        authMethod: _authMethod,
        keyId: _authMethod == 'key' ? _selectedKeyId : null,
        createdAt: widget.isEditing
            ? ref.read(connectionsProvider.notifier).getById(connectionId)?.createdAt ?? DateTime.now()
            : DateTime.now(),
      );
      developer.log('Connection object created: ${connection.name}', name: 'ConnectionForm');

      if (widget.isEditing) {
        developer.log('Updating existing connection...', name: 'ConnectionForm');
        await ref.read(connectionsProvider.notifier).update(connection);
        developer.log('Connection updated successfully', name: 'ConnectionForm');
      } else {
        developer.log('Adding new connection...', name: 'ConnectionForm');
        await ref.read(connectionsProvider.notifier).add(connection);
        developer.log('Connection added successfully', name: 'ConnectionForm');
      }

      developer.log('Save completed, popping navigator...', name: 'ConnectionForm');
      if (mounted) {
        Navigator.of(context).pop(true);
        developer.log('Navigator popped', name: 'ConnectionForm');
      }
    } catch (e, stackTrace) {
      developer.log('Error saving connection: $e', name: 'ConnectionForm', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving connection: $e'),
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

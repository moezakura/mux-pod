import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/connection_provider.dart';
import '../../services/keychain/secure_storage.dart';
import '../../theme/design_colors.dart';
import 'connection_form_screen.dart';
import '../terminal/terminal_screen.dart';

/// 接続一覧画面
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsState = ref.watch(connectionsProvider);
    developer.log(
      'ConnectionsScreen.build() - connections: ${connectionsState.connections.length}, isLoading: ${connectionsState.isLoading}',
      name: 'ConnectionsScreen',
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
            sliver: _buildBody(context, ref, connectionsState),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(context, ref),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 100,
      backgroundColor: DesignColors.canvasDark.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connections',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'GATEWAY_STATUS: ONLINE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: DesignColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: DesignColors.textSecondary),
          onPressed: () {},
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.sort, color: DesignColors.textSecondary),
          onPressed: () {},
          tooltip: 'Sort',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFAB(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 72),
      child: FloatingActionButton.extended(
        onPressed: () => _addConnection(context, ref),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add New Connection'),
        elevation: 0,
        backgroundColor: DesignColors.primary,
        foregroundColor: Colors.black,
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ConnectionsState state) {
    if (state.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return SliverFillRemaining(
        child: _buildErrorState(context, ref, state.error!),
      );
    }

    if (state.connections.isEmpty) {
      return SliverFillRemaining(
        child: _buildEmptyState(context),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final connection = state.connections[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ConnectionCard(
              connection: connection,
              onTap: () => _connectToServer(context, ref, connection),
              onEdit: () => _editConnection(context, ref, connection),
              onDelete: () => _deleteConnection(context, ref, connection),
            ),
          );
        },
        childCount: state.connections.length,
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: DesignColors.error),
          const SizedBox(height: 16),
          Text(
            'Error loading connections',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(error, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => ref.read(connectionsProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: DesignColors.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DesignColors.borderDark),
            ),
            child: const Icon(
              Icons.dns_outlined,
              size: 64,
              color: DesignColors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No connections yet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: DesignColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first server',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: DesignColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _addConnection(BuildContext context, WidgetRef ref) async {
    developer.log('_addConnection() - navigating to ConnectionFormScreen', name: 'ConnectionsScreen');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const ConnectionFormScreen()),
    );
    developer.log('_addConnection() - returned with result: $result', name: 'ConnectionsScreen');
    if (result == true) {
      developer.log('_addConnection() - invalidating connectionsProvider', name: 'ConnectionsScreen');
      ref.invalidate(connectionsProvider);
    }
  }

  void _editConnection(BuildContext context, WidgetRef ref, Connection connection) async {
    developer.log('_editConnection() - navigating to ConnectionFormScreen for ${connection.id}', name: 'ConnectionsScreen');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ConnectionFormScreen(connectionId: connection.id),
      ),
    );
    developer.log('_editConnection() - returned with result: $result', name: 'ConnectionsScreen');
    if (result == true) {
      developer.log('_editConnection() - invalidating connectionsProvider', name: 'ConnectionsScreen');
      ref.invalidate(connectionsProvider);
    }
  }

  Future<void> _deleteConnection(
    BuildContext context,
    WidgetRef ref,
    Connection connection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete "${connection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final storage = SecureStorageService();
      await storage.deletePassword(connection.id);
      await ref.read(connectionsProvider.notifier).remove(connection.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${connection.name} deleted')),
        );
      }
    }
  }

  void _connectToServer(BuildContext context, WidgetRef ref, Connection connection) {
    ref.read(connectionsProvider.notifier).updateLastConnected(connection.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(connectionId: connection.id),
      ),
    );
  }
}

/// 接続カード（展開可能）
class _ConnectionCard extends StatefulWidget {
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.connection.lastConnectedAt != null;
    final statusColor = isConnected ? DesignColors.success : DesignColors.textMuted;

    return Container(
      decoration: BoxDecoration(
        color: DesignColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignColors.borderDark),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Status Icon
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? const Color(0xFF153E42)
                              : DesignColors.borderDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isConnected
                                ? const Color(0xFF1F5F66)
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          Icons.dns,
                          size: 20,
                          color: isConnected
                              ? DesignColors.primary
                              : DesignColors.textSecondary,
                        ),
                      ),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: DesignColors.surfaceDark,
                              width: 2,
                            ),
                            boxShadow: isConnected
                                ? [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Connection Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.connection.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.connection.host} • ${widget.connection.username}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: DesignColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand Icon
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: DesignColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // Expanded Content
          if (_isExpanded) _buildExpandedContent(),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF15161C),
        border: Border(top: BorderSide(color: DesignColors.borderDark)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection Details
          _buildDetailRow(Icons.person, 'User', widget.connection.username),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.numbers, 'Port', widget.connection.port.toString()),
          const SizedBox(height: 8),
          _buildDetailRow(
            widget.connection.authMethod == 'key' ? Icons.vpn_key : Icons.password,
            'Auth',
            widget.connection.authMethod == 'key' ? 'SSH Key' : 'Password',
          ),
          const SizedBox(height: 16),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignColors.textSecondary,
                    side: const BorderSide(color: DesignColors.borderDark),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignColors.error,
                    side: const BorderSide(color: DesignColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Connect Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onTap,
              icon: const Icon(Icons.terminal, size: 18),
              label: const Text('CONNECT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: DesignColors.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: DesignColors.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            color: DesignColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

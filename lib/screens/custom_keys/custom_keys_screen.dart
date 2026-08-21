import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/custom_keys_provider.dart';
import '../../services/custom_keys/custom_key_button.dart';
import '../../theme/design_colors.dart';
import '../../widgets/dialogs/custom_key_button_editor_dialog.dart';

/// Full editor for custom key buttons: the button library plus the row
/// layout strips for the special keys bar.
class CustomKeysScreen extends ConsumerWidget {
  const CustomKeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customKeysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Custom Buttons')),
      body: ListView(
        children: [
          const _SectionHeader('Buttons'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addButton(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('+ Add button'),
              ),
            ),
          ),
          for (final button in state.buttons)
            ListTile(
              leading: const _AmberDot(),
              title: Text(button.label),
              subtitle: Text(_stepSummary(button.steps)),
              trailing: IconButton(
                key: Key('delete-${button.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete button',
                onPressed: () => ref
                    .read(customKeysProvider.notifier)
                    .deleteButton(button.id),
              ),
              onTap: () => _editButton(context, ref, button),
            ),
          const Divider(),
          for (var row = 0; row < state.rows.length; row++) ...[
            _RowHeader(
              title: 'Layout — Row ${row + 1}',
              onAdd: () => _addButton(context, ref, row: row, toIndex: null),
              onDelete: () =>
                  ref.read(customKeysProvider.notifier).removeRow(row),
              addKey: Key('row-$row-add'),
              deleteKey: Key('row-$row-delete'),
            ),
            _buildRowStrip(context, ref, state, row, state.rows[row]),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-row'),
                onPressed: state.rows.length >= CustomKeyRows.maxRows
                    ? null
                    : () => ref.read(customKeysProvider.notifier).addRow(),
                icon: const Icon(Icons.playlist_add),
                label: const Text('+ Add row'),
              ),
            ),
          ),
          const _SectionHeader('Unused'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Drag buttons here to hide them from the bar.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
            ),
          ),
          _buildShelfStrip(context, ref, state, state.unusedTokens()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// A horizontal strip of draggable chips with drop slots interleaved so a
  /// chip can be dropped at any index (the trailing slot appends). The whole
  /// strip is also a drop target that appends, so a sloppy drop is not lost.
  Widget _buildRowStrip(
    BuildContext context,
    WidgetRef ref,
    CustomKeysState state,
    int row,
    List<String> tokens,
  ) {
    final children = <Widget>[];
    for (var i = 0; i <= tokens.length; i++) {
      if (i > 0) {
        final token = tokens[i - 1];
        final button = CustomKeyRows.isCustomToken(token)
            ? _buttonForToken(state, token)
            : null;
        if (!CustomKeyRows.isCustomToken(token) || button != null) {
          children.add(
            _draggableChip(
              context,
              ref,
              key: Key('chip-$row-$token'),
              token: token,
              button: button,
            ),
          );
        }
      }
      children.add(_dropSlot(context, ref, row, i));
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => ref
          .read(customKeysProvider.notifier)
          .placeToken(details.data, toRow: row, toIndex: tokens.length),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          key: Key('layout-row-$row'),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active ? colorScheme.primary.withValues(alpha: 0.06) : null,
            border: Border.all(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          // Wrap, never a horizontal scroller: during a drag the strip cannot
          // be scrolled, so every chip and drop slot has to stay on screen.
          child: Wrap(
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...children,
              // An empty row renders nothing in the bar; say so, otherwise the
              // row looks broken rather than unused.
              if (tokens.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Empty — hidden in the bar',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The "Unused" shelf: a single drop target covering the whole strip. Any
  /// chip dropped here is removed from every row and hidden from the bar.
  Widget _buildShelfStrip(
    BuildContext context,
    WidgetRef ref,
    CustomKeysState state,
    List<String> tokens,
  ) {
    final chips = <Widget>[];
    for (final token in tokens) {
      final button = CustomKeyRows.isCustomToken(token)
          ? _buttonForToken(state, token)
          : null;
      if (CustomKeyRows.isCustomToken(token) && button == null) continue;
      chips.add(
        _draggableChip(
          context,
          ref,
          key: Key('chip-shelf-$token'),
          token: token,
          button: button,
        ),
      );
    }

    return DragTarget<String>(
      key: const Key('slot-shelf'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => ref
          .read(customKeysProvider.notifier)
          .placeToken(details.data, toRow: CustomKeyRows.shelfRow, toIndex: 0),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          key: const Key('layout-shelf'),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? colorScheme.primary.withValues(alpha: 0.06)
                : colorScheme.surface.withValues(alpha: 0.4),
            border: Border.all(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: chips.isEmpty
              ? Center(
                  child: Text(
                    'No unused buttons',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                    ),
                  ),
                )
              : Wrap(spacing: 8, runSpacing: 8, children: chips),
        );
      },
    );
  }

  /// A chip that starts a drag on long-press. A plain tap still reaches the
  /// chip underneath, so custom chips keep their editor-open tap behaviour.
  Widget _draggableChip(
    BuildContext context,
    WidgetRef ref, {
    required Key key,
    required String token,
    required CustomKeyButton? button,
  }) {
    Widget visual({required bool elevated}) {
      final chip = button == null
          ? _standardChip(context, token)
          : _customChip(context, ref, button);
      if (!elevated) return chip;
      return Material(
        color: Colors.transparent,
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: chip,
      );
    }

    return LongPressDraggable<String>(
      key: key,
      data: token,
      feedback: visual(elevated: true),
      childWhenDragging: Opacity(opacity: 0.4, child: visual(elevated: false)),
      child: visual(elevated: false),
    );
  }

  Widget _standardChip(BuildContext context, String token) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Chip(
      label: Text(CustomKeyRows.tokenLabel(token) ?? token),
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
      ),
    );
  }

  Widget _customChip(
    BuildContext context,
    WidgetRef ref,
    CustomKeyButton button,
  ) {
    return ActionChip(
      avatar: const Icon(Icons.tune, size: 16, color: DesignColors.secondary),
      label: Text(button.label),
      labelStyle: const TextStyle(color: DesignColors.secondary),
      side: const BorderSide(color: DesignColors.secondary),
      visualDensity: VisualDensity.compact,
      onPressed: () => _editButton(context, ref, button),
    );
  }

  Widget _dropSlot(BuildContext context, WidgetRef ref, int row, int index) {
    return DragTarget<String>(
      key: Key('slot-$row-$index'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => ref
          .read(customKeysProvider.notifier)
          .placeToken(details.data, toRow: row, toIndex: index),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          width: 12,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active
                ? colorScheme.primary.withValues(alpha: 0.25)
                : Colors.transparent,
            border: Border.all(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
        );
      },
    );
  }

  /// Creates a button and places it in [row].
  ///
  /// [toIndex] null appends, 0 prepends. When [row] is out of range (the layout
  /// has no rows yet) a row is created first, so the button is never invisible.
  Future<void> _addButton(
    BuildContext context,
    WidgetRef ref, {
    int row = 0,
    int? toIndex = 0,
  }) async {
    final result = await _openEditor(
      context,
      initialLabel: '',
      initialSteps: const [
        CustomKeyStep(type: CustomKeyStepType.text, value: ''),
      ],
    );
    if (result == null) return;
    final notifier = ref.read(customKeysProvider.notifier);
    if (ref.read(customKeysProvider).rows.isEmpty) notifier.addRow();
    final target = row < ref.read(customKeysProvider).rows.length ? row : 0;
    final button = notifier.addButton(result.$1, result.$2);
    notifier.placeToken(
      'ck:${button.id.substring(3)}',
      toRow: target,
      toIndex: toIndex ?? ref.read(customKeysProvider).rows[target].length,
    );
  }

  Future<void> _editButton(
    BuildContext context,
    WidgetRef ref,
    CustomKeyButton button,
  ) async {
    final result = await _openEditor(
      context,
      initialLabel: button.label,
      initialSteps: button.steps,
      onDelete: () =>
          ref.read(customKeysProvider.notifier).deleteButton(button.id),
    );
    if (result == null) return;
    ref
        .read(customKeysProvider.notifier)
        .updateButton(button.id, label: result.$1, steps: result.$2);
  }

  Future<(String, List<CustomKeyStep>)?> _openEditor(
    BuildContext context, {
    required String initialLabel,
    required List<CustomKeyStep> initialSteps,
    VoidCallback? onDelete,
  }) {
    return showDialog<(String, List<CustomKeyStep>)>(
      context: context,
      builder: (context) => CustomKeyButtonEditorDialog(
        initialLabel: initialLabel,
        initialSteps: initialSteps,
        onDelete: onDelete,
      ),
    );
  }

  static CustomKeyButton? _buttonForToken(CustomKeysState state, String token) {
    return state.buttonById('ck_${token.substring(3)}');
  }

  static String _stepSummary(List<CustomKeyStep> steps) {
    return steps
        .map(
          (s) => switch (s.type) {
            CustomKeyStepType.text => "'${s.value}'",
            CustomKeyStepType.key => s.value,
            CustomKeyStepType.pause => 'pause(${s.value}ms)',
          },
        )
        .join(' + ');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
        ),
      ),
    );
  }
}

/// Section header for one layout row: the label plus a delete affordance.
class _RowHeader extends StatelessWidget {
  const _RowHeader({
    required this.title,
    required this.onAdd,
    required this.onDelete,
    required this.addKey,
    required this.deleteKey,
  });

  final String title;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final Key addKey;
  final Key deleteKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SectionHeader(title)),
        IconButton(
          key: addKey,
          icon: const Icon(Icons.add),
          iconSize: 20,
          tooltip: 'New button in this row',
          onPressed: onAdd,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: deleteKey,
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            tooltip: 'Delete row',
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _AmberDot extends StatelessWidget {
  const _AmberDot();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      backgroundColor: DesignColors.secondary,
      radius: 5,
    );
  }
}

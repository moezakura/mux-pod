import 'package:flutter/material.dart';

import '../../services/custom_keys/custom_key_button.dart';

/// Editor dialog for a single custom key button.
///
/// Shown via `showDialog<(String, List<CustomKeyStep>)>`; pops
/// `(label.trim(), steps)` on Save, `null` on Cancel.
class CustomKeyButtonEditorDialog extends StatefulWidget {
  const CustomKeyButtonEditorDialog({
    super.key,
    required this.initialLabel,
    required this.initialSteps,
    this.onDelete,
  });

  final String initialLabel;
  final List<CustomKeyStep> initialSteps;
  final VoidCallback? onDelete;

  @override
  State<CustomKeyButtonEditorDialog> createState() =>
      _CustomKeyButtonEditorDialogState();
}

class _CustomKeyButtonEditorDialogState
    extends State<CustomKeyButtonEditorDialog> {
  late final TextEditingController _labelController;
  late final List<CustomKeyStep> _steps;
  late final List<TextEditingController> _valueControllers;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel);
    _steps = List.of(widget.initialSteps);
    _valueControllers = widget.initialSteps
        .map((s) => TextEditingController(text: s.value))
        .toList();
  }

  @override
  void dispose() {
    _labelController.dispose();
    for (final controller in _valueControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _typeLabel(CustomKeyStepType type) {
    switch (type) {
      case CustomKeyStepType.text:
        return 'Text';
      case CustomKeyStepType.key:
        return 'Key';
      case CustomKeyStepType.pause:
        return 'Pause';
    }
  }

  static String _hintFor(CustomKeyStepType type) {
    switch (type) {
      case CustomKeyStepType.text:
        return 'Text to type';
      case CustomKeyStepType.key:
        return 'tmux key (Enter, C-c, …)';
      case CustomKeyStepType.pause:
        return 'Milliseconds';
    }
  }

  void _addStep() {
    setState(() {
      _steps.add(const CustomKeyStep(type: CustomKeyStepType.text, value: ''));
      _valueControllers.add(TextEditingController());
    });
  }

  void _deleteStep(int index) {
    setState(() {
      _steps.removeAt(index);
      _valueControllers.removeAt(index).dispose();
    });
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(target, step);
      final controller = _valueControllers.removeAt(index);
      _valueControllers.insert(target, controller);
    });
  }

  void _changeType(int index, CustomKeyStepType? type) {
    if (type == null) return;
    setState(() {
      _steps[index] = CustomKeyStep(type: type, value: _steps[index].value);
    });
  }

  String? _validate() {
    if (_labelController.text.trim().isEmpty) return 'Label is required';
    if (_steps.isEmpty) return 'At least one step';
    for (var i = 0; i < _steps.length; i++) {
      final type = _steps[i].type;
      final value = _valueControllers[i].text;
      if ((type == CustomKeyStepType.text || type == CustomKeyStepType.key) &&
          value.trim().isEmpty) {
        return 'Step value is required';
      }
      if (type == CustomKeyStepType.pause &&
          !CustomKeyStep.isValid(type, value)) {
        return 'Invalid pause value';
      }
    }
    return null;
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final steps = <CustomKeyStep>[
      for (var i = 0; i < _steps.length; i++)
        CustomKeyStep(type: _steps[i].type, value: _valueControllers[i].text),
    ];
    Navigator.pop(context, (_labelController.text.trim(), steps));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Button'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('label-field'),
              controller: _labelController,
              autofocus: true,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              cursorColor: Theme.of(context).colorScheme.onSurface,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            const Text('Steps'),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _steps.length; i++) _buildStepRow(i),
                  ],
                ),
              ),
            ),
            TextButton(onPressed: _addStep, child: const Text('+ Add step')),
            if (_errorText != null)
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      // One explicit row instead of three loose actions: AlertDialog's
      // OverflowBar stacks them vertically as soon as they do not fit. Sizing
      // is intrinsic (a Flexible cell splits the width evenly and ellipsises
      // "Delete" into "Dele"), and the whole group scales down as a unit when
      // the dialog is too narrow - so the labels are always shown whole and
      // the row never wraps.
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actions: [
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onDelete != null) ...[
                  TextButton(
                    key: const Key('dialog-delete'),
                    onPressed: _confirmDelete,
                    style: _compactAction(
                      foreground: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('Delete', maxLines: 1, softWrap: false),
                  ),
                  const SizedBox(width: 16),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: _compactAction(),
                  child: const Text('Cancel', maxLines: 1, softWrap: false),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _save,
                  style: _compactAction(),
                  child: const Text('Save', maxLines: 1, softWrap: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Action button style trimmed to its label: the default 64px minimum width
  /// and 12-24px side padding are what pushes three buttons out of a narrow
  /// dialog. The 40px height keeps the tap target usable.
  static ButtonStyle _compactAction({Color? foreground}) {
    return ButtonStyle(
      foregroundColor: foreground == null
          ? null
          : WidgetStatePropertyAll<Color>(foreground),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 40)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Future<void> _confirmDelete() async {
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete button?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      navigator.pop();
      widget.onDelete?.call();
    }
  }

  Widget _buildStepRow(int index) {
    final isFirst = index == 0;
    final isLast = index == _steps.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Align the type/actions row with the value field's 16px content
        // inset (inputDecorationTheme.contentPadding): the trailing icon
        // glyph sits 8px inside its 36px tap target, hence right: 8.
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              // Shrinkable type selector. The row's fixed parts (140px selector
              // + three 40px actions + 24px padding = 284px) exceed the dialog
              // content box on narrow screens - a 411dp phone at a large
              // display-size setting gives ~230px - and a Row does not clip, so
              // the actions used to paint outside the dialog card. The Expanded
              // cell clamps the selector instead.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 140,
                    child: DropdownButton<CustomKeyStepType>(
                      key: Key('step-type-$index'),
                      value: _steps[index].type,
                      isDense: true,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final type in CustomKeyStepType.values)
                          DropdownMenuItem<CustomKeyStepType>(
                            value: type,
                            child: Text(
                              _typeLabel(type),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => _changeType(index, value),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('step-up-$index'),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward),
                onPressed: isFirst ? null : () => _moveStep(index, -1),
              ),
              IconButton(
                key: Key('step-down-$index'),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward),
                onPressed: isLast ? null : () => _moveStep(index, 1),
              ),
              IconButton(
                key: Key('step-delete-$index'),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Delete step',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteStep(index),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Full-width value field: always wide enough to show typed text,
        // regardless of the system font scale.
        TextField(
          key: Key('step-value-$index'),
          controller: _valueControllers[index],
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          cursorColor: Theme.of(context).colorScheme.onSurface,
          decoration: InputDecoration(
            hintText: _hintFor(_steps[index].type),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

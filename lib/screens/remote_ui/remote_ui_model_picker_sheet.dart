import 'package:flutter/material.dart';

/// Bottom sheet picking the model id for an agent.
///
/// With a non-empty `availableModels` list the options are shown with a
/// checkmark on the current selection. An empty list means the agent
/// accepts free-text model ids (see `AgentCapabilities.availableModels`),
/// so a text field is shown instead.
class RemoteUiModelPickerSheet {
  RemoteUiModelPickerSheet._();

  /// Shows the sheet and returns the chosen model id, or null when the
  /// sheet is dismissed without a choice.
  static Future<String?> show(
    BuildContext context, {
    required String? selectedModel,
    List<String> availableModels = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => availableModels.isEmpty
          ? _FreeTextModelPicker(initialModel: selectedModel)
          : _ModelListPicker(
              selectedModel: selectedModel,
              availableModels: availableModels,
            ),
    );
  }
}

class _ModelListPicker extends StatelessWidget {
  final String? selectedModel;
  final List<String> availableModels;

  const _ModelListPicker({
    required this.selectedModel,
    required this.availableModels,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Text(
              'Model',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final model in availableModels)
            ListTile(
              title: Text(model),
              trailing:
                  model == selectedModel ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, model),
            ),
        ],
      ),
    );
  }
}

class _FreeTextModelPicker extends StatefulWidget {
  final String? initialModel;

  const _FreeTextModelPicker({required this.initialModel});

  @override
  State<_FreeTextModelPicker> createState() => _FreeTextModelPickerState();
}

class _FreeTextModelPickerState extends State<_FreeTextModelPicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialModel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Lift the field above the software keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Model',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Model id or name',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

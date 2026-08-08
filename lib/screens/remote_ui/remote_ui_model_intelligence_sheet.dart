import 'package:flutter/material.dart';

import '../../services/agent/agent_types.dart';
import 'remote_ui_model_picker_sheet.dart';

/// The values chosen in [RemoteUiModelIntelligenceSheet].
///
/// Null fields mean "agent default" (shown as `Auto` in the UI); the
/// caller decides how to apply them (live-pane apply vs. pending chat
/// configuration).
class RemoteUiModelIntelligenceSelection {
  /// Chosen model id, null for the agent default.
  final String? model;

  /// Chosen reasoning effort, null when the agent has no effort control
  /// or none was chosen.
  final UnifiedIntelligence? intelligence;

  const RemoteUiModelIntelligenceSelection({this.model, this.intelligence});
}

/// Bottom sheet combining the reasoning-effort options with an entry
/// point to the model picker.
class RemoteUiModelIntelligenceSheet {
  RemoteUiModelIntelligenceSheet._();

  /// Shows the sheet.
  ///
  /// [intelligenceLevels] lists the selectable effort levels (from the
  /// agent's capabilities); when empty the Intelligence section is
  /// hidden. [availableModels] is forwarded to [RemoteUiModelPickerSheet]
  /// (empty means free-text model entry).
  static Future<RemoteUiModelIntelligenceSelection?> show(
    BuildContext context, {
    required String? selectedModel,
    required UnifiedIntelligence? selectedIntelligence,
    List<UnifiedIntelligence> intelligenceLevels = const [],
    List<String> availableModels = const [],
  }) {
    return showModalBottomSheet<RemoteUiModelIntelligenceSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RemoteUiModelIntelligenceSheetContent(
        selectedModel: selectedModel,
        selectedIntelligence: selectedIntelligence,
        intelligenceLevels: intelligenceLevels,
        availableModels: availableModels,
      ),
    );
  }
}

class _RemoteUiModelIntelligenceSheetContent extends StatefulWidget {
  final String? selectedModel;
  final UnifiedIntelligence? selectedIntelligence;
  final List<UnifiedIntelligence> intelligenceLevels;
  final List<String> availableModels;

  const _RemoteUiModelIntelligenceSheetContent({
    required this.selectedModel,
    required this.selectedIntelligence,
    required this.intelligenceLevels,
    required this.availableModels,
  });

  @override
  State<_RemoteUiModelIntelligenceSheetContent> createState() =>
      _RemoteUiModelIntelligenceSheetContentState();
}

class _RemoteUiModelIntelligenceSheetContentState
    extends State<_RemoteUiModelIntelligenceSheetContent> {
  String? _model;
  UnifiedIntelligence? _intelligence;

  @override
  void initState() {
    super.initState();
    _model = widget.selectedModel;
    _intelligence = widget.selectedIntelligence;
  }

  @override
  Widget build(BuildContext context) {
    final levels = widget.intelligenceLevels;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (levels.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Intelligence',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final level in levels)
              ListTile(
                title: Text(level.label),
                trailing:
                    level == _intelligence ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(
                  context,
                  RemoteUiModelIntelligenceSelection(
                    model: _model,
                    intelligence: level,
                  ),
                ),
              ),
            const Divider(height: 1),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Model',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Model'),
            subtitle: Text(_model ?? 'Auto'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickModel,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickModel() async {
    final model = await RemoteUiModelPickerSheet.show(
      context,
      selectedModel: _model,
      availableModels: widget.availableModels,
    );
    if (!mounted || model == null) return;
    // Pop this sheet too so the model choice is applied immediately
    // instead of being lost when the sheet is dismissed later.
    Navigator.pop(
      context,
      RemoteUiModelIntelligenceSelection(
        model: model,
        intelligence: _intelligence,
      ),
    );
  }
}

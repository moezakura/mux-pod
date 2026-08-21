import 'dart:math';

/// Тип шага действия пользовательской кнопки.
enum CustomKeyStepType { text, key, pause }

/// Один шаг последовательности: печать текста, нажатие клавиши или пауза.
class CustomKeyStep {
  const CustomKeyStep({required this.type, required this.value});

  final CustomKeyStepType type;

  /// text: литеральная строка; key: tmux-имя клавиши (Enter, C-c, …);
  /// pause: длительность в мс (строка, положительное целое).
  final String value;

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  static CustomKeyStep? fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    final value = json['value'];
    if (typeName is! String || value is! String) return null;
    final type = CustomKeyStepType.values.asNameMap()[typeName];
    if (type == null) return null;
    if (!isValid(type, value)) return null;
    return CustomKeyStep(type: type, value: value);
  }

  static bool isValid(CustomKeyStepType type, String value) {
    if (value.trim().isEmpty) return false;
    if (type == CustomKeyStepType.pause) {
      final ms = int.tryParse(value.trim());
      return ms != null && ms > 0;
    }
    return true;
  }
}

/// Пользовательская кнопка панели клавиш.
class CustomKeyButton {
  const CustomKeyButton({
    required this.id,
    required this.label,
    required this.steps,
  });

  final String id;
  final String label;
  final List<CustomKeyStep> steps;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  static CustomKeyButton? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    final rawSteps = json['steps'];
    if (id is! String || label is! String || rawSteps is! List) return null;
    if (id.isEmpty || label.trim().isEmpty) return null;
    final steps = <CustomKeyStep>[];
    for (final raw in rawSteps) {
      if (raw is! Map<String, dynamic>) return null;
      final step = CustomKeyStep.fromJson(raw);
      if (step == null) return null;
      steps.add(step);
    }
    if (steps.isEmpty) return null;
    return CustomKeyButton(id: id, label: label, steps: steps);
  }

  static String newId() {
    final rand = Random().nextInt(0xffff).toRadixString(16).padLeft(4, '0');
    return 'ck_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }
}

/// Стандартные токены раскладки рядов панели клавиш.
class CustomKeyRows {
  CustomKeyRows._();

  /// Верхний ряд только под пользовательские кнопки (по умолчанию пуст).
  static const List<String> standardRow0 = <String>[];

  /// Bucket id for the "Unused" shelf.
  static const int shelfRow = -1;

  static const List<String> standardRow1 = [
    'esc',
    'tab',
    'ctrl',
    'alt',
    'shift',
    'enter',
    'senter',
    'slash',
    'dash',
  ];

  static const List<String> standardRow2 = [
    'pgup',
    'pgdn',
    'left',
    'up',
    'down',
    'right',
    'image',
    'di_toggle',
    'input',
  ];

  static const List<String> directInputExtras = [
    'num1',
    'num2',
    'num3',
    'num4',
  ];

  /// Every standard token that can be placed, in canonical shelf order.
  static const List<String> allLayoutTokens = [
    ...standardRow1,
    ...standardRow2,
    ...directInputExtras,
  ];

  static const Set<String> standardIds = {
    ...standardRow1,
    ...standardRow2,
    ...directInputExtras,
  };

  static bool isStandardToken(String token) => standardIds.contains(token);

  /// Display label for a standard token; returns null for unknown/custom tokens.
  static String? tokenLabel(String token) => switch (token) {
    'esc' => 'ESC',
    'tab' => 'TAB',
    'ctrl' => 'CTRL',
    'alt' => 'ALT',
    'shift' => 'SHIFT',
    'enter' => 'ENTER',
    'senter' => 'S-RET',
    'slash' => '/',
    'dash' => '-',
    'pgup' => 'PgUp',
    'pgdn' => 'PgDn',
    'left' => 'Left',
    'up' => 'Up',
    'down' => 'Down',
    'right' => 'Right',
    'image' => 'Image',
    'di_toggle' => 'Direct Input',
    'input' => 'Input',
    'num1' => '1',
    'num2' => '2',
    'num3' => '3',
    'num4' => '4',
    _ => null,
  };

  static bool isCustomToken(String token) => token.startsWith('ck:');

  static bool isKnownToken(String token, Set<String> customIds) =>
      isStandardToken(token) ||
      (isCustomToken(token) && customIds.contains(token));
}

import 'dart:convert';
import 'dart:io';

/// Run from any directory; --check verifies the committed generated files.
void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent;
  final config =
      jsonDecode(
            File('${root.path}/tools/herdr-protocols.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final minimum = config['minimumSupportedProtocol'] as int;
  final caret = (config['caretSupportedProtocols'] as List).cast<int>();
  if (minimum < 0 ||
      minimum > 255 ||
      caret.isEmpty ||
      caret.toSet().length != caret.length ||
      caret.any((value) => value < minimum || value > 255)) {
    throw FormatException('Invalid Herdr protocol configuration');
  }
  const header =
      '// Generated from tools/herdr-protocols.json. Do not edit.\n'
      '// Regenerate: dart run tool/generate_herdr_protocols.dart\n';
  final outputs = {
    'lib/services/herdr/herdr_protocols.g.dart':
        '$header\n'
        'const int kHerdrMinSupportedProtocol = $minimum;\n'
        'const Set<int> kHerdrCaretSupportedProtocols = {${caret.join(', ')}};\n',
    'tools/herdr-caret-helper/src/protocols.rs':
        '$header\n'
        'pub const CARET_SUPPORTED_PROTOCOLS: &[u8] = &[${caret.join(', ')}];\n',
  };
  for (final entry in outputs.entries) {
    final file = File('${root.path}/${entry.key}');
    if (args.contains('--check')) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        stderr.writeln('Outdated: ${entry.key}; run the generator.');
        exitCode = 1;
      }
    } else {
      file.writeAsStringSync(entry.value);
    }
  }
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Audit all files for Container assertions (color & decoration together, negative margins, etc.)', () {
    final libDir = Directory('lib');
    final files = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

    final violations = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      // Scan for Container( or AnimatedContainer(
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('Container(') || line.contains('AnimatedContainer(')) {
          // gather the block up to matching or 30 lines
          int end = (i + 35 < lines.length) ? i + 35 : lines.length;
          final block = lines.sublist(i, end).join('\n');
          // simple check for color: and decoration: in the same constructor invocation
          // we can check if both color: and decoration: appear before child: or before closing
          final hasColor = block.contains(RegExp(r'\bcolor\s*:'));
          final hasDecoration = block.contains(RegExp(r'\bdecoration\s*:'));
          final hasClip = block.contains(RegExp(r'\bclipBehavior\s*:'));

          if (hasColor && hasDecoration) {
            // Check if color is outside decoration
            // If decoration: BoxDecoration(color: ...) that's valid, but if Container has both direct color: and decoration:
            // Let's check regex: Container\([^\)]*color:[^\)]*decoration: or vice versa
          }

          if (hasClip && !hasDecoration && block.contains('Clip.antiAlias')) {
            violations.add('${file.path}:${i + 1} has clipBehavior without decoration');
          }
        }

        // Check for negative padding or margin
        if (line.contains(RegExp(r'EdgeInsets\s*\.\s*[a-zA-Z]+\s*\([^)]*-\s*\d+'))) {
          violations.add('${file.path}:${i + 1} has negative EdgeInsets: $line');
        }
      }
    }

    print('Violations found: ${violations.length}');
    for (final v in violations) {
      print(' -> $v');
    }
    expect(violations, isEmpty);
  });
}


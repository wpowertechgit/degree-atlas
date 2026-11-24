import 'dart:io';

import 'package:degree_atlas/note_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('note_export_test');
    Directory('${dir.path}/figures').createSync();
    File('${dir.path}/figures/plot.svg').writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg"/>');
    File('${dir.parent.path}/secret.svg').writeAsStringSync('<svg/>');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    File('${dir.parent.path}/secret.svg').deleteSync();
  });

  const text = r'''# Limits (L1)

If $a<b$ then [1]:

$$\frac{1}{2}$$

![A plot](figures/plot.svg)

![x](../secret.svg)
''';
  final sources = [
    {'level': 'L1', 'title': 'Calculus notes', 'url': 'https://example.edu/calc'},
    {'level': 'L1', 'title': 'Course slides', 'file': 'materials/c/slides.pdf', 'pages': '3-5'},
  ];

  test('markdown appends numbered sources and points figures at the export folder', () {
    final out = noteMarkdown(text, sources, figureDir: 'limits-L1_figures');
    expect(out, contains('![A plot](limits-L1_figures/plot.svg)'));
    expect(out, contains('## Sources\n\n1. [Calculus notes](https://example.edu/calc)\n2. Course slides (materials/c/slides.pdf, 3-5)'));
  });

  test('html keeps formulas for KaTeX, embeds figures and never reads outside the subject', () {
    final html = noteHtml('Limits (L1)', text, sources, dir);
    expect(html, contains('<span class="math" data-display="text">a&lt;b</span>'));
    expect(html, contains('data-display="display">\\frac{1}{2}</span>'));
    expect(html, contains('src="data:image/svg+xml;base64,'));
    expect(html, contains('src="../secret.svg"'));
    expect(html, contains('<li>Calculus notes<br><a href="https://example.edu/calc">'));
  });

  test('inline math closes before any punctuation and leaves prices alone', () {
    String math(String s) => RegExp(r'<span class="math"[^>]*>([^<]*)</span>')
        .allMatches(noteHtml('t', s, const [], dir))
        .map((m) => m[1]!)
        .join(' | ');
    expect(math(r'its form is $I$; $A\mathbf{x}=0$ has'), r'I | A\mathbf{x}=0');
    expect(math(r"(see $x^2$) and $y$'s value"), r'x^2 | y');
    expect(math(r'costs $5 and $10 today'), '');
    expect(math(r'display $$\frac{a}{b}$$ inline'), r'\frac{a}{b}');
  });

  test('pdf prints through a headless browser', () async {
    final out = '${dir.path}/note.pdf';
    try {
      await printPdf(noteHtml('Limits (L1)', text, sources, dir), out);
    } on Exception catch (e) {
      if ('$e'.contains('needs Microsoft Edge')) return markTestSkipped('no browser');
      rethrow;
    }
    expect(File(out).readAsBytesSync().take(4), '%PDF'.codeUnits);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Exports one level of a subject (the note in the reading dialog) as Markdown, HTML or PDF.
///
/// Markdown keeps the text as written, appends the numbered sources and copies figures into a folder next to
/// the file. HTML is one self-contained file: figures are embedded and formulas are rendered by KaTeX (loaded
/// from a CDN when the file is opened). PDF prints that HTML with a headless Edge or Chrome, which ships with
/// Windows, so no PDF library is needed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'main.dart' show Subject;
import 'math_syntax.dart';
import 'profiles.dart' show messengerKey;

enum NoteFormat {
  markdown('md', 'Markdown (.md)'),
  html('html', 'Web page (.html)'),
  pdf('pdf', 'PDF (.pdf)');

  const NoteFormat(this.ext, this.label);
  final String ext, label;
}

final _figureLink = RegExp(r'!\[([^\]]*)\]\((figures/[^)\s]+)\)');

/// The note as Markdown with its sources appended; figure links point at [figureDir] when given.
String noteMarkdown(String text, List<Map<String, dynamic>> sources, {String? figureDir}) {
  final body = figureDir == null
      ? text
      : text.replaceAllMapped(_figureLink, (m) => '![${m[1]}]($figureDir/${p.posix.basename(m[2]!)})');
  if (sources.isEmpty) return body;
  final list = [
    for (final (i, s) in sources.indexed)
      '${i + 1}. ${s['url'] is String ? '[${s['title']}](${s['url']})' : s['title']}'
          '${s['file'] is String ? ' (${s['file']}${s['pages'] == null ? '' : ', ${s['pages']}'})' : ''}'
  ];
  return '${body.trimRight()}\n\n## Sources\n\n${list.join('\n')}\n';
}

/// The note as one self-contained HTML page. Figures under [dir] are embedded as data URIs.
String noteHtml(String title, String text, List<Map<String, dynamic>> sources, Directory dir) {
  const esc = HtmlEscape(HtmlEscapeMode.attribute); // escapes & < > " but keeps the slashes in URLs
  var body = md.markdownToHtml(text, extensionSet: mathExtensionSet);
  // The LaTeX syntaxes emit <latex MathStyle="text|display">raw TeX</latex>; KaTeX renders them in the page.
  body = body.replaceAllMapped(RegExp(r'<latex MathStyle="(\w+)">([\s\S]*?)</latex>'),
      (m) => '<span class="math" data-display="${m[1]}">${esc.convert(m[2]!)}</span>');
  body = body.replaceAllMapped(RegExp(r'<img src="([^"]+)"'), (m) {
    final file = File(p.normalize(p.join(dir.path, Uri.decodeFull(m[1]!))));
    if (!p.isWithin(dir.path, file.path) || !file.existsSync()) return m[0]!; // never read outside the subject
    final mime = switch (p.extension(file.path).toLowerCase()) {
      '.svg' => 'image/svg+xml',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      _ => null,
    };
    return mime == null ? m[0]! : '<img src="data:$mime;base64,${base64Encode(file.readAsBytesSync())}"';
  });
  final refs = sources.isEmpty
      ? ''
      : '<h2>Sources</h2><ol>${[
          for (final s in sources)
            '<li>${esc.convert('${s['title'] ?? 'Untitled source'}')}'
                '${s['url'] is String ? '<br><a href="${esc.convert(s['url'])}">${esc.convert(s['url'])}</a>' : ''}'
                '${s['file'] is String ? '<br>${esc.convert('${s['file']}${s['pages'] == null ? '' : ', ${s['pages']}'}')}' : ''}</li>'
        ].join()}</ol>';
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${esc.convert(title)}</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
<script>
document.addEventListener('DOMContentLoaded', () => {
  if (!window.katex) return; // offline: formulas stay readable as TeX
  for (const el of document.querySelectorAll('.math')) {
    katex.render(el.textContent, el, {displayMode: el.dataset.display === 'display', throwOnError: false});
  }
});
</script>
<style>
body { font: 16px/1.6 "Segoe UI", system-ui, sans-serif; color: #262321; max-width: 760px; margin: 40px auto; padding: 0 24px; }
h1, h2, h3 { line-height: 1.25; } h1 { font-size: 30px; } a { color: #2f5f8f; overflow-wrap: anywhere; }
img { max-width: 100%; } pre, code { background: #f4f1ea; border-radius: 4px; } pre { padding: 12px; overflow-x: auto; }
table { border-collapse: collapse; } td, th { border: 1px solid #ddd5c8; padding: 4px 8px; }
ol li { margin-bottom: 6px; } @media print { body { margin: 0 auto; } }
</style></head><body>
$body
$refs
</body></html>
''';
}

/// A Chromium-based browser that can print to PDF headlessly, or null.
String? _browser() {
  final candidates = Platform.isWindows
      ? [
          for (final env in ['ProgramFiles(x86)', 'ProgramFiles', 'LOCALAPPDATA'])
            if (Platform.environment[env] case final base?) ...[
              p.join(base, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
              p.join(base, 'Google', 'Chrome', 'Application', 'chrome.exe'),
            ]
        ]
      : Platform.isMacOS
          ? ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
             '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge']
          : ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/microsoft-edge'];
  return candidates.where((c) => File(c).existsSync()).firstOrNull;
}

/// Prints [html] to a PDF at [out] with a headless browser.
Future<void> printPdf(String html, String out) async {
  final browser = _browser();
  if (browser == null) throw Exception('PDF export needs Microsoft Edge or Google Chrome');
  final tmp = Directory.systemTemp.createTempSync('note_pdf');
  if (File(out).existsSync()) File(out).deleteSync(); // the wait below must not see an older file
  try {
    final page = File(p.join(tmp.path, 'note.html'))..writeAsStringSync(html);
    final r = await Process.run(browser, [
      '--headless',
      '--disable-gpu',
      '--user-data-dir=${p.join(tmp.path, 'profile')}', // separate instance, even when the browser is already open
      '--no-pdf-header-footer',
      '--virtual-time-budget=10000', // lets KaTeX finish before printing
      '--print-to-pdf=$out',
      page.uri.toString(),
    ]).timeout(const Duration(minutes: 1));
    // msedge.exe returns before its background process has written the file: wait until it exists and stops growing.
    final pdf = File(out);
    var last = -1;
    for (var i = 0; i < 120; i++) {
      final size = pdf.existsSync() ? pdf.lengthSync() : -1;
      if (size > 0 && size == last) return;
      last = size;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw Exception('the browser did not write the PDF (exit ${r.exitCode})');
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {} // the browser may still hold its profile folder for a moment
  }
}

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// Asks where to save and writes level [level] of [s] in [lang] as [format].
Future<void> exportNote(Subject s, int level, String lang, NoteFormat format) async {
  final text = s.levelText(level, lang: lang);
  if (text == null) return;
  final sources = s.levelSources(level);
  final base = '${_slug(s.title)}-L$level${lang == 'en' ? '' : '-$lang'}';
  final title = '${s.title} (L$level)';
  final figures = _figureLink.allMatches(text).map((m) => m[2]!).toSet();
  final folder = '${base}_figures'; // Markdown links point here, next to the saved file
  final messenger = messengerKey.currentState;
  try {
    // saveFile writes the bytes itself, so every format is built first.
    final Uint8List bytes;
    switch (format) {
      case NoteFormat.markdown:
        bytes = utf8.encode(noteMarkdown(text, sources, figureDir: figures.isEmpty ? null : folder));
      case NoteFormat.html:
        bytes = utf8.encode(noteHtml(title, text, sources, s.dir));
      case NoteFormat.pdf:
        messenger?.showSnackBar(const SnackBar(content: Text('Creating the PDF…')));
        final tmp = Directory.systemTemp.createTempSync('note_export');
        try {
          final out = p.join(tmp.path, '$base.pdf');
          await printPdf(noteHtml(title, text, sources, s.dir), out);
          bytes = File(out).readAsBytesSync();
        } finally {
          tmp.deleteSync(recursive: true);
        }
    }
    final saved = await FilePicker.saveFile(dialogTitle: 'Export note', fileName: '$base.${format.ext}', bytes: bytes);
    if (saved == null) {
      messenger?.hideCurrentSnackBar();
      return;
    }
    final path = saved.toFilePath();
    if (format == NoteFormat.markdown) {
      for (final f in figures) {
        final src = File(p.normalize(p.join(s.dir.path, f)));
        if (!p.isWithin(s.dir.path, src.path) || !src.existsSync()) continue; // never copy from outside the subject
        final dest = File(p.join(p.dirname(path), folder, p.basename(f)))..parent.createSync(recursive: true);
        src.copySync(dest.path);
      }
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Exported to $path')));
  } catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

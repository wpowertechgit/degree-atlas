import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent.dart' show agentOpenProvider, agentProvider;
import 'main.dart' show atlasProvider, dataDir;
import 'progress.dart';

/// Export format: a plain JSON file (one line)
///   {"format":"degree-atlas-export","version":1,"created":"...","fileCount":N,"compression":"lzw","encoding":"base64","payload":"..."}
/// where payload is base64 of the LZW-compressed UTF-8 JSON bundle {"files":{"data/...":"text","progress.json":"text"}}.
const _format = 'degree-atlas-export';
const _maxCodes = 1 << 20; // dictionary stops growing here
const _textExt = {'.json', '.md', '.svg', '.txt'};

/// Code width depends only on how many codes were already written (k), so the decoder needs no extra state.
int _width(int k) => (256 + k < _maxCodes ? 256 + k : _maxCodes).bitLength;

/// Variable-width LZW over bytes: codes 0-255 are literals, new entries start at 256, LSB-first bit packing.
Uint8List lzwEncode(List<int> data) {
  final dict = <int, int>{}; // (prefix code << 8 | byte) -> code
  final out = BytesBuilder(copy: false);
  var next = 256, k = 0, acc = 0, nb = 0;
  void emit(int code) {
    final w = _width(k++);
    acc |= code << nb;
    nb += w;
    while (nb >= 8) {
      out.addByte(acc & 255);
      acc >>= 8;
      nb -= 8;
    }
  }

  var w = -1;
  for (final b in data) {
    if (w < 0) {
      w = b;
      continue;
    }
    final key = (w << 8) | b;
    final c = dict[key];
    if (c != null) {
      w = c;
      continue;
    }
    emit(w);
    if (next < _maxCodes) dict[key] = next++;
    w = b;
  }
  if (w >= 0) emit(w);
  if (nb > 0) out.addByte(acc & 255);
  return out.takeBytes();
}

Uint8List lzwDecode(Uint8List bytes) {
  final prefix = Int32List(_maxCodes), len = Int32List(_maxCodes);
  final last = Uint8List(_maxCodes);
  for (var i = 0; i < 256; i++) {
    prefix[i] = -1;
    last[i] = i;
    len[i] = 1;
  }
  var buf = Uint8List(1 << 20), olen = 0;
  void reserve(int n) {
    if (olen + n <= buf.length) return;
    var cap = buf.length * 2;
    while (cap < olen + n) {
      cap *= 2;
    }
    buf = Uint8List(cap)..setRange(0, olen, buf);
  }

  // writes the string of `code` at olen and returns its length
  int expand(int code) {
    final n = len[code];
    reserve(n + 1);
    var i = olen + n - 1;
    for (var c = code; c >= 0; c = prefix[c]) {
      buf[i--] = last[c];
    }
    return n;
  }

  var size = 256, k = 0, acc = 0, nb = 0, pos = 0, prev = -1;
  while (true) {
    final w = _width(k);
    while (nb < w && pos < bytes.length) {
      acc |= bytes[pos++] << nb;
      nb += 8;
    }
    if (nb < w) break; // only padding bits left
    final code = acc & ((1 << w) - 1);
    acc >>= w;
    nb -= w;
    k++;
    if (prev < 0) {
      if (code > 255) throw const FormatException('corrupt LZW stream');
      reserve(1);
      buf[olen++] = code;
      prev = code;
      continue;
    }
    final start = olen;
    int n;
    if (code < size) {
      n = expand(code);
    } else if (code == size) {
      n = expand(prev);
      buf[olen + n] = buf[olen]; // previous string plus its own first byte
      n++;
    } else {
      throw const FormatException('corrupt LZW stream');
    }
    olen = start + n;
    if (size < _maxCodes) {
      prefix[size] = prev;
      last[size] = buf[start];
      len[size] = len[prev] + 1;
      size++;
    }
    prev = code;
  }
  return Uint8List.sublistView(buf, 0, olen);
}

/// Builds the one-line export text for everything under data/ plus progress.json.
String buildExport(String dataPath) {
  final root = p.dirname(dataPath);
  final files = <String, String>{};
  void add(File f) {
    if (!_textExt.contains(p.extension(f.path).toLowerCase())) return;
    files[p.relative(f.path, from: root).replaceAll(r'\', '/')] = f.readAsStringSync();
  }

  for (final e in Directory(dataPath).listSync(recursive: true, followLinks: false)) {
    if (e is File) add(e);
  }
  final prog = File(p.join(root, 'progress.json'));
  if (prog.existsSync()) add(prog);
  final bundle = jsonEncode({'files': files});
  return jsonEncode({
    'format': _format,
    'version': 1,
    'created': DateTime.now().toUtc().toIso8601String(),
    'fileCount': files.length,
    'compression': 'lzw',
    'encoding': 'base64',
    'payload': base64Encode(lzwEncode(utf8.encode(bundle))),
  });
}

/// Union of read keys; per exercise the record with more attempts wins.
Map<String, dynamic> mergeProgress(Map mine, Map theirs) {
  final read = Set<String>.from(mine['read'] ?? [])..addAll(Set<String>.from(theirs['read'] ?? []));
  final practice = <String, dynamic>{...?(mine['practice'] as Map?)?.cast<String, dynamic>()};
  for (final e in ((theirs['practice'] as Map?) ?? const {}).entries) {
    final have = practice[e.key];
    if (have == null || ((e.value['n'] ?? 0) as num) > ((have['n'] ?? 0) as num)) practice[e.key as String] = e.value;
  }
  return {'read': read.toList()..sort(), if (practice.isNotEmpty) 'practice': practice};
}

/// Writes an export into [dataPath]'s parent. Existing files with the same path are overwritten, nothing is
/// deleted, progress.json is merged (union of read keys). Returns the number of files written.
int applyImport(String dataPath, String text) {
  final env = jsonDecode(text);
  if (env is! Map || env['format'] != _format) throw const FormatException('Not a Degree Atlas export');
  if (env['version'] != 1 || env['compression'] != 'lzw' || env['encoding'] != 'base64') {
    throw const FormatException('Unsupported export version');
  }
  final bundle = jsonDecode(utf8.decode(lzwDecode(base64Decode(env['payload'] as String))));
  final root = p.dirname(dataPath);
  final files = Map<String, dynamic>.from(bundle['files']);
  var n = 0;
  for (final e in files.entries) {
    final rel = p.posix.normalize(e.key);
    final ok = rel == 'progress.json' || (rel.startsWith('data/') && !rel.contains('..') && !p.isAbsolute(rel));
    if (!ok) continue; // never write outside data/
    final f = File(p.join(root, rel));
    var content = e.value as String;
    if (rel == 'progress.json' && f.existsSync()) {
content = jsonEncode(mergeProgress(jsonDecode(f.readAsStringSync()), jsonDecode(content)));
    }
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    n++;
  }
  return n;
}

Future<void> exportData(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  final path = dataDir().absolute.path;
  msg.showSnackBar(const SnackBar(content: Text('Building export…')));
  try {
    final text = await Isolate.run(() => buildExport(path));
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await FilePicker.saveFile(
        dialogTitle: 'Export Degree Atlas data',
        fileName: 'degree-atlas-$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(text)));
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(saved == null ? 'Export cancelled' : 'Exported ${(text.length / 1048576).toStringAsFixed(1)} MB')));
  } catch (e) {
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

Future<void> importData(BuildContext context, WidgetRef ref) async {
  final msg = ScaffoldMessenger.of(context);
  final picked = await FilePicker.pickFiles(
      dialogTitle: 'Import Degree Atlas data', type: FileType.custom, allowedExtensions: ['json']);
  final file = picked.isEmpty ? null : picked.first.path;
  if (file == null || !context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Import data?'),
      content: const Text(
          'Files with the same path will be overwritten. Nothing is deleted, and reading progress is merged with yours.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
      ],
    ),
  );
  if (go != true) return;
  final path = dataDir().absolute.path;
  msg.showSnackBar(const SnackBar(content: Text('Importing…')));
  try {
    final n = await Isolate.run(() => applyImport(path, File(file).readAsStringSync()));
    ref.invalidate(progressProvider);
    ref.invalidate(atlasProvider);
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Imported $n files')));
  } catch (e) {
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

String _slug(String s) {
  final v = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return v.isEmpty ? 'course' : v;
}

/// Copies [from] into [to] (files only, no symlinks, no hidden entries). Returns the number of files.
int _copyTree(String from, String to) {
  var n = 0;
  for (final e in Directory(from).listSync(recursive: true, followLinks: false)) {
    final rel = p.relative(e.path, from: from);
    if (e is! File || p.split(rel).any((part) => part.startsWith('.'))) continue;
    final dest = File(p.join(to, rel))..parent.createSync(recursive: true);
    e.copySync(dest.path);
    n++;
  }
  return n;
}

/// Copies a folder of the user's own course files into the profile and asks the agent to ingest it.
Future<void> importMaterials(BuildContext context, WidgetRef ref) async {
  final msg = ScaffoldMessenger.of(context);
  final src = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder with your course materials');
  if (src == null || !context.mounted) return;
  final root = dataDir().absolute.parent.path;
  var name = _slug(p.basename(src));
  for (var i = 2; Directory(p.join(root, 'materials', name)).existsSync(); i++) {
    name = '${_slug(p.basename(src))}-$i';
  }
  final dest = p.join(root, 'materials', name);
  msg.showSnackBar(const SnackBar(content: Text('Copying materials…')));
  try {
    final n = await Isolate.run(() => _copyTree(src, dest));
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $n files to materials/$name')));
    if (n == 0) return;
    ref.read(agentProvider.notifier).send(
        'The user imported their own course materials into materials/$name. Follow AGENTS.md (Own course materials): read everything, '
        'write index.json, create the subject, degree and domain entry, then write an elementary L0 and L1, an L2 that follows the '
        'materials, and exercises from the problem sets and exams. Validate when done.');
    ref.read(agentOpenProvider.notifier).set(true);
  } catch (e) {
    msg
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

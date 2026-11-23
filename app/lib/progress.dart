import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'main.dart' show dataDir;

/// Personal reading progress, kept next to data/ (not inside it): keys look like "linear-algebra:L0".
File _file() => File(p.join(dataDir().absolute.parent.path, 'progress.json'));

class ProgressNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final f = _file();
    if (!f.existsSync()) return {};
    try {
      return Set<String>.from(jsonDecode(f.readAsStringSync())['read']);
    } catch (_) {
      return {};
    }
  }

  void toggle(String key) {
    final s = {...state};
    if (!s.remove(key)) s.add(key);
    state = s;
    _file().writeAsStringSync(jsonEncode({'read': s.toList()..sort()}));
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, Set<String>>(ProgressNotifier.new);

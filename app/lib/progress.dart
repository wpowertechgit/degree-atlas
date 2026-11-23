import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'main.dart' show dataDir;

/// Personal progress, kept next to data/ (not inside it) in progress.json:
/// {"read": ["linear-algebra:L0", ...], "practice": {"linear-algebra:ex-id": {"n": attempts, "ok": lastCorrect}}}
File _file() => File(p.join(dataDir().absolute.parent.path, 'progress.json'));

Map<String, dynamic> _load() {
  final f = _file();
  if (!f.existsSync()) return {};
  try {
    final j = jsonDecode(f.readAsStringSync());
    return j is Map<String, dynamic> ? j : {};
  } catch (_) {
    return {};
  }
}

/// Replaces one key and keeps the rest of the file (each notifier owns its own key).
void _save(String key, Object value) {
  final j = _load()..[key] = value;
  _file().writeAsStringSync(jsonEncode(j));
}

class ProgressNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    try {
      return Set<String>.from(_load()['read'] ?? const []);
    } catch (_) {
      return {};
    }
  }

  void toggle(String key) {
    final s = {...state};
    if (!s.remove(key)) s.add(key);
    state = s;
    _save('read', s.toList()..sort());
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, Set<String>>(ProgressNotifier.new);

/// Latest result per exercise ("subject:exercise-id") and the number of attempts.
typedef Attempt = ({int n, bool ok});

class PracticeNotifier extends Notifier<Map<String, Attempt>> {
  @override
  Map<String, Attempt> build() {
    final raw = _load()['practice'];
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.value is Map) e.key as String: (n: (e.value['n'] as num?)?.toInt() ?? 0, ok: e.value['ok'] == true),
    };
  }

  void record(String key, bool ok) {
    final prev = state[key];
    state = {...state, key: (n: (prev?.n ?? 0) + 1, ok: ok)};
    _save('practice', {for (final e in state.entries) e.key: {'n': e.value.n, 'ok': e.value.ok}});
  }
}

final practiceProvider = NotifierProvider<PracticeNotifier, Map<String, Attempt>>(PracticeNotifier.new);

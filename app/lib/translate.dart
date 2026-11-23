import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent.dart';
import 'exercises.dart' show hasExerciseTranslation;
import 'main.dart';

/// Tree picker (domain > degree > subject) for translating existing material into [lang] with the agent.
Future<void> showTranslateDialog(BuildContext context, WidgetRef ref, Atlas atlas, String lang) =>
    showDialog(context: context, builder: (_) => _TranslateDialog(ref: ref, atlas: atlas, lang: lang));

class _TranslateDialog extends StatefulWidget {
  const _TranslateDialog({required this.ref, required this.atlas, required this.lang});
  final WidgetRef ref;
  final Atlas atlas;
  final String lang;
  @override
  State<_TranslateDialog> createState() => _TranslateDialogState();
}

typedef _Row = (String kind, String id, int depth);

class _TranslateDialogState extends State<_TranslateDialog> {
  final selected = <String>{}; // subject ids
  final levels = <int>{0, 1, 2, 3, 4}; // 4 stands for the exercises file
  final open = <String>{};

  late final Map<String, Degree> degrees = {for (final d in widget.atlas.degrees) d.id: d};

  /// Subjects of a degree that have at least one written level.
  List<String> _subjects(String degreeId) => [
        for (final e in degrees[degreeId]?.subjects ?? const <Map<String, dynamic>>[])
          if (widget.atlas.subjects[e['subject']] case final s? when [0, 1, 2, 3].any((n) => s.levelState(n) != 'none')) s.id,
      ];

  List<String> _domainSubjects(String domain) =>
      {for (final d in widget.atlas.domains[domain] ?? const <String>[]) ..._subjects(d)}.toList();

  bool? _state(Iterable<String> ids) {
    var any = false, all = true;
    for (final id in ids) {
      if (selected.contains(id)) {
        any = true;
      } else {
        all = false;
      }
    }
    return !any ? false : (all ? true : null);
  }

  void _toggle(Iterable<String> ids) => setState(() {
        if (_state(ids) == true) {
          selected.removeAll(ids);
        } else {
          selected.addAll(ids);
        }
      });

  /// Level 4 is the exercises file.
  bool _needs(String id, int n) {
    final s = widget.atlas.subjects[id]!;
    if (n == 4) return File(p.join(s.dir.path, 'exercises.json')).existsSync() && !hasExerciseTranslation(s, widget.lang);
    return s.levelState(n) != 'none' && !s.hasTranslation(n, widget.lang);
  }

  /// (subject, level) pairs that exist in English but not yet in the target language.
  List<(String, int)> get _pending => [
        for (final id in selected)
          for (final n in levels.toList()..sort())
            if (_needs(id, n)) (id, n),
      ];

  List<_Row> get _rows {
    final out = <_Row>[];
    for (final dom in widget.atlas.domains.keys) {
      out.add(('domain', dom, 0));
      if (!open.contains('d:$dom')) continue;
      for (final deg in widget.atlas.domains[dom]!) {
        if (!degrees.containsKey(deg) || _subjects(deg).isEmpty) continue;
        out.add(('degree', deg, 1));
        if (!open.contains('g:$deg')) continue;
        for (final s in _subjects(deg)) {
          out.add(('subject', s, 2));
        }
      }
    }
    return out;
  }

  Widget _row(_Row r) {
    final (kind, id, depth) = r;
    final ids = switch (kind) {
      'domain' => _domainSubjects(id),
      'degree' => _subjects(id),
      _ => [id],
    };
    final key = kind == 'domain' ? 'd:$id' : 'g:$id';
    final title = switch (kind) {
      'domain' => id,
      'degree' => degrees[id]!.title,
      _ => widget.atlas.subjects[id]!.title,
    };
    return InkWell(
      onTap: kind == 'subject' ? () => _toggle(ids) : () => setState(() => open.contains(key) ? open.remove(key) : open.add(key)),
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 22, right: 8),
        child: Row(children: [
          SizedBox(
              width: 24,
              child: kind == 'subject'
                  ? null
                  : Icon(open.contains(key) ? Icons.expand_more : Icons.chevron_right, size: 20, color: Colors.black54)),
          Checkbox(tristate: true, value: _state(ids), onChanged: (_) => _toggle(ids), visualDensity: VisualDensity.compact),
          Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: kind == 'subject' ? FontWeight.w400 : FontWeight.w600))),
          if (kind != 'subject') Text('${ids.length}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
        ]),
      ),
    );
  }

  void _start() {
    final pending = _pending;
    final byId = <String, List<int>>{};
    for (final (id, n) in pending) {
      byId.putIfAbsent(id, () => []).add(n);
    }
    final root = dataDir().absolute.parent.path;
    final job = File(p.join(root, 'work', 'translate_job.json'))..parent.createSync(recursive: true);
    job.writeAsStringSync(jsonEncode({
      'language': widget.lang,
      'name': languages[widget.lang],
      'items': [
        for (final e in byId.entries)
          {'subject': e.key, 'levels': e.value.where((n) => n < 4).toList(), 'exercises': e.value.contains(4)}
      ],
    }));
    widget.ref.read(agentProvider.notifier).send(
        'Translate the study material listed in work/translate_job.json into ${languages[widget.lang]}. For every item and level '
        'write data/subjects/<subject>/L<n>.${widget.lang}.md from L<n>.md following AGENTS.md (Languages); where '
        '"exercises" is true also write exercises.${widget.lang}.json from exercises.json (AGENTS.md, Exercises). Skip files that '
        'already exist. ${pending.length} files in ${byId.length} subjects. Work in batches (parallel subagents are fine), '
        'run validate.py at the end. Do not report progress.');
    widget.ref.read(agentOpenProvider.notifier).set(true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final n = _pending.length;
    return Dialog(
      backgroundColor: paper,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Translate to ${languages[widget.lang]}', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            const Text('Pick domains, degrees or single subjects. English is the source text.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (var l = 0; l < 5; l++)
                FilterChip(
                  selected: levels.contains(l),
                  label: Text(l == 4 ? 'Exercises' : 'L$l', style: const TextStyle(color: Colors.black87)),
                  onSelected: (v) => setState(() => v ? levels.add(l) : levels.remove(l)),
                ),
            ]),
            const Divider(),
            Flexible(
              child: SizedBox(
                height: 420,
                child: ListView.builder(itemCount: rows.length, itemExtent: 36, itemBuilder: (_, i) => _row(rows[i])),
              ),
            ),
            const Divider(),
            Row(children: [
              Text('$n file${n == 1 ? '' : 's'} to translate', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              const Spacer(),
              TextButton(onPressed: selected.isEmpty ? null : () => setState(selected.clear), child: const Text('Clear')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: n == 0 ? null : _start,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Translate with agent'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

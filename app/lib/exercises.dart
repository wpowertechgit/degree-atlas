import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent.dart';
import 'house_style.dart';
import 'main.dart' show Md, Subject;
import 'progress.dart';

enum ExType { mcq, numeric, short, open }

class Exercise {
  Exercise({
    required this.id,
    required this.level,
    required this.type,
    required this.prompt,
    required this.solution,
    this.choices = const [],
    this.answer,
    this.tolerance = 0.01,
    this.unit,
    this.hints = const [],
    this.difficulty,
  });

  final String id, prompt, solution;
  final int level;
  final ExType type;
  final List<String> choices, hints;
  final dynamic answer; // mcq: List<int>, numeric: num, short: List<String>
  final double tolerance; // relative; absolute when the answer is 0
  final String? unit;
  final int? difficulty;

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'],
        level: j['level'],
        type: ExType.values.byName(j['type']),
        prompt: j['prompt'],
        solution: j['solution'],
        choices: List<String>.from(j['choices'] ?? const []),
        answer: j['answer'],
        tolerance: (j['tolerance'] as num?)?.toDouble() ?? 0.01,
        unit: j['unit'],
        hints: List<String>.from(j['hints'] ?? const []),
        difficulty: j['difficulty'],
      );

  /// [given] is a Set<int> for mcq and a String otherwise. Returns null when the type has no automatic grading.
  bool? grade(Object given) {
    switch (type) {
      case ExType.mcq:
        final want = Set<int>.from(answer as List);
        return given is Set<int> && given.length == want.length && given.containsAll(want);
      case ExType.numeric:
        final x = parseNumber(given as String, unit);
        if (x == null) return false;
        final a = (answer as num).toDouble();
        return (x - a).abs() <= (a == 0 ? tolerance : tolerance * a.abs());
      case ExType.short:
        final text = given as String;
        final g = _norm(text);
        return List<String>.from(answer as List)
            .any((a) => a.startsWith('re:') ? RegExp(a.substring(3), caseSensitive: false).hasMatch(text.trim()) : _norm(a) == g);
      case ExType.open:
        return null;
    }
  }
}

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[.!]+$'), '');

/// Parses "1.5", "1,5", "-2e-3", "3 m/s" (a trailing [unit] is ignored) and "1.2x10^3" / "1.2*10^3".
double? parseNumber(String input, [String? unit]) {
  var s = input.trim().replaceAll('−', '-').replaceAll(',', '.');
  if (unit != null && unit.isNotEmpty && s.toLowerCase().endsWith(unit.toLowerCase())) {
    s = s.substring(0, s.length - unit.length).trim();
  }
  final sci = RegExp(r'^([-+]?\d*\.?\d+)\s*[x*×]\s*10\^?\s*([-+]?\d+)$').firstMatch(s);
  if (sci != null) return double.parse(sci.group(1)!) * double.parse('1e${sci.group(2)}');
  return double.tryParse(s.replaceAll(RegExp(r'\s'), ''));
}

/// Exercises of [s] in [lang], or the English file when there is no translation. Empty when there is none.
List<Exercise> loadExercises(Subject s, String lang) {
  for (final name in [if (lang != 'en') 'exercises.$lang.json', 'exercises.json']) {
    final f = File(p.join(s.dir.path, name));
    if (!f.existsSync()) continue;
    try {
      return [for (final j in jsonDecode(f.readAsStringSync())) Exercise.fromJson(Map<String, dynamic>.from(j))];
    } catch (_) {
      return const []; // caught mid-write or malformed; validate.py reports it
    }
  }
  return const [];
}

bool hasExerciseTranslation(Subject s, String lang) =>
    lang == 'en' || File(p.join(s.dir.path, 'exercises.$lang.json')).existsSync();

/// Practice tab of the reading overlay. [close] dismisses the overlay before the agent is asked for something.
class PracticeView extends ConsumerStatefulWidget {
  const PracticeView({super.key, required this.subject, required this.lang, required this.close});
  final Subject subject;
  final String lang;
  final VoidCallback close;
  @override
  ConsumerState<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends ConsumerState<PracticeView> {
  late List<Exercise> all = loadExercises(widget.subject, widget.lang);
  int? levelFilter;
  int index = 0;
  Set<int> picked = {};
  final text = TextEditingController();
  int hintsShown = 0;
  bool? verdict; // set once the attempt is recorded
  bool revealed = false;

  Subject get s => widget.subject;
  List<Exercise> get items => levelFilter == null ? all : all.where((e) => e.level == levelFilter).toList();
  String key(Exercise e) => '${s.id}:${e.id}';

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void _go(int i, int count) => setState(() {
        index = count == 0 ? 0 : i.clamp(0, count - 1);
        picked = {};
        text.clear();
        hintsShown = 0;
        verdict = null;
        revealed = false;
      });

  void _check(Exercise e) {
    final ok = e.grade(e.type == ExType.mcq ? picked : text.text)!;
    ref.read(practiceProvider.notifier).record(key(e), ok);
    setState(() {
      verdict = ok;
      revealed = true;
    });
  }

  void _selfRate(Exercise e, bool ok) {
    ref.read(practiceProvider.notifier).record(key(e), ok);
    setState(() => verdict = ok);
  }

  void _toggleChoice(int i, bool multi) => setState(() {
        if (!multi) {
          picked = {i};
        } else {
          picked = picked.contains(i) ? ({...picked}..remove(i)) : {...picked, i};
        }
      });

  void _ask(String message) {
    ref.read(agentProvider.notifier).send(message);
    ref.read(agentOpenProvider.notifier).set(true);
    widget.close();
  }

  Widget _agentButton(String label, String message) =>
      TextButton.icon(onPressed: () => _ask(message), icon: const Icon(Icons.auto_awesome, size: 16), label: Text(label));

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(practiceProvider);
    final agent = ref.read(agentProvider.notifier);
    final lang = widget.lang;
    if (all.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('No exercises for this subject yet.'),
        const SizedBox(height: HouseStyle.spacing),
        if (s.levelState(1) == 'none')
          const Text('Write L1 first.')
        else
          _agentButton('Generate exercises with agent', agent.exercisesRequest(s, lang)),
        TextButton(onPressed: () => setState(() => all = loadExercises(s, lang)), child: const Text('Reload')),
      ]);
    }
    final list = items;
    final solved = all.where((e) => progress[key(e)]?.ok == true).length;
    final at = index.clamp(0, list.length - 1);
    final e = list[at];
    final past = progress[key(e)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: HouseStyle.spacing, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Solved $solved of ${all.length}', style: HouseStyle.label),
        for (final l in [null, 1, 2, 3])
          if (l == null || all.any((x) => x.level == l))
            ChoiceChip(
              selected: levelFilter == l,
              selectedColor: HouseStyle.margin,
              label: Text(l == null ? 'All' : 'L$l', style: HouseStyle.label.copyWith(color: HouseStyle.ink)),
              onSelected: (_) {
                levelFilter = l;
                _go(0, items.length);
              },
            ),
        IconButton(
            tooltip: 'Reload exercises',
            iconSize: 18,
            onPressed: () => setState(() => all = loadExercises(s, lang)),
            icon: const Icon(Icons.sync)),
      ]),
      if (lang != 'en' && !hasExerciseTranslation(s, lang))
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Shown in English; no ${languages[lang]} version yet.', style: const TextStyle(color: HouseStyle.graphite)),
          _agentButton('Translate with agent', agent.exercisesTranslationRequest(s, lang)),
        ]),
      const Divider(color: HouseStyle.margin),
      Text(
          'Question ${at + 1} of ${list.length} · L${e.level}'
          '${e.difficulty == null ? '' : ' · ${['easy', 'medium', 'hard'][e.difficulty! - 1]}'}'
          '${past == null ? '' : past.ok ? ' · solved before' : ' · missed last time'}',
          style: HouseStyle.label),
      const SizedBox(height: HouseStyle.spacing),
      Md(e.prompt, s.dir, key: ValueKey('p${e.id}$lang')),
      const SizedBox(height: HouseStyle.spacing),
      _answerInput(e),
      for (var i = 0; i < hintsShown && i < e.hints.length; i++)
        Padding(padding: const EdgeInsets.only(top: 6), child: Md('Hint ${i + 1}: ${e.hints[i]}', s.dir)),
      const SizedBox(height: HouseStyle.spacing),
      Wrap(spacing: HouseStyle.spacing, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!revealed && e.type != ExType.open)
          FilledButton(
              onPressed: (e.type == ExType.mcq ? picked.isEmpty : text.text.trim().isEmpty) ? null : () => _check(e),
              child: const Text('Check')),
        if (!revealed && e.type == ExType.open)
          FilledButton(onPressed: () => setState(() => revealed = true), child: const Text('Show solution')),
        if (!revealed && hintsShown < e.hints.length)
          OutlinedButton(onPressed: () => setState(() => hintsShown++), child: const Text('Hint')),
        if (!revealed && e.type != ExType.open)
          TextButton(onPressed: () => setState(() => revealed = true), child: const Text('Show answer')),
      ]),
      if (revealed) ...[
        const SizedBox(height: HouseStyle.spacing),
        if (e.type == ExType.open && verdict == null)
          Wrap(spacing: HouseStyle.spacing, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Did you get it?'),
            FilledButton(onPressed: () => _selfRate(e, true), child: const Text('Got it')),
            OutlinedButton(onPressed: () => _selfRate(e, false), child: const Text('Missed it')),
          ])
        else if (verdict != null)
          Text(verdict! ? 'Correct' : 'Not quite',
              style: TextStyle(fontWeight: FontWeight.w600, color: verdict! ? const Color(0xFF2E7D32) : const Color(0xFFB3261E))),
        if (e.type != ExType.open && verdict != true)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Answer: ${_answerText(e)}', style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 6),
        Md(e.solution, s.dir, key: ValueKey('s${e.id}$lang')),
        Wrap(spacing: HouseStyle.spacing, children: [
          if (e.type == ExType.open || (e.type == ExType.short && verdict != true))
            _agentButton(
                'Ask the agent to check my answer',
                'Practice exercise in `${s.id}` (L${e.level}):\n\n${e.prompt}\n\n'
                    'My answer: ${text.text.trim().isEmpty ? '(not written)' : text.text.trim()}\n\n'
                    'Reference solution:\n${e.solution}\n\nCheck my answer against the reference and tell me what is wrong or missing.'),
          _agentButton(
              'Report a problem with this exercise',
              'Exercise `${e.id}` in data/subjects/${s.id}/exercises${lang == 'en' ? '' : '.$lang'}.json looks wrong or unclear. '
                  'Re-derive it, fix prompt, answer and solution (and the files of the other languages with the same id), then run validate.py.'),
        ]),
      ],
      const Divider(color: HouseStyle.margin),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(onPressed: at > 0 ? () => _go(at - 1, list.length) : null, child: const Text('Previous')),
        TextButton(onPressed: at < list.length - 1 ? () => _go(at + 1, list.length) : null, child: const Text('Next')),
        TextButton(
            onPressed: () {
              final from = [...list.sublist(at + 1), ...list.sublist(0, at)];
              final next = from.where((x) => progress[key(x)]?.ok != true).firstOrNull;
              if (next != null) _go(list.indexOf(next), list.length);
            },
            child: const Text('Next unsolved')),
        _agentButton('More exercises', agent.exercisesRequest(s, lang, more: true)),
      ]),
    ]);
  }

  String _answerText(Exercise e) => switch (e.type) {
        ExType.mcq => [for (final i in List<int>.from(e.answer)) e.choices[i]].join('; '),
        ExType.numeric => '${e.answer}${e.unit == null ? '' : ' ${e.unit}'}',
        ExType.short => List<String>.from(e.answer).where((a) => !a.startsWith('re:')).join(' / '),
        ExType.open => '',
      };

  Widget _answerInput(Exercise e) {
    if (e.type == ExType.open) {
      return revealed
          ? const SizedBox.shrink()
          : TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Work it out here (optional)', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}));
    }
    if (e.type == ExType.mcq) {
      final multi = List<int>.from(e.answer).length > 1;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < e.choices.length; i++)
          InkWell(
            onTap: revealed ? null : () => _toggleChoice(i, multi),
            child: Row(children: [
              Icon(
                  multi
                      ? (picked.contains(i) ? Icons.check_box : Icons.check_box_outline_blank)
                      : (picked.contains(i) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  size: 20,
                  color: HouseStyle.ink),
              const SizedBox(width: 8),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: IgnorePointer(child: Md(e.choices[i], s.dir, key: ValueKey('c${e.id}$i${widget.lang}'))))),
            ]),
          ),
        if (multi) const Text('Select all that apply.', style: TextStyle(fontSize: 12)),
      ]);
    }
    return TextField(
      controller: text,
      enabled: !revealed,
      decoration: InputDecoration(
          hintText: e.type == ExType.numeric ? 'Number${e.unit == null ? '' : ' (${e.unit})'}' : 'Your answer',
          border: const OutlineInputBorder()),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => text.text.trim().isEmpty || revealed ? null : _check(e),
    );
  }
}

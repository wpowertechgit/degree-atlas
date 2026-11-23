import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'agent.dart';
import 'atlas_campus.dart';
import 'atlas_emblems.dart';
import 'atlas_paper.dart';
import 'course_notebook.dart';
import 'house_style.dart';
import 'exercises.dart';
import 'main.dart';
import 'profiles.dart';
import 'progress.dart';
import 'transfer.dart';
import 'translate.dart';

const _radius = [0.0, 150.0, 330.0, 560.0]; // ring radius per level: you, domain, degree, subject
const _canvas = 1600.0;
const _centre = Offset(_canvas / 2, _canvas / 2);
const _levels = ['BSc', 'MSc'];

/// One colour per domain; degrees and subjects inherit it so you always know where you are.
const _domainColors = {
  'Computing': Color(0xFF3B6EA5),
  'Engineering': Color(0xFFD9822B),
  'Humanities': Color(0xFF8E5BA6),
  'Mathematics': Color(0xFF2A9D8F),
  'Natural Science': Color(0xFF5B9A3C),
  'Social Science': Color(0xFFC2547A),
};
const _fallbackColors = [Color(0xFF6B7280), Color(0xFF9A6B3B), Color(0xFF3B9AA5)];

class _N {
  _N(this.key, this.label, this.level, {this.parent, this.sid, this.semester, this.color = accent});
  final String key, label;
  final int level; // 0 you, 1 domain, 2 degree, 3 subject
  final _N? parent;
  final String? sid;
  final int? semester;
  final Color color;
  final List<_N> kids = [];
  final Set<String> subjects = {};
}

class _P {
  const _P(this.a, this.r);
  final double a, r; // angle, radius
  Offset get xy => _centre + Offset(math.cos(a), math.sin(a)) * r;
}

class ReadToggle extends ConsumerWidget {
  const ReadToggle(this.sid, {super.key, this.level = 0});
  final String sid;
  final int level;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$sid:L$level';
    final read = ref.watch(progressProvider).contains(key);
    return TextButton.icon(
      onPressed: () => ref.read(progressProvider.notifier).toggle(key),
      icon: Icon(read ? Icons.check_circle : Icons.radio_button_unchecked, color: read ? Colors.green : accent),
      label: Text(read ? 'Read (tap to undo)' : 'Mark L$level as read', style: const TextStyle(color: accent)),
    );
  }
}

class RadialPage extends ConsumerWidget {
  const RadialPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(agentOpenProvider);
    return Scaffold(
      appBar: dragBar(context, 'Degree Atlas', actions: [
        const ProfileMenu(),
        SizedBox(
          width: 120,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              alignment: Alignment.center,
              value: ref.watch(langProvider),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              items: [
                for (final e in languages.entries)
                  DropdownMenuItem(value: e.key, alignment: Alignment.center, child: Text(e.value, textAlign: TextAlign.center)),
              ],
              onChanged: (v) => ref.read(langProvider.notifier).set(v!),
            ),
          ),
        ),
        if (ref.watch(langProvider) != 'en')
          IconButton(
            tooltip: 'Translate material to ${languages[ref.watch(langProvider)]} with the agent',
            icon: const Icon(Icons.translate, size: 20),
            onPressed: () {
              final a = ref.read(atlasProvider).value;
              if (a != null) showTranslateDialog(context, ref, a, ref.read(langProvider));
            },
          ),
        PopupMenuButton<String>(
          tooltip: 'Data',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => switch (v) {
            'export' => exportData(context),
            'materials' => importMaterials(context, ref),
            _ => importData(context, ref),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('Export data…')),
            PopupMenuItem(value: 'import', child: Text('Import data…')),
            PopupMenuItem(value: 'materials', child: Text('Import course materials…')),
          ],
        ),
        TextButton(
            onPressed: () => ref.read(agentOpenProvider.notifier).set(!open),
            child: Text(open ? 'Hide agent' : 'Agent')),
        TextButton(onPressed: () => context.push('/list'), child: const Text('List view')),
      ]),
      body: Row(children: [
        Expanded(child: AtlasBody((a) => _hasContent(a) ? _RadialView(atlas: a) : const EmptyProfileHint())),
        if (open) const AgentPanel(),
      ]),
    );
  }
}

/// True once some degree has at least one named subject; an empty profile shows no graph at all.
bool _hasContent(Atlas a) => a.degrees.any((g) => g.requiredCourses.any((e) => a.subjects.containsKey(e['subject'])));

class _RadialView extends ConsumerStatefulWidget {
  const _RadialView({required this.atlas});
  final Atlas atlas;
  @override
  ConsumerState<_RadialView> createState() => _RadialViewState();
}

class _RadialViewState extends ConsumerState<_RadialView> with TickerProviderStateMixin {
  late final move = AnimationController(vsync: this, duration: const Duration(milliseconds: 640), value: 1);
  late final prog = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);
  late final pick = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);
  late final emblem = AnimationController(vsync: this, duration: const Duration(milliseconds: 440), value: 1);
  late final settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  // intro after an empty profile got its first content: You, domains, degree, courses, then the "Start here" note
  late final intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 800), value: 1);
  late final note = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400), value: 0);
  late final idle = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  int revealStage = 4; // 0 you, 1 domains, 2 degree, 3 courses, 4 done
  bool startHint = false;
  String? _startKey;
  final _revealTimers = <Timer>[];
  final view = TransformationController();
  final paperDrag = ValueNotifier(Offset.zero);
  final deskActivity = ValueNotifier(0);
  final doodleReplay = ValueNotifier(0);
  final _cardKey = GlobalKey();
  final _readFocus = FocusNode();
  final _tp = <String, TextPainter>{};
  late final _graphMotion = Listenable.merge([move, prog, pick, emblem, intro, note, idle]);
  late final _cardMotion = Listenable.merge([view, move, pick]);

  late _N root;
  final byKey = <String, _N>{};
  String level = 'BSc';
  String? openDomain, openDegree, selected; // selected = subject node key
  Map<String, _P> from = {}, to = {};
  Map<String, double> inkDelays = {};
  Set<String> prerequisites = {}, unlocks = {};
  String? firstSemesterNode;
  String? _lastOpenDomain;
  int? _semester;
  List<_N> vis = [];
  Map<String, double> fracFrom = {}, fracTo = {};
  bool fitted = false;
  bool reducedMotion = false, panning = false;

  Degree? get _activeDegree => widget.atlas.degrees
      .where((degree) => 'g:${degree.id}' == openDegree).firstOrNull;
  int? get _shownSemester {
    final terms = _activeDegree?.semesters ?? const <int>[];
    return terms.contains(_semester) ? _semester : terms.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final playIntro = emptyProfileShown && !reduce;
    emptyProfileShown = false;
    if (playIntro) {
      level = _levels.firstWhere(
          (l) => widget.atlas.degrees.any((g) => g.level == l && g.requiredCourses.isNotEmpty),
          orElse: () => 'BSc');
      revealStage = 0;
      intro.value = 0;
    }
    if (!reduce) idle.repeat();
    _build();
    to = _layout();
    from = to;
    vis = to.keys.map((k) => byKey[k]!).toList();
    fracFrom = fracTo = _fractions(ref.read(progressProvider));
    if (playIntro) _startIntro();
  }

  void _startIntro() {
    final dom = root.kids.where((d) => d.kids.isNotEmpty).firstOrNull;
    final deg = dom?.kids.firstOrNull;
    void at(int ms, VoidCallback f) => _revealTimers.add(Timer(Duration(milliseconds: ms), () {
          if (mounted) f();
        }));
    intro.forward(from: 0);
    at(1000, () {
      revealStage = 1;
      _relayout();
    });
    at(2500, () {
      revealStage = 2;
      openDomain = dom?.key;
      _relayout();
    });
    at(4000, () {
      revealStage = 3;
      openDegree = deg?.key;
      _relayout();
    });
    at(5600, () {
      revealStage = 4;
      _startKey = vis.where((n) => n.sid != null).firstOrNull?.key;
      startHint = _startKey != null;
      if (startHint) note.forward(from: 0);
      setState(() {});
    });
  }

  /// Subtle idle drift so the map never sits perfectly still.
  _P _bob(_N n, _P p) {
    if (n.level == 0 || reducedMotion) return p;
    final ph = idle.value * 2 * math.pi + (n.key.hashCode % 628) / 100;
    return _P(p.a + .0012 * math.cos(ph), p.r + 1.5 * math.sin(ph));
  }

  @override
  void didUpdateWidget(_RadialView old) {
    super.didUpdateWidget(old);
    if (old.atlas != widget.atlas) {
      _build();
      if (openDomain != null && !byKey.containsKey(openDomain)) openDomain = openDegree = selected = null;
      if (openDegree != null && !byKey.containsKey(openDegree)) openDegree = selected = null;
      if (!byKey.containsKey(selected)) selected = null;
      _updateRelated();
      fracTo = _fractions(ref.read(progressProvider));
      _relayout();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      idle.stop();
      revealStage = 4;
      intro.value = 1;
      for (final animation in [move, prog, pick, emblem, settle, flip]) {
        animation.value = 1;
      }
      paperDrag.value = Offset.zero;
    }
  }

  @override
  void dispose() {
    move.dispose();
    prog.dispose();
    pick.dispose();
    emblem.dispose();
    settle.dispose();
    flip.dispose();
    paperDrag.dispose();
    deskActivity.dispose();
    doodleReplay.dispose();
    for (final timer in _revealTimers) {
      timer.cancel();
    }
    intro.dispose();
    note.dispose();
    idle.dispose();
    _readFocus.dispose();
    for (final text in _tp.values) {
      text.dispose();
    }
    view.dispose();
    super.dispose();
  }

  // ---- tree ----
  void _build() {
    final a = widget.atlas;
    byKey.clear();
    root = _N('root', '', 0);
    byKey['root'] = root;
    var fallback = 0;
    for (final dn in a.domains.keys.toList()..sort()) {
      final color = _domainColors[dn] ?? _fallbackColors[fallback++ % _fallbackColors.length];
      final dom = _N('d:$dn', dn, 1, parent: root, color: color);
      for (final g in a.degrees.where((g) => g.level == level && a.domains[dn]!.contains(g.id))) {
        final uni = g.id.split('-').first.toUpperCase();
        final deg = _N('g:${g.id}', '${g.title} · $uni', 2, parent: dom, color: color);
        dom.kids.add(deg);
        byKey[deg.key] = deg;
        final entries = g.requiredCourses
            .where((e) => a.subjects.containsKey(e['subject']))
            .toList()
          ..sort((x, y) {
            final term = (x['semester'] as int? ?? 999).compareTo(y['semester'] as int? ?? 999);
            if (term != 0) return term;
            return a.subjects[x['subject']]!.title.compareTo(a.subjects[y['subject']]!.title);
          });
        for (final entry in entries) {
          final sid = entry['subject'] as String;
          final subject = a.subjects[sid]!;
          final semester = entry['semester'] as int?;
          final label = semester == null ? subject.title : 'S$semester · ${subject.title}';
          final n = _N('s:${g.id}:$sid', label, 3, parent: deg, sid: sid, semester: semester, color: color);
          deg.kids.add(n);
          byKey[n.key] = n;
          deg.subjects.add(sid);
          dom.subjects.add(sid);
        }
        final list = _N('courses:${g.id}', 'Course list · ${g.subjects.length}', 3, parent: deg, color: color);
        deg.kids.add(list);
        byKey[list.key] = list;
      }
      if (dom.kids.isEmpty && activeProfile == null) continue; // profiles keep every domain visible
      root.kids.add(dom);
      byKey[dom.key] = dom;
      root.subjects.addAll(dom.subjects);
    }
  }

  void _setLevel(String l) {
    if (l == level) return;
    level = l;
    openDomain = openDegree = selected = null;
    _semester = null;
    _build();
    fracFrom = {for (final k in fracTo.keys) k: _frac(k)};
    fracTo = _fractions(ref.read(progressProvider));
    _play(prog);
    _play(flip);
    _relayout();
  }

  void _play(AnimationController animation) {
    if (reducedMotion) {
      animation.value = 1;
    } else {
      animation.forward(from: 0);
    }
  }

  void _onDeskActivity() => deskActivity.value++;

  void _beginPan(ScaleStartDetails details) {
    panning = true;
    _onDeskActivity();
    if (reducedMotion) return;
    paperDrag.value *= 1 - Curves.easeOut.transform(settle.value);
    settle.value = 0;
  }

  void _movePaper(ScaleUpdateDetails details) {
    if (reducedMotion) return;
    final pull = paperDrag.value + details.focalPointDelta * .2;
    paperDrag.value = Offset(pull.dx.clamp(-8.0, 8.0).toDouble(), pull.dy.clamp(-8.0, 8.0).toDouble());
  }

  void _endPan(ScaleEndDetails details) {
    panning = false;
    _onDeskActivity();
    if (paperDrag.value.distance > .25) {
      _play(settle);
    } else {
      settle.value = 1;
    }
  }

  void _recenter() {
    paperDrag.value = const Offset(0, 4);
    _play(settle);
    _onDeskActivity();
    setState(() => fitted = false);
  }

  bool _open(_N n) => n.level == 0 ? revealStage >= 1 : n.key == openDomain || n.key == openDegree;

  Iterable<_N> _visibleChildren(_N n) {
    if (n.level != 2) return n.kids;
    final term = _shownSemester;
    return term == null ? n.kids : n.kids.where((child) => child.sid == null || child.semester == term);
  }

  void _changeSemester(int term) {
    if (term == _shownSemester) return;
    _semester = term;
    _select(null);
    _relayout();
  }

  double _w(_N n) {
    if (!_open(n) || n.level == 0) return 1;
    final s = _visibleChildren(n).fold(0.0, (t, k) => t + _w(k));
    return n.level == 2 ? math.max(2.0, 0.55 * s) : 2 + 0.35 * s;
  }

  Map<String, _P> _layout() {
    final out = <String, _P>{};
    void go(_N n, double a0, double a1) {
      out[n.key] = _P((a0 + a1) / 2, _radius[n.level]);
      if (!_open(n)) return;
      final children = _visibleChildren(n);
      final total = children.fold(0.0, (t, k) => t + _w(k));
      var a = a0;
      for (final k in children) {
        final span = (a1 - a0) * _w(k) / total;
        go(k, a, a + span);
        a += span;
      }
    }

    go(root, -math.pi / 2, 3 * math.pi / 2);
    return out;
  }

  _P _cur(_N n) {
    final t = inkDelays.containsKey(n.key)
        ? _ink(n)
        : Curves.easeInOutCubic.transform(move.value);
    final b = to[n.key]!;
    final p = n.parent;
    final a = from[n.key] ?? (p == null ? b : (from[p.key] ?? to[p.key] ?? b));
    return _P(lerpDouble(a.a, b.a, t)!, lerpDouble(a.r, b.r, t)!);
  }

  double _ink(_N node) {
    final delay = inkDelays[node.key];
    return delay == null ? 1 : Interval(delay, delay + .56, curve: Curves.easeOutCubic).transform(move.value);
  }

  void _relayout() {
    from = {for (final n in vis) if (to.containsKey(n.key)) n.key: _cur(n)};
    to = _layout();
    vis = to.keys.map((k) => byKey[k]!).toList();
    final terms = vis.where((n) => n.semester != null).map((n) => n.semester!).toSet().toList()..sort();
    firstSemesterNode = _shownSemester == _activeDegree?.semesters.firstOrNull
        ? vis.where((n) => n.semester != null).firstOrNull?.key
        : null;
    inkDelays = {
      for (final n in vis)
        if (!from.containsKey(n.key))
          n.key: n.semester == null
              ? .085 * (n.parent?.kids.indexOf(n) ?? 0) / math.max(1, (n.parent?.kids.length ?? 1) - 1)
              : .16 * terms.indexOf(n.semester!) / math.max(1, terms.length - 1) +
                  (from.containsKey(n.parent?.key) ? 0 : .12),
    };
    if (_lastOpenDomain != openDomain) {
      if (openDomain != null) _play(emblem);
      _lastOpenDomain = openDomain;
    }
    _play(move);
    _onDeskActivity();
    setState(() {});
  }

  void _searchFor(Subject subject) {
    final current = _activeDegree;
    final degree = current != null && current.subjects.any((e) => e['subject'] == subject.id)
        ? current
        : widget.atlas.degrees.where((d) => d.level == level &&
            d.requiredCourses.any((e) => e['subject'] == subject.id)).firstOrNull;
    final entry = degree?.requiredCourses.where((e) => e['subject'] == subject.id).firstOrNull;
    if (degree == null || entry == null || (degree.semesters.isNotEmpty && entry['semester'] == null)) {
      context.push('/subject/${subject.id}');
      return;
    }
    final domain = widget.atlas.domains.entries
        .where((e) => e.value.contains(degree.id)).firstOrNull;
    if (domain == null) return;
    openDomain = 'd:${domain.key}';
    openDegree = 'g:${degree.id}';
    _semester = entry['semester'] as int?;
    _select('s:${degree.id}:${subject.id}');
    _relayout();
  }

  void _updateRelated() {
    final sid = byKey[selected]?.sid;
    prerequisites = sid == null ? {} : _relatedTo(sid, prerequisites: true);
    unlocks = sid == null ? {} : _relatedTo(sid, prerequisites: false);
  }

  void _select(String? key) {
    if (selected == key) return;
    selected = key;
    _updateRelated();
    if (key != null) _play(pick);
    _onDeskActivity();
  }

  Set<String> _relatedTo(String sid, {required bool prerequisites}) {
    final found = <String>{};
    final pending = <String>[sid];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final adjacent = prerequisites
          ? widget.atlas.subjects[current]?.prereqs ?? const <String>[]
          : widget.atlas.subjects.values
              .where((s) => s.prereqs.contains(current))
              .map((s) => s.id);
      for (final next in adjacent) {
        if (found.add(next)) pending.add(next);
      }
    }
    found.remove(sid);
    return found;
  }

  // ---- progress ----
  /// Progress counts every written level: (read, available) over L0-L3 of one subject.
  (int, int) _levelCount(Set<String> read, String sid) {
    final m = widget.atlas.subjects[sid]!;
    var avail = 0, got = 0;
    for (var n = 0; n < 4; n++) {
      if (m.levelState(n) == 'none') continue;
      avail++;
      if (read.contains('$sid:L$n')) got++;
    }
    return (got, avail);
  }

  Map<String, double> _fractions(Set<String> read) {
    final out = <String, double>{};
    for (final n in byKey.values) {
      var got = 0, avail = 0;
      for (final sid in n.sid == null ? n.subjects : [n.sid!]) {
        final (g, v) = _levelCount(read, sid);
        got += g;
        avail += v;
      }
      out[n.key] = avail == 0 ? 0 : got / avail;
    }
    return out;
  }

  double _frac(String key) {
    final t = Curves.easeOut.transform(prog.value);
    return lerpDouble(fracFrom[key] ?? 0, fracTo[key] ?? 0, t)!;
  }

  // ---- interaction ----
  void _tap(Offset p) {
    if (revealStage < 4) return;
    startHint = false;
    _N? best;
    var bestD = double.infinity;
    for (final n in vis) {
      final d = (_cur(n).xy - p).distance;
      final hit = const [48.0, 38.0, 14.0, 11.0][n.level];
      if (d <= hit && d < bestD) {
        best = n;
        bestD = d;
      }
    }
    if (best == null) {
      if (selected != null) {
        _select(null);
        setState(() {});
      }
      return;
    }
    switch (best.level) {
      case 0:
        openDomain = openDegree = selected = null;
        _semester = null;
      case 1:
        openDomain = openDomain == best.key ? null : best.key;
        openDegree = selected = null;
        _semester = null;
      case 2:
        openDomain = best.parent!.key;
        openDegree = openDegree == best.key ? null : best.key;
        _semester = null;
        selected = null;
      default:
        if (best.sid == null) {
          final degree = _activeDegree;
          if (degree != null) showDegreeCourses(context, degree, widget.atlas);
          return;
        }
        _select(best.key);
        setState(() {});
        return; // subjects do not move anything, just show the brief
    }
    _relayout();
  }

  TextPainter _text(String s, double size, Color c, double maxW, {bool bold = false, bool centre = false}) {
    return _tp.putIfAbsent(
        '$s|$size|${c.toARGB32()}|$maxW|$bold|$centre',
        () => TextPainter(
            text: TextSpan(text: s, style: GoogleFonts.notoSans(fontSize: size, color: c, fontWeight: bold ? FontWeight.w600 : null)),
            maxLines: centre ? 2 : 1,
            ellipsis: '…',
            textAlign: centre ? TextAlign.center : TextAlign.start,
            textDirection: TextDirection.ltr)
          ..layout(maxWidth: maxW, minWidth: centre ? maxW : 0));
  }

  Future<void> _readDialog(Subject s, Color color, {int level = 0}) async {
    final card = _cardKey.currentContext?.findRenderObject();
    final origin = card is RenderBox && card.hasSize
        ? card.localToGlobal(Offset.zero) & card.size
        : null;
    final duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 340);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: duration,
      transitionBuilder: (context, animation, _, child) => origin == null || reducedMotion
          ? FadeTransition(opacity: animation, child: child)
          : NotebookUnfold(origin: origin, animation: animation, child: child),
      pageBuilder: (c, _, _) => StatefulBuilder(builder: (c, setSt) {
        final lang = ref.read(langProvider);
        final text = level < 4 ? s.levelText(level, lang: lang) : null;
        final translated = level < 4 && s.hasTranslation(level, lang);
        return Dialog(
          backgroundColor: HouseStyle.desk,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: SizedBox(
            width: HouseStyle.readingWidth + 48,
            height: MediaQuery.sizeOf(c).height * 0.9,
            child: CourseNotebook(
              title: s.title,
              entranceDelay: duration,
              onClose: () => Navigator.pop(c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: HouseStyle.spacing, children: [
                    for (var n = 0; n < 4; n++)
                      ChoiceChip(
                        selected: n == level,
                        selectedColor: HouseStyle.margin,
                        labelStyle: HouseStyle.label.copyWith(
                          color: s.levelText(n) != null ? HouseStyle.ink : HouseStyle.graphite,
                        ),
                        label: Text('L$n'),
                        onSelected: (_) => setSt(() => level = n),
                      ),
                    ChoiceChip(
                      selected: level == 4,
                      selectedColor: HouseStyle.margin,
                      labelStyle: HouseStyle.label.copyWith(color: HouseStyle.ink),
                      label: Consumer(builder: (_, r, _) {
                        r.watch(practiceProvider);
                        return Text('Practice${_practiceBadge(s, lang)}');
                      }),
                      onSelected: (_) => setSt(() => level = 4),
                    ),
                  ]),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (text != null) ...[
                        ReadToggle(s.id, level: level),
                        IconButton(
                          tooltip: 'Report a problem',
                          iconSize: 20,
                          onPressed: () => _fixDialog(c, s, level, lang),
                          icon: const Icon(Icons.flag_outlined),
                        ),
                        IconButton(
                          tooltip: 'Regenerate',
                          iconSize: 20,
                          onPressed: () {
                            ref.read(agentProvider.notifier).regenerate(s, level, lang);
                            ref.read(agentOpenProvider.notifier).set(true);
                            Navigator.pop(c);
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                      TextButton(
                        onPressed: () {
                          Navigator.pop(c);
                          context.push('/subject/${s.id}');
                        },
                        child: const Text('All levels'),
                      ),
                    ],
                  ),
                  const Divider(color: HouseStyle.margin),
                  if (text != null && !translated)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Shown in English; no ${languages[lang]} version yet.',
                          style: const TextStyle(color: HouseStyle.graphite),
                        ),
                        TextButton(
                          onPressed: () {
                            ref.read(agentProvider.notifier).requestTranslation(s, level, lang);
                            ref.read(agentOpenProvider.notifier).set(true);
                            Navigator.pop(c);
                          },
                          child: const Text('Translate with agent'),
                        ),
                      ],
                    ),
                  const SizedBox(height: HouseStyle.spacing * 2),
                  if (level == 4)
                    PracticeView(subject: s, lang: lang, close: () => Navigator.pop(c))
                  else if (text != null)
                    Md(text, s.dir, key: ValueKey(level), courseTitle: s.title)
                  else ...[
                    Text('L$level has not been written yet.'),
                    const SizedBox(height: HouseStyle.spacing),
                    if (level == 0 || s.levelText(level - 1) != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: color),
                        onPressed: () {
                          ref.read(agentProvider.notifier).requestLevel(s, level, lang: lang);
                          ref.read(agentOpenProvider.notifier).set(true);
                          Navigator.pop(c);
                        },
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: Text('Write L$level with agent'),
                      )
                    else
                      Text('Needs L${level - 1} first.'),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (mounted && byKey[selected]?.sid == s.id && ModalRoute.isCurrentOf(context) == true) {
      _readFocus.requestFocus();
    }
  }


  String _practiceBadge(Subject s, String lang) {
    final all = loadExercises(s, lang);
    if (all.isEmpty) return '';
    final done = ref.read(practiceProvider);
    return ' ${all.where((e) => done['${s.id}:${e.id}']?.ok == true).length}/${all.length}';
  }

  void _fixDialog(BuildContext parent, Subject s, int level, String lang) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('What is wrong with L$level?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(color: Colors.black87),
            decoration: const InputDecoration(hintText: 'e.g. the equations do not render, section 2 is wrong'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              ref.read(agentProvider.notifier).fix(s, level, lang, text);
              ref.read(agentOpenProvider.notifier).set(true);
              Navigator.pop(c);
              if (parent.mounted) Navigator.pop(parent);
            },
            child: const Text('Send to agent'),
          ),
        ],
      ),
    );
  }

  int _highest(Subject s) {
    for (var n = 3; n > 0; n--) {
      if (s.levelText(n) != null) return n;
    }
    return 0;
  }

  int? _nextMissing(Subject s) {
    for (var n = 0; n < 4; n++) {
      if (s.levelState(n) == 'none') return n;
    }
    return null;
  }

  Widget _brief(Subject s, _N node, BoxConstraints box) {
    final w = math.min(310.0, math.max(1.0, box.maxWidth - 16));
    const h = 268.0;
    return AnimatedBuilder(
      animation: _cardMotion,
      builder: (context, _) {
        final o = MatrixUtils.transformPoint(view.value, _cur(node).xy);
        var left = o.dx + 20;
        if (left + w > box.maxWidth - 8) left = o.dx - 20 - w;
        left = left.clamp(8.0, math.max(8.0, box.maxWidth - w - 8)).toDouble();
        final top = (o.dy - 40).clamp(8.0, math.max(8.0, box.maxHeight - h - 8)).toDouble();
        final t = const Interval(0, .57, curve: Curves.easeOutCubic).transform(pick.value);
        final side = left + w / 2 < o.dx ? -1 : 1;
        final slip = -side * 19 * (1 - t);
        final bend = math.sin(math.pi * t);
        return Positioned.fill(
          child: Stack(children: [
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: CardLeader(o, Offset(left + (side < 0 ? w : 0) + slip, top + 28), t),
            ))),
            Positioned(
              left: left + slip,
              top: top + (1 - t) * 6,
              width: w,
              child: ClipPath(
                clipBehavior: bend > .01 ? Clip.antiAlias : Clip.none,
                clipper: CourseCardClip(bend),
                child: Material(
            key: _cardKey,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: HouseStyle.pageEdge),
            ),
            color: HouseStyle.paper,
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 6, color: node.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            child: Text(s.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: HouseStyle.noteHeading.copyWith(fontSize: 17, height: 1.1))),
                        SizedBox(
                            width: 32,
                            height: 28,
                            child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                onPressed: () => setState(() => _select(null)),
                                icon: const Icon(Icons.close))),
                      ]),
                      Text(s.meta['aliases'].map((x) => '${x['university']} ${x['code'] ?? ''}').take(3).join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: HouseStyle.label.copyWith(color: HouseStyle.graphite, letterSpacing: .15, fontSize: 10)),
                      const SizedBox(height: 6),
                      Text(s.summary, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Text(
                        'Requires ${s.prereqs.length}  ·  Unlocks ${widget.atlas.subjects.values.where((other) => other.prereqs.contains(s.id)).length}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      Row(children: [
                        FilledButton(
                            focusNode: _readFocus,
                            style: FilledButton.styleFrom(backgroundColor: HouseStyle.binder, visualDensity: VisualDensity.compact),
                            onPressed: () => _readDialog(s, node.color, level: _highest(s)),
                            child: const Text('Read')),
                        const Spacer(),
                        ReadToggle(s.id),
                      ]),
                      if (_nextMissing(s) case final n?)
                        TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                          onPressed: () {
                            ref.read(agentProvider.notifier).requestLevel(s, n, lang: ref.read(langProvider));
                            ref.read(agentOpenProvider.notifier).set(true);
                          },
                          icon: const Icon(Icons.auto_awesome, size: 15),
                          label: Text('Write L$n with agent', style: const TextStyle(fontSize: 12)),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.atlas;
    final degree = _activeDegree;
    final shownSemester = _shownSemester;
    ref.listen(progressProvider, (_, next) {
      fracFrom = {for (final k in fracTo.keys) k: _frac(k)};
      fracTo = _fractions(next);
      _play(prog);
    });
    final selNode = selected == null ? null : byKey[selected];
    final sel = selNode == null ? null : a.subjects[selNode.sid!];
    final focusNode = byKey[selected ?? openDegree ?? openDomain ?? 'root'] ?? root;
    final crumbs = [
      'Atlas',
      if (openDomain != null) byKey[openDomain]?.label ?? '',
      if (openDegree != null) byKey[openDegree]?.label ?? '',
    ].join('  ›  ');

    return LayoutBuilder(builder: (context, box) {
      if (!fitted && box.maxWidth > 0) {
        fitted = true;
        final s = math.min(box.maxWidth, box.maxHeight) / _canvas * 1.05;
        view.value = Matrix4.diagonal3Values(s, s, 1)
          ..setTranslationRaw((box.maxWidth - _canvas * s) / 2, (box.maxHeight - _canvas * s) / 2, 0);
      }
      return Stack(children: [
        Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
          child: CustomPaint(painter: AtlasDesk(view: view, drag: paperDrag, settle: settle, flip: flip)),
        ))),
        Positioned.fill(child: CampusMargins(
          activity: deskActivity, replay: doodleReplay, isPanning: () => panning,
        )),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: view,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(600),
            minScale: 0.25,
            maxScale: 3,
            onInteractionStart: _beginPan,
            onInteractionUpdate: _movePaper,
            onInteractionEnd: _endPan,
            child: GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(_canvas, _canvas),
                  painter: _AtlasPainter(this, _graphMotion),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          top: 8,
          right: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IgnorePointer(child: Text(crumbs, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final l in _levels)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(l, style: HouseStyle.label.copyWith(letterSpacing: .25)),
                      selected: level == l,
                      selectedColor: HouseStyle.margin,
                      onSelected: (_) => _setLevel(l)),
                ),
              const SizedBox(width: 8),
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: prog,
                  builder: (_, _) => Text(
                      '$level ${(100 * _frac('root')).round()}%'
                      '${focusNode.level == 0 ? '' : '   ·   ${focusNode.level == 3 ? 'This subject' : 'Here'} ${(100 * _frac(focusNode.key)).round()}%'}',
                      style: TextStyle(color: focusNode.color, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
            if (degree != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final term in degree.semesters)
                    ChoiceChip(
                      label: Text('S$term'),
                      visualDensity: VisualDensity.compact,
                      selected: term == shownSemester,
                      selectedColor: HouseStyle.margin,
                      onSelected: (_) => _changeSemester(term),
                    ),
                  TextButton.icon(
                    onPressed: () => showDegreeCourses(context, degree, a),
                    icon: const Icon(Icons.list_alt, size: 17),
                    label: const Text('Course list'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  shownSemester != null ? 'Required courses for S$shownSemester'
                      : degree.requiredCourses.isEmpty ? 'No verified requirements yet'
                      : 'Verified required courses · no fixed semester',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
            ],
          ]),
        ),
        Positioned(
          top: 10,
          right: 24,
          width: math.min(340, math.max(160, box.maxWidth * 0.34)),
          child: Material(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: HouseStyle.margin),
            ),
            color: HouseStyle.paper,
            child: Autocomplete<Subject>(
              displayStringForOption: (s) => s.title,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.length < 2) return const Iterable<Subject>.empty();
                return a.subjects.values
                    .where((s) => s.title.toLowerCase().contains(query))
                    .take(12);
              },
              onSelected: _searchFor,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (_) => _onDeskActivity(),
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: 'Find a subject',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320, maxWidth: 340),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: Text(option.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: Row(children: [
            IconButton(
              tooltip: 'Recentre',
              onPressed: _recenter,
              icon: const Icon(Icons.center_focus_strong),
            ),
            if (!reducedMotion && box.maxWidth >= 295 && box.maxHeight >= 200)
              IconButton(
                tooltip: 'Play both margin doodles',
                onPressed: () => doodleReplay.value++,
                icon: const Icon(Icons.gesture),
              ),
          ]),
        ),
        if (sel != null && selNode != null && to.containsKey(selNode.key)) _brief(sel, selNode, box),
      ]);
    });
  }
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _RadialViewState s;

  static final _guide = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0x0F000000);

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in _radius.skip(1).take(2)) {
      canvas.drawCircle(_centre, r, _guide);
    }
    final pos = {for (final n in s.vis) n.key: s._bob(n, s._cur(n))};
    final selectedSid = s.byKey[s.selected]?.sid;
    final prereqs = s.prerequisites;
    final dependents = s.unlocks;
    final highlighted = {...prereqs, ...dependents, ?selectedSid};
    // tree edges, tinted by domain
    for (final n in s.vis) {
      final p = n.parent;
      if (p != null && pos.containsKey(p.key)) {
        final start = pos[p.key]!.xy, end = pos[n.key]!.xy;
        final delta = end - start;
        final amount = s._ink(n);
        final bow = Offset(-delta.dy, delta.dx) * (.1 * math.sin(math.pi * amount));
        canvas.drawPath(
            Path()..moveTo(start.dx, start.dy)
              ..quadraticBezierTo(start.dx + delta.dx * .56 + bow.dx,
                  start.dy + delta.dy * .56 + bow.dy, end.dx, end.dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = n.level == 1 ? 2 : 1
              ..color = n.color.withValues(alpha: (n.level == 1 ? .58 : .39) * amount));
      }
    }
    // prerequisite arcs between visible subjects (pulled toward the centre, bundle-style)
    final bySid = {for (final n in s.vis.where((n) => n.sid != null)) n.sid!: n};
    for (final n in bySid.values) {
      for (final pre in s.widget.atlas.subjects[n.sid]!.prereqs) {
        final m = bySid[pre];
        if (m == null) continue;
        final a = pos[m.key]!.xy, b = pos[n.key]!.xy;
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(_centre.dx + (a.dx + b.dx - 2 * _centre.dx) * .15,
              _centre.dy + (a.dy + b.dy - 2 * _centre.dy) * .15, b.dx, b.dy);
        final alpha = math.min(s._ink(m), s._ink(n));
        canvas.drawPath(path, _stroke(n.color.withValues(alpha: (selectedSid == null ? .56 : .12) * alpha), 1.4));
        if (selectedSid == null) continue;
        final incoming = prereqs.contains(pre) && (prereqs.contains(n.sid) || n.sid == selectedSid);
        final outgoing = dependents.contains(n.sid) && (dependents.contains(pre) || pre == selectedSid);
        if (incoming || outgoing) _sweep(canvas, path, n.color, alpha, incoming);
      }
    }
    for (final n in s.vis) {
      final p = pos[n.key]!;
      final c = p.xy;
      final f = s._frac(n.key);
      final col = n.color;
      final amount = n.level == 0 ? s.intro.value : s._ink(n);
      if (amount == 0) continue;
      if (n.level == 3) {
        if (n.sid == null) {
          canvas.drawCircle(c, 7, Paint()..color = HouseStyle.paper);
          canvas.drawCircle(c, 7, _stroke(HouseStyle.binder, 1.5));
          for (final y in [-2.3, 0.0, 2.3]) {
            canvas.drawLine(c + Offset(-2.4, y), c + Offset(2.4, y),
                _stroke(HouseStyle.binder, 1));
          }
          if (amount > .4) _label(canvas, p, n.label, 10, HouseStyle.binder, 160, 12, bold: true);
          continue;
        }
        final isSel = n.key == s.selected;
        final related = highlighted.contains(n.sid);
        final r = isSel ? 8.0 : related ? 6.5 : 5.0;
        canvas.drawCircle(c, r, Paint()..color = (f > 0 ? col : HouseStyle.paper).withValues(alpha: amount));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSel ? 2.4 : related ? 2 : 1.4
              ..color = col.withValues(alpha: (selectedSid == null || related ? 1 : .24) * amount));
        final labelColor = selectedSid == null || related ? (isSel ? col : Colors.black87) : Colors.black38;
        if (amount > .40) {
          _label(canvas, p, n.label, 9.5, labelColor,
              190, 11, bold: isSel || related,
              semester: n.key == s.firstSemesterNode ? n.semester : null);
        }
        continue;
      }
      final r = const [46.0, 34.0, 7.0][n.level] + (n.level == 0 && !s.reducedMotion ? 1.4 * math.sin(s.idle.value * 2 * math.pi) : 0);
      canvas.drawCircle(c, r, Paint()..color = (n.level == 1 ? Color.alphaBlend(col.withValues(alpha: 0.12), HouseStyle.paper) : HouseStyle.paper).withValues(alpha: amount));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.level == 1 ? 2 : 1.4
            ..color = n.level == 0 ? Colors.black26 : col.withValues(alpha: amount));
      // progress ring
      final ring = Rect.fromCircle(center: c, radius: r + 5);
      canvas.drawArc(
          ring,
          0,
          2 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.black12);
      canvas.drawArc(
          ring,
          -math.pi / 2,
          2 * math.pi * f,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 3
            ..color = f >= 0.999 ? Colors.green : (n.level == 0 ? accent : col));
      if (n.level == 0) {
        _centred(canvas, c, 'You', 15, Colors.black87, 80, dy: -9, bold: true);
        _centred(canvas, c, '${(100 * f).round()}%', 13, accent, 80, dy: 9);
      } else if (n.level == 1) {
        final art = paintAtlasEmblem(canvas, c + const Offset(0, -10), n.label, col,
            n.key == s.openDomain ? s.emblem.value : 1);
        _centred(canvas, c, n.label, 10.5, Color.alphaBlend(Colors.black54, col), 62,
            dy: art ? 11 : 0, bold: true);
        if (activeProfile != null && n.kids.isNotEmpty) {
          // a dot marks the domain that holds content
          final pulse = s.reducedMotion ? 0.0 : 1.2 * math.sin(s.idle.value * 2 * math.pi * 2);
          final spot = c + Offset(r * .74, -r * .74);
          canvas.drawCircle(spot, 6.5 + pulse, Paint()..color = HouseStyle.paper);
          canvas.drawCircle(spot, 4.8 + pulse, Paint()..color = col);
        }
      } else {
        final open = n.key == s.openDegree;
        if (amount > .40) {
          _label(canvas, p, n.label, open ? 10.5 : 9.5, open ? col : Colors.black87,
              150, r + 8, bold: open);
        }
      }
    }
    final target = s._startKey;
    if (s.startHint && target != null && pos.containsKey(target)) _startHere(canvas, pos[target]!);
  }

  /// Handwritten "Start here" with an underline that turns into an arrow pointing at the first course.
  void _startHere(Canvas canvas, _P p) {
    final t = s.note.value;
    if (t <= 0) return;
    final c = p.xy;
    final d = Offset(math.cos(p.a), math.sin(p.a));
    final side = Offset(-d.dy, d.dx);
    final tp = TextPainter(
      text: TextSpan(
          text: 'Start here',
          style: TextStyle(fontFamily: HouseStyle.handwriting, fontSize: 27, fontWeight: FontWeight.w700, color: HouseStyle.binder)),
      textDirection: TextDirection.ltr,
    )..layout();
    final centre = c - d * 150 + side * 34;
    final box = Rect.fromCenter(center: centre, width: tp.width, height: tp.height);
    final sway = t >= 1 && !s.reducedMotion ? math.sin(s.idle.value * 2 * math.pi * 2) : 0.0;
    canvas.save();
    canvas.translate(d.dx * sway * 3, d.dy * sway * 3);
    // the words are written left to right
    final write = const Interval(0, .5, curve: Curves.easeInOut).transform(t);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(box.left - 6, box.top - 6, (box.width + 12) * write, box.height + 12));
    tp.paint(canvas, box.topLeft);
    canvas.restore();
    // underline, then a curve ending in an arrowhead at the course
    final start = Offset(box.left, box.bottom - 2), mid = Offset(box.right, box.bottom + 1);
    final end = c - d * 17;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(box.center.dx, box.bottom + 7, mid.dx, mid.dy);
    final run = end - mid;
    final bend = Offset(-run.dy, run.dx) / math.max(1, run.distance);
    path.cubicTo(mid.dx + run.dx * .35 + bend.dx * 22, mid.dy + run.dy * .35 + bend.dy * 22,
        mid.dx + run.dx * .7 - bend.dx * 12, mid.dy + run.dy * .7 - bend.dy * 12, end.dx, end.dy);
    final line = path.computeMetrics().first;
    final draw = const Interval(.45, 1, curve: Curves.easeInOut).transform(t);
    canvas.drawPath(line.extractPath(0, line.length * draw), _stroke(HouseStyle.binder, 2.4));
    if (draw > .97) {
      final tip = line.getTangentForOffset(line.length)!;
      final fwd = tip.vector;
      for (final turn in [-.5, .5]) {
        final wing = Offset(fwd.dx * math.cos(turn) - fwd.dy * math.sin(turn), fwd.dx * math.sin(turn) + fwd.dy * math.cos(turn));
        canvas.drawLine(tip.position, tip.position - wing * 11, _stroke(HouseStyle.binder, 2.4));
      }
    }
    canvas.restore();
  }

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width;

  void _sweep(Canvas canvas, Path path, Color color, double alpha, bool incoming) {
    final route = path.computeMetrics().firstOrNull;
    if (route == null || route.length <= 11) return;
    final begin = 5.0;
    final end = begin + (route.length - 11) * Curves.easeOut.transform(s.pick.value);
    if (end <= begin) return;
    final highlight = route.extractPath(begin, end);
    if (incoming) {
      canvas.drawPath(route.extractPath(begin, math.max(begin, end - 3)),
          _stroke(const Color(0xFFF2CA68).withValues(alpha: .40 * alpha), 7.5));
    }
    canvas.drawPath(highlight, _stroke(color.withValues(alpha: (.80 + (incoming ? .15 : 0)) * alpha), incoming ? 1.9 : 1.35));
    final tip = route.getTangentForOffset(end);
    if (tip == null || end - begin < 7) return;
    final fwd = tip.vector;
    final back = tip.position - fwd * 5;
    final wing = Offset(-fwd.dy, fwd.dx) * 2.7;
    canvas.drawPath(
      Path()..moveTo((back + wing).dx, (back + wing).dy)
        ..lineTo(tip.position.dx, tip.position.dy)
        ..lineTo((back - wing).dx, (back - wing).dy),
      _stroke(color.withValues(alpha: .76 * alpha), 1.25),
    );
  }

  void _centred(Canvas c, Offset o, String t, double size, Color col, double w, {double dy = 0, bool bold = false}) {
    final tp = s._text(t, size, col, w, bold: bold, centre: true);
    tp.paint(c, o + Offset(-w / 2, -tp.height / 2 + dy));
  }

  void _label(Canvas c, _P p, String t, double size, Color col, double maxW, double gap, {bool bold = false, int? semester}) {
    final tp = s._text(t, size, col, maxW, bold: bold);
    final flip = math.cos(p.a) < 0;
    c.save();
    c.translate(_centre.dx + math.cos(p.a) * (p.r + gap), _centre.dy + math.sin(p.a) * (p.r + gap));
    c.rotate(flip ? p.a + math.pi : p.a);
    final x = flip ? -tp.width : 0.0;
    tp.paint(c, Offset(x, -tp.height / 2));
    if (semester != null) {
      final amount = const Interval(.56, 1, curve: Curves.easeOutCubic).transform(s.move.value);
      final width = s._text('S$semester', size, col, 64, bold: bold).width + 2;
      final y = tp.height / 2 - 1;
      final stroke = Path()..moveTo(x - 1, y + 1)
        ..quadraticBezierTo(x + width * .58, y - 1, x + width, y)
        ..quadraticBezierTo(x + width + 3, y + 1, x + width - 2, y + 2.7);
      final line = stroke.computeMetrics().first;
      c.drawPath(line.extractPath(0, line.length * amount), _stroke(HouseStyle.binder, .95));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_AtlasPainter o) => true;
}

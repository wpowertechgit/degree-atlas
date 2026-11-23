import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'main.dart';
import 'progress.dart';

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
  _N(this.key, this.label, this.level, {this.parent, this.sid, this.color = accent});
  final String key, label;
  final int level; // 0 you, 1 domain, 2 degree, 3 subject
  final _N? parent;
  final String? sid;
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

class RadialPage extends StatelessWidget {
  const RadialPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: dragBar(context, 'Degree Atlas', actions: [
          TextButton(onPressed: () => context.push('/list'), child: const Text('List view')),
        ]),
        body: AtlasBody((a) => _RadialView(atlas: a)),
      );
}

class _RadialView extends ConsumerStatefulWidget {
  const _RadialView({required this.atlas});
  final Atlas atlas;
  @override
  ConsumerState<_RadialView> createState() => _RadialViewState();
}

class _RadialViewState extends ConsumerState<_RadialView> with TickerProviderStateMixin {
  late final move = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
  late final prog = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);
  final view = TransformationController();
  final _tp = <String, TextPainter>{};

  late _N root;
  final byKey = <String, _N>{};
  String level = 'BSc';
  String? openDomain, openDegree, selected; // selected = subject node key
  Map<String, _P> from = {}, to = {};
  List<_N> vis = [];
  Map<String, double> fracFrom = {}, fracTo = {};
  bool fitted = false;

  @override
  void initState() {
    super.initState();
    _build();
    to = _layout();
    from = to;
    vis = to.keys.map((k) => byKey[k]!).toList();
    fracFrom = fracTo = _fractions(ref.read(progressProvider));
  }

  @override
  void didUpdateWidget(_RadialView old) {
    super.didUpdateWidget(old);
    if (old.atlas != widget.atlas) {
      _build();
      if (openDomain != null && !byKey.containsKey(openDomain)) openDomain = openDegree = selected = null;
      if (openDegree != null && !byKey.containsKey(openDegree)) openDegree = selected = null;
      fracTo = _fractions(ref.read(progressProvider));
      _relayout();
    }
  }

  @override
  void dispose() {
    move.dispose();
    prog.dispose();
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
        final entries = g.subjects
            .where((e) => a.subjects.containsKey(e['subject']))
            .toList()
          ..sort((x, y) {
            final semester = (x['semester'] as num? ?? 999).compareTo(y['semester'] as num? ?? 999);
            if (semester != 0) return semester;
            return a.subjects[x['subject']]!.title.compareTo(a.subjects[y['subject']]!.title);
          });
        for (final entry in entries) {
          final sid = entry['subject'] as String;
          final semester = (entry['semester'] as num?)?.toInt();
          final title = a.subjects[sid]!.title;
          final label = semester == null ? title : 'S$semester · $title';
          final n = _N('s:${g.id}:$sid', label, 3, parent: deg, sid: sid, color: color);
          deg.kids.add(n);
          byKey[n.key] = n;
        }
        final ids = entries.map((e) => e['subject'] as String).toList();
        deg.subjects.addAll(ids);
        dom.subjects.addAll(ids);
      }
      if (dom.kids.isEmpty) continue; // nothing at this level in this domain
      root.kids.add(dom);
      byKey[dom.key] = dom;
      root.subjects.addAll(dom.subjects);
    }
  }

  void _setLevel(String l) {
    if (l == level) return;
    level = l;
    openDomain = openDegree = selected = null;
    _build();
    fracFrom = {for (final k in fracTo.keys) k: _frac(k)};
    fracTo = _fractions(ref.read(progressProvider));
    prog.forward(from: 0);
    _relayout();
  }

  bool _open(_N n) => n.level == 0 || n.key == openDomain || n.key == openDegree;

  double _w(_N n) {
    if (!_open(n) || n.level == 0) return 1;
    final s = n.kids.fold(0.0, (t, k) => t + _w(k));
    return n.level == 2 ? math.max(2.0, 0.55 * s) : 2 + 0.35 * s;
  }

  Map<String, _P> _layout() {
    final out = <String, _P>{};
    void go(_N n, double a0, double a1) {
      out[n.key] = _P((a0 + a1) / 2, _radius[n.level]);
      if (!_open(n)) return;
      final total = n.kids.fold(0.0, (t, k) => t + _w(k));
      var a = a0;
      for (final k in n.kids) {
        final span = (a1 - a0) * _w(k) / total;
        go(k, a, a + span);
        a += span;
      }
    }

    go(root, -math.pi / 2, 3 * math.pi / 2);
    return out;
  }

  _P _cur(_N n) {
    final t = Curves.easeInOutCubic.transform(move.value);
    final b = to[n.key]!;
    final p = n.parent;
    final a = from[n.key] ?? (p == null ? b : (from[p.key] ?? to[p.key] ?? b));
    return _P(lerpDouble(a.a, b.a, t)!, lerpDouble(a.r, b.r, t)!);
  }

  void _relayout() {
    from = {for (final n in vis) if (to.containsKey(n.key)) n.key: _cur(n)};
    to = _layout();
    vis = to.keys.map((k) => byKey[k]!).toList();
    move.forward(from: 0);
    setState(() {});
  }

  void _searchFor(Subject subject) {
    final degree = widget.atlas.degrees.where((d) => d.level == level &&
        d.subjects.any((e) => e['subject'] == subject.id)).firstOrNull;
    if (degree == null) return;
    final domain = widget.atlas.domains.entries
        .where((e) => e.value.contains(degree.id)).firstOrNull;
    if (domain == null) return;
    openDomain = 'd:${domain.key}';
    openDegree = 'g:${degree.id}';
    selected = 's:${degree.id}:${subject.id}';
    _relayout();
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
  Map<String, double> _fractions(Set<String> read) {
    final a = widget.atlas;
    final out = <String, double>{};
    for (final n in byKey.values) {
      if (n.level == 3) {
        out[n.key] = read.contains('${n.sid}:L0') ? 1 : 0;
      } else {
        final avail = n.subjects.where((s) => a.subjects[s]!.levelState(0) != 'none').toList();
        out[n.key] = avail.isEmpty ? 0 : avail.where((s) => read.contains('$s:L0')).length / avail.length;
      }
    }
    return out;
  }

  double _frac(String key) {
    final t = Curves.easeOut.transform(prog.value);
    return lerpDouble(fracFrom[key] ?? 0, fracTo[key] ?? 0, t)!;
  }

  // ---- interaction ----
  void _tap(Offset p) {
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
        selected = null;
        setState(() {});
      }
      return;
    }
    switch (best.level) {
      case 0:
        openDomain = openDegree = selected = null;
      case 1:
        openDomain = openDomain == best.key ? null : best.key;
        openDegree = selected = null;
      case 2:
        openDomain = best.parent!.key;
        openDegree = openDegree == best.key ? null : best.key;
        selected = null;
      default:
        selected = best.key;
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

  void _readDialog(Subject s, Color color) {
    final l0 = s.levelText(0);
    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: paper,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(c).height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 6, height: 28, color: color, margin: const EdgeInsets.only(right: 12)),
                Expanded(child: Text(s.title, style: Theme.of(c).textTheme.titleLarge)),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
              ]),
              Row(children: [
                ReadToggle(s.id),
                const Spacer(),
                TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/subject/${s.id}');
                    },
                    child: const Text('All levels')),
              ]),
              const Divider(),
              Flexible(child: SingleChildScrollView(child: l0 == null ? const Text('No L0 yet.') : Md(l0, s.dir))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _brief(Subject s, _N node, BoxConstraints box) {
    const w = 310.0, h = 230.0;
    return AnimatedBuilder(
      animation: Listenable.merge([view, move]),
      builder: (context, _) {
        final o = MatrixUtils.transformPoint(view.value, _cur(node).xy);
        var left = o.dx + 20;
        if (left + w > box.maxWidth - 8) left = o.dx - 20 - w;
        left = left.clamp(8.0, math.max(8.0, box.maxWidth - w - 8)).toDouble();
        final top = (o.dy - 40).clamp(8.0, math.max(8.0, box.maxHeight - h - 8)).toDouble();
        return Positioned(
          left: left,
          top: top,
          width: w,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
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
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                        SizedBox(
                            width: 32,
                            height: 28,
                            child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                onPressed: () => setState(() => selected = null),
                                icon: const Icon(Icons.close))),
                      ]),
                      Text(s.meta['aliases'].map((x) => '${x['university']} ${x['code'] ?? ''}').take(3).join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Text(s.summary, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Text(
                        'Requires ${s.prereqs.length}  ·  Unlocks ${widget.atlas.subjects.values.where((other) => other.prereqs.contains(s.id)).length}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      Row(children: [
                        FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: node.color, visualDensity: VisualDensity.compact),
                            onPressed: s.levelText(0) == null ? null : () => _readDialog(s, node.color),
                            child: const Text('Read L0')),
                        const Spacer(),
                        ReadToggle(s.id),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.atlas;
    ref.listen(progressProvider, (_, next) {
      fracFrom = {for (final k in fracTo.keys) k: _frac(k)};
      fracTo = _fractions(next);
      prog.forward(from: 0);
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
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: view,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(600),
            minScale: 0.25,
            maxScale: 3,
            child: GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(_canvas, _canvas),
                  painter: _AtlasPainter(this, Listenable.merge([move, prog])),
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
                      label: Text(l, style: const TextStyle(color: Colors.black87)), selected: level == l, selectedColor: const Color(0xFFF3D9D7), onSelected: (_) => _setLevel(l)),
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
            if (openDegree != null)
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Start at S1; follow the subjects clockwise by semester.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
          ]),
        ),
        Positioned(
          top: 10,
          right: 24,
          width: math.min(340, math.max(160, box.maxWidth * 0.34)),
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
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
          child: IconButton(
              tooltip: 'Recentre',
              onPressed: () => setState(() => fitted = false),
              icon: const Icon(Icons.center_focus_strong)),
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
    final pos = {for (final n in s.vis) n.key: s._cur(n)};
    final selectedSid = s.byKey[s.selected]?.sid;
    final prereqs = selectedSid == null
        ? <String>{}
        : s._relatedTo(selectedSid, prerequisites: true);
    final dependents = selectedSid == null
        ? <String>{}
        : s._relatedTo(selectedSid, prerequisites: false);
    final highlighted = {...prereqs, ...dependents, ?selectedSid};
    // tree edges, tinted by domain
    for (final n in s.vis) {
      final p = n.parent;
      if (p != null && pos.containsKey(p.key)) {
        canvas.drawLine(
            pos[p.key]!.xy,
            pos[n.key]!.xy,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = n.level == 1 ? 2 : 1
              ..color = n.color.withValues(alpha: n.level == 1 ? 0.5 : 0.28));
      }
    }
    // prerequisite arcs between visible subjects (pulled toward the centre, bundle-style)
    final bySid = {for (final n in s.vis.where((n) => n.level == 3)) n.sid!: n};
    for (final n in bySid.values) {
      for (final pre in s.widget.atlas.subjects[n.sid]!.prereqs) {
        final m = bySid[pre];
        if (m == null) continue;
        final a = pos[m.key]!.xy, b = pos[n.key]!.xy;
        canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..quadraticBezierTo(_centre.dx + (a.dx + b.dx - 2 * _centre.dx) * 0.15,
                  _centre.dy + (a.dy + b.dy - 2 * _centre.dy) * 0.15, b.dx, b.dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = selectedSid == null
                  ? n.color.withValues(alpha: 0.7)
                  : (highlighted.contains(pre) && highlighted.contains(n.sid)
                      ? n.color.withValues(alpha: 0.95)
                      : Colors.black.withValues(alpha: 0.07)));
      }
    }
    for (final n in s.vis) {
      final p = pos[n.key]!;
      final c = p.xy;
      final f = s._frac(n.key);
      final col = n.color;
      if (n.level == 3) {
        final isSel = n.key == s.selected;
        final related = highlighted.contains(n.sid);
        final r = isSel ? 8.0 : related ? 6.5 : 5.0;
        canvas.drawCircle(c, r, Paint()..color = f > 0 ? col : Colors.white);
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSel ? 2.4 : related ? 2 : 1.4
              ..color = selectedSid == null || related ? col : col.withValues(alpha: 0.24));
        _label(canvas, p, n.label, 9.5,
            selectedSid == null || related ? (isSel ? col : Colors.black87) : Colors.black38,
            190, 11, bold: isSel || related);
        continue;
      }
      final r = const [46.0, 34.0, 7.0][n.level];
      canvas.drawCircle(c, r, Paint()..color = n.level == 1 ? Color.alphaBlend(col.withValues(alpha: 0.14), Colors.white) : Colors.white);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.level == 1 ? 2 : 1.4
            ..color = n.level == 0 ? Colors.black26 : col);
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
        _centred(canvas, c, n.label, 10.5, Color.alphaBlend(Colors.black54, col), 62, bold: true);
      } else {
        final open = n.key == s.openDegree;
        _label(canvas, p, n.label, open ? 10.5 : 9.5, open ? col : Colors.black87, 150, r + 8, bold: open);
      }
    }
  }

  void _centred(Canvas c, Offset o, String t, double size, Color col, double w, {double dy = 0, bool bold = false}) {
    final tp = s._text(t, size, col, w, bold: bold, centre: true);
    tp.paint(c, o + Offset(-w / 2, -tp.height / 2 + dy));
  }

  void _label(Canvas c, _P p, String t, double size, Color col, double maxW, double gap, {bool bold = false}) {
    final tp = s._text(t, size, col, maxW, bold: bold);
    final flip = math.cos(p.a) < 0;
    c.save();
    c.translate(_centre.dx + math.cos(p.a) * (p.r + gap), _centre.dy + math.sin(p.a) * (p.r + gap));
    c.rotate(flip ? p.a + math.pi : p.a);
    tp.paint(c, Offset(flip ? -tp.width : 0, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(_AtlasPainter o) => true;
}

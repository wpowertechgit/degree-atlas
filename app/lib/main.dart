import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'package:window_manager/legacy.dart';
import 'agent.dart' show killRunningAgent, langProvider;
import 'course_notebook.dart';
import 'house_style.dart';
import 'profiles.dart';
import 'radial.dart';

const accent = HouseStyle.binder;
const paper = HouseStyle.paper;

/// Folder of the repository's own data set: DEGREE_ATLAS_DATA, else ./data or ../data relative to the working dir,
/// else the data folder of an installed copy.
Directory baseDataDir() {
  final env = Platform.environment['DEGREE_ATLAS_DATA'];
  if (env != null) return Directory(env);
  // The installer puts the exe in <install>\bin and the data in <install>\data.
  final installed = p.join(p.dirname(Platform.resolvedExecutable), '..', 'data');
  for (final c in ['data', '../data', installed]) {
    if (Directory(c).existsSync()) return Directory(c);
  }
  return Directory('data');
}

/// Repository root (holds scripts/, AGENTS.md and profiles/).
Directory repoRoot() => baseDataDir().absolute.parent;

/// Name of the active profile, or null for the repository's own data/ folder. See profiles.dart.
String? activeProfile;

/// Data folder of the active profile.
Directory dataDir() =>
    activeProfile == null ? baseDataDir() : Directory(p.join(repoRoot().path, 'profiles', activeProfile!, 'data'));

class Subject {
  Subject(this.meta, this.dir);
  final Map<String, dynamic> meta;
  final Directory dir;
  String get id => meta['id'];
  String get title => meta['title'];
  String get summary => meta['summary'] ?? '';
  List<String> get prereqs => List<String>.from(meta['prerequisites'] ?? []);
  String levelState(int n) => meta['levels']?['L$n']?['state'] ?? 'none';

  /// Level texts are read on demand and kept in a small LRU, revalidated by modification time.
  static final _texts = <String, (int, String)>{};
  static const _textCacheSize = 48;
  /// Text of level [n] in [lang]; falls back to the English file `L<n>.md` when there is no translation.
  String? levelText(int n, {String lang = 'en'}) {
    if (lang != 'en') {
      final t = _read('L$n.$lang.md');
      if (t != null) return t;
    }
    return _read('L$n.md');
  }

  /// Sources of level [n] from sources.json, in the order that numbers the level's inline [n] citations.
  List<Map<String, dynamic>> levelSources(int n) {
    try {
      final all = jsonDecode(_read('sources.json') ?? '[]');
      return [
        for (final e in all is List ? all : const [])
          if (e is Map && e['level'] == 'L$n') Map<String, dynamic>.from(e)
      ];
    } on FormatException {
      return const []; // caught mid-write or malformed; validate.py reports it
    }
  }

  bool hasTranslation(int n, String lang) => lang == 'en' || File(p.join(dir.path, 'L$n.$lang.md')).existsSync();

  String? _read(String name) {
    final f = File(p.join(dir.path, name));
    final st = f.statSync();
    if (st.type == FileSystemEntityType.notFound) return null;
    final stamp = st.modified.millisecondsSinceEpoch;
    final hit = _texts.remove(f.path);
    if (hit != null && hit.$1 == stamp) {
      _texts[f.path] = hit;
      return hit.$2;
    }
    final text = f.readAsStringSync();
    _texts[f.path] = (stamp, text);
    if (_texts.length > _textCacheSize) _texts.remove(_texts.keys.first);
    return text;
  }
}

class Degree {
  Degree(this.id, this.title, this.level, this.subjects, {
    this.curriculumSource,
    this.choices = const [],
  });
  final String id, title, level;
  final List<Map<String, dynamic>> subjects;
  final String? curriculumSource;
  final List<Map<String, dynamic>> choices;

  /// Electives form choice groups; every other course link (with or without a plan source) counts as a course.
  String kindOf(Map<String, dynamic> entry) => entry['kind'] == 'elective' ? 'elective' : 'mandatory';
  Iterable<Map<String, dynamic>> get requiredCourses =>
      subjects.where((entry) => kindOf(entry) == 'mandatory');
  List<int> get semesters =>
      (requiredCourses.map((entry) => entry['semester']).whereType<int>().toSet().toList()..sort());
}

class Atlas {
  Atlas(this.subjects, this.degrees, this.domains);
  final Map<String, Subject> subjects;
  final List<Degree> degrees;
  final Map<String, List<String>> domains; // domain title -> degree ids
}

dynamic _json(File f) => jsonDecode(f.readAsStringSync());

List<File> _jsonFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
}

/// Reads every structural file. Runs in a background isolate; returns plain JSON only.
/// Level texts (L*.md) are never touched here, so the cost does not grow with L1-L3.
Map<String, dynamic> _readRaw(String root) {
  final subjects = <dynamic>[];
  final sd = Directory(p.join(root, 'subjects'));
  if (sd.existsSync()) {
    for (final d in sd.listSync().whereType<Directory>()) {
      final f = File(p.join(d.path, 'meta.json'));
      if (f.existsSync()) subjects.add(_json(f));
    }
  }
  return {
    'subjects': subjects,
    'degrees': [for (final f in _jsonFiles(p.join(root, 'degrees'))) _json(f)],
    'domains': [for (final f in _jsonFiles(p.join(root, 'domains'))) _json(f)],
  };
}

Future<Atlas> loadAtlas() async {
  final root = dataDir().absolute.path;
  final raw = await Isolate.run(() => _readRaw(root));
  final subjects = <String, Subject>{
    for (final m in raw['subjects'] as List)
      m['id'] as String: Subject(Map<String, dynamic>.from(m), Directory(p.join(root, 'subjects', m['id'])))
  };
  final degrees = [
    for (final j in raw['degrees'] as List)
      Degree(j['id'], j['title'], j['level'], List<Map<String, dynamic>>.from(j['subjects']),
          curriculumSource: j['curriculum_source'] as String?,
          choices: List<Map<String, dynamic>>.from(j['choices'] ?? const []))
  ]..sort((a, b) => a.title.compareTo(b.title));
  final domains = <String, List<String>>{
    for (final j in raw['domains'] as List) j['title'] as String: List<String>.from(j['degrees'])
  };
  return Atlas(subjects, degrees, domains);
}

/// Re-reads only the meta.json files that changed (no full rescan).
Atlas _patch(Atlas a, Set<String> changed) {
  final s = {...a.subjects};
  for (final path in changed) {
    final f = File(path);
    final id = p.basename(p.dirname(path));
    if (!f.existsSync()) {
      s.remove(id);
      continue;
    }
    try {
      s[id] = Subject(Map<String, dynamic>.from(_json(f)), f.parent);
    } on FormatException {
      // file caught mid-write; the next change event retries
    }
  }
  return Atlas(s, a.degrees, a.domains);
}

/// Initial load in the background, then incremental updates: a changed meta.json is re-read alone,
/// a changed degree or domain file triggers a full background reload. L*.md writes are ignored.
final atlasProvider = StreamProvider<Atlas>((ref) {
  final c = StreamController<Atlas>();
  Atlas? cur;
  Future<void> full() async {
    final a = await loadAtlas();
    cur = a;
    if (!c.isClosed) c.add(a);
  }

  full();
  final metas = <String>{};
  var structural = false;
  Timer? debounce;
  final sub = DirectoryWatcher(dataDir().absolute.path)
      .events
      .where((e) => e.path.endsWith('meta.json') || e.path.contains('degrees') || e.path.contains('domains'))
      .listen((e) {
    if (e.path.endsWith('meta.json')) {
      metas.add(e.path);
    } else {
      structural = true;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 5), () async {
      if (cur == null || c.isClosed) return;
      if (structural) {
        structural = false;
        metas.clear();
        await full();
      } else {
        cur = _patch(cur!, {...metas});
        metas.clear();
        c.add(cur!);
      }
    });
  });
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
    c.close();
  });
  return c.stream;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
        const WindowOptions(titleBarStyle: TitleBarStyle.hidden, minimumSize: Size(420, 600)),
        () async {
      await windowManager.show();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(_CloseGuard());
  }
  activeProfile = readActiveProfile();
  runApp(const ProfileScope(child: App()));
}

/// Ends a running agent before the window closes; its child processes would otherwise outlive the app.
class _CloseGuard with WindowListener {
  @override
  Future<void> onWindowClose() async {
    await killRunningAgent();
    await windowManager.destroy();
  }
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const RadialPage(), routes: [
    GoRoute(path: 'list', builder: (_, _) => const HomePage()),
    GoRoute(
        path: 'subject/:id',
        builder: (_, s) => SubjectPage(id: s.pathParameters['id']!)),
  ]),
]);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: paper),
      scaffoldBackgroundColor: paper,
      useMaterial3: true,
    );
    final sans = GoogleFonts.notoSansTextTheme(base.textTheme).apply(bodyColor: HouseStyle.ink, displayColor: HouseStyle.ink);
    final theme = base.copyWith(
      textTheme: sans.copyWith(
        headlineMedium: HouseStyle.heading.copyWith(fontSize: 31),
        titleLarge: HouseStyle.noteHeading.copyWith(fontSize: 22),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: HouseStyle.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: HouseStyle.margin)),
      ),
      dividerColor: HouseStyle.pageEdge,
    );
    return MaterialApp.router(
      scaffoldMessengerKey: messengerKey,
        title: 'Degree Atlas', theme: theme, routerConfig: _router, debugShowCheckedModeBanner: false);
  }
}

PreferredSizeWidget dragBar(BuildContext context, String title, {List<Widget> actions = const []}) {
  return AppBar(
    titleSpacing: HouseStyle.spacing * 2,
    title: DragToMoveArea(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: toggleMaximize,
        child: SizedBox(
          width: double.infinity,
          child: LayoutBuilder(builder: (context, space) {
            final compact = space.maxWidth < 170;
            return Align(
              alignment: Alignment.centerLeft,
              child: SvgPicture.asset(
                compact ? HouseStyle.mark : HouseStyle.wordmark,
                width: compact ? 30 : 162,
                height: compact ? 24 : 30,
                fit: BoxFit.contain,
                semanticsLabel: title,
              ),
            );
          }),
        ),
      ),
    ),
    actions: [...actions, const WindowButtons()],
  );
}

Future<void> toggleMaximize() async =>
    await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize();

class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});
  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool max = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) => mounted ? setState(() => max = v) : null);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => max = true);
  @override
  void onWindowUnmaximize() => setState(() => max = false);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: windowManager.minimize, icon: const Icon(Icons.minimize, size: 18)),
        IconButton(
            onPressed: toggleMaximize,
            icon: Icon(max ? Icons.filter_none : Icons.crop_square, size: 18)),
        IconButton(onPressed: windowManager.close, icon: const Icon(Icons.close, size: 18)),
        const SizedBox(width: 8),
      ]);
}

class AtlasBody extends ConsumerWidget {
  const AtlasBody(this.builder, {super.key});
  final Widget Function(Atlas) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(atlasProvider).when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      );
}

String levelsBadge(Subject s) =>
    [for (var n = 0; n < 4; n++) if (s.levelState(n) != 'none') 'L$n'].join(' ');

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: dragBar(context, 'Degree Atlas', actions: [
          IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
        ]),
        body: AtlasBody((a) {
          final inDegree = <String>{};
          final tiles = <Widget>[];
          for (final d in a.degrees) {
            tiles.add(ExpansionTile(
              title: Text(d.title),
              subtitle: Text('${d.level} · ${d.requiredCourses.length} required'),
              shape: const Border(),
              children: [
                DegreeCourseSections(degree: d, atlas: a,
                    onSubject: (id) => context.push('/subject/$id')),
              ],
            ));
            inDegree.addAll(d.subjects.map((e) => e['subject'] as String));
          }
          final loose = a.subjects.values.where((s) => !inDegree.contains(s.id)).toList();
          if (loose.isNotEmpty) {
            tiles.add(ExpansionTile(
                title: const Text('Unassigned'),
                shape: const Border(),
                children: [for (final s in loose) subjectTile(context, s, '')]));
          }
          if (tiles.isEmpty) return const Center(child: Text('No data found. Set DEGREE_ATLAS_DATA.'));
          return ListView(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), children: tiles);
        }),
      );

  Widget subjectTile(BuildContext context, Subject s, String tag) => ListTile(
        dense: true,
        title: Text(s.title),
        subtitle: Text(levelsBadge(s)),
        trailing: Text(tag),
        onTap: () => context.push('/subject/${s.id}'),
      );
}

Future<void> showDegreeCourses(BuildContext context, Degree degree, Atlas atlas) async {
  final id = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: HouseStyle.paper,
      title: Text(degree.title),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(dialog).height * .60,
        child: ListView(
          children: [
            DegreeCourseSections(
              degree: degree,
              atlas: atlas,
              onSubject: (id) => Navigator.pop(dialog, id),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
    ),
  );
  if (id != null && context.mounted) context.push('/subject/$id');
}

class DegreeCourseSections extends StatelessWidget {
  const DegreeCourseSections({
    super.key,
    required this.degree,
    required this.atlas,
    required this.onSubject,
  });
  final Degree degree;
  final Atlas atlas;
  final ValueChanged<String> onSubject;

  List<Widget> _tiles(Iterable<Map<String, dynamic>> entries) => [
    for (final entry in entries)
      if (atlas.subjects[entry['subject']] case final subject?)
        ListTile(
          dense: true,
          title: Text(subject.title),
          subtitle: Text(levelsBadge(subject)),
          trailing: entry['semester'] is int ? Text('S${entry['semester']}') : null,
          onTap: () => onSubject(subject.id),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final required = degree.requiredCourses.toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final entry in degree.subjects.where((e) => degree.kindOf(e) == 'elective')) {
      groups.putIfAbsent(entry['group'] as String? ?? 'Electives', () => []).add(entry);
    }
    final rules = {
      for (final choice in degree.choices)
        choice['name'] as String: choice['rule'] as String,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (required.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No required courses yet.'),
          )
        else
          ExpansionTile(
            title: Text('Required courses (${required.length})'),
            initiallyExpanded: groups.isEmpty && rules.isEmpty,
            children: [
              for (final semester in degree.semesters) ...[
                ListTile(dense: true, title: Text('S$semester', style: HouseStyle.label)),
                ..._tiles(required.where((entry) => entry['semester'] == semester)),
              ],
              if (required.any((entry) => entry['semester'] == null)) ...[
                const ListTile(dense: true, title: Text('No fixed term', style: HouseStyle.label)),
                ..._tiles(required.where((entry) => entry['semester'] == null)),
              ],
            ],
          ),
        if (groups.isNotEmpty || rules.isNotEmpty)
          ExpansionTile(
            title: const Text('Electives and requirement choices'),
            initiallyExpanded: true,
            children: [
              for (final name in {...rules.keys, ...groups.keys})
                if (groups[name] case final entries?)
                  ExpansionTile(
                    title: Text('$name (${entries.length})'),
                    subtitle: rules[name] == null ? null : Text(rules[name]!),
                    children: _tiles(entries),
                  )
                else
                  ListTile(title: Text(name), subtitle: Text(rules[name]!)),
            ],
          ),
      ],
    );
  }
}

class SubjectPage extends ConsumerWidget {
  const SubjectPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AtlasBody((a) {
        final lang = ref.watch(langProvider);
        final s = a.subjects[id];
        return Scaffold(
          appBar: dragBar(context, 'Degree Atlas', actions: [
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'), icon: const Icon(Icons.arrow_back)),
          ]),
          body: s == null
              ? const Center(child: Text('Unknown subject'))
              : CourseNotebook(
                  key: ValueKey(s.id),
                  title: s.title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.summary.isNotEmpty) Text(s.summary),
                      if (s.prereqs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: HouseStyle.spacing),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: HouseStyle.spacing,
                            children: [
                              const Text('Requires'),
                              for (final r in s.prereqs)
                                TextButton(
                                  onPressed: () => context.push('/subject/$r'),
                                  style: TextButton.styleFrom(foregroundColor: HouseStyle.pen),
                                  child: Text(a.subjects[r]?.title ?? r),
                                ),
                            ],
                          ),
                        ),
                      const Divider(height: 32, color: HouseStyle.margin),
                      for (var n = 0; n < 4; n++) levelCell(s, n, lang),
                    ],
                  ),
                ),
        );
      });

  Widget levelCell(Subject s, int n, String lang) {
    const names = ['L0 · ELI5', 'L1 · Basics', 'L2 · Master crash course', 'L3 · Research frontier'];
    final text = s.levelText(n, lang: lang);
    final state = s.levelState(n);
    return ExpansionTile(
      key: PageStorageKey('${s.id}-$n'),
      title: Text(names[n]),
      subtitle: Text(state == 'none' ? 'not generated' : 'ready'),
      shape: const Border(),
      initiallyExpanded: n == 0 && text != null,
      enabled: text != null,
      children: [
        if (text != null && n == 0) Align(alignment: Alignment.centerLeft, child: ReadToggle(s.id)),
        if (text != null)
          Padding(
            padding: const EdgeInsets.only(bottom: HouseStyle.spacing * 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Md(text, s.dir, courseTitle: s.title),
              SourcesList(s.levelSources(n)),
            ]),
          ),
      ],
    );
  }
}

/// Opens an http(s) link in the default browser. The URL is handed to the OS as a single argument, never
/// through a shell, so text in agent-written files cannot run commands.
void openUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return;
  if (Platform.isWindows) {
    Process.run('rundll32', ['url.dll,FileProtocolHandler', u.toString()]).ignore();
  } else {
    Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [u.toString()]).ignore();
  }
}

/// Numbered reference list under a level; the numbers match the level's inline [n] citations.
class SourcesList extends StatelessWidget {
  const SourcesList(this.sources, {super.key});
  final List<Map<String, dynamic>> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: HouseStyle.spacing * 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sources', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: HouseStyle.spacing),
        for (final (i, s) in sources.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('[${i + 1}] ${s['title'] ?? 'Untitled source'}'),
              if (s['url'] is String)
                InkWell(
                  onTap: () => openUrl(s['url']),
                  child: Text(s['url'], style: const TextStyle(color: HouseStyle.pen, decoration: TextDecoration.underline)),
                ),
              if (s['file'] is String)
                Text('${s['file']}${s['pages'] == null ? '' : ', ${s['pages']}'}',
                    style: const TextStyle(color: HouseStyle.graphite)),
            ]),
          ),
      ]),
    );
  }
}

class Md extends StatelessWidget {
  const Md(this.data, this.dir, {super.key, this.courseTitle, this.selectable = true});
  final String data;
  final Directory dir;
  final String? courseTitle;
  final bool selectable; // false when an enclosing SelectionArea handles selection

  String get _body {
    final title = courseTitle;
    if (title == null) return data;
    // The notebook already presents the heading for this course.
    final heading = RegExp(
      '^(?:[ \\t]*\\r?\\n)*# +${RegExp.escape(title)}(?: +\\(L[0-3]\\))? *\\r?\\n',
      caseSensitive: false,
    );
    final match = heading.matchAsPrefix(data);
    if (match == null) return data;
    return data.substring(match.end).replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '');
  }

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: _body,
        selectable: selectable,
        onTapLink: (_, href, _) => href == null ? null : openUrl(href),
        builders: {'latex': LatexElementBuilder()},
        extensionSet: md.ExtensionSet([...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
            [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()]),
        styleSheet: MarkdownStyleSheet(
          h1: Theme.of(context).textTheme.headlineMedium,
          h2: Theme.of(context).textTheme.titleLarge,
          a: TextStyle(color: courseTitle == null ? accent : HouseStyle.pen),
        ),
        // figures/ SVGs are referenced relatively, so resolve against the subject folder
        imageBuilder: (uri, _, _) => uri.path.endsWith('.svg')
            ? SvgPicture.file(File(p.join(dir.path, uri.toFilePath())))
            : Image.file(File(p.join(dir.path, uri.toFilePath()))),
      );
}

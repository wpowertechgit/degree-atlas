import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'radial.dart';

const accent = Color(0xFFB3261E);
const paper = Color(0xFFFAF8F3);

/// Data folder: DEGREE_ATLAS_DATA, else ./data or ../data relative to the working dir.
Directory dataDir() {
  final env = Platform.environment['DEGREE_ATLAS_DATA'];
  if (env != null) return Directory(env);
  for (final c in ['data', '../data', r'C:\dev\tanuloprogi\data']) {
    if (Directory(c).existsSync()) return Directory(c);
  }
  return Directory('data');
}

class Subject {
  Subject(this.meta, this.dir);
  final Map<String, dynamic> meta;
  final Directory dir;
  String get id => meta['id'];
  String get title => meta['title'];
  String get summary => meta['summary'] ?? '';
  List<String> get prereqs => List<String>.from(meta['prerequisites'] ?? []);
  String levelState(int n) => meta['levels']?['L$n']?['state'] ?? 'none';
  String? levelText(int n) {
    final f = File(p.join(dir.path, 'L$n.md'));
    return f.existsSync() ? f.readAsStringSync() : null;
  }
}

class Degree {
  Degree(this.id, this.title, this.level, this.subjects);
  final String id, title, level;
  final List<Map<String, dynamic>> subjects;
}

class Atlas {
  Atlas(this.subjects, this.degrees, this.domains);
  final Map<String, Subject> subjects;
  final List<Degree> degrees;
  final Map<String, List<String>> domains; // domain title -> degree ids
}

Atlas loadAtlas() {
  final root = dataDir();
  final subjects = <String, Subject>{};
  final sd = Directory(p.join(root.path, 'subjects'));
  if (sd.existsSync()) {
    for (final d in sd.listSync().whereType<Directory>()) {
      final f = File(p.join(d.path, 'meta.json'));
      if (f.existsSync()) {
        final s = Subject(jsonDecode(f.readAsStringSync()), d);
        subjects[s.id] = s;
      }
    }
  }
  final degrees = <Degree>[];
  final dd = Directory(p.join(root.path, 'degrees'));
  if (dd.existsSync()) {
    for (final f in dd.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final j = jsonDecode(f.readAsStringSync());
      degrees.add(Degree(j['id'], j['title'], j['level'],
          List<Map<String, dynamic>>.from(j['subjects'])));
    }
  }
  degrees.sort((a, b) => a.title.compareTo(b.title));
  final domains = <String, List<String>>{};
  final dm = Directory(p.join(root.path, 'domains'));
  if (dm.existsSync()) {
    for (final f in dm.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final j = jsonDecode(f.readAsStringSync());
      domains[j['title']] = List<String>.from(j['degrees']);
    }
  }
  return Atlas(subjects, degrees, domains);
}

/// Reloads whenever anything under data/ changes.
final atlasProvider = StreamProvider<Atlas>((ref) {
  final c = StreamController<Atlas>();
  c.add(loadAtlas());
  Timer? debounce;
  // Only structural files matter; L*.md writes are read lazily when a page opens.
  final sub = DirectoryWatcher(dataDir().absolute.path)
      .events
      .where((e) => e.path.endsWith('meta.json') || e.path.contains('degrees') || e.path.contains('domains'))
      .listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 10), () => c.add(loadAtlas()));
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
  }
  runApp(const ProviderScope(child: App()));
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
    final sans = GoogleFonts.notoSansTextTheme(base.textTheme).apply(bodyColor: Colors.black87, displayColor: Colors.black87);
    final theme = base.copyWith(
      textTheme: sans.copyWith(
        headlineMedium: GoogleFonts.notoSerif(fontWeight: FontWeight.w300, fontSize: 30, color: Colors.black87),
        titleLarge: GoogleFonts.notoSerif(fontWeight: FontWeight.w300, fontSize: 22, color: Colors.black87),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: paper, elevation: 0, scrolledUnderElevation: 0),
      dividerColor: Colors.black12,
    );
    return MaterialApp.router(
        title: 'Degree Atlas', theme: theme, routerConfig: _router, debugShowCheckedModeBanner: false);
  }
}

PreferredSizeWidget dragBar(BuildContext context, String title, {List<Widget> actions = const []}) {
  return AppBar(
    title: DragToMoveArea(
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: toggleMaximize,
            child: SizedBox(width: double.infinity, child: Text(title, style: Theme.of(context).textTheme.titleLarge)))),
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
              subtitle: Text('${d.level} · ${d.subjects.length} subjects'),
              shape: const Border(),
              children: [
                for (final e in ([...d.subjects]..sort((x, y) => (x['semester'] as int).compareTo(y['semester'] as int))))
                  if (a.subjects[e['subject']] != null) subjectTile(context, a.subjects[e['subject']]!, 'S${e['semester']}'),
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

class SubjectPage extends StatelessWidget {
  const SubjectPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => AtlasBody((a) {
        final s = a.subjects[id];
        return Scaffold(
          appBar: dragBar(context, s?.title ?? id, actions: [
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'), icon: const Icon(Icons.arrow_back)),
          ]),
          body: s == null
              ? const Center(child: Text('Unknown subject'))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  children: [
                    Text(s.summary),
                    if (s.prereqs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 8, children: [
                          const Text('Requires:'),
                          for (final r in s.prereqs)
                            InkWell(
                                onTap: () => context.push('/subject/$r'),
                                child: Text(a.subjects[r]?.title ?? r, style: const TextStyle(color: accent))),
                        ]),
                      ),
                    const Divider(height: 32),
                    for (var n = 0; n < 4; n++) levelCell(s, n),
                  ],
                ),
        );
      });

  Widget levelCell(Subject s, int n) {
    const names = ['L0 · ELI5', 'L1 · Basics', 'L2 · Master crash course', 'L3 · Research frontier'];
    final text = s.levelText(n);
    final state = s.levelState(n);
    return ExpansionTile(
      key: PageStorageKey('${s.id}-$n'),
      title: Text(names[n]),
      subtitle: Text(state == 'verified' ? 'verified' : state == 'done' ? 'unverified' : 'not generated'),
      shape: const Border(),
      initiallyExpanded: n == 0 && text != null,
      enabled: text != null,
      children: [
        if (text != null && n == 0) Align(alignment: Alignment.centerLeft, child: ReadToggle(s.id)),
        if (text != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Md(text, s.dir)),
      ],
    );
  }
}

class Md extends StatelessWidget {
  const Md(this.data, this.dir, {super.key});
  final String data;
  final Directory dir;
  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: data,
        selectable: true,
        builders: {'latex': LatexElementBuilder()},
        extensionSet: md.ExtensionSet([...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
            [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()]),
        styleSheet: MarkdownStyleSheet(
          h1: Theme.of(context).textTheme.headlineMedium,
          h2: Theme.of(context).textTheme.titleLarge,
          a: const TextStyle(color: accent),
        ),
        // figures/ SVGs are referenced relatively, so resolve against the subject folder
        imageBuilder: (uri, _, _) => uri.path.endsWith('.svg')
            ? SvgPicture.file(File(p.join(dir.path, uri.toFilePath())))
            : Image.file(File(p.join(dir.path, uri.toFilePath()))),
      );
}

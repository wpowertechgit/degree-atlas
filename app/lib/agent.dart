import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'claude_connection.dart';
import 'main.dart' show Md, Subject, accent, activeProfile, dataDir, repoRoot;

enum Role { user, assistant, tool, error }

class Msg {
  Msg(this.role, this.text);
  final Role role;
  String text;
}

class AgentState {
  const AgentState({this.msgs = const [], this.busy = false, this.model = 'sonnet'});
  final List<Msg> msgs;
  final bool busy;
  final String model;
  AgentState copyWith({List<Msg>? msgs, bool? busy, String? model}) =>
      AgentState(msgs: msgs ?? this.msgs, busy: busy ?? this.busy, model: model ?? this.model);
}

String _systemPrompt(String profileRoot, bool profile) =>
    'You are driven from the Degree Atlas desktop app; the user reads a small chat panel. '
    'Follow AGENTS.md exactly. Do the task without asking for confirmation. '
    'Do not narrate: no plans, no status updates, no commentary between tool calls, no caveats. '
    'Run subagents in the foreground and never poll or wait on background work. '
    'Your only text output is one final message of at most three short lines stating the result. '
    'Paths such as data/, work/ and progress.json in AGENTS.md and in user messages are relative to the active profile folder '
    '$profileRoot${profile ? ' (the scripts read it from the DEGREE_ATLAS_PROFILE environment variable)' : ''}.';

/// The agent process currently running, so the app can end it when the window closes.
Process? _running;

/// Ends [proc] and everything it started (tool commands, scripts, subagents).
/// On Windows `Process.kill` ends only the top process, which would orphan its children
/// (and with `runInShell` it would end only the shell, leaving `claude` itself running).
Future<void> _killTree(Process proc) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);
  } else {
    proc.kill();
  }
}

/// Ends the running agent, if any. Called before the app window closes.
Future<void> killRunningAgent() async {
  final proc = _running;
  _running = null;
  if (proc != null) await _killTree(proc);
}

/// One long-lived `claude` process speaking stream-json, with all permissions bypassed.
/// The session id is kept in work/agent_session.txt so the conversation survives app restarts.
class AgentNotifier extends Notifier<AgentState> {
  /// Older messages are dropped from the panel; long runs produce one tool line per call.
  static const _maxMsgs = 400;

  Process? _proc;
  List<StreamSubscription<String>> _subs = [];
  String? _session;
  Msg? _live; // assistant message currently streaming
  int _pending = 0; // user messages not yet answered by a result event

  String get _root => dataDir().absolute.parent.path;
  File get _sessionFile => File(p.join(_root, 'work', 'agent_session.txt'));

  @override
  AgentState build() {
    ref.onDispose(_kill);
    if (_sessionFile.existsSync()) _session = _sessionFile.readAsStringSync().trim();
    return const AgentState();
  }

  /// Stops the current process tree and its output streams, so a stopped agent cannot write into the chat.
  void _kill() {
    final proc = _proc;
    _proc = null;
    _live = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs = [];
    if (proc == null) return;
    if (identical(_running, proc)) _running = null;
    unawaited(_killTree(proc));
  }

  Msg _push(Role r, String text) {
    final m = Msg(r, text);
    var msgs = [...state.msgs, m];
    if (msgs.length > _maxMsgs) msgs = msgs.sublist(msgs.length - _maxMsgs);
    state = state.copyWith(msgs: msgs);
    return m;
  }

  void _touch({bool? busy}) => state = state.copyWith(msgs: List.of(state.msgs), busy: busy);

  void _saveSession(String? id) {
    if (id == null || id == _session) return;
    _session = id;
    _sessionFile.parent.createSync(recursive: true);
    _sessionFile.writeAsStringSync(id);
  }

  void _forgetSession() {
    _session = null;
    if (_sessionFile.existsSync()) _sessionFile.deleteSync();
  }

  Future<void> _start() async {
    final (exe, shell) = claudeExe();
    final proc = await Process.start(
      exe,
      [
        '-p',
        '--input-format', 'stream-json',
        '--output-format', 'stream-json',
        '--include-partial-messages',
        '--verbose',
        '--permission-mode', 'bypassPermissions',
        '--model', state.model,
        '--append-system-prompt', _systemPrompt(_root, activeProfile != null),
        if (_session != null) ...['--resume', _session!],
      ],
      workingDirectory: repoRoot().path,
      environment: {if (activeProfile != null) 'DEGREE_ATLAS_PROFILE': _root},
      runInShell: shell,
    );
    _proc = proc;
    _running = proc;
    var err = ''; // only the tail is kept for the error message
    _subs = [
      proc.stderr.transform(utf8.decoder).listen((s) {
        err += s;
        if (err.length > 4000) err = err.substring(err.length - 2000);
      }),
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine),
    ];
    unawaited(proc.exitCode.then((code) {
      if (identical(_running, proc)) _running = null;
      if (_proc != proc) return; // killed on purpose
      _proc = null;
      _live = null;
      if (_pending > 0 || code != 0) {
        final tail = err.trim();
        _push(Role.error, 'Agent exited ($code). ${tail.length > 300 ? tail.substring(tail.length - 300) : tail}');
        _forgetSession(); // a stale session id is the usual cause; the next message starts fresh
      }
      _pending = 0;
      _touch(busy: false);
    }));
  }

  void _onLine(String line) {
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(line);
    } on FormatException {
      return;
    }
    switch (e['type']) {
      case 'system':
        if (e['subtype'] == 'init') _saveSession(e['session_id']);
      case 'stream_event':
        if (e['parent_tool_use_id'] != null) return; // subagent chatter
        final ev = e['event'];
        if (ev['type'] == 'content_block_delta' && ev['delta']['type'] == 'text_delta') {
          _live ??= _push(Role.assistant, '');
          _live!.text += ev['delta']['text'] as String;
          _touch();
        } else if (ev['type'] == 'message_stop') {
          _live = null;
        }
      case 'assistant':
        for (final b in (e['message']['content'] as List)) {
          if (b['type'] == 'tool_use') _push(Role.tool, _describe(b));
        }
      case 'result':
        _saveSession(e['session_id']);
        _live = null;
        if (e['is_error'] == true) _push(Role.error, '${e['result'] ?? 'Agent error'}');
        _pending = (_pending - 1).clamp(0, 1 << 30);
        _touch(busy: _pending > 0);
    }
  }

  String _describe(Map b) {
    final name = b['name'] as String;
    final i = (b['input'] ?? {}) as Map;
    String short(Object? s) {
      final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
      return t.length > 110 ? '${t.substring(0, 110)}…' : t;
    }

    final hint = i['command'] ?? i['file_path'] ?? i['query'] ?? i['url'] ?? i['pattern'] ?? i['description'];
    if (hint == null) return name;
    final h = i['file_path'] != null ? p.basename('${i['file_path']}') : short(hint);
    return '$name  $h';
  }

  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    try {
      if (_proc == null) await _start();
    } on ProcessException catch (e) {
      _push(Role.error, 'Could not start claude: ${e.message}');
      return;
    }
    _push(Role.user, text);
    _pending++;
    _touch(busy: true);
    _proc!.stdin.writeln(jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
    }));
  }

  /// Interrupts the current work; the conversation continues from the saved session on the next message.
  void stop() {
    _kill();
    _pending = 0;
    if (state.busy) _push(Role.tool, 'Stopped');
    _touch(busy: false);
  }

  void setModel(String m) {
    if (state.busy) return;
    _kill();
    state = state.copyWith(model: m);
  }

  void newChat() {
    stop();
    _forgetSession();
    state = AgentState(model: state.model);
  }

  String _file(Subject s, int n, String lang) => lang == 'en' ? 'L$n.md' : 'L$n.$lang.md';

  /// Writes the English level if missing; for another language also produces the translation.
  void requestLevel(Subject s, int n, {String lang = 'en'}) => send(
      'Write L$n for subject `${s.id}` (${s.title}). Follow AGENTS.md: check with `python scripts/next.py L$n`, '
      'write any missing prerequisite levels first, then run validate.py.'
      '${lang == 'en' ? '' : ' Afterwards also write the ${languages[lang]} version as ${_file(s, n, lang)} (AGENTS.md, Languages).'}');

  void requestTranslation(Subject s, int n, String lang) => send(
      'Translate L$n of `${s.id}` into ${languages[lang]}: write data/subjects/${s.id}/${_file(s, n, lang)} from L$n.md '
      'following AGENTS.md (Languages). Do not change sources.json or meta.json.');

  /// The user asked for a fresh version, which overrides the "never regenerate" rule in AGENTS.md.
  void regenerate(Subject s, int n, String lang) => send(lang == 'en'
      ? 'The user asked to regenerate L$n of `${s.id}` (${s.title}) from scratch; this overrides the never-regenerate rule. '
          'Follow AGENTS.md as for a new write, replace the entries of this level in sources.json, run validate.py, then re-translate '
          'every existing L$n.<lang>.md from the new English text.'
      : 'The user asked to redo the ${languages[lang]} version of L$n of `${s.id}`: rewrite ${_file(s, n, lang)} from the current '
          'L$n.md (AGENTS.md, Languages). Do not change the English file.');

  /// Prompt (not sent) asking for exercises of [s]; with [more] it adds new ones to an existing file.
  String exercisesRequest(Subject s, String lang, {bool more = false}) =>
      '${more ? 'Add about 6 new exercises to' : 'Write exercises for'} subject `${s.id}` (${s.title}) following AGENTS.md (Exercises): '
      'data/subjects/${s.id}/exercises.json for every written level L1-L3, verify every numeric answer by running it, then run validate.py.'
      '${lang == 'en' ? '' : ' Afterwards also write exercises.$lang.json in ${languages[lang]} with the same ids, types and answer keys.'}';

  String exercisesTranslationRequest(Subject s, String lang) =>
      'Translate data/subjects/${s.id}/exercises.json into ${languages[lang]} as exercises.$lang.json following AGENTS.md (Exercises): '
      'same ids, levels, types and answer keys for multiple choice and numeric items, translated prompts, choices, hints and solutions. Run validate.py.';

  void continueLevel(int n) => send(
      'Run `python scripts/next.py L$n -n 5` and write every READY subject it lists, following AGENTS.md. '
      'Validate after the batch, then report what you wrote.');

  void fix(Subject s, int n, String lang, String problem) => send(
      'Fix ${_file(s, n, lang)} of `${s.id}` (${s.title}). Problem reported by the user: "$problem". '
      'Edit the existing file minimally to resolve it, check the rest of the file for the same kind of problem, '
      'and apply the same fix to the other language versions of this level if they exist. Run validate.py.');
}

const languages = {
  'en': 'English',
  'hu': 'Hungarian',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'pl': 'Polish',
  'nl': 'Dutch',
  'ru': 'Russian',
  'zh': 'Chinese',
  'ja': 'Japanese',
};

/// Reading and generation language, kept in settings.json next to data/ (personal, gitignored).
class LangNotifier extends Notifier<String> {
  File get _f => File(p.join(dataDir().absolute.parent.path, 'settings.json'));

  @override
  String build() {
    try {
      final l = jsonDecode(_f.readAsStringSync())['language'];
      if (languages.containsKey(l)) return l;
    } catch (_) {}
    return 'en';
  }

  void set(String code) {
    state = code;
    _f.writeAsStringSync(jsonEncode({'language': code}));
  }
}

final langProvider = NotifierProvider<LangNotifier, String>(LangNotifier.new);

final agentProvider = NotifierProvider<AgentNotifier, AgentState>(AgentNotifier.new);

class AgentOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final agentOpenProvider = NotifierProvider<AgentOpen, bool>(AgentOpen.new);

class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key});
  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<AgentPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text;
    _ctrl.clear();
    ref.read(agentProvider.notifier).send(t);
  }

  Widget _tile(Msg m) {
    switch (m.role) {
      case Role.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 40, top: 6, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF4DEDB), borderRadius: BorderRadius.circular(8)),
            child: Text(m.text, style: const TextStyle(fontSize: 13)),
          ),
        );
      case Role.assistant:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Md(m.text, dataDir(), selectable: false));
      case Role.tool:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('› ${m.text}',
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 11, color: Colors.black54)),
        );
      case Role.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(m.text, style: const TextStyle(fontSize: 12, color: accent)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(agentProvider);
    final agent = ref.read(agentProvider.notifier);
    return Container(
      width: 390,
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: Color(0x22000000)))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
          child: Row(children: [
            const Text('Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            DropdownButton<String>(
              value: s.model,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: const [
                DropdownMenuItem(value: 'haiku', child: Text('haiku')),
                DropdownMenuItem(value: 'sonnet', child: Text('sonnet')),
                DropdownMenuItem(value: 'opus', child: Text('opus')),
              ],
              onChanged: s.busy ? null : (v) => agent.setModel(v!),
            ),
            IconButton(
                tooltip: 'Copy chat',
                onPressed: () => Clipboard.setData(ClipboardData(
                    text: s.msgs.map((m) => m.role == Role.tool ? '> ${m.text}' : m.text).join('\n\n'))),
                icon: const Icon(Icons.copy_all_outlined, size: 20)),
            IconButton(
                tooltip: 'Claude connection',
                onPressed: () => showDialog(context: context, builder: (_) => const ClaudeConnectionDialog()),
                icon: const Icon(Icons.link, size: 20)),
            IconButton(tooltip: 'New chat', onPressed: agent.newChat, icon: const Icon(Icons.add_comment_outlined, size: 20)),
            IconButton(
                tooltip: 'Close',
                onPressed: () => ref.read(agentOpenProvider.notifier).set(false),
                icon: const Icon(Icons.close, size: 20)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 6, children: [
            for (final n in [0, 1, 2, 3])
              ActionChip(
                  label: Text('Next L$n', style: const TextStyle(fontSize: 11.5, color: Colors.black87)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => agent.continueLevel(n)),
          ]),
        ),
        const Divider(height: 12),
        Expanded(
          child: s.msgs.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Ask the agent to write levels, or use "Write L1 with agent" on a subject. It works in this repo and the atlas updates as files change.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13)),
                ))
              // Reversed and lazy: stays pinned to the newest message and builds only visible tiles.
              : SelectionArea(
                  child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: s.msgs.length,
                      itemBuilder: (_, i) => _tile(s.msgs[s.msgs.length - 1 - i]))),
        ),
        // Own layer: the indeterminate bar animates every frame and must not repaint the chat with it.
        if (s.busy) const RepaintBoundary(child: LinearProgressIndicator(minHeight: 2)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                decoration: const InputDecoration(hintText: 'Message the agent', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) => _send(),
              ),
            ),
            if (s.busy)
              IconButton(tooltip: 'Stop', onPressed: agent.stop, icon: const Icon(Icons.stop_circle_outlined, color: accent))
            else
              IconButton(tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.send, size: 20)),
          ]),
        ),
      ]),
    );
  }
}

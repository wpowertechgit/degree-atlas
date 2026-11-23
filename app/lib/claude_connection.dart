import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

/// Path of the `claude` CLI and whether it must run through the shell (PATH lookup on Windows).
(String, bool) claudeExe() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final f = File(p.join(home, '.local', 'bin', Platform.isWindows ? 'claude.exe' : 'claude'));
  return f.existsSync() ? (f.path, false) : ('claude', Platform.isWindows);
}

/// Shows the state of the local `claude` CLI and lets the user sign in, sign out or test the connection.
class ClaudeConnectionDialog extends StatefulWidget {
  const ClaudeConnectionDialog({super.key});
  @override
  State<ClaudeConnectionDialog> createState() => _ClaudeConnectionDialogState();
}

class _ClaudeConnectionDialogState extends State<ClaudeConnectionDialog> {
  String version = '…', status = 'Checking…', log = '';
  bool? loggedIn; // null: CLI missing
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<ProcessResult> _run(List<String> args) {
    final (exe, shell) = claudeExe();
    return Process.run(exe, args, runInShell: shell, stdoutEncoding: utf8, stderrEncoding: utf8);
  }

  Future<void> _refresh() async {
    try {
      final v = await _run(['--version']);
      final s = await _run(['auth', 'status', '--json']);
      Map<String, dynamic> j = {};
      try {
        j = jsonDecode(s.stdout as String);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        version = (v.stdout as String).trim();
        loggedIn = j['loggedIn'] == true;
        status = loggedIn! ? 'Signed in with ${j['authMethod']}${j['email'] != null ? ' as ${j['email']}' : ''}' : 'Not signed in';
      });
    } on ProcessException {
      if (!mounted) return;
      setState(() {
        version = 'not installed';
        loggedIn = null;
        status = 'The claude CLI was not found. Install Claude Code (https://claude.com/claude-code) and reopen this window.';
      });
    }
  }

  Future<void> _go(Future<String> Function() job) async {
    setState(() {
      busy = true;
      log = '';
    });
    String out;
    try {
      out = await job();
    } catch (e) {
      out = '$e';
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      log = out.trim();
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Claude connection'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('CLI: $version\n$status', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton(
                onPressed: busy || loggedIn == null
                    ? null
                    : () => _go(() async {
                          // opens the browser sign-in and returns when it finishes
                          final r = await _run(['auth', 'login']);
                          return '${r.stdout}${r.stderr}';
                        }),
                child: Text(loggedIn == true ? 'Sign in again' : 'Sign in'),
              ),
              OutlinedButton(
                onPressed: busy || loggedIn != true
                    ? null
                    : () => _go(() async {
                          final r = await _run(['-p', 'Reply with the single word ok.']).timeout(const Duration(seconds: 90));
                          return r.exitCode == 0 ? 'Test reply: ${r.stdout}' : 'Test failed: ${r.stderr}';
                        }),
                child: const Text('Test connection'),
              ),
              if (loggedIn == true)
                TextButton(
                    onPressed: busy ? null : () => _go(() async => '${(await _run(['auth', 'logout'])).stdout}'),
                    child: const Text('Sign out')),
            ]),
            if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (log.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(log, style: const TextStyle(fontSize: 12))),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}

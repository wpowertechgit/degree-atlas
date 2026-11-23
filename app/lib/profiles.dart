import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent.dart' show agentOpenProvider;
import 'main.dart';

/// A profile is a separate data set under `profiles/<name>/` (data/, work/, progress.json, settings.json).
/// With no profile active the app uses the repository's own data/ folder.
final _nameRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$');

Directory _profilesDir() => Directory(p.join(repoRoot().path, 'profiles'));
File _activeFile() => File(p.join(_profilesDir().path, 'active.txt'));

String? readActiveProfile() {
  try {
    final n = _activeFile().readAsStringSync().trim();
    return n.isNotEmpty && Directory(p.join(_profilesDir().path, n)).existsSync() ? n : null;
  } on FileSystemException {
    return null;
  }
}

List<String> listProfiles() {
  final d = _profilesDir();
  if (!d.existsSync()) return [];
  return [for (final e in d.listSync().whereType<Directory>()) p.basename(e.path)]..sort();
}

String? validateProfileName(String name) {
  if (!_nameRe.hasMatch(name)) return 'Use lowercase letters, digits and dashes';
  if (listProfiles().contains(name)) return 'Already exists';
  return null;
}

/// Creates an empty profile that only contains the domain files of the repository's data set.
void createProfile(String name) {
  final root = Directory(p.join(_profilesDir().path, name));
  final data = p.join(root.path, 'data');
  for (final sub in ['domains', 'degrees', 'subjects']) {
    Directory(p.join(data, sub)).createSync(recursive: true);
  }
  Directory(p.join(root.path, 'work')).createSync();
  final src = Directory(p.join(baseDataDir().path, 'domains'));
  if (src.existsSync()) {
    for (final f in src.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      f.copySync(p.join(data, 'domains', p.basename(f.path)));
    }
  }
}

/// Shown from anywhere, also after the widget tree was rebuilt by a profile switch.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void _say(String text) => messengerKey.currentState
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Windows refuses to rename or delete a folder that a process still holds open (the file watcher, the agent).
/// Switching to the default data set first disposes all of them.
Future<void> _release() async {
  switchProfile(null);
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

Future<void> _retry(void Function() op) async {
  for (var i = 0;; i++) {
    try {
      op();
      return;
    } on FileSystemException {
      if (i == 5) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
}

/// Renames a profile folder and opens it under its new name.
Future<void> renameProfile(String from, String to) async {
  await _release();
  try {
    await _retry(() => Directory(p.join(_profilesDir().path, from)).renameSync(p.join(_profilesDir().path, to)));
    switchProfile(to);
  } on FileSystemException catch (e) {
    switchProfile(from);
    _say('Rename failed: ${e.osError?.message ?? e.message}');
  }
}

/// Deletes a profile folder with everything in it and stays on the default data set.
Future<void> deleteProfile(String name) async {
  await _release();
  try {
    await _retry(() {
      final d = Directory(p.join(_profilesDir().path, name));
      if (d.existsSync()) d.deleteSync(recursive: true);
    });
  } on FileSystemException catch (e) {
    _say('Delete failed: ${e.osError?.message ?? e.message}');
  }
}

/// Bumped on every switch; [ProfileScope] rebuilds all providers (and stops the agent process) when it changes.
final _reload = ValueNotifier<int>(0);

/// Set while the empty-profile hint is on screen; the atlas then plays its intro when content arrives.
bool emptyProfileShown = false;

void switchProfile(String? name) {
  emptyProfileShown = false;
  activeProfile = name;
  _profilesDir().createSync(recursive: true);
  _activeFile().writeAsStringSync(name ?? '');
  _reload.value++;
}

class ProfileScope extends StatelessWidget {
  const ProfileScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _reload,
        builder: (_, n, _) => ProviderScope(key: ValueKey(n), child: child),
      );
}

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NewProfileDialog());
    if (name == null) return;
    createProfile(name);
    switchProfile(name);
  }

  Future<void> _rename(BuildContext context, String name) async {
    final to = await showDialog<String>(context: context, builder: (_) => _NewProfileDialog(rename: name));
    if (to != null) renameProfile(name, to);
  }

  Future<void> _delete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete profile "$name"?'),
        content: const Text('All its subjects, levels, progress and chat history are removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) deleteProfile(name);
  }

  @override
  Widget build(BuildContext context) {
    // listens to profile switches so the label follows, and reads the folders each time the menu opens
    return ValueListenableBuilder<int>(valueListenable: _reload, builder: (_, _, _) => _menu(context));
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      onSelected: (v) {
        if (v == '\u0000new') {
          _create(context);
        } else if (v == '\u0000rename') {
          _rename(context, activeProfile!);
        } else if (v == '\u0000delete') {
          _delete(context, activeProfile!);
        } else {
          switchProfile(v.isEmpty ? null : v);
        }
      },
      itemBuilder: (_) => [
        for (final n in ['', ...listProfiles()])
          CheckedPopupMenuItem(value: n, checked: (activeProfile ?? '') == n, child: Text(n.isEmpty ? 'default' : n)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '\u0000new', child: Text('New empty profile…')),
        if (activeProfile != null) PopupMenuItem(value: '\u0000rename', child: Text('Rename "$activeProfile"…')),
        if (activeProfile != null) PopupMenuItem(value: '\u0000delete', child: Text('Delete "$activeProfile"…')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_outlined, size: 18),
          const SizedBox(width: 6),
          Text(activeProfile ?? 'default', style: const TextStyle(fontSize: 13)),
        ]),
      ),
    );
  }
}

class _NewProfileDialog extends StatefulWidget {
  const _NewProfileDialog({this.rename});
  final String? rename; // current name when renaming
  @override
  State<_NewProfileDialog> createState() => _NewProfileDialogState();
}

class _NewProfileDialogState extends State<_NewProfileDialog> {
  final c = TextEditingController();
  String? get _error => c.text.isEmpty ? null : validateProfileName(c.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.rename == null ? 'New empty profile' : 'Rename "${widget.rename}"'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.rename == null) ...[
            const Text('It starts with the domains only. Tell the agent what you want to learn and it builds the rest.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _ok(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: c.text.isNotEmpty && _error == null ? _ok : null, child: Text(widget.rename == null ? 'Create' : 'Rename')),
        ],
      );

  void _ok() {
    if (c.text.isNotEmpty && _error == null) Navigator.pop(context, c.text);
  }
}

/// Shown instead of the atlas while a profile has no content.
class EmptyProfileHint extends ConsumerStatefulWidget {
  const EmptyProfileHint({super.key});
  @override
  ConsumerState<EmptyProfileHint> createState() => _EmptyProfileHintState();
}

class _EmptyProfileHintState extends ConsumerState<EmptyProfileHint> {
  @override
  void initState() {
    super.initState();
    emptyProfileShown = true;
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Nothing here yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
                'Open the agent and tell it what you want to learn, for example "I want to learn material science". '
                'It looks up the real curriculum, builds the subjects and writes the levels. The map appears when it is done.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(agentOpenProvider.notifier).set(true),
              child: const Text('Open agent'),
            ),
          ]),
        ),
      );
}

/// In-app update check against the project's GitHub Releases (Windows, installed copies only).
///
/// A release is offered only when its tag is a higher version than [appVersion] and it carries the
/// installer asset with a GitHub-published SHA-256 digest. The download is hashed while it streams and is
/// refused on a missing or different digest. Git clones are told to update with git instead, because their
/// scripts and agent instructions come from the repository, not from the installer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent.dart' show killRunningAgent;
import 'profiles.dart' show messengerKey;

/// Stamped by the release build (`--dart-define=APP_VERSION=1.2.3`); empty in local builds, which never update.
const appVersion = String.fromEnvironment('APP_VERSION');
const updateRepository = 'wpowertechgit/degree-atlas';
const setupAssetPrefix = 'DegreeAtlas-Setup-';

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, required this.sha256});
  final String name;
  final Uri url;

  /// Lower-case hex SHA-256 from the GitHub digest; null when GitHub published none.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.setup});

  /// Tag without the leading `v`.
  final String version;

  /// The Windows installer, or null when the release has none.
  final UpdateAsset? setup;
}

/// Compares dotted numeric versions, with an optional leading `v`. Missing parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.replaceFirst(RegExp(r'^v'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// Reads one GitHub release object; null when it has no tag.
ReleaseInfo? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String || tag.isEmpty) return null;
  UpdateAsset? setup;
  for (final a in (json['assets'] as List?) ?? const []) {
    if (a is! Map) continue;
    final name = a['name'], url = a['browser_download_url'], digest = a['digest'];
    if (name is String && url is String && name.startsWith(setupAssetPrefix) && name.endsWith('.exe')) {
      setup = UpdateAsset(
        name: name,
        url: Uri.parse(url),
        sha256: digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
      );
    }
  }
  return ReleaseInfo(version: tag.replaceFirst(RegExp(r'^v'), ''), setup: setup);
}

/// Throws unless [actualHex] equals [expected]. A missing expected digest is refused as well.
void verifyDigest(String actualHex, String? expected) {
  if (expected == null || expected.isEmpty) throw UpdateException('The update has no checksum; not installing it.');
  if (actualHex != expected.toLowerCase()) throw UpdateException('The downloaded update is damaged (checksum mismatch).');
}

Future<HttpClientResponse> _get(HttpClient client, Uri url, String accept) async {
  final request = await client.getUrl(url);
  request.headers
    ..set(HttpHeaders.acceptHeader, accept)
    ..set(HttpHeaders.userAgentHeader, 'degree-atlas-updater'); // GitHub rejects requests without one
  return request.close();
}

/// The latest published release; null when there is none.
Future<ReleaseInfo?> latestRelease(HttpClient client, {String repository = updateRepository}) async {
  final response = await _get(client, Uri.https('api.github.com', '/repos/$repository/releases/latest'),
          'application/vnd.github+json')
      .timeout(const Duration(seconds: 20));
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) throw UpdateException('Update check failed (${response.statusCode}).');
  final json = jsonDecode(body);
  return json is Map<String, dynamic> ? parseRelease(json) : null;
}

/// Streams [asset] into [directory] while hashing it, then verifies the digest. A partial or damaged file is deleted.
Future<File> downloadUpdate(HttpClient client, UpdateAsset asset, Directory directory) async {
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, p.basename(asset.name)));
  final response = await _get(client, asset.url, 'application/octet-stream').timeout(const Duration(minutes: 1));
  if (response.statusCode != 200) {
    await response.drain<void>();
    throw UpdateException('Update download failed (${response.statusCode}).');
  }
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  final sink = file.openWrite();
  try {
    await for (final chunk in response.timeout(const Duration(minutes: 2))) {
      hasher.add(chunk);
      sink.add(chunk);
    }
    hasher.close();
    await sink.close();
    verifyDigest(digest.value.toString(), asset.sha256);
  } catch (_) {
    await sink.close().catchError((_) {});
    if (await file.exists()) await file.delete();
    rethrow;
  }
  return file;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// True for a copy installed by the Windows installer: the exe sits in `<install>\bin` next to the uninstaller.
bool get isInstalledCopy =>
    Platform.isWindows && File(p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'unins000.exe')).existsSync();

/// Looks for a newer release once per start and offers it in a snackbar. Never interrupts work by itself.
Future<void> checkForUpdate() async {
  if (appVersion.isEmpty) return; // local build
  final client = HttpClient();
  try {
    final release = await latestRelease(client);
    if (release == null || compareVersions(release.version, appVersion) <= 0) return;
    final setup = release.setup;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    if (!isInstalledCopy || setup == null) {
      messenger.showSnackBar(SnackBar(
        persist: true,
        showCloseIcon: true,
        content: Text('Degree Atlas ${release.version} is available. Update with `git pull` and '
            '`python scripts/setup.py`.'),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      persist: true,
      showCloseIcon: true,
      content: Text('Degree Atlas ${release.version} is available (you have $appVersion).'),
      action: SnackBarAction(label: 'Update', onPressed: () => unawaited(_install(setup))),
    ));
  } catch (_) {
    // offline or GitHub unavailable: try again next start
  } finally {
    client.close();
  }
}

/// Downloads and verifies the installer, ends the agent, starts the installer silently and quits.
/// The installer replaces the files (profiles and generated data stay) and starts the app again.
Future<void> _install(UpdateAsset setup) async {
  final messenger = messengerKey.currentState;
  messenger?.showSnackBar(const SnackBar(persist: true, content: Text('Downloading the update…')));
  final client = HttpClient();
  try {
    final file = await downloadUpdate(client, setup, Directory(p.join(Directory.systemTemp.path, 'degree-atlas-update')));
    await killRunningAgent();
    await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/RELAUNCH=1'],
        mode: ProcessStartMode.detached);
    exit(0); // the installer needs the exe closed to replace it
  } catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(showCloseIcon: true, content: Text('Update failed: $e')));
  } finally {
    client.close();
  }
}

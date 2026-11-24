import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:degree_atlas/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versions compare numerically', () {
    expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
    expect(compareVersions('v1.2', '1.2.0'), 0);
    expect(compareVersions('0.1.2', '0.2.0'), lessThan(0));
  });

  test('release parsing picks the setup asset and its digest', () {
    final r = parseRelease({
      'tag_name': 'v0.1.3',
      'assets': [
        {'name': 'degree-atlas-windows.zip', 'browser_download_url': 'https://x/zip', 'digest': 'sha256:aa'},
        {'name': 'DegreeAtlas-Setup-0.1.3.exe', 'browser_download_url': 'https://x/exe', 'digest': 'sha256:ABC'},
      ],
    })!;
    expect(r.version, '0.1.3');
    expect(r.setup!.url.toString(), 'https://x/exe');
    expect(r.setup!.sha256, 'abc');
    expect(parseRelease({'assets': []}), isNull);
  });

  group('download', () {
    late HttpServer server;
    late Directory dir;
    final bytes = List<int>.generate(300000, (i) => i % 251);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('updater_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => req.response
        ..add(bytes)
        ..close());
    });
    tearDown(() async {
      await server.close(force: true);
      dir.deleteSync(recursive: true);
    });

    UpdateAsset asset(String? digest) => UpdateAsset(
        name: 'DegreeAtlas-Setup-9.9.9.exe', url: Uri.parse('http://127.0.0.1:${server.port}/setup'), sha256: digest);

    test('a matching checksum keeps the file', () async {
      final client = HttpClient();
      final file = await downloadUpdate(client, asset(sha256.convert(bytes).toString()), dir);
      client.close();
      expect(file.readAsBytesSync(), bytes);
    });

    test('a wrong or missing checksum is refused and the file deleted', () async {
      for (final digest in ['0' * 64, null]) {
        final client = HttpClient();
        await expectLater(downloadUpdate(client, asset(digest), dir), throwsA(isA<UpdateException>()));
        client.close();
        expect(dir.listSync(), isEmpty);
      }
    });
  });
}

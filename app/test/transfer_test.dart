import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:degree_atlas/transfer.dart';

void main() {
  test('lzw round trips', () {
    final r = Random(1);
    final cases = <List<int>>[
      [],
      [65],
      [65, 65, 65, 65, 65, 65, 65, 65, 65],
      utf8.encode('TOBEORNOTTOBEORTOBEORNOT' * 50),
      utf8.encode('Mass transfer ∇·J = −D∇c — équations 方程 ' * 3000),
      List.generate(3000000, (_) => r.nextInt(256)), // more than 2^20 codes: exercises the dictionary cap
      List.generate(2000000, (_) => r.nextInt(4) * 60), // forces the dictionary to fill
    ];
    for (final c in cases) {
      final enc = lzwEncode(c);
      expect(lzwDecode(enc), Uint8List.fromList(c), reason: 'len ${c.length}');
    }
    final text = utf8.encode('Mass transfer is the movement of a substance. ' * 2000);
    // ignore: avoid_print
    print('ratio ${lzwEncode(text).length / text.length}');
  });

  test('export and import through a temp dir, rejecting escapes', () {
    final tmp = Directory.systemTemp.createTempSync('atlas');
    final data = Directory('${tmp.path}/data/subjects/x')..createSync(recursive: true);
    File('${data.path}/meta.json').writeAsStringSync('{"id":"x","title":"Équation"}');
    File('${data.path}/L0.md').writeAsStringSync('# X\n\n\$a^2\$ 方程');
    File('${tmp.path}/progress.json').writeAsStringSync('{"read":["x:L0"]}');
    final out = buildExport('${tmp.path}/data');
    expect(out.contains('\n'), false);
    final dst = Directory.systemTemp.createTempSync('atlas2');
    File('${dst.path}/progress.json').writeAsStringSync('{"read":["y:L0"]}');
    Directory('${dst.path}/data').createSync();
    final n = applyImport('${dst.path}/data', out);
    expect(n, 3);
    expect(File('${dst.path}/data/subjects/x/L0.md').readAsStringSync(), contains('方程'));
    expect(File('${dst.path}/progress.json').readAsStringSync(), allOf(contains('x:L0'), contains('y:L0')));
    tmp.deleteSync(recursive: true);
    dst.deleteSync(recursive: true);
  });
}

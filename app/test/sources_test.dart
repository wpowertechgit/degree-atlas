import 'dart:convert';
import 'dart:io';

import 'package:degree_atlas/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('levelSources keeps one level in citation order and survives a broken file', () {
    final dir = Directory.systemTemp.createTempSync('sources_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sources.json');
    file.writeAsStringSync(jsonEncode([
      {'level': 'L1', 'title': 'First', 'url': 'https://a.example'},
      {'level': 'L2', 'title': 'Other level', 'url': 'https://b.example'},
      {'level': 'L1', 'title': 'Second', 'file': 'materials/x/notes.pdf', 'pages': '3-5'},
    ]));
    final s = Subject({'id': 'x', 'title': 'X'}, dir);

    expect(s.levelSources(1).map((e) => e['title']), ['First', 'Second']);
    expect(s.levelSources(0), isEmpty);

    file.writeAsStringSync('[{"level": "L1", "tit'); // caught mid-write
    file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    expect(s.levelSources(1), isEmpty);
  });
}

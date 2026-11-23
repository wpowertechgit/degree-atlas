import 'dart:async';
import 'dart:io';
import 'package:degree_atlas/main.dart';
import 'package:degree_atlas/profiles.dart';
import 'package:degree_atlas/radial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Atlas full() {
  final dir = Directory('${dataDir().path}/subjects/x');
  Subject s(String id) => Subject({'id': id, 'title': id, 'prerequisites': [], 'levels': {'L0': {'state': 'done'}}}, dir);
  return Atlas(
    {'a': s('a'), 'b': s('b')},
    [
      Degree('own-net', 'Networking', 'BSc', [
        {'subject': 'a', 'semester': null, 'kind': 'mandatory', 'source': 'https://x'},
        {'subject': 'b', 'semester': null, 'kind': 'mandatory', 'source': 'https://x'},
      ])
    ],
    {'Computing': ['own-net'], 'Humanities': []},
  );
}

void main() {
  testWidgets('empty profile hides the graph, content plays the intro', (tester) async {
    activeProfile = 'p';
    final c = StreamController<Atlas>();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [atlasProvider.overrideWith((ref) => c.stream)],
      child: const MaterialApp(home: RadialPage()),
    ));
    c.add(Atlas({}, [], {'Computing': [], 'Humanities': []}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(emptyProfileShown, true);
    c.add(full());
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Nothing here yet'), findsNothing);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // 8 s covers all four stages and the note
    }
    expect(tester.takeException(), isNull);
    expect(emptyProfileShown, false);
    activeProfile = null;
    await c.close();
  });
}

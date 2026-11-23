import 'package:degree_atlas/exercises.dart';
import 'package:degree_atlas/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise ex(Map<String, dynamic> j) =>
    Exercise.fromJson({'id': 'x', 'level': 1, 'prompt': 'p', 'solution': 's', ...j});

void main() {
  test('mcq grading', () {
    final one = ex({'type': 'mcq', 'choices': ['a', 'b', 'c'], 'answer': [1]});
    expect(one.grade({1}), true);
    expect(one.grade({0}), false);
    expect(one.grade(<int>{}), false);
    final many = ex({'type': 'mcq', 'choices': ['a', 'b', 'c'], 'answer': [0, 2]});
    expect(many.grade({0, 2}), true);
    expect(many.grade({0}), false);
    expect(many.grade({0, 1, 2}), false);
  });

  test('numeric grading and parsing', () {
    final e = ex({'type': 'numeric', 'answer': 9.81, 'tolerance': 0.01, 'unit': 'm/s'});
    expect(e.grade('9.81'), true);
    expect(e.grade('9,8'), true);
    expect(e.grade('9.81 m/s'), true);
    expect(e.grade('9.5'), false);
    expect(e.grade('abc'), false);
    expect(parseNumber('1.5x10^3'), 1500);
    expect(parseNumber('-2e-3'), -0.002);
    expect(parseNumber('−3'), -3);
    final zero = ex({'type': 'numeric', 'answer': 0, 'tolerance': 0.001});
    expect(zero.grade('0.0005'), true);
    expect(zero.grade('0.01'), false);
  });

  test('short grading and open', () {
    final e = ex({'type': 'short', 'answer': ['eigenvalue', r're:^eigen-?value$']});
    expect(e.grade('  Eigenvalue. '), true);
    expect(e.grade('Eigen-value'), true);
    expect(e.grade('eigenvector'), false);
    expect(ex({'type': 'open'}).grade('anything'), isNull);
  });

  test('progress merge keeps the record with more attempts', () {
    final m = mergeProgress({
      'read': ['a:L0'],
      'practice': {'a:e1': {'n': 1, 'ok': false}, 'a:e2': {'n': 3, 'ok': true}}
    }, {
      'read': ['b:L1'],
      'practice': {'a:e1': {'n': 2, 'ok': true}, 'a:e2': {'n': 1, 'ok': false}, 'a:e3': {'n': 1, 'ok': true}}
    });
    expect(m['read'], ['a:L0', 'b:L1']);
    expect(m['practice']['a:e1']['ok'], true);
    expect(m['practice']['a:e2']['n'], 3);
    expect(m['practice'].containsKey('a:e3'), true);
  });
}

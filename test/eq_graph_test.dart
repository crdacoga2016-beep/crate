import 'package:crate/util/eq_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('devuelve vacio cuando no hay EQ', () {
    expect(buildEqFilter(EqSettings.empty), isEmpty);
  });

  test('compone EQ base y transicion en un solo grafo', () {
    final filter = buildEqFilter(
      const EqSettings(
        bassDb: 3.0,
        trebleDb: -2.0,
        transitionBassCut: 1.0,
        transitionHighCut: 1.0,
        transitionIntensity: 0.5,
      ),
    );

    expect(filter.startsWith('lavfi=['), isTrue);
    expect(filter.endsWith(']'), isTrue);
    expect(filter, contains('f=80'));
    expect(filter, contains('g=3.0'));
    expect(filter, contains('f=10000'));
    expect(filter, contains('g=-2.0'));
    expect(filter, contains('f=60'));
    expect(filter, contains('f=120'));
    expect(filter, contains('g=-10.0'));
    expect(filter, contains('g=-9.0'));
    expect(filter, contains('f=7000'));
    expect(filter, contains('f=11000'));
    expect(filter, contains('g=-8.0'));
  });

  test('no fuerza conversion a 16 bits', () {
    final filter = buildEqFilter(const EqSettings(bassDb: 2.0, trebleDb: 1.0));

    expect(filter, isNot(contains('format=s16')));
    expect(filter, isNot(contains('format=')));
  });
}

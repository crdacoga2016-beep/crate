import 'package:crate/util/eq_graph.dart';
import 'package:crate/util/eq_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('devuelve vacio cuando no hay EQ', () {
    expect(buildEqFilter(EqSettings.empty), isEmpty);
  });

  test('genera la cadena de diez bandas', () {
    final filter = buildEqFilter(
      const EqSettings(
        baseEq: EqState(
          gainsDb: [0.5, 1.0, 1.5, -2.0, -1.5, 0.5, 2.0, 2.5, 3.0, 1.0],
          selectedPresetId: 'custom',
        ),
      ),
    );

    expect(filter.startsWith('lavfi=['), isTrue);
    expect(filter.endsWith(']'), isTrue);
    for (final frequency in eqBandFrequencies) {
      expect(filter, contains('f=$frequency'));
    }
    expect(filter, contains('g=0.5'));
    expect(filter, contains('g=-2.0'));
    expect(filter, contains('g=3.0'));
  });

  test('usa shelves en los extremos cuando estan habilitados', () {
    final filter = buildEqFilter(
      const EqSettings(
        baseEq: EqState(
          gainsDb: [3.0, 2.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, 2.0, 3.0],
          selectedPresetId: 'custom',
        ),
        useShelves: true,
      ),
    );

    expect(filter, contains('lowshelf=f=31'));
    expect(filter, contains('lowshelf=f=62'));
    expect(filter, contains('highshelf=f=8000'));
    expect(filter, contains('highshelf=f=16000'));
    expect(filter, contains('equalizer=f=125'));
    expect(filter, contains('equalizer=f=250'));
  });

  test('el fallback usa peaking ancho en los extremos', () {
    final filter = buildEqFilter(
      const EqSettings(
        baseEq: EqState(
          gainsDb: [3.0, 2.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, 2.0, 3.0],
          selectedPresetId: 'custom',
        ),
        useShelves: false,
      ),
    );

    expect(filter, isNot(contains('lowshelf')));
    expect(filter, isNot(contains('highshelf')));
    expect(filter, contains('equalizer=f=31:t=q:w=0.5'));
    expect(filter, contains('equalizer=f=62:t=q:w=0.5'));
    expect(filter, contains('equalizer=f=8000:t=q:w=0.5'));
    expect(filter, contains('equalizer=f=16000:t=q:w=0.5'));
    expect(filter, contains('equalizer=f=125:t=q:w=1.0'));
  });

  test('copyWith puede desactivar shelves para el fallback', () {
    const settings = EqSettings(useShelves: true);
    final fallback = settings.copyWith(useShelves: false);

    expect(fallback.useShelves, isFalse);
  });

  test('compone EQ base y transicion en un solo grafo', () {
    final filter = buildEqFilter(
      const EqSettings(
        baseEq: EqState(
          gainsDb: [0.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -2.0, 0.0],
          selectedPresetId: 'custom',
        ),
        transitionBassCut: 1.0,
        transitionHighCut: 1.0,
        transitionIntensity: 0.5,
      ),
    );

    expect(filter.startsWith('lavfi=['), isTrue);
    expect(filter.endsWith(']'), isTrue);
    expect(filter, contains('f=62'));
    expect(filter, contains('g=3.0'));
    expect(filter, contains('f=8000'));
    expect(filter, contains('g=-2.0'));
    expect(filter, contains('f=60'));
    expect(filter, contains('f=120'));
    expect(filter, contains('g=-10.0'));
    expect(filter, contains('g=-9.0'));
    expect(filter, contains('f=7000'));
    expect(filter, contains('f=11000'));
    expect(filter, contains('g=-8.0'));
  });

  test('el bypass elimina la EQ base pero conserva la transicion', () {
    final filter = buildEqFilter(
      EqSettings(
        baseEq: EqState.fromPreset('soft_bass').withBypass(true),
        transitionBassCut: 1.0,
        transitionIntensity: 0.5,
      ),
    );

    expect(filter, contains('f=60'));
    expect(filter, isNot(contains('f=31')));
    expect(filter, isNot(contains('f=62')));
    expect(filter, isNot(contains('f=16000')));
  });

  test('no fuerza conversion a 16 bits', () {
    final filter = buildEqFilter(const EqSettings(baseEq: EqState.flat));

    expect(filter, isEmpty);
    expect(filter, isNot(contains('format=s16')));
    expect(filter, isNot(contains('format=')));
  });
}

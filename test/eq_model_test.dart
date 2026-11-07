import 'package:crate/util/eq_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modelo EQ', () {
    test('define diez bandas y pasos de 0.5 dB', () {
      expect(eqBandFrequencies, [
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
      ]);
      expect(quantizeEqGain(1.26), 1.5);
      expect(quantizeEqGain(1.24), 1.0);
      expect(quantizeEqGain(12.4), 12.0);
      expect(quantizeEqGain(-13.2), -12.0);
      expect(quantizeEqGain(double.nan), 0.0);
    });

    test('presets tienen diez bandas cuantizadas', () {
      expect(eqPresets.map((preset) => preset.id), [
        'flat',
        'natural',
        'soft_bass',
        'vocal',
        'bluetooth',
        'speaker_powerful',
      ]);
      for (final preset in eqPresets) {
        expect(preset.gainsDb.length, eqBandFrequencies.length);
        for (final gain in preset.gainsDb) {
          expect(gain, quantizeEqGain(gain));
        }
      }
    });

    test('migra graves y agudos antiguos sin cambiar su intencion', () {
      final migrated = EqState.migratedFromLegacy(bassDb: 6.0, trebleDb: -4.0);

      expect(migrated.gainsDb, [
        3.0,
        6.0,
        3.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        -2.0,
        -2.0,
      ]);
      expect(
        EqState.migratedFromLegacy(bassDb: 0.0, trebleDb: 0.0),
        EqState.flat,
      );
    });

    test('codifica y decodifica un estado', () {
      final original = EqState.fromPreset('natural').withBypass(true);
      final decoded = EqState.decode(original.encode());

      expect(decoded.gainsDb, original.gainsDb);
      expect(decoded.bypass, isTrue);
      expect(decoded.selectedPresetId, 'natural');
    });

    test('el bypass produce respuesta plana', () {
      final state = EqState.fromPreset('vocal').withBypass(true);

      expect(state.effectiveGainsDb.every((gain) => gain == 0.0), isTrue);
      expect(state.responseDbAtHz(1000.0), 0.0);
      expect(state.maximumResponseDb, 0.0);
      expect(state.smartHeadroomDb, 0.0);
    });
  });

  group('respuesta en frecuencia', () {
    test('una banda produce su ganancia en la frecuencia central', () {
      final gains = List<double>.filled(eqBandFrequencies.length, 0.0);
      gains[5] = 6.0;
      final state = EqState(gainsDb: gains);

      expect(state.responseDbAtHz(1000.0), closeTo(6.0, 0.01));
      expect(state.responseDbAtHz(100.0), greaterThan(0.0));
      expect(state.responseDbAtHz(100.0), lessThan(6.0));
    });

    test(
      'el preset Altavoz Potente activa el cuerpo y agudos sin subgraves',
      () {
        final preset = EqState.fromPreset('speaker_powerful');

        expect(preset.gainsDb, [
          0.0,
          0.0,
          4.0,
          5.0,
          0.0,
          0.0,
          2.0,
          2.5,
          1.0,
          0.0,
        ]);
        expect(preset.gainsDb[0], 0.0);
        expect(preset.gainsDb[1], 0.0);
        expect(preset.gainsDb[2], greaterThan(0.0));
        expect(preset.gainsDb[3], greaterThan(0.0));
        expect(preset.gainsDb[6], greaterThan(0.0));
        expect(preset.gainsDb[7], greaterThan(0.0));
      },
    );

    test('el altavoz ignora 31 y 62 Hz al calcular headroom', () {
      final gains = List<double>.filled(eqBandFrequencies.length, 0.0);
      gains[0] = 12.0;
      gains[1] = 12.0;
      gains[5] = 6.0;
      final state = EqState(gainsDb: gains);

      expect(
        state.maximumResponseDbFor(AudioOutputProfile.speaker),
        closeTo(6.0, 0.05),
      );
      expect(
        state.smartHeadroomDbFor(AudioOutputProfile.speaker),
        closeTo(-6.5, 0.05),
      );
      expect(
        state.maximumResponseDbFor(AudioOutputProfile.headphones),
        greaterThan(12.0),
      );
      expect(
        state.smartHeadroomDbFor(AudioOutputProfile.headphones),
        lessThan(-12.5),
      );
      expect(state.effectivePreampDbFor(-1.0, AudioOutputProfile.speaker), 2.0);
      expect(
        state.effectivePreampDbFor(-1.0, AudioOutputProfile.headphones),
        -1.0,
      );
    });

    test('flat tiene respuesta cero y no requiere headroom', () {
      expect(EqState.flat.responseDbAtHz(1000.0), 0.0);
      expect(EqState.flat.maximumResponseDb, 0.0);
      expect(EqState.flat.smartHeadroomDb, 0.0);
      expect(EqState.flat.smartHeadroomGain, 1.0);
    });

    test(
      'el smart headroom compensa el pico de respuesta mas la seguridad',
      () {
        final gains = List<double>.filled(eqBandFrequencies.length, 0.0);
        gains[5] = 6.0;
        final state = EqState(gainsDb: gains);

        expect(state.maximumResponseDb, closeTo(6.0, 0.05));
        expect(state.smartHeadroomDb, closeTo(-6.5, 0.05));
        expect(
          state.maximumResponseDb + state.smartHeadroomDb,
          closeTo(-smartHeadroomSafetyDb, 0.05),
        );
      },
    );

    test('la respuesta compuesta puede superar el boost de una sola banda', () {
      final state = EqState.fromPreset('soft_bass');

      expect(state.maximumResponseDb, greaterThan(2.5));
      expect(state.smartHeadroomDb, lessThan(-2.5));
    });

    test('todas las frecuencias de banda son validas en 48 kHz', () {
      final state = EqState.fromPreset('natural');
      for (final frequency in eqBandFrequencies) {
        final response = state.responseDbAtHz(frequency.toDouble());
        expect(response.isFinite, isTrue);
      }
    });
  });

  group('A/B', () {
    test('el snapshot compara procesado y bypass', () {
      final processed = EqState.fromPreset('natural');
      final snapshot = eqABSnapshotFor(processed);

      expect(snapshot.state(false), processed);
      expect(snapshot.state(true).bypass, isTrue);
      expect(
        snapshot.differenceDbAt(frequencyHz: 1000.0),
        closeTo(processed.responseDbAtHz(1000.0), 1e-12),
      );
    });

    test('el snapshot de flat no tiene diferencia', () {
      final snapshot = eqABSnapshotFor(EqState.flat);

      expect(snapshot.differenceDbAt(frequencyHz: 1000.0), 0.0);
    });
  });
}

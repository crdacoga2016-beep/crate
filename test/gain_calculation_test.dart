import 'dart:math' as math;

import 'package:crate/util/gain_calculation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ganancia', () {
    test('convierte entre dB y ganancia lineal', () {
      expect(dbToLinearGain(0.0), closeTo(1.0, 1e-12));
      expect(dbToLinearGain(-20.0), closeTo(0.1, 1e-12));
      expect(dbToLinearGain(20.0), closeTo(10.0, 1e-12));
      expect(linearGainToDb(0.1), closeTo(-20.0, 1e-9));
      expect(linearGainToDb(2.0), closeTo(6.020599913279624, 1e-9));
    });

    test('convierte ganancia lineal a volumen cubico de mpv', () {
      expect(mpvVolumeForLinearGain(1.0), closeTo(100.0, 1e-12));
      expect(mpvVolumeForLinearGain(8.0), closeTo(158.7401052, 1e-6));
      expect(mpvVolumeForLinearGain(0.125), closeTo(50.0, 1e-12));
      expect(linearGainFromMpvVolume(50.0), closeTo(0.125, 1e-12));
      expect(
        linearGainFromMpvVolume(mpvVolumeForLinearGain(0.4)),
        closeTo(0.4, 1e-12),
      );
    });

    test('combina usuario, pista, preamp, fade y headroom', () {
      expect(
        combinedLinearGain(
          userVolume: 0.5,
          trackGain: 2.0,
          preampDb: 6.0,
          fadeGain: 0.5,
          eqHeadroomGain: 0.5,
        ),
        closeTo(0.4988, 0.001),
      );
      expect(
        combinedLinearGain(userVolume: 1.0, trackGain: 2.0, preampDb: 6.0),
        closeTo(3.9905, 0.001),
      );
    });

    test('rechaza valores no finitos', () {
      expect(
        combinedLinearGain(
          userVolume: double.nan,
          trackGain: double.infinity,
          preampDb: double.nan,
        ),
        0.0,
      );
      expect(clampFinite(double.infinity, -12.0, 6.0), 0.0);
    });
  });

  group('normalizacion y picos', () {
    test('normaliza hacia el objetivo y respeta el techo de pico', () {
      expect(
        trackGainFor(normalize: true, lufs: -14.0, peakDb: -20.0),
        closeTo(1.0, 1e-12),
      );
      expect(
        trackGainFor(normalize: true, lufs: -16.0, peakDb: -0.3),
        closeTo(0.922571427, 1e-9),
      );
    });

    test('el True Peak prevalece sobre el pico de muestra', () {
      expect(
        trackGainFor(normalize: false, peakDb: -3.0, truePeakDb: -0.2),
        closeTo(0.9120107, 1e-6),
      );
      expect(
        trackGainFor(normalize: false, peakDb: -0.2, truePeakDb: -3.0),
        greaterThan(0.9120107),
      );
    });

    test('aplica techo de pico aunque falte LUFS', () {
      expect(
        trackGainFor(normalize: true, lufs: null, peakDb: -0.3),
        closeTo(0.922571427, 1e-9),
      );
      expect(
        trackGainFor(normalize: false, lufs: -20.0, peakDb: -0.3),
        closeTo(0.922571427, 1e-9),
      );
    });

    test('la senal limitada queda por debajo del techo', () {
      const peakDb = -0.3;
      final gain = trackGainFor(normalize: false, peakDb: peakDb);
      final resultingPeakDb = peakDb + linearGainToDb(gain);

      expect(resultingPeakDb, lessThanOrEqualTo(peakCeilingDb + 1e-12));
    });

    test('el crossfade de potencia igualada no supera la suma coherente', () {
      for (var i = 0; i <= 40; i++) {
        final gains = equalPowerCrossfadeGains(i / 40.0);

        expect(gains.incoming + gains.outgoing, lessThanOrEqualTo(1.0 + 1e-12));
      }
      final midpoint = equalPowerCrossfadeGains(0.5);

      expect(midpoint.incoming, closeTo(0.5, 1e-12));
      expect(midpoint.outgoing, closeTo(0.5, 1e-12));
    });

    test(
      'el peor caso coherente del crossfade no clippea una senal en techo',
      () {
        final sourceLinearPeak = math.pow(10.0, peakCeilingDb / 20.0);
        var maximumSum = 0.0;
        for (var i = 0; i <= 200; i++) {
          final gains = equalPowerCrossfadeGains(i / 200.0);
          maximumSum = math.max(
            maximumSum,
            (gains.incoming + gains.outgoing) * sourceLinearPeak,
          );
        }

        expect(maximumSum, lessThanOrEqualTo(sourceLinearPeak + 1e-12));
      },
    );
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crate/services/audio_core_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Audio Core FFI devuelve un resultado seguro', () {
    expect(AudioCoreFfi.versionLabel, anyOf('no disponible', '0.1.0'));
  });

  test('el limitador atenua un pico superior a 0 dBFS', () {
    final samples = Float32List.fromList([0.2, -0.4, 2.0, -1.5, 0.3]);
    final appliedGain = AudioCoreFfi.processLimiter(samples, -1.0);

    if (appliedGain == null) {
      markTestSkipped('Crate Audio Core native library not available');
      return;
    }

    final ceiling = math.pow(10.0, -1.0 / 20.0).toDouble();
    expect(appliedGain, closeTo(ceiling / 2.0, 0.0001));
    expect(samples[2], closeTo(ceiling, 0.0001));
    expect(samples[3], closeTo(-ceiling * 0.75, 0.0001));
    expect(samples.every((sample) => sample.abs() <= ceiling + 0.0001), isTrue);
  });

  test('el limitador deja intacta una senal bajo el techo', () {
    final samples = Float32List.fromList([0.2, -0.4, 0.3, -0.1]);
    final original = Float32List.fromList(samples);
    final appliedGain = AudioCoreFfi.processLimiter(samples, -1.0);

    if (appliedGain == null) {
      markTestSkipped('Crate Audio Core native library not available');
      return;
    }

    expect(appliedGain, 1.0);
    expect(samples, orderedEquals(original));
  });

  test('el limitador avanzado ve el pico antes de que llegue', () {
    final original = List<double>.generate(240, (index) {
      final sign = index.isEven ? 1.0 : -1.0;
      if (index == 110) return sign * 2.5;
      if (index >= 111 && index < 125) return sign * 1.8;
      return sign * 0.8;
    });
    final samples = Float32List.fromList(original);
    final appliedGain = AudioCoreFfi.processLimiterAdvanced(
      samples,
      ceilingDb: -1.0,
      lookaheadMs: 5.0,
      attackMs: 1.0,
      releaseMs: 50.0,
      sampleRate: 48000,
    );

    if (appliedGain == null) {
      markTestSkipped('Crate Audio Core native library not available');
      return;
    }

    final ceiling = math.pow(10.0, -1.0 / 20.0).toDouble();
    expect(samples[110] / 2.5, lessThan(0.6));
    expect(samples.every((sample) => sample.abs() <= ceiling + 0.02), isTrue);
  });

  test('el envolvente sube la ganancia despues del pico', () {
    final original = List<double>.generate(900, (index) {
      final sign = index.isEven ? 1.0 : -1.0;
      if (index == 100) return sign * 2.5;
      return sign * 0.8;
    });
    final samples = Float32List.fromList(original);
    final appliedGain = AudioCoreFfi.processLimiterAdvanced(
      samples,
      ceilingDb: -1.0,
      lookaheadMs: 5.0,
      attackMs: 1.0,
      releaseMs: 50.0,
      sampleRate: 48000,
    );

    if (appliedGain == null) {
      markTestSkipped('Crate Audio Core native library not available');
      return;
    }

    final gainAtSpike = samples[100] / original[100];
    final gainLater = samples[700] / original[700];
    expect(gainAtSpike, lessThan(0.6));
    expect(gainLater, greaterThan(gainAtSpike));
    expect(samples.every((sample) => sample.abs() <= 0.8913 + 0.02), isTrue);
  });

  test('el limitador avanzado deja intacta una senal bajo el techo', () {
    final samples = Float32List.fromList([0.2, -0.4, 0.3, -0.1]);
    final original = Float32List.fromList(samples);
    final appliedGain = AudioCoreFfi.processLimiterAdvanced(
      samples,
      ceilingDb: -1.0,
      lookaheadMs: 5.0,
      attackMs: 1.0,
      releaseMs: 50.0,
      sampleRate: 48000,
    );

    if (appliedGain == null) {
      markTestSkipped('Crate Audio Core native library not available');
      return;
    }

    expect(appliedGain, 1.0);
    expect(samples, orderedEquals(original));
  });
}

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
}

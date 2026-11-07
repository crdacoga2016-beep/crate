import 'package:crate/models/replay_gain.dart';
import 'package:crate/models/track.dart';
import 'package:crate/util/gain_calculation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReplayGain', () {
    test('parsea ganancia en dB y pico lineal', () {
      final replayGain = ReplayGainData.fromTags(
        trackGain: '-3.50 dB',
        trackPeak: '0.918055',
        albumGain: '2.25 dB',
        albumPeak: '1.00',
      );

      expect(replayGain.trackGainDb, closeTo(-3.5, 1e-12));
      expect(replayGain.trackPeakDb, closeTo(-0.7429, 0.001));
      expect(replayGain.albumGainDb, closeTo(2.25, 1e-12));
      expect(replayGain.albumPeakDb, closeTo(0.0, 1e-12));
      expect(replayGain.effectiveTrackGainDb, closeTo(-3.5, 1e-12));
      expect(replayGain.effectiveTrackPeakDb, closeTo(-0.7429, 0.001));
    });

    test('usa album como fallback cuando falta pista', () {
      final replayGain = ReplayGainData.fromTags(
        albumGain: '1.50',
        albumPeak: '0.5',
      );

      expect(replayGain.effectiveTrackGainDb, closeTo(1.5, 1e-12));
      expect(replayGain.effectiveTrackPeakDb, closeTo(-6.0206, 0.001));
    });

    test('ignora valores invalidos', () {
      final replayGain = ReplayGainData.fromTags(
        trackGain: 'not-a-number',
        trackPeak: '-1.00',
      );

      expect(replayGain.hasAnyData, isFalse);
    });

    test('se serializa con la pista', () {
      const track = Track(
        id: 'track-id',
        path: '/music/track.mp3',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        replayGain: ReplayGainData(
          trackGainDb: -2.5,
          trackPeakDb: -0.2,
          albumGainDb: -2.0,
          albumPeakDb: -0.1,
        ),
      );

      final restored = Track.fromJson(track.toJson());

      expect(restored.replayGain?.trackGainDb, closeTo(-2.5, 1e-12));
      expect(restored.replayGain?.trackPeakDb, closeTo(-0.2, 1e-12));
      expect(restored.replayGain?.albumGainDb, closeTo(-2.0, 1e-12));
      expect(restored.replayGain?.albumPeakDb, closeTo(-0.1, 1e-12));
    });

    test('aplica la ganancia como factor adicional', () {
      expect(
        trackGainFor(normalize: false, replayGainDb: -3.0),
        closeTo(0.707945784, 1e-9),
      );
      expect(
        trackGainFor(normalize: true, lufs: -14.0, replayGainDb: 2.0),
        closeTo(1.258925412, 1e-9),
      );
    });

    test('respeta el pico de ReplayGain', () {
      expect(
        trackGainFor(
          normalize: false,
          replayGainDb: 6.0,
          replayGainPeakDb: 0.0,
        ),
        closeTo(0.891250938, 1e-9),
      );
    });
  });
}

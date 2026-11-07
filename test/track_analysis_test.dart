import 'package:crate/models/track_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carga truePeakDb desde analysis.json', () {
    final analysis = TrackAnalysis.fromJson({
      'version': 5,
      'bpm': 120,
      'barLength': 2,
      'downbeats': <double>[],
      'downbeatPhase': 0,
      'duration': 10,
      'leadIn': 0,
      'audibleEnd': 10,
      'mixIn': 0,
      'mixOut': 9,
      'energy': 0.5,
      'peakDb': -3.0,
      'truePeakDb': -0.9,
      'keyRoot': 0,
      'isMinor': false,
      'key': '',
      'camelot': '',
      'features': <double>[],
    });

    expect(analysis.peakDb, -3.0);
    expect(analysis.truePeakDb, -0.9);
  });
}

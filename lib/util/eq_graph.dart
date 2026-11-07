import 'eq_model.dart';

class EqSettings {
  const EqSettings({
    this.baseEq = EqState.flat,
    this.transitionBassCut = 0.0,
    this.transitionHighCut = 0.0,
    this.transitionIntensity = 0.6,
  });

  static const empty = EqSettings();

  final EqState baseEq;
  final double transitionBassCut;
  final double transitionHighCut;
  final double transitionIntensity;
}

String buildEqFilter(EqSettings settings) {
  final filters = <String>[];
  if (!settings.baseEq.bypass) {
    for (var index = 0; index < eqBandFrequencies.length; index++) {
      final gainDb = index < settings.baseEq.gainsDb.length
          ? settings.baseEq.gainsDb[index]
          : 0.0;
      _addBand(filters, frequency: eqBandFrequencies[index], gainDb: gainDb);
    }
  }

  final intensity = settings.transitionIntensity.clamp(0.0, 1.0).toDouble();
  if (settings.transitionBassCut > 0.0) {
    _addBand(filters, frequency: 60, gainDb: -20.0 * intensity);
    _addBand(filters, frequency: 120, gainDb: -18.0 * intensity);
  }
  if (settings.transitionHighCut > 0.0) {
    _addBand(filters, frequency: 7000, gainDb: -16.0 * intensity);
    _addBand(filters, frequency: 11000, gainDb: -18.0 * intensity);
  }

  if (filters.isEmpty) return '';
  return 'lavfi=[${filters.join(',')}]';
}

void _addBand(
  List<String> filters, {
  required int frequency,
  required double gainDb,
}) {
  if (gainDb.abs() < 0.05) return;
  filters.add('equalizer=f=$frequency:t=q:w=1:g=${gainDb.toStringAsFixed(1)}');
}

import 'eq_model.dart';

class EqSettings {
  const EqSettings({
    this.baseEq = EqState.flat,
    this.transitionBassCut = 0.0,
    this.transitionHighCut = 0.0,
    this.transitionIntensity = 0.6,
    this.useShelves = false,
  });

  static const empty = EqSettings();

  final EqState baseEq;
  final double transitionBassCut;
  final double transitionHighCut;
  final double transitionIntensity;
  final bool useShelves;

  EqSettings copyWith({bool? useShelves}) {
    return EqSettings(
      baseEq: baseEq,
      transitionBassCut: transitionBassCut,
      transitionHighCut: transitionHighCut,
      transitionIntensity: transitionIntensity,
      useShelves: useShelves ?? this.useShelves,
    );
  }
}

String buildEqFilter(EqSettings settings) {
  final filters = <String>[];
  if (!settings.baseEq.bypass) {
    if (settings.useShelves) {
      _appendShelfFilters(filters, settings.baseEq.gainsDb);
    } else {
      _appendPeakingFilters(filters, settings.baseEq.gainsDb);
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

void _appendShelfFilters(List<String> filters, List<double> gainsDb) {
  if (gainsDb.isNotEmpty) {
    _addShelf(
      filters,
      filterName: 'lowshelf',
      frequency: 31,
      gainDb: gainsDb[0],
    );
  }
  if (gainsDb.length > 1) {
    _addShelf(
      filters,
      filterName: 'lowshelf',
      frequency: 62,
      gainDb: gainsDb[1],
    );
  }
  for (var index = 2; index < 8 && index < gainsDb.length; index++) {
    _addBand(
      filters,
      frequency: eqBandFrequencies[index],
      gainDb: gainsDb[index],
    );
  }
  if (gainsDb.length > 8) {
    _addShelf(
      filters,
      filterName: 'highshelf',
      frequency: 8000,
      gainDb: gainsDb[8],
    );
  }
  if (gainsDb.length > 9) {
    _addShelf(
      filters,
      filterName: 'highshelf',
      frequency: 16000,
      gainDb: gainsDb[9],
    );
  }
}

void _appendPeakingFilters(List<String> filters, List<double> gainsDb) {
  for (var index = 0; index < eqBandFrequencies.length; index++) {
    final gainDb = index < gainsDb.length ? gainsDb[index] : 0.0;
    final isShelfFallbackBand =
        index == 0 || index == 1 || index == 8 || index == 9;
    _addBand(
      filters,
      frequency: eqBandFrequencies[index],
      gainDb: gainDb,
      width: isShelfFallbackBand ? 0.5 : 1.0,
    );
  }
}

void _addBand(
  List<String> filters, {
  required int frequency,
  required double gainDb,
  double width = 1.0,
}) {
  if (gainDb.abs() < 0.05) return;
  filters.add(
    'equalizer=f=$frequency:t=q:w=${width.toStringAsFixed(1)}:g=${gainDb.toStringAsFixed(1)}',
  );
}

void _addShelf(
  List<String> filters, {
  required String filterName,
  required int frequency,
  required double gainDb,
}) {
  if (gainDb.abs() < 0.05) return;
  filters.add(
    '$filterName=f=$frequency:t=q:w=1.0:g=${gainDb.toStringAsFixed(1)}',
  );
}

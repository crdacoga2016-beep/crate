import 'dart:math' as math;

const double normalizeTargetLufs = -14.0;
const double peakCeilingDb = -1.0;
const double minimumTrackGain = 0.25;
const double maximumTrackGain = 2.0;
const double maximumMpvLinearGain = 4.0;
const double maximumMpvVolume = 1000.0;

double clampFinite(
  double value,
  double minimum,
  double maximum, {
  double fallback = 0.0,
}) {
  final safeValue = value.isFinite ? value : fallback;
  return safeValue.clamp(minimum, maximum).toDouble();
}

double dbToLinearGain(double db) {
  return math.pow(10.0, clampFinite(db, -96.0, 96.0) / 20.0).toDouble();
}

double linearGainToDb(double gain) {
  if (!gain.isFinite || gain <= 0.0) {
    return double.negativeInfinity;
  }
  return 20.0 * math.log(gain) / math.ln10;
}

double mpvVolumeForLinearGain(double gain) {
  final safeGain = clampFinite(gain, 0.0, maximumMpvLinearGain);
  return 100.0 * math.pow(safeGain, 1.0 / 3.0).toDouble();
}

double linearGainFromMpvVolume(double volume) {
  final safeVolume = clampFinite(volume, 0.0, maximumMpvVolume);
  return math.pow(safeVolume / 100.0, 3.0).toDouble();
}

double combinedLinearGain({
  required double userVolume,
  required double trackGain,
  required double preampDb,
  double fadeGain = 1.0,
  double eqHeadroomGain = 1.0,
}) {
  final gain =
      clampFinite(userVolume, 0.0, 1.0) *
      clampFinite(trackGain, 0.0, maximumMpvLinearGain, fallback: 1.0) *
      dbToLinearGain(preampDb) *
      clampFinite(fadeGain, 0.0, 1.0) *
      clampFinite(eqHeadroomGain, 0.0, 1.0, fallback: 1.0);
  return gain.clamp(0.0, maximumMpvLinearGain).toDouble();
}

double trackGainFor({
  required bool normalize,
  double? lufs,
  double? peakDb,
  double? replayGainDb,
  double? replayGainPeakDb,
  double targetLufs = normalizeTargetLufs,
  double ceilingDb = peakCeilingDb,
}) {
  var gain = 1.0;
  if (normalize && lufs != null && lufs.isFinite) {
    gain = dbToLinearGain(targetLufs - lufs);
  }
  if (peakDb != null && peakDb.isFinite) {
    final ceilingGain = dbToLinearGain(ceilingDb - peakDb);
    if (gain > ceilingGain) gain = ceilingGain;
  }
  if (replayGainDb != null && replayGainDb.isFinite) {
    gain *= dbToLinearGain(replayGainDb);
  }
  if (replayGainPeakDb != null && replayGainPeakDb.isFinite) {
    final replayGainCeiling = dbToLinearGain(ceilingDb - replayGainPeakDb);
    if (gain > replayGainCeiling) gain = replayGainCeiling;
  }
  return gain.clamp(minimumTrackGain, maximumTrackGain).toDouble();
}

({double incoming, double outgoing}) equalPowerCrossfadeGains(double progress) {
  final safeProgress = clampFinite(progress, 0.0, 1.0);
  final peakSafeScale = 1.0 / math.sqrt2;
  return (
    incoming: math.sin(safeProgress * math.pi / 2.0) * peakSafeScale,
    outgoing: math.cos(safeProgress * math.pi / 2.0) * peakSafeScale,
  );
}

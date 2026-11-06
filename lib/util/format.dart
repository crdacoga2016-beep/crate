String formatDuration(Duration? d) {
  if (d == null || d <= Duration.zero) return '--:--';
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatTotal(Iterable<Duration?> durations) {
  var seconds = 0;
  for (final d in durations) {
    seconds += d?.inSeconds ?? 0;
  }
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}min';
}

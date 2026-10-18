/// `m:ss`, or `h:mm:ss` for durations of an hour or more.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// Human-friendly total length, e.g. `42 min` or `1 h 12 min`.
String formatTotalDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours > 0) return '$hours h $minutes min';
  return '${d.inMinutes} min';
}

String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

/// `3.4 MB`, `812 KB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// `+3.5 dB`, `-6.0 dB`, `0.0 dB` (never "-0.0" or "+-0.0").
String formatDb(double db, {bool unit = true}) {
  final rounded = (db * 10).round() / 10;
  final text = rounded == 0 ? '0.0' : '${rounded > 0 ? '+' : ''}${rounded.toStringAsFixed(1)}';
  return unit ? '$text dB' : text;
}

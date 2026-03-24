import 'package:intl/intl.dart';

/// Few x-axis ticks so labels stay distinct (avoids repeated “Mar 24” from fl_chart).
List<int> xAxisLabelIndices(int len) {
  if (len <= 1) return [0];
  if (len <= 6) return List.generate(len, (i) => i);
  return [0, len ~/ 4, len ~/ 2, (3 * len) ~/ 4, len - 1];
}

/// Bottom date labels for chart x-axis; includes year when span is long.
String bottomAxisDateLabel(DateTime dt, double spanDays) {
  if (spanDays <= 1) return DateFormat('HH:mm').format(dt);
  if (spanDays <= 7) return DateFormat('EEE d').format(dt);
  if (spanDays <= 120) return DateFormat('MMM d').format(dt);
  return DateFormat('MMM \'yy').format(dt);
}

/// Prevents a “flat” chart when the visible slice has almost no price variance (or zoom).
(double, double) yRangeWithMinSpan(
  double dataMin,
  double dataMax, {
  double minSpanFraction = 0.012,
  double padFraction = 0.08,
}) {
  final mid = (dataMin + dataMax) / 2;
  var span = (dataMax - dataMin).abs();
  if (span < 1e-9) span = mid * minSpanFraction;
  if (span < mid * minSpanFraction) span = mid * minSpanFraction;
  final pad = span * padFraction;
  return (dataMin - pad, dataMax + pad);
}

/// Y-axis labels: when price range is tiny, [formatAxisUsdCompact] rounds everything to the same "70.7K".
String formatAxisUsdForRange(double v, double axisMin, double axisMax) {
  final mid = ((axisMin + axisMax) / 2).abs();
  final span = (axisMax - axisMin).abs();
  if (mid > 1e-9 && span / mid < 0.003) {
    final a = v.abs();
    final sign = v < 0 ? '-' : '';
    if (a >= 1e3) {
      return '$sign\$${(a / 1e3).toStringAsFixed(2)}K';
    }
    return '$sign\$${a.toStringAsFixed(0)}';
  }
  return formatAxisUsdCompact(v);
}

/// Compact Y-axis labels for mobile charts (short form, minimal width).
String formatAxisUsdCompact(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e12) return '$sign\$${(a / 1e12).toStringAsFixed(2)}T';
  if (a >= 1e9) return '$sign\$${(a / 1e9).toStringAsFixed(2)}B';
  if (a >= 1e6) return '$sign\$${(a / 1e6).toStringAsFixed(2)}M';
  if (a >= 1e3) return '$sign\$${(a / 1e3).toStringAsFixed(1)}K';
  return '$sign\$${a.toStringAsFixed(0)}';
}

/// Non-currency large values (e.g. P&L in USD terms without $ in some charts).
String formatAxisNumberCompact(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e12) return '$sign${(a / 1e12).toStringAsFixed(2)}T';
  if (a >= 1e9) return '$sign${(a / 1e9).toStringAsFixed(2)}B';
  if (a >= 1e6) return '$sign${(a / 1e6).toStringAsFixed(2)}M';
  if (a >= 1e3) return '$sign${(a / 1e3).toStringAsFixed(1)}K';
  return '$sign${a.toStringAsFixed(0)}';
}

/// Default reserved width for right-side chart labels (short style).
const double kChartAxisReservedRight = 44.0;

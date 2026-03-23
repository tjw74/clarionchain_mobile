import 'dart:math' show log, sqrt, pow;

/// Rolling SMA — O(n). First (period-1) entries are null.
List<double?> sma(List<double> values, int period) {
  if (values.length < period) return List.filled(values.length, null);
  final result = List<double?>.filled(values.length, null);
  double sum = values.sublist(0, period).fold(0.0, (a, b) => a + b);
  result[period - 1] = sum / period;
  for (int i = period; i < values.length; i++) {
    sum += values[i] - values[i - period];
    result[i] = sum / period;
  }
  return result;
}

/// Weighted MA with linear weights (most recent = highest weight). O(n*period).
List<double?> wma(List<double> values, int period) {
  if (values.length < period) return List.filled(values.length, null);
  final denom = period * (period + 1) / 2.0;
  final result = List<double?>.filled(values.length, null);
  for (int i = period - 1; i < values.length; i++) {
    double ws = 0;
    for (int w = 1; w <= period; w++) {
      ws += values[i - period + w] * w;
    }
    result[i] = ws / denom;
  }
  return result;
}

/// Fraction [0,1] of values at or below target. 1.0 = all-time high.
double quantile(List<double> values, double target) {
  if (values.isEmpty) return 0;
  int n = 0;
  for (final v in values) {
    if (v <= target) n++;
  }
  return n / values.length;
}

/// Z-score on log(value) distribution — appropriate for price (log-normal).
/// Returns 0 if insufficient data.
double logZScore(List<double> values, double current) {
  final logs = values.where((v) => v > 0).map((v) => log(v)).toList();
  if (logs.length < 2 || current <= 0) return 0;
  final mean = logs.fold(0.0, (a, b) => a + b) / logs.length;
  final variance = logs.fold(0.0, (a, b) => a + pow(b - mean, 2)) / (logs.length - 1);
  final std = sqrt(variance);
  return std > 0 ? (log(current) - mean) / std : 0;
}

/// Z-score on raw values — for metrics that are not log-normal (e.g. MVRV, funding rate).
double rawZScore(List<double> values, double current) {
  if (values.length < 2) return 0;
  final mean = values.fold(0.0, (a, b) => a + b) / values.length;
  final variance =
      values.fold(0.0, (a, b) => a + pow(b - mean, 2)) / (values.length - 1);
  final std = sqrt(variance);
  return std > 0 ? (current - mean) / std : 0;
}

/// Mayer Multiple = price / 200 DMA
double mayerMultiple(double price, List<double?> dma200) {
  for (int i = dma200.length - 1; i >= 0; i--) {
    final d = dma200[i];
    if (d != null && d > 0) return price / d;
  }
  return 0;
}

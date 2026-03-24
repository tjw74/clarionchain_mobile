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

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/price_provider.dart';
import '../theme/app_theme.dart';
import '../utils/chart_axis_labels.dart';

/// An optional overlay line on the price chart.
class ChartOverlay {
  final List<double?> values; // aligned with chartDailyPriceHistoryProvider; null = skip
  final Color color;
  final bool dashed;
  final String label;
  const ChartOverlay({
    required this.values,
    required this.color,
    this.dashed = false,
    this.label = '',
  });
}

class PriceChart extends ConsumerStatefulWidget {
  final List<ChartOverlay> overlays;
  /// Optional compact label (e.g. live spot) drawn inside the chart area.
  final Widget? overlayHeader;
  const PriceChart({super.key, this.overlays = const [], this.overlayHeader});

  @override
  ConsumerState<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends ConsumerState<PriceChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  // Viewport as fractions [0,1] of the full history
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  // Captured at gesture start (all math is relative to start, avoids drift)
  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allHistory = ref.watch(chartDailyPriceHistoryProvider);
    final dailyAsync = ref.watch(priceHistoryDailyProvider);
    final notifierLoading = ref.watch(historyLoadingProvider);

    if (allHistory.isEmpty) {
      final loading = dailyAsync.isLoading || notifierLoading;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                const CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2),
                const SizedBox(height: 12),
                const Text(
                  'Loading daily prices from Bitview…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ] else ...[
                const Icon(Icons.cloud_off_rounded,
                    color: AppColors.textMuted, size: 40),
                const SizedBox(height: 12),
                Text(
                  dailyAsync.hasError
                      ? 'Bitview price data failed to load.'
                      : 'No daily price data. Check network / VPN and try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final n = allHistory.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final history = startIdx < endIdx
        ? allHistory.sublist(startIdx, endIdx + 1)
        : [allHistory.last];

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    final prices = history.map((t) => t.price).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final (effMin, effMax) = yRangeWithMinSpan(minPrice, maxPrice);

    final isUp = history.last.price >= history.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final dotCore = AppColors.accent;
    final vc = history.length;
    final labelIdx = xAxisLabelIndices(vc).toSet();
    final spanDays =
        history.last.timestamp.difference(history.first.timestamp).inMinutes /
            1440.0;

    const rightReserved = kChartAxisReservedRight;
    const bottomReserved = 22.0;

    return GestureDetector(
      onScaleStart: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        _gsWidth = rb?.size.width ?? 300;
        _gsFocalX = d.localFocalPoint.dx;
        _gsViewStart = _viewStart;
        _gsViewEnd = _viewEnd;
      },
      onScaleUpdate: (d) {
        if (_gsWidth == 0 || d.pointerCount < 2) return;
        final oldSpan = _gsViewEnd - _gsViewStart;
        final newSpan = (oldSpan / d.scale).clamp(0.002, 1.0);
        final focalFrac = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final focalData = _gsViewStart + focalFrac * oldSpan;
        final panPixels = d.localFocalPoint.dx - _gsFocalX;
        final panData = -(panPixels / _gsWidth) * newSpan;
        var s = (focalData - focalFrac * newSpan + panData)
            .clamp(0.0, 1.0 - newSpan);
        setState(() {
          _viewStart = s;
          _viewEnd = s + newSpan;
        });
      },
      onDoubleTap: () => setState(() {
        _viewStart = 0;
        _viewEnd = 1.0;
      }),
      child: LayoutBuilder(builder: (context, constraints) {
        final chartW = constraints.maxWidth - rightReserved;
        final chartH = constraints.maxHeight - bottomReserved;

        // Screen coords of the last (live) data point
        final lastPrice = history.last.price;
        final dotX = chartW; // last index = right edge
        final dotY = chartH * (1.0 - (lastPrice - effMin) / (effMax - effMin));

        return Stack(children: [
          // ── Chart ──────────────────────────────────────────
          LineChart(
            LineChartData(
              minY: effMin,
              maxY: effMax,
              clipData: const FlClipData.all(),
              // Disable fl_chart's internal gesture detector so ours wins
              lineTouchData: const LineTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: rightReserved,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        formatAxisUsdForRange(value, meta.min, meta.max),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9),
                        textAlign: TextAlign.right,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: bottomReserved,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.round().clamp(0, history.length - 1);
                      if (!labelIdx.contains(idx)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          bottomAxisDateLabel(
                              history[idx].timestamp, spanDays),
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: vc < 500,
                  curveSmoothness: 0.2,
                  color: lineColor,
                  barWidth: vc > 300 ? 1.5 : 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.15),
                        lineColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                // Overlay lines (200 DMA, realized price, etc.)
                ...widget.overlays.map((o) {
                  final oSpots = <FlSpot>[];
                  for (int i = 0; i < history.length; i++) {
                    final globalIdx = startIdx + i;
                    if (globalIdx < o.values.length) {
                      final v = o.values[globalIdx];
                      if (v != null) oSpots.add(FlSpot(i.toDouble(), v));
                    }
                  }
                  return LineChartBarData(
                    spots: oSpots,
                    isCurved: false,
                    color: o.color,
                    barWidth: 1.2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    dashArray: o.dashed ? [6, 4] : null,
                    belowBarData: BarAreaData(show: false),
                  );
                }),
              ],
            ),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          ),

          if (widget.overlayHeader != null)
            Positioned(
              left: 0,
              top: 0,
              right: rightReserved,
              child: widget.overlayHeader!,
            ),

          // ── Pulsing live-price dot ──────────────────────────
          Positioned(
            left: dotX - 10,
            top: dotY - 10,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return SizedBox(
                  width: 20,
                  height: 20,
                  child: Stack(alignment: Alignment.center, children: [
                    // outer ring expands and fades
                    Container(
                      width: 6 + 14 * t,
                      height: 6 + 14 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotCore.withValues(alpha: (1 - t) * 0.28),
                      ),
                    ),
                    // solid core (accent blue — visible on green/red line)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotCore,
                        boxShadow: [
                          BoxShadow(
                            color: dotCore.withValues(alpha: 0.45),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]);
      }),
    );
  }
}

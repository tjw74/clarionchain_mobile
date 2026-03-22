import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/price_provider.dart';
import '../theme/app_theme.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

String _timeLabel(DateTime dt, double visibleDays) {
  if (visibleDays <= 1) return DateFormat('HH:mm').format(dt);
  if (visibleDays <= 7) return DateFormat('EEE').format(dt);
  if (visibleDays <= 60) return DateFormat('MMM d').format(dt);
  if (visibleDays <= 365) return DateFormat('MMM').format(dt);
  return DateFormat('MMM yy').format(dt);
}

class PriceChart extends ConsumerStatefulWidget {
  const PriceChart({super.key});

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
    final allHistory = ref.watch(priceHistoryProvider);
    final loading = ref.watch(historyLoadingProvider);

    if (allHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppColors.btcOrange, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              loading ? 'Loading price history…' : 'Connecting to exchanges…',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
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
    final yPad = ((maxPrice - minPrice) * 0.08).clamp(50.0, double.infinity);
    final effMin = minPrice - yPad;
    final effMax = maxPrice + yPad;

    final isUp = history.last.price >= history.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final vc = history.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays =
        history.last.timestamp.difference(history.first.timestamp).inMinutes /
            1440.0;

    // Chart layout constants (must match SideTitles reservedSize)
    const rightReserved = 68.0;
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
                        '\$${_priceFmt.format(value)}',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                        textAlign: TextAlign.right,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: bottomReserved,
                    interval: labelInterval,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= history.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _timeLabel(history[idx].timestamp, visibleDays),
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
              ],
            ),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
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
                        color: lineColor.withValues(alpha: (1 - t) * 0.35),
                      ),
                    ),
                    // solid core
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lineColor,
                        boxShadow: [
                          BoxShadow(
                            color: lineColor.withValues(alpha: 0.6),
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

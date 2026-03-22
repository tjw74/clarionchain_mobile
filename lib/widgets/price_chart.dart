import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/price_provider.dart';
import '../theme/app_theme.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

String _formatTimeLabel(DateTime dt, Duration visibleSpan) {
  if (visibleSpan.inDays > 365) return DateFormat('MMM yy').format(dt);
  if (visibleSpan.inDays > 60)  return DateFormat('MMM d').format(dt);
  if (visibleSpan.inDays > 2)   return DateFormat('MMM d').format(dt);
  if (visibleSpan.inHours > 1)  return DateFormat('HH:mm').format(dt);
  return DateFormat('HH:mm').format(dt);
}

class PriceChart extends ConsumerStatefulWidget {
  const PriceChart({super.key});

  @override
  ConsumerState<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends ConsumerState<PriceChart> {
  double _lastScaleFactor = 1.0;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(priceHistoryProvider);
    final window = ref.watch(chartWindowProvider);
    final loading = ref.watch(historyLoadingProvider);

    if (history.isEmpty) {
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

    final totalPoints = history.length;
    final visibleCount =
        (window.visibleCount ?? totalPoints).clamp(2, totalPoints);
    final maxStart = totalPoints - visibleCount;
    final startIdx =
        (maxStart * window.scrollFraction).round().clamp(0, maxStart);
    final endIdx = (startIdx + visibleCount).clamp(0, totalPoints);

    final visible = history.sublist(startIdx, endIdx);
    final spots = visible.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.price);
    }).toList();

    final prices = visible.map((t) => t.price).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final yPadding = ((maxY - minY) * 0.08).clamp(10.0, double.infinity);

    final isUp = visible.last.price >= visible.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;

    // Time span of visible data for adaptive labels
    final visibleSpan = visible.last.timestamp.difference(visible.first.timestamp);
    final labelInterval = (visibleCount / 4).floorToDouble().clamp(1.0, double.infinity);

    return GestureDetector(
      onScaleStart: (_) => _lastScaleFactor = 1.0,
      onScaleUpdate: (details) {
        final delta = details.scale / _lastScaleFactor;
        if ((delta - 1.0).abs() > 0.02) {
          ref.read(chartWindowProvider.notifier).zoom(delta, totalPoints);
          _lastScaleFactor = details.scale;
        }
        if (details.pointerCount == 1 && details.scale == 1.0) {
          ref
              .read(chartWindowProvider.notifier)
              .scroll(-details.focalPointDelta.dx / 600);
        }
      },
      onDoubleTap: () => ref.read(chartWindowProvider.notifier).resetToAll(),
      child: LineChart(
        LineChartData(
          minY: minY - yPadding,
          maxY: maxY + yPadding,
          clipData: const FlClipData.all(),
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
                reservedSize: 68,
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
                reservedSize: 22,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = startIdx + value.toInt();
                  if (idx < 0 || idx >= history.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTimeLabel(history[idx].timestamp, visibleSpan),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceElevated,
              tooltipRoundedRadius: 8,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = startIdx + s.x.toInt();
                final ts = idx < history.length
                    ? history[idx].timestamp
                    : DateTime.now();
                return LineTooltipItem(
                  '\$${_priceFmt.format(s.y)}\n',
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: DateFormat('MMM d, HH:mm').format(ts),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: visibleCount < 200,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: visibleCount > 500 ? 1 : 2,
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
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
  }
}

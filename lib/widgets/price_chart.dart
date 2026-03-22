import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/price_provider.dart';
import '../theme/app_theme.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');
final _timeFmt = DateFormat('HH:mm');

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

    if (history.length < 2) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.btcOrange,
              strokeWidth: 2,
            ),
            SizedBox(height: 12),
            Text('Connecting to exchanges…',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    final visibleCount = window.visibleCount.clamp(2, history.length);
    final maxStart = history.length - visibleCount;
    final startIdx =
        (maxStart * window.scrollFraction).round().clamp(0, maxStart);
    final endIdx = startIdx + visibleCount;

    final visible = history.sublist(startIdx, endIdx);
    final spots = visible.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.price);
    }).toList();

    final prices = visible.map((t) => t.price).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final yPadding = (maxY - minY) * 0.1;

    final isUp = visible.last.price >= visible.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;

    return GestureDetector(
      onScaleStart: (_) => _lastScaleFactor = 1.0,
      onScaleUpdate: (details) {
        final delta = details.scale / _lastScaleFactor;
        if ((delta - 1.0).abs() > 0.02) {
          ref.read(chartWindowProvider.notifier).zoom(delta);
          _lastScaleFactor = details.scale;
        }
        if (details.pointerCount == 1 && details.scale == 1.0) {
          // pan
          ref
              .read(chartWindowProvider.notifier)
              .scroll(-details.focalPointDelta.dx / 800);
        }
      },
      onDoubleTap: () => ref.read(chartWindowProvider.notifier).resetToLatest(),
      child: LineChart(
        LineChartData(
          minY: minY - yPadding,
          maxY: maxY + yPadding,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.border,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
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
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.right,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (visibleCount / 4).floorToDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = startIdx + value.toInt();
                  if (idx < 0 || idx >= history.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _timeFmt.format(history[idx].timestamp),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
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
                return LineTooltipItem(
                  '\$${_priceFmt.format(s.y)}',
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: lineColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.2),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 150),
        curve: Curves.linear,
      ),
    );
  }
}

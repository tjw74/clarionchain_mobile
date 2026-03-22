import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/price_provider.dart';
import '../theme/app_theme.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

String _timeLabel(DateTime dt, double visibleDays) {
  if (visibleDays <= 1) return DateFormat('HH:mm').format(dt);
  if (visibleDays <= 7) return DateFormat('EEE HH:mm').format(dt);
  if (visibleDays <= 60) return DateFormat('MMM d').format(dt);
  if (visibleDays <= 365) return DateFormat('MMM').format(dt);
  return DateFormat('MMM yy').format(dt);
}

class PriceChart extends ConsumerStatefulWidget {
  const PriceChart({super.key});

  @override
  ConsumerState<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends ConsumerState<PriceChart> {
  // Visible window: indices into the history list
  double _viewStart = 0; // 0.0 = oldest
  double _viewEnd = 1.0; // 1.0 = newest

  // For gesture tracking
  double? _scaleStartSpan;
  double? _scaleStartMid;
  double? _scaleStartViewStart;
  double? _scaleStartViewEnd;

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
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final yPadding = ((maxY - minY) * 0.08).clamp(50.0, double.infinity);

    final isUp = history.last.price >= history.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final visibleCount = history.length;
    final labelInterval =
        (visibleCount / 4).floorToDouble().clamp(1.0, double.infinity);

    // Compute visible time span for label formatting
    final visibleDays = history.last.timestamp
        .difference(history.first.timestamp)
        .inMinutes / 1440.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Absorb horizontal drags with 2+ fingers to prevent PageView conflict
      onScaleStart: (details) {
        _scaleStartSpan = 1.0; // relative; we use details.scale from onScaleUpdate
        _scaleStartMid = details.localFocalPoint.dx;
        _scaleStartViewStart = _viewStart;
        _scaleStartViewEnd = _viewEnd;
      },
      onScaleUpdate: (details) {
        if (_scaleStartViewStart == null || _scaleStartViewEnd == null) return;
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final width = renderBox.size.width;

        final oldSpan = _scaleStartViewEnd! - _scaleStartViewStart!;

        // Pinch-to-zoom: scale > 1 = zoom in, < 1 = zoom out
        final newSpan = (oldSpan / details.scale.clamp(0.01, 100.0))
            .clamp(0.005, 1.0);

        // Focal point as fraction of view width → fraction of data span
        final focalFrac = ((_scaleStartMid ?? width / 2) / width)
            .clamp(0.0, 1.0);
        final focalData =
            _scaleStartViewStart! + focalFrac * oldSpan;

        // Pan: horizontal translation
        double panDelta = 0;
        if (width > 0) {
          panDelta = -(details.focalPointDelta.dx / width) * newSpan;
        }

        double newStart =
            (focalData - focalFrac * newSpan + panDelta).clamp(0.0, 1.0 - newSpan);
        double newEnd = (newStart + newSpan).clamp(newSpan, 1.0);
        newStart = newEnd - newSpan;

        setState(() {
          _viewStart = newStart;
          _viewEnd = newEnd;
        });
      },
      onDoubleTap: () {
        setState(() {
          _viewStart = 0;
          _viewEnd = 1.0;
        });
      },
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
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceElevated,
              tooltipRoundedRadius: 8,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt();
                final ts =
                    idx < history.length ? history[idx].timestamp : DateTime.now();
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
              isCurved: visibleCount < 500,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: visibleCount > 300 ? 1.5 : 2,
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
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    );
  }
}

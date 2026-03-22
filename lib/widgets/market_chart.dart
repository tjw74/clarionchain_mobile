import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/exchange_tick.dart';
import '../theme/app_theme.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

class MarketChart extends StatefulWidget {
  final List<PriceTick> priceHistory;
  final List<PriceTick> realizedHistory;

  const MarketChart({
    super.key,
    required this.priceHistory,
    required this.realizedHistory,
  });

  @override
  State<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends State<MarketChart> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final allPrice = widget.priceHistory;
    final allRealized = widget.realizedHistory;
    if (allPrice.isEmpty) return const SizedBox.shrink();

    final n = allPrice.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final priceSlice = startIdx < endIdx
        ? allPrice.sublist(startIdx, endIdx + 1)
        : [allPrice.last];

    // Align realized price to same date range by timestamp
    final startTs = priceSlice.first.timestamp;
    final endTs = priceSlice.last.timestamp;
    final realizedSlice = allRealized
        .where((t) =>
            !t.timestamp.isBefore(startTs) && !t.timestamp.isAfter(endTs))
        .toList();

    final priceSpots = priceSlice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    // Map realized price to same x-axis indices by interpolating dates
    final List<FlSpot> realizedSpots;
    if (realizedSlice.isNotEmpty && priceSlice.isNotEmpty) {
      realizedSpots = realizedSlice.map((t) {
        // Find fractional x position based on timestamp
        final totalMs =
            endTs.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
        final elapsedMs =
            t.timestamp.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
        final x = totalMs > 0
            ? (elapsedMs / totalMs) * (priceSlice.length - 1)
            : 0.0;
        return FlSpot(x, t.price);
      }).toList();
    } else {
      realizedSpots = [];
    }

    // Y axis bounds across both series
    final allPrices = [
      ...priceSlice.map((t) => t.price),
      ...realizedSlice.map((t) => t.price),
    ];
    final minY = allPrices.reduce((a, b) => a < b ? a : b);
    final maxY = allPrices.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxY - minY) * 0.08).clamp(500.0, double.infinity);

    final vc = priceSlice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays = endTs.difference(startTs).inMinutes / 1440.0;

    String timeLabel(DateTime dt) {
      if (visibleDays <= 7) return DateFormat('MMM d').format(dt);
      if (visibleDays <= 60) return DateFormat('MMM d').format(dt);
      if (visibleDays <= 365) return DateFormat('MMM').format(dt);
      return DateFormat('MMM yy').format(dt);
    }

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
        final s = (focalData - focalFrac * newSpan + panData)
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
      child: LineChart(
        LineChartData(
          minY: minY - yPad,
          maxY: maxY + yPad,
          clipData: const FlClipData.all(),
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
                  if (idx < 0 || idx >= priceSlice.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      timeLabel(priceSlice[idx].timestamp),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            // BTC market price
            LineChartBarData(
              spots: priceSpots,
              isCurved: vc < 500,
              curveSmoothness: 0.15,
              color: AppColors.positive,
              barWidth: vc > 300 ? 1.5 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.positive.withValues(alpha: 0.12),
                    AppColors.positive.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // Realized price
            if (realizedSpots.isNotEmpty)
              LineChartBarData(
                spots: realizedSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.btcOrange,
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                dashArray: [4, 4],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }
}

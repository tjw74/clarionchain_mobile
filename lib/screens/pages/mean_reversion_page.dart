import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../utils/chart_math.dart';
import '../../models/exchange_tick.dart';
import '../../widgets/category_page_layout.dart';

class MeanReversionPage extends ConsumerStatefulWidget {
  const MeanReversionPage({super.key});

  @override
  ConsumerState<MeanReversionPage> createState() => _MeanReversionPageState();
}

class _MeanReversionPageState extends ConsumerState<MeanReversionPage> {
  // Default 4yr view: show last ~50% of 2yr history = last half
  // priceHistoryProvider = 730 days; we default to show all
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final priceState = ref.watch(priceStateProvider);
    final history = ref.watch(priceHistoryProvider);
    final dailyAsync = ref.watch(priceHistoryDailyProvider);

    final price = priceState.vwap;

    final dailyHistory = dailyAsync.valueOrNull ?? [];
    final dailyPrices = dailyHistory.map((t) => t.price).toList();

    final dma50 =
        dailyPrices.length >= 50 ? sma(dailyPrices, 50) : <double?>[];
    final dma200 =
        dailyPrices.length >= 200 ? sma(dailyPrices, 200) : <double?>[];
    final wma200w = dailyPrices.length >= 1400
        ? wma(dailyPrices, 1400)
        : <double?>[];

    // Current values of each MA
    double? cur50Dma;
    for (int i = dma50.length - 1; i >= 0; i--) {
      if (dma50[i] != null) {
        cur50Dma = dma50[i];
        break;
      }
    }
    double? cur200Dma;
    for (int i = dma200.length - 1; i >= 0; i--) {
      if (dma200[i] != null) {
        cur200Dma = dma200[i];
        break;
      }
    }
    double? cur200Wma;
    for (int i = wma200w.length - 1; i >= 0; i--) {
      if (wma200w[i] != null) {
        cur200Wma = wma200w[i];
        break;
      }
    }

    // Z-scores — computed on the MA values themselves
    final dma50Values = dma50.whereType<double>().toList();
    final dma200Values = dma200.whereType<double>().toList();
    final wma200wValues = wma200w.whereType<double>().toList();

    final zScore50 = cur50Dma != null && dma50Values.length >= 2
        ? logZScore(dma50Values, cur50Dma)
        : 0.0;
    final zScore200Dma = cur200Dma != null && dma200Values.length >= 2
        ? logZScore(dma200Values, cur200Dma)
        : 0.0;
    final zScore200Wma = cur200Wma != null && wma200wValues.length >= 2
        ? logZScore(wma200wValues, cur200Wma)
        : 0.0;

    final mayer = cur200Dma != null && cur200Dma > 0 && price > 0
        ? mayerMultiple(price, dma200)
        : 0.0;

    final priceQuantile =
        dailyPrices.isNotEmpty ? quantile(dailyPrices, price) : 0.0;

    // Signal
    String signal;
    if (zScore200Dma > 2.0) {
      signal = 'Historically overextended';
    } else if (zScore200Dma < -1.0) {
      signal = 'Historically undervalued';
    } else {
      signal = 'Fairly valued';
    }

    // Align overlays to chart history
    final chartLen = history.length;
    final totalDaily = dailyPrices.length;

    List<double?> _alignOverlay(List<double?> full) {
      if (full.isEmpty || chartLen == 0) return List.filled(chartLen, null);
      if (totalDaily >= chartLen) {
        return full.sublist(totalDaily - chartLen);
      }
      return List.filled(chartLen, null);
    }

    final overlay50 = _alignOverlay(dma50);
    final overlay200 = _alignOverlay(dma200);
    final overlayWma = _alignOverlay(wma200w);

    return CategoryPageLayout(
      header: const CategoryPageHeader(
        category: 'BTC',
        title: 'Mean reversion',
        accentColor: AppColors.btcOrange,
        trailingHint: 'MA bands',
      ),
      chart: _buildChart(
          context, history, overlay50, overlay200, overlayWma),
      stats: _buildStats(
        zScore50,
        zScore200Dma,
        zScore200Wma,
        mayer,
        priceQuantile,
        signal,
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<PriceTick> history,
    List<double?> overlay50,
    List<double?> overlay200,
    List<double?> overlayWma,
  ) {
    if (history.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.btcOrange, strokeWidth: 2),
      );
    }

    final n = history.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final slice = startIdx < endIdx
        ? history.sublist(startIdx, endIdx + 1)
        : [history.last];

    final spots = slice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    double minP = slice.map((t) => t.price).reduce((a, b) => a < b ? a : b);
    double maxP = slice.map((t) => t.price).reduce((a, b) => a > b ? a : b);

    List<FlSpot> _makeOverlaySpots(List<double?> overlay) {
      final result = <FlSpot>[];
      for (int i = 0; i < slice.length; i++) {
        final gi = startIdx + i;
        if (gi < overlay.length) {
          final v = overlay[gi];
          if (v != null) {
            if (v < minP) minP = v;
            if (v > maxP) maxP = v;
            result.add(FlSpot(i.toDouble(), v));
          }
        }
      }
      return result;
    }

    final spots50 = _makeOverlaySpots(overlay50);
    final spots200 = _makeOverlaySpots(overlay200);
    final spotsWma = _makeOverlaySpots(overlayWma);

    final yPad = ((maxP - minP) * 0.08).clamp(50.0, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final vc = slice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays =
        slice.last.timestamp.difference(slice.first.timestamp).inMinutes /
            1440.0;

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
        final s =
            (focalData - focalFrac * newSpan + panData).clamp(0.0, 1.0 - newSpan);
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
          minY: effMin,
          maxY: effMax,
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
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: kChartAxisReservedRight,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    formatAxisUsdCompact(value),
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
                reservedSize: 22,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= slice.length) {
                    return const SizedBox.shrink();
                  }
                  final dt = slice[idx].timestamp;
                  final label = visibleDays > 365
                      ? DateFormat('MMM yy').format(dt)
                      : visibleDays > 60
                          ? DateFormat('MMM').format(dt)
                          : DateFormat('MMM d').format(dt);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            // Price (teal)
            LineChartBarData(
              spots: spots,
              isCurved: vc < 200,
              curveSmoothness: 0.2,
              color: AppColors.positive,
              barWidth: vc > 300 ? 1.5 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            // 50 DMA (blue)
            if (spots50.isNotEmpty)
              LineChartBarData(
                spots: spots50,
                isCurved: false,
                color: const Color(0xFF4488FF),
                barWidth: 1.2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            // 200 DMA (gold)
            if (spots200.isNotEmpty)
              LineChartBarData(
                spots: spots200,
                isCurved: false,
                color: const Color(0xFFFFD700),
                barWidth: 1.2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            // 200 WMA (orange dashed)
            if (spotsWma.isNotEmpty)
              LineChartBarData(
                spots: spotsWma,
                isCurved: false,
                color: const Color(0xFFFF8C00),
                barWidth: 1.2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                dashArray: [6, 4],
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _buildStats(
    double zScore50,
    double zScore200Dma,
    double zScore200Wma,
    double mayer,
    double priceQuantile,
    String signal,
  ) {
    Color _zColor(double z) {
      if (z > 2.0) return AppColors.negative;
      if (z < -1.0) return AppColors.positive;
      return AppColors.textPrimary;
    }

    final mayerColor = mayer > 2.4
        ? AppColors.negative
        : (mayer > 0 && mayer < 0.8)
            ? AppColors.positive
            : AppColors.textPrimary;

    final signalColor = signal == 'Historically overextended'
        ? AppColors.negative
        : signal == 'Historically undervalued'
            ? AppColors.positive
            : AppColors.textPrimary;

    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: '50 DMA Z-SCORE',
                        value: zScore50 != 0
                            ? zScore50.toStringAsFixed(2)
                            : '—',
                        valueColor: _zColor(zScore50),
                        signal: zScore50 > 2
                            ? 'Overextended vs 50DMA'
                            : zScore50 < -1
                                ? 'Undervalued vs 50DMA'
                                : 'Normal range',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: '200 DMA Z-SCORE',
                        value: zScore200Dma != 0
                            ? zScore200Dma.toStringAsFixed(2)
                            : '—',
                        valueColor: _zColor(zScore200Dma),
                        signal: zScore200Dma > 2
                            ? 'Overextended vs 200DMA'
                            : zScore200Dma < -1
                                ? 'Undervalued vs 200DMA'
                                : 'Normal range',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: '200 WMA Z-SCORE',
                        value: zScore200Wma != 0
                            ? zScore200Wma.toStringAsFixed(2)
                            : '—',
                        valueColor: _zColor(zScore200Wma),
                        signal: zScore200Wma > 2
                            ? 'Overextended vs 200WMA'
                            : zScore200Wma < -1
                                ? 'Undervalued vs 200WMA'
                                : 'Normal range',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'MAYER MULTIPLE',
                        value: mayer > 0 ? mayer.toStringAsFixed(2) : '—',
                        valueColor: mayer > 0 ? mayerColor : AppColors.textPrimary,
                        signal: 'price / 200 DMA',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: 'PRICE QUANTILE',
                        value: priceQuantile > 0
                            ? '${(priceQuantile * 100).toStringAsFixed(1)}%'
                            : '—',
                        valueColor: priceQuantile > 0.9
                            ? AppColors.negative
                            : priceQuantile > 0 && priceQuantile < 0.3
                                ? AppColors.positive
                                : AppColors.textPrimary,
                        signal: 'of full price history',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'SIGNAL',
                        value: signal,
                        valueColor: signalColor,
                        signal: 'Based on 200DMA z-score',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

class _StatPanel extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String signal;

  const _StatPanel({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
                color: valueColor, fontSize: 20, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (signal.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(signal,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

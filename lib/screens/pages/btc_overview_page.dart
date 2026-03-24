import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/derivatives_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../utils/chart_math.dart';
import '../../models/exchange_tick.dart';
import '../../widgets/category_page_layout.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

class BtcOverviewPage extends ConsumerStatefulWidget {
  const BtcOverviewPage({super.key});

  @override
  ConsumerState<BtcOverviewPage> createState() => _BtcOverviewPageState();
}

class _BtcOverviewPageState extends ConsumerState<BtcOverviewPage> {
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
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);
    final supplyAsync = ref.watch(supplyInProfitProvider);
    final fundingAsync = ref.watch(fundingProvider);

    final price = priceState.vwap;

    final dailyPrices =
        dailyAsync.valueOrNull?.map((t) => t.price).toList() ?? [];
    final dma200 =
        dailyPrices.length >= 200 ? sma(dailyPrices, 200) : <double?>[];

    double? currentDma;
    if (dma200.isNotEmpty) {
      for (int i = dma200.length - 1; i >= 0; i--) {
        if (dma200[i] != null) {
          currentDma = dma200[i];
          break;
        }
      }
    }

    final mayer =
        currentDma != null && currentDma > 0 && price > 0
            ? mayerMultiple(price, dma200)
            : 0.0;

    final realizedHistory = realizedAsync.valueOrNull ?? [];
    final currentRealized =
        realizedHistory.isNotEmpty ? realizedHistory.last.price : 0.0;
    final mvrv =
        currentRealized > 0 && price > 0 ? price / currentRealized : 0.0;

    final supplyHistory = supplyAsync.valueOrNull ?? [];
    final supplyInProfit =
        supplyHistory.isNotEmpty ? supplyHistory.last.price : 0.0;

    final fundingRate = fundingAsync.valueOrNull?.rate ?? 0.0;
    final fundingAnnualized = fundingAsync.valueOrNull?.annualizedPct ?? 0.0;

    final mayerColor = mayer > 2.4
        ? AppColors.negative
        : (mayer > 0 && mayer < 0.8)
            ? AppColors.positive
            : AppColors.textPrimary;

    final mvrvColor = mvrv > 3.5
        ? AppColors.negative
        : (mvrv > 0 && mvrv < 1.0)
            ? AppColors.positive
            : AppColors.textPrimary;

    final fundColor = fundingRate > 0.0003
        ? AppColors.negative
        : (fundingRate < -0.0001 ? AppColors.positive : AppColors.textPrimary);

    // Align DMA overlay to priceHistoryProvider (2yr daily) indices
    // priceHistoryProvider has up to 730 points; dailyAsync has full history
    // We take the last N points of dma200 matching the chart data length
    final chartLen = history.length;
    final List<double?> overlayDma200;
    if (dma200.isNotEmpty && chartLen > 0) {
      final totalDaily = dailyAsync.valueOrNull?.length ?? 0;
      if (totalDaily >= chartLen) {
        overlayDma200 = dma200.sublist(totalDaily - chartLen);
      } else {
        overlayDma200 = List.filled(chartLen, null);
      }
    } else {
      overlayDma200 = List.filled(chartLen, null);
    }

    return CategoryPageLayout(
      header: const CategoryPageHeader(
        category: 'BTC',
        title: 'Overview',
        accentColor: AppColors.btcOrange,
        trailingHint: 'Spot vs on-chain',
      ),
      chart: _buildChart(context, history, overlayDma200),
      stats: _buildStats(
        mayer,
        mayerColor,
        currentDma,
        mvrv,
        mvrvColor,
        currentRealized,
        supplyInProfit,
        fundingRate,
        fundingAnnualized,
        fundColor,
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<PriceTick> history,
    List<double?> overlayDma200,
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

    final prices = slice.map((t) => t.price).toList();
    double minP = prices.reduce((a, b) => a < b ? a : b);
    double maxP = prices.reduce((a, b) => a > b ? a : b);

    // Include overlay values in y range
    for (int i = startIdx; i <= endIdx && i < overlayDma200.length; i++) {
      final v = overlayDma200[i];
      if (v != null) {
        if (v < minP) minP = v;
        if (v > maxP) maxP = v;
      }
    }

    final yPad = ((maxP - minP) * 0.08).clamp(50.0, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final isUp = slice.last.price >= slice.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final vc = slice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays = slice.last.timestamp
            .difference(slice.first.timestamp)
            .inMinutes /
        1440.0;

    // Overlay spots
    final dmaSpots = <FlSpot>[];
    for (int i = 0; i < slice.length; i++) {
      final gi = startIdx + i;
      if (gi < overlayDma200.length) {
        final v = overlayDma200[gi];
        if (v != null) dmaSpots.add(FlSpot(i.toDouble(), v));
      }
    }

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
            LineChartBarData(
              spots: spots,
              isCurved: vc < 200,
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
            if (dmaSpots.isNotEmpty)
              LineChartBarData(
                spots: dmaSpots,
                isCurved: false,
                color: const Color(0xFFFFD700),
                barWidth: 1.2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
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
    double mayer,
    Color mayerColor,
    double? currentDma,
    double mvrv,
    Color mvrvColor,
    double currentRealized,
    double supplyInProfit,
    double fundingRate,
    double fundingAnnualized,
    Color fundColor,
  ) {
    final mayerSignal = mayer > 2.4
        ? 'Historically expensive'
        : (mayer > 0 && mayer < 0.8)
            ? 'Historically cheap'
            : 'Normal range';
    final mvrvSignal = mvrv > 3.5
        ? 'Overvalued zone'
        : (mvrv > 0 && mvrv < 1.0)
            ? 'Undervalued zone'
            : 'Fair value range';
    final supplyStr = supplyInProfit > 0
        ? '${(supplyInProfit).toStringAsFixed(1)}%'
        : '—';
    final fundStr = fundingRate != 0
        ? '${(fundingRate * 100).toStringAsFixed(4)}%'
        : '—';
    final fundSignal =
        fundingAnnualized != 0 ? '${fundingAnnualized.toStringAsFixed(1)}% annualized' : '';

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
                        label: 'MAYER MULTIPLE',
                        value: mayer > 0 ? mayer.toStringAsFixed(2) : '—',
                        valueColor: mayer > 0 ? mayerColor : AppColors.textPrimary,
                        signal: mayerSignal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: '200 DMA',
                        value: currentDma != null
                            ? '\$${_priceFmt.format(currentDma.round())}'
                            : '—',
                        valueColor: AppColors.textPrimary,
                        signal: '200-day moving average',
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
                        label: 'MVRV RATIO',
                        value: mvrv > 0 ? mvrv.toStringAsFixed(2) : '—',
                        valueColor: mvrv > 0 ? mvrvColor : AppColors.textPrimary,
                        signal: mvrvSignal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'REALIZED PRICE',
                        value: currentRealized > 0
                            ? '\$${_priceFmt.format(currentRealized.round())}'
                            : '—',
                        valueColor: AppColors.btcOrange,
                        signal: 'Avg cost basis on-chain',
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
                        label: 'SUPPLY IN PROFIT',
                        value: supplyStr,
                        valueColor: supplyInProfit > 80
                            ? AppColors.negative
                            : supplyInProfit > 0 && supplyInProfit < 50
                                ? AppColors.positive
                                : AppColors.textPrimary,
                        signal: '% of UTXOs above cost',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'FUNDING RATE',
                        value: fundStr,
                        valueColor: fundColor,
                        signal: fundSignal,
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

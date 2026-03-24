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

class _BtcOverviewPageState extends ConsumerState<BtcOverviewPage>
    with SingleTickerProviderStateMixin {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  late final AnimationController _pulse;

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
    final priceState = ref.watch(priceStateProvider);
    final history = ref.watch(chartDailyPriceHistoryProvider);
    final dailyAsync = ref.watch(priceHistoryDailyProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);
    final supplyAsync = ref.watch(supplyInProfitProvider);
    final fundingAsync = ref.watch(fundingProvider);

    final price = priceState.vwap;

    final dailyPrices =
        dailyAsync.valueOrNull?.map((t) => t.price).toList() ?? [];
    final chartPrices = history.map((t) => t.price).toList();
    final pricesForStats =
        dailyPrices.isNotEmpty ? dailyPrices : chartPrices;

    final dma200 = pricesForStats.length >= 200
        ? sma(pricesForStats, 200)
        : <double?>[];

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
    final hasSupplyInProfit = supplyHistory.isNotEmpty;

    final fundingData = fundingAsync.valueOrNull;
    final fundingRate = fundingData?.rate ?? 0.0;
    final fundingAnnualized = fundingData?.annualizedPct ?? 0.0;

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

    final chartLen = history.length;
    List<double?> tailAlign(List<double?> full) {
      if (full.isEmpty || chartLen == 0) {
        return List<double?>.filled(chartLen, null);
      }
      if (full.length == chartLen) return List<double?>.from(full);
      if (full.length > chartLen) return full.sublist(full.length - chartLen);
      return List<double?>.filled(chartLen, null);
    }

    final overlayDma200 = tailAlign(dma200);

    Widget chartBody;
    if (dailyAsync.isLoading && history.isEmpty) {
      chartBody = const Center(
        child: CircularProgressIndicator(
            color: AppColors.accent, strokeWidth: 2),
      );
    } else if (history.isEmpty) {
      chartBody = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            dailyAsync.hasError
                ? 'Bitview daily prices failed to load.'
                : 'No daily price data. Check network / VPN and reopen the app.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      );
    } else {
      chartBody = _buildChart(context, history, overlayDma200);
    }

    return CategoryPageLayout(
      header: const CategoryPageHeader(
        category: 'BTC',
        title: 'Overview',
        accentColor: AppColors.accent,
        trailingHint: 'Spot vs on-chain',
      ),
      chart: chartBody,
      stats: _buildStats(
        mayer,
        mayerColor,
        currentDma,
        mvrv,
        mvrvColor,
        currentRealized,
        supplyInProfit,
        hasSupplyInProfit,
        fundingRate,
        fundingAnnualized,
        fundColor,
        fundingData != null,
        dailyAsync.isLoading,
        realizedAsync.isLoading,
        realizedAsync.hasError,
        supplyAsync.isLoading,
        supplyAsync.hasError,
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
            color: AppColors.accent, strokeWidth: 2),
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

    for (int i = startIdx; i <= endIdx && i < overlayDma200.length; i++) {
      final v = overlayDma200[i];
      if (v != null) {
        if (v < minP) minP = v;
        if (v > maxP) maxP = v;
      }
    }

    final (effMin, effMax) = yRangeWithMinSpan(minP, maxP);

    final isUp = slice.last.price >= slice.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final dotCore = AppColors.accent;
    final vc = slice.length;
    final labelIdx = xAxisLabelIndices(vc).toSet();
    final spanDays =
        slice.last.timestamp.difference(slice.first.timestamp).inMinutes /
            1440.0;

    final dmaSpots = <FlSpot>[];
    for (int i = 0; i < slice.length; i++) {
      final gi = startIdx + i;
      if (gi < overlayDma200.length) {
        final v = overlayDma200[gi];
        if (v != null) dmaSpots.add(FlSpot(i.toDouble(), v));
      }
    }

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartW = constraints.maxWidth - rightReserved;
          final chartH = constraints.maxHeight - bottomReserved;
          final lastPrice = slice.last.price;
          final denom = (effMax - effMin).abs();
          final dotY = denom > 1e-12
              ? chartH * (1.0 - (lastPrice - effMin) / denom)
              : chartH * 0.5;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              LineChart(
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
                          final idx = value.round().clamp(0, slice.length - 1);
                          if (!labelIdx.contains(idx)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              bottomAxisDateLabel(
                                  slice[idx].timestamp, spanDays),
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
                        color: AppColors.accentSecondary,
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
              Positioned(
                left: chartW - 10,
                top: dotY - 10,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return SizedBox(
                      width: 20,
                      height: 20,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 6 + 14 * t,
                            height: 6 + 14 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotCore.withValues(alpha: (1 - t) * 0.28),
                            ),
                          ),
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
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
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
    bool hasSupplyInProfit,
    double fundingRate,
    double fundingAnnualized,
    Color fundColor,
    bool hasFunding,
    bool dailyLoading,
    bool realizedLoading,
    bool realizedError,
    bool supplyLoading,
    bool supplyError,
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
    final supplyStr = hasSupplyInProfit
        ? '${supplyInProfit.toStringAsFixed(1)}%'
        : '—';
    final fundStr = hasFunding
        ? '${(fundingRate * 100).toStringAsFixed(4)}%'
        : '—';
    final fundSignal = hasFunding
        ? '${fundingAnnualized.toStringAsFixed(1)}% annualized'
        : '';

    String dmaSub() {
      if (currentDma != null) return '200-day moving average';
      if (dailyLoading) return 'Loading history…';
      return 'Need ≥200 daily closes';
    }

    String mvrvSub() {
      if (mvrv > 0) return mvrvSignal;
      if (realizedLoading) return 'Loading on-chain…';
      if (realizedError) return 'On-chain data unavailable';
      return 'Fair value range';
    }

    String realizedSub() {
      if (currentRealized > 0) return 'Avg cost basis on-chain';
      if (realizedLoading) return 'Loading on-chain…';
      if (realizedError) return 'Unavailable';
      return 'Avg cost basis on-chain';
    }

    String supplySub() {
      if (hasSupplyInProfit) return '% of UTXOs above cost';
      if (supplyLoading) return 'Loading…';
      if (supplyError) return 'Unavailable';
      return '% of UTXOs above cost';
    }

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
                        signal: mayer > 0
                            ? mayerSignal
                            : (dailyLoading
                                ? 'Loading…'
                                : 'Need 200 DMA + spot'),
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
                        signal: dmaSub(),
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
                        signal: mvrvSub(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'REALIZED PRICE',
                        value: currentRealized > 0
                            ? '\$${_priceFmt.format(currentRealized.round())}'
                            : '—',
                        valueColor: AppColors.accent,
                        signal: realizedSub(),
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
                        signal: supplySub(),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

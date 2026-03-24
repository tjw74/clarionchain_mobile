import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_math.dart';
import '../../widgets/price_chart.dart';
import '../../widgets/stat_card.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');
final _pctFmt = NumberFormat('+0.00%;-0.00%', 'en_US');

class PricePage extends ConsumerWidget {
  const PricePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceState = ref.watch(priceStateProvider);
    final chartHistory = ref.watch(chartDailyPriceHistoryProvider);
    final dailyAsync = ref.watch(priceHistoryDailyProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);

    final price = priceState.vwap;

    // ── Overlay computation ──────────────────────────────────────────────────
    final dailyPrices =
        dailyAsync.valueOrNull?.map((t) => t.price).toList() ?? [];
    final dma200 = dailyPrices.isNotEmpty ? sma(dailyPrices, 200) : <double?>[];
    final wma200 =
        dailyPrices.length >= 1400 ? wma(dailyPrices, 1400) : <double?>[];

    // Realized price aligned to same length as daily
    final realizedHistory = realizedAsync.valueOrNull ?? [];
    final dailyHistory = dailyAsync.valueOrNull ?? [];

    // Build a realized price array aligned to dailyHistory timestamps
    final Map<int, double> realizedByDay = {};
    for (final t in realizedHistory) {
      realizedByDay[t.timestamp.millisecondsSinceEpoch ~/ 86400000] = t.price;
    }
    final realizedAligned = dailyHistory
        .map((t) =>
            realizedByDay[t.timestamp.millisecondsSinceEpoch ~/ 86400000])
        .toList();

    final chartLen = chartHistory.length;
    final totalDaily = dailyHistory.length;
    List<double?> tailAlign(List<double?> full) {
      if (full.isEmpty || chartLen == 0) {
        return List<double?>.filled(chartLen, null);
      }
      if (totalDaily >= chartLen) return full.sublist(totalDaily - chartLen);
      return List<double?>.filled(chartLen, null);
    }

    final dma200Chart = tailAlign(dma200);
    final wma200Chart = tailAlign(wma200);
    final realizedChart = realizedAligned.isEmpty
        ? List<double?>.filled(chartLen, null)
        : tailAlign(realizedAligned);

    // ── Current stats ────────────────────────────────────────────────────────
    final currentDma =
        dma200.isNotEmpty ? dma200.lastWhere((v) => v != null, orElse: () => null) : null;
    // ignore: unused_local_variable — reserved for future WMA stat card
    final currentWma =
        wma200.isNotEmpty ? wma200.lastWhere((v) => v != null, orElse: () => null) : null;
    final mayer = currentDma != null && price > 0
        ? mayerMultiple(price, dma200)
        : 0.0;
    final currentRealized = realizedHistory.isNotEmpty ? realizedHistory.last.price : 0.0;
    final mvrv = currentRealized > 0 && price > 0 ? price / currentRealized : 0.0;

    final pQuantile = dailyPrices.isNotEmpty
        ? quantile(dailyPrices, price)
        : 0.0;
    final pZScore = dailyPrices.isNotEmpty ? logZScore(dailyPrices, price) : 0.0;
    final hasPZ = dailyPrices.isNotEmpty;

    // 24h change
    double? change24h;
    if (chartHistory.length >= 2) {
      final oldest = chartHistory.first.price;
      final newest = chartHistory.last.price;
      if (oldest > 0) change24h = (newest - oldest) / oldest;
    }
    final changeColor =
        (change24h ?? 0) >= 0 ? AppColors.positive : AppColors.negative;

    // Mayer color
    final mayerColor = mayer > 2.4
        ? AppColors.negative
        : mayer > 0 && mayer < 1.0
            ? const Color(0xFF6B8EFF)
            : AppColors.textPrimary;

    // MVRV color
    final mvrvColor = mvrv > 3.5
        ? AppColors.negative
        : mvrv > 0 && mvrv < 1.0
            ? const Color(0xFF6B8EFF)
            : AppColors.textPrimary;

    // Overlays for the chart (indices match chartDailyPriceHistoryProvider)
    final overlays = [
      if (dma200Chart.any((v) => v != null))
        ChartOverlay(
          values: dma200Chart,
          color: const Color(0xFFFFD700), // gold
          label: '200 DMA',
        ),
      if (wma200Chart.any((v) => v != null))
        ChartOverlay(
          values: wma200Chart,
          color: const Color(0xFFFF8C00), // orange
          dashed: true,
          label: '200 WMA',
        ),
      if (realizedChart.any((v) => v != null))
        ChartOverlay(
          values: realizedChart,
          color: AppColors.btcOrange.withValues(alpha: 0.8),
          dashed: true,
          label: 'Realized',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Price header
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BTC / USD',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                price > 0 ? '\$${_priceFmt.format(price)}' : '—',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1),
              ),
            ]),
            const Spacer(),
            if (change24h != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: changeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_pctFmt.format(change24h),
                    style: TextStyle(
                        color: changeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
          ]),

          const SizedBox(height: 2),
          Text(
            priceState.hasData
                ? '${priceState.ticks.length} exchange${priceState.ticks.length != 1 ? 's' : ''} · VWAP'
                : 'Connecting…',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),

          const SizedBox(height: 8),

          // Overlay legend
          if (overlays.isNotEmpty)
            Row(children: [
              for (final o in overlays) ...[
                Container(
                    width: 16,
                    height: 2,
                    color: o.color),
                const SizedBox(width: 4),
                Text(o.label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9)),
                const SizedBox(width: 10),
              ],
            ]),

          const SizedBox(height: 4),

          // Chart
          Expanded(child: PriceChart(overlays: overlays)),

          const SizedBox(height: 10),

          // Stats row 1: Mayer + MVRV
          StatRow(cards: [
            StatCard(
              label: 'Mayer Multiple',
              icon: Icons.speed_rounded,
              value: mayer > 0 ? mayer.toStringAsFixed(2) : '—',
              valueColor: mayer > 0 ? mayerColor : null,
              subValue: mayer > 2.4
                  ? 'Historically expensive'
                  : mayer > 0 && mayer < 1.0
                      ? 'Below 200 DMA'
                      : 'Normal range',
              compact: true,
            ),
            StatCard(
              label: 'MVRV Ratio',
              icon: Icons.show_chart_rounded,
              value: mvrv > 0 ? mvrv.toStringAsFixed(2) : '—',
              valueColor: mvrv > 0 ? mvrvColor : null,
              subValue: mvrv > 3.5
                  ? 'Overvalued zone'
                  : mvrv > 0 && mvrv < 1.0
                      ? 'Undervalued zone'
                      : 'Fair value',
              compact: true,
            ),
          ]),

          const SizedBox(height: 6),

          // Stats row 2: Z-Score + Quantile
          StatRow(cards: [
            StatCard(
              label: 'Price Z-Score',
              icon: Icons.analytics_outlined,
              value: hasPZ ? pZScore.toStringAsFixed(2) : '—',
              valueColor: pZScore > 3
                  ? AppColors.negative
                  : pZScore < -1
                      ? const Color(0xFF6B8EFF)
                      : AppColors.textPrimary,
              subValue: pZScore > 3
                  ? 'Extreme — historic tops'
                  : pZScore < -1
                      ? 'Deep value territory'
                      : 'Normal distribution',
              compact: true,
            ),
            StatCard(
              label: 'Price Quantile',
              icon: Icons.percent_rounded,
              value: hasPZ
                  ? '${(pQuantile * 100).toStringAsFixed(1)}%'
                  : '—',
              subValue: pQuantile > 0.8
                  ? 'Top ${((1 - pQuantile) * 100).toStringAsFixed(0)}% of history'
                  : pQuantile < 0.3
                      ? 'Bottom ${(pQuantile * 100).toStringAsFixed(0)}% of history'
                      : 'Mid-range historically',
              compact: true,
            ),
          ]),

          const SizedBox(height: 6),

          // Stats row 3: 200 DMA + Realized Price
          StatRow(cards: [
            StatCard(
              label: '200 DMA',
              icon: Icons.trending_flat_rounded,
              value: currentDma != null
                  ? '\$${_priceFmt.format(currentDma)}'
                  : '—',
              subValue: currentDma != null && price > 0
                  ? price > currentDma
                      ? '+${((price / currentDma - 1) * 100).toStringAsFixed(1)}% above'
                      : '${((price / currentDma - 1) * 100).toStringAsFixed(1)}% below'
                  : 'Loading…',
              compact: true,
            ),
            StatCard(
              label: 'Realized Price',
              icon: Icons.price_check_rounded,
              value: currentRealized > 0
                  ? '\$${_priceFmt.format(currentRealized.round())}'
                  : '—',
              subValue: currentRealized > 0 && price > 0
                  ? price > currentRealized
                      ? '+${((price / currentRealized - 1) * 100).toStringAsFixed(1)}% premium'
                      : '${((price / currentRealized - 1) * 100).toStringAsFixed(1)}% discount'
                  : 'Avg acquisition cost',
              compact: true,
            ),
          ]),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

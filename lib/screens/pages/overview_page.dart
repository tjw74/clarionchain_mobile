import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/derivatives_provider.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_math.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceState = ref.watch(priceStateProvider);
    final priceHistory = ref.watch(priceHistoryProvider);
    final dailyAsync = ref.watch(priceHistoryDailyProvider);
    ref.watch(marketMetricsProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);
    final uProfitAsync = ref.watch(unrealizedProfitProvider);
    final uLossAsync = ref.watch(unrealizedLossProvider);
    final fundingAsync = ref.watch(fundingProvider);
    final oiAsync = ref.watch(oiProvider);
    final mstrAsync = ref.watch(stockQuoteProvider('MSTR'));
    final ibitAsync = ref.watch(stockQuoteProvider('IBIT'));

    final price = priceState.vwap;

    // 24h change
    double? change24h;
    if (priceHistory.length >= 2) {
      final o = priceHistory.first.price;
      final n = priceHistory.last.price;
      if (o > 0) change24h = (n - o) / o;
    }

    // Computed metrics
    final dailyPrices =
        dailyAsync.valueOrNull?.map((t) => t.price).toList() ?? [];
    final dma200 = dailyPrices.isNotEmpty ? sma(dailyPrices, 200) : <double?>[];
    final mayer = dma200.isNotEmpty && price > 0
        ? mayerMultiple(price, dma200)
        : 0.0;

    final realized = realizedAsync.valueOrNull ?? [];
    final realizedPrice = realized.isNotEmpty ? realized.last.price : 0.0;
    final mvrv =
        realizedPrice > 0 && price > 0 ? price / realizedPrice : 0.0;

    final pQuantile =
        dailyPrices.isNotEmpty ? quantile(dailyPrices, price) : 0.0;
    final pZScore =
        dailyPrices.isNotEmpty ? logZScore(dailyPrices, price) : 0.0;

    final curUP = uProfitAsync.valueOrNull?.isNotEmpty == true
        ? uProfitAsync.valueOrNull!.last.price
        : 0.0;
    final curUL = uLossAsync.valueOrNull?.isNotEmpty == true
        ? uLossAsync.valueOrNull!.last.price
        : 0.0;
    final fundRate = fundingAsync.valueOrNull?.rate ?? 0;
    final oiUsd = oiAsync.valueOrNull?.oiUsd ?? 0;
    final mstrPrice = mstrAsync.valueOrNull?.price ?? 0;
    final ibitPrice = ibitAsync.valueOrNull?.price ?? 0;

    final changeColor =
        (change24h ?? 0) >= 0 ? AppColors.positive : AppColors.negative;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),

          // Header
          Row(children: [
            const Icon(Icons.dashboard_outlined,
                color: AppColors.btcOrange, size: 20),
            const SizedBox(width: 8),
            const Text('OVERVIEW',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
          ]),

          const SizedBox(height: 16),

          // Big price
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              price > 0 ? '\$${_priceFmt.format(price)}' : '—',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5),
            ),
            const SizedBox(width: 12),
            if (change24h != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${change24h >= 0 ? '+' : ''}${(change24h * 100).toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: changeColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
          ]),
          const Text('BTC / USD · VWAP · 5 exchanges',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),

          const SizedBox(height: 20),

          // Pricing models
          _SectionTitle('PRICING MODELS'),
          const SizedBox(height: 8),
          _Grid(children: [
            _OverviewTile(
              'Mayer Multiple',
              mayer > 0 ? mayer.toStringAsFixed(2) : '—',
              mayer > 2.4 ? AppColors.negative : mayer > 0 && mayer < 1 ? const Color(0xFF6B8EFF) : AppColors.positive,
              'price / 200 DMA',
            ),
            _OverviewTile(
              'MVRV',
              mvrv > 0 ? mvrv.toStringAsFixed(2) : '—',
              mvrv > 3.5 ? AppColors.negative : mvrv > 0 && mvrv < 1 ? const Color(0xFF6B8EFF) : AppColors.positive,
              'market / realized cap',
            ),
            _OverviewTile(
              'Z-Score',
              pZScore != 0 ? pZScore.toStringAsFixed(2) : '—',
              pZScore > 3 ? AppColors.negative : pZScore < -1 ? const Color(0xFF6B8EFF) : AppColors.textPrimary,
              'log price distribution',
            ),
            _OverviewTile(
              'Quantile',
              pQuantile > 0 ? '${(pQuantile * 100).toStringAsFixed(0)}%' : '—',
              pQuantile > 0.8 ? AppColors.negative : pQuantile < 0.3 ? const Color(0xFF6B8EFF) : AppColors.textPrimary,
              'of price history',
            ),
          ]),

          const SizedBox(height: 20),

          // P&L
          _SectionTitle('PROFIT & LOSS'),
          const SizedBox(height: 8),
          _Grid(children: [
            _OverviewTile(
              'Unrealized Profit',
              curUP > 0 ? _compact(curUP) : '—',
              AppColors.positive,
              'sell incentive',
            ),
            _OverviewTile(
              'Unrealized Loss',
              curUL > 0 ? _compact(curUL) : '—',
              AppColors.negative,
              'capitulation pressure',
            ),
          ]),

          const SizedBox(height: 20),

          // Derivatives
          _SectionTitle('DERIVATIVES'),
          const SizedBox(height: 8),
          _Grid(children: [
            _OverviewTile(
              'Funding Rate',
              fundRate != 0
                  ? '${(fundRate * 100).toStringAsFixed(4)}%'
                  : '—',
              fundRate > 0.0003 ? AppColors.negative : fundRate < -0.0001 ? const Color(0xFF6B8EFF) : AppColors.positive,
              'Binance perpetual',
            ),
            _OverviewTile(
              'Open Interest',
              oiUsd > 0 ? _compact(oiUsd) : '—',
              AppColors.textPrimary,
              'total futures OI',
            ),
          ]),

          const SizedBox(height: 20),

          // Strategy & ETFs
          _SectionTitle('STRATEGY & ETFs'),
          const SizedBox(height: 8),
          _Grid(children: [
            _OverviewTile(
              'MSTR',
              mstrPrice > 0 ? '\$${mstrPrice.toStringAsFixed(2)}' : '—',
              AppColors.btcOrange,
              mstrAsync.valueOrNull != null
                  ? '${(mstrAsync.valueOrNull!.changePct * 100).toStringAsFixed(2)}% today'
                  : 'Strategy',
            ),
            _OverviewTile(
              'IBIT',
              ibitPrice > 0 ? '\$${ibitPrice.toStringAsFixed(2)}' : '—',
              const Color(0xFF00D4AA),
              ibitAsync.valueOrNull != null
                  ? '${(ibitAsync.valueOrNull!.changePct * 100).toStringAsFixed(2)}% today'
                  : 'BlackRock ETF',
            ),
          ]),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  static String _compact(double v) {
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0));
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: children[i]),
        const SizedBox(width: 8),
        Expanded(
            child: i + 1 < children.length
                ? children[i + 1]
                : const SizedBox.shrink()),
      ]));
      if (i + 2 < children.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _OverviewTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String sub;
  const _OverviewTile(this.label, this.value, this.valueColor, this.sub);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

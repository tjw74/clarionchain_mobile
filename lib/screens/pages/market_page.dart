import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/market_chart.dart';

final _numFmt = NumberFormat('#,##0', 'en_US');

String _compactUsd(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(1)}M';
  return '\$${_numFmt.format(v)}';
}

String _compactBtc(double v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(3)}M ₿';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K ₿';
  return '${v.toStringAsFixed(2)} ₿';
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String sub;

  const _Tile({required this.label, required this.value,
               required this.valueColor, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(
                color: AppColors.textMuted, fontSize: 9,
                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(
                color: valueColor, fontSize: 18,
                fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 3),
            Text(sub, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketAsync   = ref.watch(marketMetricsProvider);
    final priceState    = ref.watch(priceStateProvider);
    final priceHistory  = ref.watch(priceHistoryProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);

    final realizedHistory = realizedAsync.valueOrNull ?? [];
    final realizedPrice   = realizedHistory.isNotEmpty
        ? realizedHistory.last.price : 0.0;
    final livePrice = priceState.vwap;

    return LayoutBuilder(builder: (context, constraints) {
      final totalH  = constraints.maxHeight;
      const headerH = 28.0;
      const statsH  = 220.0; // 3 rows × ~64px + 2 gaps
      const spacing = 8.0 * 3;
      final chartH  = totalH - headerH - statsH - spacing;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ───────────────────────────────────────────────────
            SizedBox(
              height: headerH,
              child: Row(children: [
                const Icon(Icons.pie_chart_outline_rounded,
                    color: AppColors.btcOrange, size: 18),
                const SizedBox(width: 8),
                const Text('MARKET', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(width: 14),
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: AppColors.positive, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('Price', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
                const SizedBox(width: 10),
                Container(width: 14, height: 2,
                    decoration: BoxDecoration(
                        color: AppColors.btcOrange,
                        borderRadius: BorderRadius.circular(1))),
                const SizedBox(width: 4),
                const Text('Realized', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
              ]),
            ),

            const SizedBox(height: 8),

            // ── Chart ────────────────────────────────────────────────────
            SizedBox(
              height: chartH,
              child: realizedAsync.when(
                loading: () => MarketChart(
                    priceHistory: priceHistory, realizedHistory: const []),
                error: (_, __) => MarketChart(
                    priceHistory: priceHistory, realizedHistory: const []),
                data: (realized) => MarketChart(
                    priceHistory: priceHistory, realizedHistory: realized),
              ),
            ),

            const SizedBox(height: 8),

            // ── Stats ─────────────────────────────────────────────────────
            SizedBox(
              height: statsH,
              child: marketAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(
                    color: AppColors.btcOrange, strokeWidth: 2)),
                error: (_, __) => const Center(child: Text(
                    'Could not load market data',
                    style: TextStyle(color: AppColors.textSecondary))),
                data: (m) {
                  final price = livePrice > 0 ? livePrice
                      : (m.circulatingSupply > 0
                          ? m.marketCapUsd / m.circulatingSupply : 0.0);

                  final marketCap = price > 0 && m.circulatingSupply > 0
                      ? price * m.circulatingSupply : m.marketCapUsd;
                  final realizedCap = realizedPrice > 0 && m.circulatingSupply > 0
                      ? realizedPrice * m.circulatingSupply : 0.0;
                  final mvrv = realizedPrice > 0 && price > 0
                      ? price / realizedPrice : 0.0;
                  final premium = realizedPrice > 0 && price > 0
                      ? (price - realizedPrice) / realizedPrice * 100 : 0.0;

                  final mvrvColor = mvrv > 3.5 ? AppColors.negative
                      : mvrv > 0 && mvrv < 1.0 ? AppColors.positive
                      : AppColors.textPrimary;

                  const rowH = (statsH - 8 * 2) / 3;

                  return Column(children: [
                    SizedBox(height: rowH, child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Tile(label: 'MARKET CAP',
                            value: _compactUsd(marketCap),
                            valueColor: AppColors.textPrimary,
                            sub: 'Live · ${_compactBtc(m.circulatingSupply)}'),
                        const SizedBox(width: 8),
                        _Tile(label: 'REALIZED CAP',
                            value: realizedCap > 0 ? _compactUsd(realizedCap) : '—',
                            valueColor: AppColors.textPrimary,
                            sub: 'Aggregate cost basis'),
                      ],
                    )),
                    const SizedBox(height: 8),
                    SizedBox(height: rowH, child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Tile(label: 'MVRV RATIO',
                            value: mvrv > 0 ? mvrv.toStringAsFixed(2) : '—',
                            valueColor: mvrv > 0 ? mvrvColor : AppColors.textPrimary,
                            sub: mvrv > 3.5 ? 'Historically overvalued'
                                : mvrv > 0 && mvrv < 1.0 ? 'Historically undervalued'
                                : 'Fair value range'),
                        const SizedBox(width: 8),
                        _Tile(label: 'PRICE PREMIUM',
                            value: realizedPrice > 0
                                ? '${premium >= 0 ? '+' : ''}${premium.toStringAsFixed(1)}%'
                                : '—',
                            valueColor: premium >= 0
                                ? AppColors.positive : AppColors.negative,
                            sub: 'vs realized price'),
                      ],
                    )),
                    const SizedBox(height: 8),
                    SizedBox(height: rowH, child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Tile(label: 'REALIZED PRICE',
                            value: realizedPrice > 0
                                ? '\$${_numFmt.format(realizedPrice.round())}' : '—',
                            valueColor: AppColors.btcOrange,
                            sub: 'Avg acquisition cost'),
                        const SizedBox(width: 8),
                        _Tile(label: 'SUPPLY MINED',
                            value: '${(m.circulatingSupply / 21000000 * 100).toStringAsFixed(2)}%',
                            valueColor: AppColors.textPrimary,
                            sub: '${_compactBtc(m.circulatingSupply)} of 21M'),
                      ],
                    )),
                  ]);
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

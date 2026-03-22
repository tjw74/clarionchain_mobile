import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

String _compactUsd(double value) {
  if (value >= 1e12) return '\$${(value / 1e12).toStringAsFixed(2)}T';
  if (value >= 1e9) return '\$${(value / 1e9).toStringAsFixed(1)}B';
  if (value >= 1e6) return '\$${(value / 1e6).toStringAsFixed(1)}M';
  return '\$${NumberFormat('#,##0').format(value)}';
}

String _compactBtc(double value) {
  if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(3)}M ₿';
  if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K ₿';
  return '${value.toStringAsFixed(2)} ₿';
}

class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketAsync = ref.watch(marketMetricsProvider);
    final priceState = ref.watch(priceStateProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.pie_chart_outline_rounded,
                    color: AppColors.btcOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'MARKET',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            marketAsync.when(
              loading: () => const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.btcOrange,
                    strokeWidth: 2,
                  ),
                ),
              ),
              error: (e, _) => Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: AppColors.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Could not load market data',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              data: (m) {
                final price = priceState.vwap;
                final liveMarketCap =
                    price > 0 && m.circulatingSupply > 0
                        ? price * m.circulatingSupply
                        : m.marketCapUsd;

                final mvrvColor = m.mvrv > 3.5
                    ? AppColors.negative
                    : m.mvrv < 1.0
                        ? AppColors.positive
                        : AppColors.textPrimary;

                return Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Market Cap full-width
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.btcOrange.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MARKET CAP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _compactUsd(liveMarketCap),
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Live · ${_compactBtc(m.circulatingSupply)} circulating',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        StatRow(cards: [
                          StatCard(
                            label: 'Realized Cap',
                            icon: Icons.account_balance_wallet_outlined,
                            value: _compactUsd(m.realizedCapUsd),
                            subValue: 'Aggregate cost basis',
                          ),
                          StatCard(
                            label: 'MVRV Ratio',
                            icon: Icons.show_chart_rounded,
                            value: m.mvrv > 0
                                ? m.mvrv.toStringAsFixed(2)
                                : '—',
                            valueColor: m.mvrv > 0 ? mvrvColor : null,
                            subValue: m.mvrv > 3.5
                                ? 'Overvalued zone'
                                : m.mvrv < 1.0
                                    ? 'Undervalued zone'
                                    : 'Neutral zone',
                          ),
                        ]),

                        const SizedBox(height: 10),

                        StatRow(cards: [
                          StatCard(
                            label: 'Supply',
                            icon: Icons.toll_outlined,
                            value: _compactBtc(m.circulatingSupply),
                            subValue: 'of 21M max',
                          ),
                          StatCard(
                            label: 'Supply %',
                            icon: Icons.percent_rounded,
                            value:
                                '${(m.circulatingSupply / 21000000 * 100).toStringAsFixed(2)}%',
                            subValue: 'Mined so far',
                          ),
                        ]),

                        const SizedBox(height: 10),

                        // MVRV Guide
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MVRV GUIDE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _mvrvRow('< 1.0', 'Historically undervalued',
                                  AppColors.positive),
                              _mvrvRow('1.0 – 3.5', 'Fair value range',
                                  AppColors.textSecondary),
                              _mvrvRow('> 3.5', 'Historically overvalued',
                                  AppColors.negative),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _mvrvRow(String range, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            range,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

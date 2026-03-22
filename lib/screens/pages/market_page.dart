import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/market_chart.dart';
import '../../widgets/stat_card.dart';

final _numFmt = NumberFormat('#,##0', 'en_US');

String _compactUsd(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
  return '\$${_numFmt.format(v)}';
}

String _compactBtc(double v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(3)}M ₿';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K ₿';
  return '${v.toStringAsFixed(2)} ₿';
}

class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketAsync = ref.watch(marketMetricsProvider);
    final priceState = ref.watch(priceStateProvider);
    final priceHistory = ref.watch(priceHistoryProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Header
          const Row(children: [
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
          ]),

          const SizedBox(height: 12),

          // Chart
          SizedBox(
            height: 220,
            child: Stack(children: [
              realizedAsync.when(
                loading: () => MarketChart(
                  priceHistory: priceHistory,
                  realizedHistory: const [],
                ),
                error: (_, __) => MarketChart(
                  priceHistory: priceHistory,
                  realizedHistory: const [],
                ),
                data: (realized) => MarketChart(
                  priceHistory: priceHistory,
                  realizedHistory: realized,
                ),
              ),
              // Legend
              Positioned(
                top: 6,
                left: 6,
                child: Row(children: [
                  _legendDot(AppColors.positive),
                  const SizedBox(width: 4),
                  const Text('Price',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                  const SizedBox(width: 12),
                  _legendDash(AppColors.btcOrange),
                  const SizedBox(width: 4),
                  const Text('Realized',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // Stats
          Expanded(
            child: marketAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.btcOrange, strokeWidth: 2),
              ),
              error: (_, __) => const Center(
                child: Text('Could not load market data',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              data: (m) {
                final price = priceState.vwap;
                final liveMarketCap = price > 0 && m.circulatingSupply > 0
                    ? price * m.circulatingSupply
                    : m.marketCapUsd;

                final realizedPrice = m.circulatingSupply > 0 && m.realizedCapUsd > 0
                    ? m.realizedCapUsd / m.circulatingSupply
                    : 0.0;

                final premium = realizedPrice > 0 && price > 0
                    ? ((price - realizedPrice) / realizedPrice * 100)
                    : 0.0;

                final mvrvColor = m.mvrv > 3.5
                    ? AppColors.negative
                    : m.mvrv < 1.0
                        ? AppColors.positive
                        : AppColors.textPrimary;

                final premiumColor = premium >= 0
                    ? AppColors.positive
                    : AppColors.negative;

                return SingleChildScrollView(
                  child: Column(children: [
                    // Market cap + Realized cap
                    StatRow(cards: [
                      StatCard(
                        label: 'Market Cap',
                        icon: Icons.monetization_on_outlined,
                        value: _compactUsd(liveMarketCap),
                        subValue: 'Live · ${_compactBtc(m.circulatingSupply)}',
                        compact: true,
                      ),
                      StatCard(
                        label: 'Realized Cap',
                        icon: Icons.account_balance_wallet_outlined,
                        value: _compactUsd(m.realizedCapUsd),
                        subValue: 'Aggregate cost basis',
                        compact: true,
                      ),
                    ]),

                    const SizedBox(height: 8),

                    // MVRV + Premium
                    StatRow(cards: [
                      StatCard(
                        label: 'MVRV Ratio',
                        icon: Icons.show_chart_rounded,
                        value: m.mvrv > 0 ? m.mvrv.toStringAsFixed(2) : '—',
                        valueColor: m.mvrv > 0 ? mvrvColor : null,
                        subValue: m.mvrv > 3.5
                            ? 'Historically overvalued'
                            : m.mvrv > 0 && m.mvrv < 1.0
                                ? 'Historically undervalued'
                                : 'Fair value range',
                        compact: true,
                      ),
                      StatCard(
                        label: 'Price Premium',
                        icon: Icons.trending_up_rounded,
                        value: realizedPrice > 0
                            ? '${premium >= 0 ? '+' : ''}${premium.toStringAsFixed(1)}%'
                            : '—',
                        valueColor: realizedPrice > 0 ? premiumColor : null,
                        subValue: 'vs realized price',
                        compact: true,
                      ),
                    ]),

                    const SizedBox(height: 8),

                    // Realized price + Supply
                    StatRow(cards: [
                      StatCard(
                        label: 'Realized Price',
                        icon: Icons.price_check_rounded,
                        value: realizedPrice > 0
                            ? '\$${_numFmt.format(realizedPrice.round())}'
                            : '—',
                        subValue: 'Avg acquisition cost',
                        compact: true,
                      ),
                      StatCard(
                        label: 'Supply Mined',
                        icon: Icons.percent_rounded,
                        value:
                            '${(m.circulatingSupply / 21000000 * 100).toStringAsFixed(2)}%',
                        subValue:
                            '${_compactBtc(m.circulatingSupply)} of 21M',
                        compact: true,
                      ),
                    ]),

                    const SizedBox(height: 16),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _legendDash(Color color) => Container(
        width: 16,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      );
}

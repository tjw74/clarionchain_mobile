import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/price_chart.dart';
import '../../widgets/stat_card.dart';

final _priceFmt = NumberFormat('#,##0.00', 'en_US');
final _priceFmtInt = NumberFormat('#,##0', 'en_US');
final _pctFmt = NumberFormat('+0.00%;-0.00%', 'en_US');

class PricePage extends ConsumerWidget {
  const PricePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceState = ref.watch(priceStateProvider);
    final history = ref.watch(priceHistoryProvider);

    final vwap = priceState.vwap;
    final avg = priceState.simpleAverage;
    final spread = priceState.spread;

    // 24h change from history
    double? change24h;
    if (history.length >= 2) {
      final oldest = history.first.price;
      final newest = history.last.price;
      if (oldest > 0) change24h = (newest - oldest) / oldest;
    }

    final changeColor = (change24h ?? 0) >= 0
        ? AppColors.positive
        : AppColors.negative;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BTC / USD',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vwap > 0
                          ? '\$${_priceFmtInt.format(vwap)}'
                          : '—',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (change24h != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _pctFmt.format(change24h),
                      style: TextStyle(
                        color: changeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              priceState.hasData
                  ? '${priceState.ticks.length} exchange${priceState.ticks.length != 1 ? 's' : ''} connected'
                  : 'Connecting…',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),

            const SizedBox(height: 16),

            // Chart
            Expanded(
              child: const PriceChart(),
            ),

            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Pinch to zoom  ·  Drag to scroll  ·  Double-tap to reset',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ),

            const SizedBox(height: 14),

            // Stat cards
            StatRow(cards: [
              StatCard(
                label: 'VWAP',
                icon: Icons.bar_chart_rounded,
                value: vwap > 0 ? '\$${_priceFmtInt.format(vwap)}' : '—',
                subValue: 'Volume-weighted',
                compact: true,
              ),
              StatCard(
                label: 'Average',
                icon: Icons.equalizer_rounded,
                value: avg > 0 ? '\$${_priceFmtInt.format(avg)}' : '—',
                subValue: 'Simple avg',
                compact: true,
              ),
            ]),

            const SizedBox(height: 8),

            StatRow(cards: [
              StatCard(
                label: 'Spread',
                icon: Icons.compare_arrows_rounded,
                value: spread > 0 ? '\$${_priceFmt.format(spread)}' : '—',
                subValue: 'VWAP vs avg',
                compact: true,
              ),
              StatCard(
                label: 'Exchanges',
                icon: Icons.hub_outlined,
                value: priceState.ticks.length.toString(),
                subValue: priceState.ticks.keys.join(', ').isNotEmpty
                    ? priceState.ticks.keys.join(', ')
                    : 'Connecting…',
                compact: true,
              ),
            ]),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

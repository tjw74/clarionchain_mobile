import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/stock_data.dart';
import '../../providers/price_provider.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

final _fmt = NumberFormat('#,##0.00', 'en_US');
final _fmtInt = NumberFormat('#,##0', 'en_US');

// Known BTC holdings (approximate, public data)
const _btcHoldings = {
  'MSTR': 528185.0,
};

class StockPage extends ConsumerWidget {
  final String ticker;
  final String displayName;
  final Color accentColor;

  const StockPage({
    super.key,
    required this.ticker,
    required this.displayName,
    this.accentColor = AppColors.btcOrange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoteAsync = ref.watch(stockQuoteProvider(ticker));
    final btcPrice = ref.watch(priceStateProvider).vwap;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),

        // Header
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(ticker,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(displayName,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ]),

        const SizedBox(height: 12),

        quoteAsync.when(
          loading: () => const Expanded(
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.btcOrange, strokeWidth: 2),
            ),
          ),
          error: (_, __) => const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded,
                      color: AppColors.textMuted, size: 28),
                  SizedBox(height: 8),
                  Text('Data unavailable',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          data: (quote) {
            if (quote == null) {
              return Expanded(
                child: Center(
                  child: Text('No data for $ticker',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              );
            }
            return _StockContent(
              quote: quote,
              btcPrice: btcPrice,
              accentColor: accentColor,
            );
          },
        ),
      ]),
    );
  }
}

class _StockContent extends StatelessWidget {
  final StockQuote quote;
  final double btcPrice;
  final Color accentColor;
  const _StockContent({
    required this.quote,
    required this.btcPrice,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor =
        quote.changePct >= 0 ? AppColors.positive : AppColors.negative;
    final btcHeld = _btcHoldings[quote.ticker];
    final navPerShare = btcHeld != null && btcPrice > 0 &&
            quote.history.isNotEmpty
        ? btcHeld * btcPrice / _sharesOutstanding(quote.ticker)
        : 0.0;
    final premium =
        navPerShare > 0 ? (quote.price - navPerShare) / navPerShare : 0.0;

    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Current price
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${_fmt.format(quote.price)}',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${quote.changePct >= 0 ? '+' : ''}${(quote.changePct * 100).toStringAsFixed(2)}%',
              style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // Chart
        Expanded(
          child: quote.history.isNotEmpty
              ? _StockChart(history: quote.history, color: accentColor)
              : const Center(
                  child: Text('No chart data',
                      style: TextStyle(color: AppColors.textMuted))),
        ),

        const SizedBox(height: 10),

        // Stats
        StatRow(cards: [
          StatCard(
            label: '52W High',
            icon: Icons.arrow_upward_rounded,
            value: '\$${_fmtInt.format(quote.fiftyTwoWeekHigh)}',
            subValue: '${((quote.price / quote.fiftyTwoWeekHigh - 1) * 100).toStringAsFixed(1)}% from high',
            compact: true,
          ),
          StatCard(
            label: '52W Low',
            icon: Icons.arrow_downward_rounded,
            value: '\$${_fmtInt.format(quote.fiftyTwoWeekLow)}',
            subValue: '+${((quote.price / quote.fiftyTwoWeekLow - 1) * 100).toStringAsFixed(1)}% from low',
            compact: true,
          ),
        ]),

        if (navPerShare > 0) ...[
          const SizedBox(height: 6),
          StatRow(cards: [
            StatCard(
              label: 'mNAV / Share',
              icon: Icons.currency_bitcoin_rounded,
              value: '\$${_fmtInt.format(navPerShare.round())}',
              subValue: 'BTC holdings / shares',
              compact: true,
            ),
            StatCard(
              label: 'Premium to NAV',
              icon: Icons.price_change_outlined,
              value: navPerShare > 0
                  ? '${premium >= 0 ? '+' : ''}${(premium * 100).toStringAsFixed(1)}%'
                  : '—',
              valueColor: premium > 0.5
                  ? AppColors.negative
                  : premium < 0
                      ? const Color(0xFF6B8EFF)
                      : AppColors.textPrimary,
              subValue: 'vs BTC-backed value',
              compact: true,
            ),
          ]),
        ],

        const SizedBox(height: 12),
      ]),
    );
  }
}

class _StockChart extends StatelessWidget {
  final List<StockBar> history;
  final Color color;
  const _StockChart({required this.history, required this.color});

  @override
  Widget build(BuildContext context) {
    final prices = history.map((b) => b.close).toList();
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final pad = (maxY - minY) * 0.08;

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();
    final vc = spots.length;
    final labelInterval =
        (vc / 4).floorToDouble().clamp(1.0, double.infinity);

    return LineChart(LineChartData(
      minY: minY - pad,
      maxY: maxY + pad,
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
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 56,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              return Text('\$${_fmtInt.format(v)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 9),
                  textAlign: TextAlign.right);
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 18,
            interval: labelInterval,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= history.length) {
                return const SizedBox.shrink();
              }
              final dt = history[i].timestamp;
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${dt.month}/${dt.year.toString().substring(2)}',
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
          isCurved: true,
          curveSmoothness: 0.15,
          color: color,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    ));
  }
}

// Approximate shares outstanding (for NAV computation)
double _sharesOutstanding(String ticker) {
  switch (ticker) {
    case 'MSTR': return 246000000;
    default: return 1;
  }
}

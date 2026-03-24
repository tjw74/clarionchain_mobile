import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/derivatives_data.dart';
import '../../models/exchange_tick.dart';
import '../../providers/derivatives_provider.dart';
import '../../providers/price_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../widgets/category_page_layout.dart';
import '../../widgets/stat_card.dart';

String _compactUsd(double v) => formatAxisUsdCompact(v);

/// Last [len] BTC closes aligned to derivative series length (pad front if shorter).
List<double> _btcPricesForLen(List<PriceTick> btc, int len) {
  if (btc.isEmpty || len <= 0) return [];
  if (btc.length >= len) {
    return btc.sublist(btc.length - len).map((e) => e.price).toList();
  }
  final first = btc.first.price;
  return [
    ...List<double>.filled(len - btc.length, first),
    ...btc.map((e) => e.price),
  ];
}

List<double> _normalize01(List<double> v) {
  if (v.isEmpty) return [];
  final lo = v.reduce(min);
  final hi = v.reduce(max);
  if (hi <= lo) return List<double>.filled(v.length, 0.5);
  return v.map((x) => (x - lo) / (hi - lo)).toList();
}

class DerivativesPage extends ConsumerWidget {
  const DerivativesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fundingAsync = ref.watch(fundingProvider);
    final oiAsync = ref.watch(oiProvider);
    final oiHistory = ref.watch(oiHistoryProvider).valueOrNull ?? [];
    final fundHistory = ref.watch(fundingHistoryProvider).valueOrNull ?? [];
    final btcHistory = ref.watch(chartDailyPriceHistoryProvider);

    final funding = fundingAsync.valueOrNull;
    final oi = oiAsync.valueOrNull;

    // Funding color
    final fundRate = funding?.rate ?? 0;
    final fundColor = fundRate > 0.0003
        ? AppColors.negative // overheated longs
        : fundRate < -0.0001
            ? const Color(0xFF6B8EFF) // shorts dominant
            : AppColors.positive;

    // L/S color
    final longPct = oi?.longPct ?? 0.5;
    final lsColor = longPct > 0.65
        ? AppColors.negative // over-leveraged longs
        : longPct < 0.35
            ? const Color(0xFF6B8EFF)
            : AppColors.textPrimary;

    return CategoryPageLayout(
      header: const CategoryPageHeader(
        category: 'BTC',
        title: 'Derivatives',
        accentColor: AppColors.btcOrange,
        trailingHint: 'Binance Futures',
      ),
      chart: _DerivativesCharts(
        oiHistory: oiHistory,
        fundHistory: fundHistory,
        btcHistory: btcHistory,
      ),
      stats: SingleChildScrollView(
        child: Column(children: [
              StatRow(cards: [
                StatCard(
                  label: 'Funding Rate',
                  icon: Icons.sync_rounded,
                  value: funding != null
                      ? '${(fundRate * 100).toStringAsFixed(4)}%'
                      : '—',
                  valueColor: fundColor,
                  subValue: funding != null
                      ? '${(funding.annualizedPct).toStringAsFixed(1)}% annualized'
                      : 'Loading…',
                  compact: true,
                ),
                StatCard(
                  label: 'Open Interest',
                  icon: Icons.stacked_bar_chart_rounded,
                  value: oi != null ? _compactUsd(oi.oiUsd) : '—',
                  subValue: oi != null
                      ? '${oi.oiBtc.toStringAsFixed(0)} BTC contracts'
                      : 'Loading…',
                  compact: true,
                ),
              ]),

              const SizedBox(height: 8),

              StatRow(cards: [
                StatCard(
                  label: 'Longs',
                  icon: Icons.trending_up_rounded,
                  value: oi != null
                      ? '${(longPct * 100).toStringAsFixed(1)}%'
                      : '—',
                  valueColor: lsColor,
                  subValue: longPct > 0.65
                      ? 'Over-leveraged — reversal risk'
                      : longPct < 0.35
                          ? 'Short squeeze potential'
                          : 'Balanced positioning',
                  compact: true,
                ),
                StatCard(
                  label: 'Shorts',
                  icon: Icons.trending_down_rounded,
                  value: oi != null
                      ? '${((1 - longPct) * 100).toStringAsFixed(1)}%'
                      : '—',
                  subValue: 'of open interest',
                  compact: true,
                ),
              ]),

              const SizedBox(height: 8),

              // Funding interpretation
              if (funding != null)
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
                      const Text('LEVERAGE SIGNAL',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      _interpretFunding(fundRate, longPct),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
            ]),
      ),
    );
  }

  Widget _interpretFunding(double rate, double longPct) {
    String text;
    Color color;
    if (rate > 0.0005 && longPct > 0.60) {
      text = 'High positive funding with long dominance — excessive leverage in longs. '
          'Historically precedes sharp deleveraging events (long squeezes).';
      color = AppColors.negative;
    } else if (rate > 0.0002) {
      text = 'Elevated positive funding — longs are paying shorts. Market is leaning bullish. '
          'Moderate risk of deleveraging if price fails to hold.';
      color = const Color(0xFFFF8C00);
    } else if (rate < -0.0002) {
      text = 'Negative funding — shorts are paying longs. Capitulation/fear positioning. '
          'Historically a contrarian buy signal when persistent.';
      color = const Color(0xFF6B8EFF);
    } else {
      text = 'Funding near neutral. Balanced leverage — no extreme positioning signal.';
      color = AppColors.textSecondary;
    }
    return Text(text, style: TextStyle(color: color, fontSize: 11, height: 1.5));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8));
}

class _OiChart extends StatelessWidget {
  final List<OiHistoryPoint> history;
  final List<PriceTick> btcHistory;

  const _OiChart({required this.history, required this.btcHistory});

  @override
  Widget build(BuildContext context) {
    final vals = history.map((p) => p.oiUsd).toList();
    final btcAligned = _btcPricesForLen(btcHistory, history.length);
    final oiN = _normalize01(vals);
    final btcN =
        btcAligned.length == history.length ? _normalize01(btcAligned) : <double>[];

    final oiSpots = oiN
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final btcSpots = btcN
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(LineChartData(
      minY: -0.02,
      maxY: 1.02,
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
            reservedSize: 28,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              return Text(v.toStringAsFixed(1),
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
            interval: (history.length / 4).floorToDouble().clamp(1, double.infinity),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= history.length) return const SizedBox.shrink();
              final dt = history[i].timestamp;
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${dt.month}/${dt.day}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: oiSpots,
          isCurved: true,
          curveSmoothness: 0.2,
          color: AppColors.btcOrange,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.btcOrange.withValues(alpha: 0.15),
                AppColors.btcOrange.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        if (btcSpots.isNotEmpty)
          LineChartBarData(
            spots: btcSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.positive,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    ));
  }
}

class _FundingChart extends StatelessWidget {
  final List<FundingHistoryPoint> history;
  final List<PriceTick> btcHistory;

  const _FundingChart({required this.history, required this.btcHistory});

  @override
  Widget build(BuildContext context) {
    final vals = history.map((p) => p.rate * 100).toList();
    final btcAligned = _btcPricesForLen(btcHistory, history.length);
    final fundN = _normalize01(vals);
    final btcN =
        btcAligned.length == history.length ? _normalize01(btcAligned) : <double>[];

    final fundSpots = fundN
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final btcSpots = btcN
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(LineChartData(
      minY: -0.02,
      maxY: 1.02,
      clipData: const FlClipData.all(),
      lineTouchData: const LineTouchData(enabled: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
          color: (v - 0.5).abs() < 0.02 ? AppColors.textMuted : AppColors.border,
          strokeWidth: (v - 0.5).abs() < 0.02 ? 1.5 : 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              return Text(v.toStringAsFixed(1),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 9),
                  textAlign: TextAlign.right);
            },
          ),
        ),
        bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: fundSpots,
          isCurved: false,
          color: AppColors.positive,
          barWidth: 1,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.positive.withValues(alpha: 0.2),
                AppColors.positive.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        if (btcSpots.isNotEmpty)
          LineChartBarData(
            spots: btcSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.btcOrange,
            barWidth: 1.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    ));
  }
}

class _DerivativesCharts extends StatelessWidget {
  final List<OiHistoryPoint> oiHistory;
  final List<FundingHistoryPoint> fundHistory;
  final List<PriceTick> btcHistory;

  const _DerivativesCharts({
    required this.oiHistory,
    required this.fundHistory,
    required this.btcHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (oiHistory.isEmpty && fundHistory.isEmpty) {
      return const Center(
        child: Text(
          'Chart data unavailable',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (oiHistory.isNotEmpty)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                    'OPEN INTEREST — 90 DAYS · orange=OI, teal=BTC (scaled)'),
                Expanded(
                    child: _OiChart(
                        history: oiHistory, btcHistory: btcHistory)),
              ],
            ),
          ),
        if (oiHistory.isNotEmpty && fundHistory.isNotEmpty)
          const SizedBox(height: 8),
        if (fundHistory.isNotEmpty)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                    'FUNDING RATE — 30 DAYS · green=funding %, orange=BTC'),
                Expanded(
                    child: _FundingChart(
                        history: fundHistory, btcHistory: btcHistory)),
              ],
            ),
          ),
      ],
    );
  }
}

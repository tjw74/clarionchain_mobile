import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/derivatives_data.dart';
import '../../providers/derivatives_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../widgets/category_page_layout.dart';
import '../../widgets/stat_card.dart';

String _compactUsd(double v) => formatAxisUsdCompact(v);

class DerivativesPage extends ConsumerWidget {
  const DerivativesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fundingAsync = ref.watch(fundingProvider);
    final oiAsync = ref.watch(oiProvider);
    final oiHistory = ref.watch(oiHistoryProvider).valueOrNull ?? [];
    final fundHistory = ref.watch(fundingHistoryProvider).valueOrNull ?? [];

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
  const _OiChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final vals = history.map((p) => p.oiUsd).toList();
    final maxY = vals.reduce((a, b) => a > b ? a : b);
    final minY = vals.reduce((a, b) => a < b ? a : b);
    final pad = (maxY - minY) * 0.1;

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.oiUsd))
        .toList();

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
            reservedSize: kChartAxisReservedRight,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              return Text(formatAxisUsdCompact(v),
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
          spots: spots,
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
      ],
    ));
  }
}

class _FundingChart extends StatelessWidget {
  final List<FundingHistoryPoint> history;
  const _FundingChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final vals = history.map((p) => p.rate * 100).toList();
    final maxY = vals.reduce((a, b) => a > b ? a : b).clamp(0.06, double.infinity);
    final minY = vals.reduce((a, b) => a < b ? a : b).clamp(double.negativeInfinity, -0.01);

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.rate * 100))
        .toList();

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      lineTouchData: const LineTouchData(enabled: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
          color: v == 0 ? AppColors.textMuted : AppColors.border,
          strokeWidth: v == 0 ? 1.5 : 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              return Text('${v.toStringAsFixed(3)}%',
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
          spots: spots,
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
      ],
    ));
  }
}

class _DerivativesCharts extends StatelessWidget {
  final List<OiHistoryPoint> oiHistory;
  final List<FundingHistoryPoint> fundHistory;

  const _DerivativesCharts({
    required this.oiHistory,
    required this.fundHistory,
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
                _SectionLabel('OPEN INTEREST — 90 DAYS'),
                Expanded(child: _OiChart(history: oiHistory)),
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
                _SectionLabel('FUNDING RATE — 30 DAYS'),
                Expanded(child: _FundingChart(history: fundHistory)),
              ],
            ),
          ),
      ],
    );
  }
}

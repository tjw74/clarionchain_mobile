import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_math.dart';
import '../../models/exchange_tick.dart';

final _priceFmt = NumberFormat('#,##0', 'en_US');

String _compactValue(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
  return '\$${v.toStringAsFixed(0)}';
}

class MvrvPage extends ConsumerStatefulWidget {
  const MvrvPage({super.key});

  @override
  ConsumerState<MvrvPage> createState() => _MvrvPageState();
}

class _MvrvPageState extends ConsumerState<MvrvPage> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final priceState = ref.watch(priceStateProvider);
    final history = ref.watch(priceHistoryProvider);
    final realizedAsync = ref.watch(realizedPriceHistoryProvider);
    final marketAsync = ref.watch(marketMetricsProvider);

    final price = priceState.vwap;
    final realizedHistory = realizedAsync.valueOrNull ?? [];
    final currentRealized =
        realizedHistory.isNotEmpty ? realizedHistory.last.price : 0.0;

    final mvrv =
        currentRealized > 0 && price > 0 ? price / currentRealized : 0.0;

    final premium = currentRealized > 0 && price > 0
        ? (price - currentRealized) / currentRealized
        : 0.0;

    // MVRV Z-score: compute daily MVRV ratios from history
    // Align realized history to price history by day
    final Map<int, double> realizedByDay = {};
    for (final t in realizedHistory) {
      realizedByDay[t.timestamp.millisecondsSinceEpoch ~/ 86400000] = t.price;
    }
    final mvrvSeries = <double>[];
    for (final tick in history) {
      final dayKey = tick.timestamp.millisecondsSinceEpoch ~/ 86400000;
      final rp = realizedByDay[dayKey];
      if (rp != null && rp > 0) {
        mvrvSeries.add(tick.price / rp);
      }
    }
    final mvrvZScore =
        mvrvSeries.length >= 2 && mvrv > 0 ? rawZScore(mvrvSeries, mvrv) : 0.0;

    final circulatingSupply =
        marketAsync.valueOrNull?.circulatingSupply ?? 19700000.0;
    final marketCap = price > 0 ? price * circulatingSupply : 0.0;
    final realizedCap =
        currentRealized > 0 ? currentRealized * circulatingSupply : 0.0;

    final mvrvColor = mvrv > 3.5
        ? AppColors.negative
        : (mvrv > 0 && mvrv < 1.0)
            ? AppColors.positive
            : AppColors.textPrimary;

    final premiumStr = premium != 0
        ? '${premium >= 0 ? '+' : ''}${(premium * 100).toStringAsFixed(1)}% ${premium >= 0 ? 'above' : 'below'} cost'
        : '—';

    final headerValue = mvrv > 0 ? mvrv.toStringAsFixed(2) : '—';
    final headerChange = premium != 0 ? premiumStr : '—';
    final headerChangeColor =
        premium >= 0 ? AppColors.positive : AppColors.negative;

    // Build aligned realized overlay for chart
    final chartLen = history.length;
    final List<double?> realizedOverlay = List.filled(chartLen, null);
    for (int i = 0; i < history.length; i++) {
      final dayKey =
          history[i].timestamp.millisecondsSinceEpoch ~/ 86400000;
      final rp = realizedByDay[dayKey];
      if (rp != null) realizedOverlay[i] = rp;
    }

    return LayoutBuilder(builder: (context, constraints) {
      const headerH = 56.0;
      final totalH = constraints.maxHeight;
      final chartH = (totalH - headerH - 16) * 0.50;
      final statsH = (totalH - headerH - 16) * 0.50;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('MVRV', '', headerValue, headerChange, headerChangeColor),
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: _buildChart(context, history, realizedOverlay),
            ),
            SizedBox(
              height: statsH,
              child: _buildStats(
                mvrv,
                mvrvColor,
                mvrvZScore,
                premium,
                currentRealized,
                marketCap,
                realizedCap,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildChart(
    BuildContext context,
    List<PriceTick> history,
    List<double?> realizedOverlay,
  ) {
    if (history.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.btcOrange, strokeWidth: 2),
      );
    }

    final n = history.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final slice = startIdx < endIdx
        ? history.sublist(startIdx, endIdx + 1)
        : [history.last];

    final priceSpots = slice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    double minP = slice.map((t) => t.price).reduce((a, b) => a < b ? a : b);
    double maxP = slice.map((t) => t.price).reduce((a, b) => a > b ? a : b);

    final realizedSpots = <FlSpot>[];
    for (int i = 0; i < slice.length; i++) {
      final gi = startIdx + i;
      if (gi < realizedOverlay.length) {
        final v = realizedOverlay[gi];
        if (v != null) {
          if (v < minP) minP = v;
          if (v > maxP) maxP = v;
          realizedSpots.add(FlSpot(i.toDouble(), v));
        }
      }
    }

    final yPad = ((maxP - minP) * 0.08).clamp(50.0, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final vc = slice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays =
        slice.last.timestamp.difference(slice.first.timestamp).inMinutes /
            1440.0;

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
      child: LineChart(
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
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 68,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  final label = value >= 1000
                      ? '\$${(value / 1000).toStringAsFixed(0)}K'
                      : '\$${value.toStringAsFixed(0)}';
                  return Text(
                    label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
                    textAlign: TextAlign.right,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= slice.length) {
                    return const SizedBox.shrink();
                  }
                  final dt = slice[idx].timestamp;
                  final label = visibleDays > 365
                      ? DateFormat('MMM yy').format(dt)
                      : visibleDays > 60
                          ? DateFormat('MMM').format(dt)
                          : DateFormat('MMM d').format(dt);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            // Market price (teal solid)
            LineChartBarData(
              spots: priceSpots,
              isCurved: vc < 200,
              curveSmoothness: 0.2,
              color: AppColors.positive,
              barWidth: vc > 300 ? 1.5 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            // Realized price (orange dashed)
            if (realizedSpots.isNotEmpty)
              LineChartBarData(
                spots: realizedSpots,
                isCurved: false,
                color: AppColors.btcOrange,
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                dashArray: [6, 4],
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _buildStats(
    double mvrv,
    Color mvrvColor,
    double mvrvZScore,
    double premium,
    double currentRealized,
    double marketCap,
    double realizedCap,
  ) {
    final zColor = mvrvZScore > 3.0
        ? AppColors.negative
        : mvrvZScore < -1.0
            ? AppColors.positive
            : AppColors.textPrimary;

    final premiumColor =
        premium >= 0 ? AppColors.positive : AppColors.negative;

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
                        label: 'MVRV RATIO',
                        value: mvrv > 0 ? mvrv.toStringAsFixed(2) : '—',
                        valueColor: mvrv > 0 ? mvrvColor : AppColors.textPrimary,
                        signal: mvrv > 3.5
                            ? 'Overvalued zone'
                            : mvrv > 0 && mvrv < 1.0
                                ? 'Undervalued zone'
                                : 'Fair value range',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'MVRV Z-SCORE',
                        value: mvrvZScore != 0
                            ? mvrvZScore.toStringAsFixed(2)
                            : '—',
                        valueColor: zColor,
                        signal: 'raw z-score of MVRV',
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
                        label: 'PRICE PREMIUM',
                        value: premium != 0
                            ? '${premium >= 0 ? '+' : ''}${(premium * 100).toStringAsFixed(1)}%'
                            : '—',
                        valueColor: premiumColor,
                        signal: '(price − realized) / realized',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'REALIZED PRICE',
                        value: currentRealized > 0
                            ? '\$${_priceFmt.format(currentRealized.round())}'
                            : '—',
                        valueColor: AppColors.btcOrange,
                        signal: 'Avg on-chain cost basis',
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
                        label: 'MARKET CAP',
                        value: marketCap > 0 ? _compactValue(marketCap) : '—',
                        valueColor: AppColors.textPrimary,
                        signal: 'price × supply',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'REALIZED CAP',
                        value:
                            realizedCap > 0 ? _compactValue(realizedCap) : '—',
                        valueColor: AppColors.textPrimary,
                        signal: 'realized price × supply',
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

  Widget _header(
    String category,
    String page,
    String value,
    String change,
    Color changeColor,
  ) {
    return SizedBox(
      height: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Text(category,
                style: const TextStyle(
                    color: AppColors.btcOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(width: 6),
            Text(page,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.0)),
          ]),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0)),
              const SizedBox(width: 8),
              Text(change,
                  style: TextStyle(
                      color: changeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

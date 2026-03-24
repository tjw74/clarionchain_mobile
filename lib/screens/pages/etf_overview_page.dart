import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../models/exchange_tick.dart';
import '../../models/stock_data.dart';
import '../../widgets/category_page_layout.dart';

final _intFmt = NumberFormat('#,##0', 'en_US');

class EtfOverviewPage extends ConsumerStatefulWidget {
  const EtfOverviewPage({super.key});

  @override
  ConsumerState<EtfOverviewPage> createState() => _EtfOverviewPageState();
}

class _EtfOverviewPageState extends ConsumerState<EtfOverviewPage> {
  static const _etfLaunchDate = '2024-01-11';
  static const _totalBtcHeld = 1150000;

  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(priceHistoryProvider);

    final ibitAsync = ref.watch(stockQuoteProvider('IBIT'));
    final fbtcAsync = ref.watch(stockQuoteProvider('FBTC'));
    final arkbAsync = ref.watch(stockQuoteProvider('ARKB'));
    final bitbAsync = ref.watch(stockQuoteProvider('BITB'));
    final gbtcAsync = ref.watch(stockQuoteProvider('GBTC'));
    final hodlAsync = ref.watch(stockQuoteProvider('HODL'));

    // Filter history to ETF launch date
    final launchDt = DateTime.parse(_etfLaunchDate);
    final etfHistory = history.where((t) => !t.timestamp.isBefore(launchDt)).toList();

    return CategoryPageLayout(
      header: CategoryPageHeader(
        category: 'ETFs',
        title: 'Overview',
        accentColor: const Color(0xFF4488FF),
        subtitle: '~${_intFmt.format(_totalBtcHeld)} BTC (est. held)',
        trailingHint: 'Since Jan 2024',
      ),
      chart: _buildChart(context, etfHistory),
      stats: _buildStats(
        ibitAsync,
        fbtcAsync,
        arkbAsync,
        bitbAsync,
        gbtcAsync,
        hodlAsync,
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<PriceTick> history) {
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

    final spots = slice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    final prices = slice.map((t) => t.price).toList();
    final minP = prices.reduce((a, b) => a < b ? a : b);
    final maxP = prices.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxP - minP) * 0.08).clamp(50.0, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final isUp = slice.last.price >= slice.first.price;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
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
                reservedSize: kChartAxisReservedRight,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    formatAxisUsdCompact(value),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9),
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
            LineChartBarData(
              spots: spots,
              isCurved: vc < 200,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: vc > 300 ? 1.5 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.15),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _buildStats(
    AsyncValue<StockQuote?> ibitAsync,
    AsyncValue<StockQuote?> fbtcAsync,
    AsyncValue<StockQuote?> arkbAsync,
    AsyncValue<StockQuote?> bitbAsync,
    AsyncValue<StockQuote?> gbtcAsync,
    AsyncValue<StockQuote?> hodlAsync,
  ) {
    final etfs = [
      ('IBIT', 'BlackRock', ibitAsync),
      ('FBTC', 'Fidelity', fbtcAsync),
      ('ARKB', 'ARK 21Shares', arkbAsync),
      ('BITB', 'Bitwise', bitbAsync),
      ('GBTC', 'Grayscale', gbtcAsync),
      ('HODL', 'VanEck', hodlAsync),
    ];

    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              for (int row = 0; row < 3; row++) ...[
                if (row > 0) const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _EtfPanel(
                          ticker: etfs[row * 2].$1,
                          name: etfs[row * 2].$2,
                          quoteAsync: etfs[row * 2].$3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _EtfPanel(
                          ticker: etfs[row * 2 + 1].$1,
                          name: etfs[row * 2 + 1].$2,
                          quoteAsync: etfs[row * 2 + 1].$3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

}

class _EtfPanel extends StatelessWidget {
  final String ticker;
  final String name;
  final AsyncValue<StockQuote?> quoteAsync;

  const _EtfPanel({
    required this.ticker,
    required this.name,
    required this.quoteAsync,
  });

  @override
  Widget build(BuildContext context) {
    final quote = quoteAsync.valueOrNull;
    final price = quote?.price ?? 0.0;
    final changePct = quote?.changePct ?? 0.0;
    final isUp = changePct >= 0;
    final changeColor = isUp ? AppColors.positive : AppColors.negative;

    String priceStr = '—';
    String changeStr = '—';
    if (price > 0) {
      priceStr = '\$${NumberFormat('#,##0.00', 'en_US').format(price)}';
      changeStr =
          '${isUp ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%';
    } else if (quoteAsync.isLoading) {
      priceStr = '...';
      changeStr = '';
    } else if (quoteAsync.hasError) {
      priceStr = 'Error';
      changeStr = '';
    }

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(ticker,
                  style: const TextStyle(
                      color: AppColors.btcOrange,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              if (changeStr.isNotEmpty)
                Text(changeStr,
                    style: TextStyle(
                        color: changeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            priceStr,
            style: TextStyle(
                color: price > 0 ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 18,
                fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(name,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

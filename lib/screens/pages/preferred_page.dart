import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../models/stock_data.dart';
import '../../widgets/category_page_layout.dart';

final _priceFmtPref = NumberFormat('#,##0.00', 'en_US');

class PreferredPage extends ConsumerStatefulWidget {
  final String ticker;
  final String displayName;
  final double parValue;
  final double dividendRate;

  const PreferredPage({
    super.key,
    required this.ticker,
    required this.displayName,
    required this.parValue,
    required this.dividendRate,
  });

  @override
  ConsumerState<PreferredPage> createState() => _PreferredPageState();
}

class _PreferredPageState extends ConsumerState<PreferredPage> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(stockQuoteProvider(widget.ticker));

    final quote = quoteAsync.valueOrNull;
    final price = quote?.price ?? 0.0;
    final changePct = quote?.changePct ?? 0.0;
    final isUp = changePct >= 0;

    final premiumToPar = price > 0 && widget.parValue > 0
        ? (price - widget.parValue) / widget.parValue
        : 0.0;

    final annualYield = price > 0
        ? (widget.dividendRate * widget.parValue / price) * 100
        : 0.0;

    final history = quote?.history ?? [];

    final headerChange = changePct != 0
        ? '${isUp ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%'
        : '—';

    final subtitle = price > 0
        ? '\$${_priceFmtPref.format(price)} · $headerChange'
        : null;

    final chartBody = quoteAsync.isLoading
        ? const Center(
            child: CircularProgressIndicator(
                color: AppColors.btcOrange, strokeWidth: 2))
        : quoteAsync.hasError
            ? Center(
                child: Text(
                  'Error loading ${widget.ticker}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              )
            : _buildChart(context, history);

    final statsBody = quoteAsync.isLoading || quoteAsync.hasError
        ? const SizedBox.expand()
        : _buildStats(
            price,
            premiumToPar,
            annualYield,
          );

    return CategoryPageLayout(
      header: CategoryPageHeader(
        category: widget.ticker,
        title: widget.displayName,
        accentColor: const Color(0xFF9B59B6),
        subtitle: subtitle,
      ),
      chart: chartBody,
      stats: statsBody,
    );
  }

  Widget _buildChart(BuildContext context, List<StockBar> history) {
    if (history.isEmpty) {
      return const Center(
        child: Text('No history available',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final n = history.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final slice = startIdx < endIdx
        ? history.sublist(startIdx, endIdx + 1)
        : [history.last];

    final spots = slice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();

    final closes = slice.map((b) => b.close).toList();
    final minP = closes.reduce((a, b) => a < b ? a : b);
    final maxP = closes.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxP - minP) * 0.08).clamp(0.5, double.infinity);

    // Include par value in Y range for context
    final effMin = (minP - yPad).clamp(0.0, double.infinity);
    final effMax = maxP + yPad > widget.parValue * 1.5
        ? maxP + yPad
        : widget.parValue * 1.05;

    final isUp = slice.last.close >= slice.first.close;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final vc = slice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays =
        slice.last.timestamp.difference(slice.first.timestamp).inDays.toDouble();

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
            getDrawingHorizontalLine: (value) {
              // Highlight par value line
              if ((value - widget.parValue).abs() <
                  (effMax - effMin) * 0.02) {
                return const FlLine(
                    color: AppColors.btcOrange, strokeWidth: 1);
              }
              return const FlLine(color: AppColors.border, strokeWidth: 1);
            },
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
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: widget.parValue,
                color: AppColors.btcOrange.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  style: const TextStyle(
                      color: AppColors.btcOrange, fontSize: 9),
                  labelResolver: (_) => 'PAR',
                ),
              ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: vc < 100,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: vc > 200 ? 1.5 : 2,
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
    double price,
    double premiumToPar,
    double annualYield,
  ) {
    final premiumColor =
        premiumToPar > 0.10 ? AppColors.negative : AppColors.positive;

    final yieldColor = annualYield > widget.dividendRate * 100 * 1.1
        ? AppColors.positive
        : annualYield < widget.dividendRate * 100 * 0.9
            ? AppColors.negative
            : AppColors.textPrimary;

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
                        label: 'CURRENT PRICE',
                        value: price > 0
                            ? '\$${_priceFmtPref.format(price)}'
                            : '—',
                        valueColor: AppColors.textPrimary,
                        signal: '${widget.ticker} market price',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'PAR VALUE',
                        value: '\$${_priceFmtPref.format(widget.parValue)}',
                        valueColor: AppColors.btcOrange,
                        signal: 'Liquidation preference',
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
                        label: 'PREMIUM TO PAR',
                        value: price > 0
                            ? '${premiumToPar >= 0 ? '+' : ''}${(premiumToPar * 100).toStringAsFixed(1)}%'
                            : '—',
                        valueColor: price > 0 ? premiumColor : AppColors.textMuted,
                        signal: '(price − par) / par',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'ANNUAL YIELD',
                        value: price > 0
                            ? '${annualYield.toStringAsFixed(2)}%'
                            : '—',
                        valueColor: price > 0 ? yieldColor : AppColors.textMuted,
                        signal:
                            '${(widget.dividendRate * 100).toStringAsFixed(0)}% dividend on \$${_priceFmtPref.format(widget.parValue)} par',
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
